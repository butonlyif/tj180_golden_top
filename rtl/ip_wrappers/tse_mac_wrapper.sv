`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: tse_mac_wrapper
// 功能描述: Triple-Speed Ethernet (TSE) MAC IP `test_tse` 的顶层包装。
//           把 Efinity TSE IP 的扁平端口整理为分类总线，并完成：
//             1) APB3 → AXI4-Lite 桥（重用 rtl/cdc/apb_to_axilite.sv, AW=10）
//                —— SoC 通过 APB 直接配置 MAC CSR 寄存器（GMII/MAC/PCS 等）。
//             2) AXI4-Stream 数据通路：RGMII 直接走物理管脚，无内环回；
//                TX 静态 idle（待 SoC DMA 驱动），RX 持续排空（接收包丢弃）。
//             3) MDIO 直通（Mdc/Mdo/MdoEn 输出，Mdi 输入）。
//             4) RGMII DDR 物理引脚直连顶层 peri 端口。
// 接口说明:
//   • mac_clk_i   — MAC/AXIS/AXI-Lite 时钟（当前 = sys_clk 50 MHz；参考设计
//                   T120F324_devkit/temac_ex.v 也是 50 MHz 收尾时序；将来可改 125 MHz）
//   • mac_rst_n_i — MAC 时钟域异步低复位
//   • rgmii_rxc_i — RGMII RX 时钟（PHY 提供，源同步 DDR）
//   • rgmii_*     — DDR 拆位物理引脚（与 peri.xml `_HI`/`_LO` 对齐）
//   • mdio_*      — PHY 管理 IO
//   • apb_*       — 从 APB decoder 来的 slave 1 端口
//   • irq_o       — 预留中断输出（MAC 自带 IRQ 信号当前未导出，留作扩展）
// 设计约束:
//   • s_axi_aclk = rx_axis_clk = tx_axis_clk = mac_clk_i（同源同步）
//   • rgmii_rxc 异步，由 SDC set_clock_groups 隔离
//   • 软件首次 bring-up：先经 MDIO 复位 PHY、配置自协商，再环回 ping。
//============================================================================
module tse_mac_wrapper (
    // -- 时钟 / 复位 --
    input  wire        mac_clk_i,       // MAC 时钟（= sys_clk 50 MHz）
    input  wire        mac_rst_n_i,     // MAC 复位（异步低）
    input  wire        mac_sw_rst_i,    // 软复位（协议层），高有效
    input  wire        phy_locked_i,    // PHY 锁定/PLL lock 标志，用于 mac_reset

    // -- RGMII DDR 物理引脚（顶层 peri 直连） --
    output wire [3:0]  rgmii_txd_HI_o,
    output wire [3:0]  rgmii_txd_LO_o,
    output wire        rgmii_tx_ctl_HI_o,
    output wire        rgmii_tx_ctl_LO_o,
    output wire        rgmii_txc_HI_o,
    output wire        rgmii_txc_LO_o,
    input  wire [3:0]  rgmii_rxd_HI_i,
    input  wire [3:0]  rgmii_rxd_LO_i,
    input  wire        rgmii_rx_ctl_HI_i,
    input  wire        rgmii_rx_ctl_LO_i,
    input  wire        rgmii_rxc_i,

    // -- MDIO --
    output wire        phy_mdc_o,
    output wire        phy_mdo_o,
    output wire        phy_mdo_en_o,
    input  wire        phy_mdi_i,

    // -- APB3 Slave (从 apb_decoder 来；用于配置 MAC CSR) --
    input  wire [15:0] apb_paddr_i,
    input  wire        apb_psel_i,
    input  wire        apb_penable_i,
    input  wire        apb_pwrite_i,
    input  wire [31:0] apb_pwdata_i,
    output wire [31:0] apb_prdata_o,
    output wire        apb_pready_o,
    output wire        apb_pslverror_o,

    // -- 链路状态（可选观测） --
    output wire [2:0]  eth_speed_o
);

    //==================================================================
    // 1. TSE IP 端口内部 wire
    //==================================================================
    wire        mac_reset;       // MAC 硬复位（高有效）
    wire        proto_reset;     // 协议层软复位（高有效）
    wire        mac_rst_n_int;   // 内部 MAC 复位（低有效）

    // AXI4-Lite（10-bit 地址 / 32-bit 数据，去 TSE CSR）
    wire [9:0]  axi_awaddr;
    wire        axi_awvalid;
    wire        axi_awready;
    wire [31:0] axi_wdata;
    wire        axi_wvalid;
    wire        axi_wready;
    wire        axi_bvalid;
    wire        axi_bready;
    wire [9:0]  axi_araddr;
    wire        axi_arvalid;
    wire        axi_arready;
    wire [1:0]  axi_rresp_unused;   // TSE 输出，桥不消费
    wire [31:0] axi_rdata;
    wire        axi_rvalid;
    wire        axi_rready;

    // 桥不消费 bresp/rresp（这些是 TSE 的输出）；本地 wire 仅吸收 TSE 输出。
    // 注意：test_tse.v 的 s_axi_bresp 端口声明为 1-bit（IPgen quirk），此处跟随。
    wire        axi_bresp_unused;
    wire [3:0]  axi_wstrb_unused;   // 桥输出 wstrb，TSE 不接（仅留观测）

    // AXI4-Stream（8-bit）
    wire        rx_axis_clk;
    wire [7:0]  rx_axis_mac_tdata;
    wire [0:0]  rx_axis_mac_tstrb;
    wire        rx_axis_mac_tvalid;
    wire        rx_axis_mac_tlast;
    wire        rx_axis_mac_tuser;
    wire        rx_axis_mac_tready;

    wire        tx_axis_clk;
    wire [7:0]  tx_axis_mac_tdata;
    wire [0:0]  tx_axis_mac_tstrb;
    wire        tx_axis_mac_tvalid;
    wire        tx_axis_mac_tlast;
    wire        tx_axis_mac_tuser;
    wire        tx_axis_mac_tready;

    wire [2:0]  eth_speed;

    //==================================================================
    // 2. 时钟 / 复位策略
    //   - rx_axis_clk 由 TSE IP 输出（其内部从 rgmii_rxc 重同步出），
    //     但本 bring-up 阶段直接用 mac_clk_i（参考 temac_ex.v 同款做法）。
    //   - tx_axis_clk 同样使用 mac_clk_i。
    //   - mac_reset = !phy_locked（PLL 未锁时整个 MAC 复位）
    //   - proto_reset = mac_sw_rst_i（软件触发的协议层复位）
    //==================================================================
    // TSE IP 的 rx_axis_clk 是 output（MAC 内部根据 rgmii_rxc 产生），但当前
    // bring-up 配置：让 mac_clk_i 作为同步基准（与 s_axi_aclk 同源）。
    // 因此把 IP 输出的 rx_axis_clk 留空观测，本模块对外侧 AXIS 用 mac_clk_i。
    wire unused_rx_axis_clk = rx_axis_clk;

    // TX/RX AXIS 时钟 — 同 mac_clk_i（参考设计 temac_ex.v 一致）
    // 注：s_axi_aclk 也必须等于 mac_clk_i，否则 APB→AXI-Lite 桥跨域。
    wire axis_clk = mac_clk_i;
    assign tx_axis_clk = axis_clk;

    // 复位极性：TSE 的 mac_reset/proto_reset 均为高有效；mac_rst_n_int = !reset
    assign mac_reset   = ~phy_locked_i;
    assign proto_reset = mac_sw_rst_i;
    assign mac_rst_n_int = mac_rst_n_i & ~(mac_reset | proto_reset);

    // PHY 硬复位由顶层独立处理（assign phy_rstn = arst_n）；本模块不涉及

    //==================================================================
    // 3. APB3 → AXI4-Lite 桥（重用 rtl/cdc/apb_to_axilite.sv, AW=10）
    //==================================================================
    apb_to_axilite #(
        .AW ( 10 ),
        .DW ( 32 )
    ) u_apb_axilite (
        .clk_i           ( mac_clk_i    ),
        .rst_n_i         ( mac_rst_n_int),

        .apb_paddr_i     ( apb_paddr_i  ),
        .apb_psel_i      ( apb_psel_i   ),
        .apb_penable_i   ( apb_penable_i),
        .apb_pwrite_i    ( apb_pwrite_i ),
        .apb_pwdata_i    ( apb_pwdata_i ),
        .apb_prdata_o    ( apb_prdata_o ),
        .apb_pready_o    ( apb_pready_o ),
        .apb_pslverror_o ( apb_pslverror_o ),

        .axi_awaddr_o    ( axi_awaddr   ),
        .axi_awvalid_o   ( axi_awvalid  ),
        .axi_awready_i   ( axi_awready  ),
        .axi_wdata_o     ( axi_wdata    ),
        .axi_wstrb_o     ( axi_wstrb_unused ),
        .axi_wvalid_o    ( axi_wvalid   ),
        .axi_wready_i    ( axi_wready   ),
        .axi_bvalid_i    ( axi_bvalid   ),
        .axi_bready_o    ( axi_bready   ),
        .axi_araddr_o    ( axi_araddr   ),
        .axi_arvalid_o   ( axi_arvalid  ),
        .axi_arready_i   ( axi_arready  ),
        .axi_rdata_i     ( axi_rdata    ),
        .axi_rvalid_i    ( axi_rvalid   ),
        .axi_rready_o    ( axi_rready   )
    );
    // axi_wstrb_unused 由桥内部驱动，但 TSE IP 无 wstrb 输入端口；保留观测
    wire unused_wstrb_tie = &axi_wstrb_unused;

    //==================================================================
    // 4. AXI4-Stream 端接（RGMII 直接走管脚；无内环回）
    //   bring-up 阶段的 RX→TX AXIS 环回已移除，MAC 数据通路现在只通过
    //   RGMII 物理管脚与 PHY 交互：
    //     • TX 路径静态 idle（tvalid=0）—— 待 SoC DMA 接管后再驱动。
    //     • RX 路径持续排空（tready=1）—— 接收包直接丢弃，避免 MAC 内部
    //       FIFO 反压或溢出；后续接入 SoC DMA 时由消费侧控制 tready。
    //==================================================================
    assign tx_axis_mac_tdata   = 8'd0;
    assign tx_axis_mac_tstrb   = 1'b0;
    assign tx_axis_mac_tvalid  = 1'b0;
    assign tx_axis_mac_tlast   = 1'b0;
    assign tx_axis_mac_tuser   = 1'b0;
    assign rx_axis_mac_tready  = 1'b1;   // 持续排空 RX，丢弃接收包

    //==================================================================
    // 5. TSE MAC IP 例化
    //==================================================================
    test_tse u_tse (
        .mac_reset           ( mac_reset        ),
        .proto_reset         ( proto_reset      ),

        // AXI4-Lite Slave (CSR)
        .s_axi_aclk          ( mac_clk_i        ),
        .s_axi_awaddr        ( axi_awaddr       ),
        .s_axi_awvalid       ( axi_awvalid      ),
        .s_axi_awready       ( axi_awready      ),
        .s_axi_wdata         ( axi_wdata        ),
        .s_axi_wvalid        ( axi_wvalid       ),
        .s_axi_wready        ( axi_wready       ),
        .s_axi_bresp         ( axi_bresp_unused ),
        .s_axi_bvalid        ( axi_bvalid       ),
        .s_axi_bready        ( axi_bready       ),
        .s_axi_araddr        ( axi_araddr       ),
        .s_axi_arvalid       ( axi_arvalid      ),
        .s_axi_arready       ( axi_arready      ),
        .s_axi_rdata         ( axi_rdata        ),
        .s_axi_rresp         ( axi_rresp_unused ),
        .s_axi_rvalid        ( axi_rvalid       ),
        .s_axi_rready        ( axi_rready       ),

        // MAC 时钟
        .rx_mac_aclk         ( rx_axis_clk      ),   // output（未用，仅观测）
        .tx_mac_aclk         ( axis_clk         ),

        // AXI4-Stream RX (从 MAC 输出)
        .rx_axis_clk         ( axis_clk         ),
        .rx_axis_mac_tdata   ( rx_axis_mac_tdata),
        .rx_axis_mac_tstrb   ( rx_axis_mac_tstrb),
        .rx_axis_mac_tvalid  ( rx_axis_mac_tvalid),
        .rx_axis_mac_tlast   ( rx_axis_mac_tlast),
        .rx_axis_mac_tuser   ( rx_axis_mac_tuser),
        .rx_axis_mac_tready  ( rx_axis_mac_tready),

        // AXI4-Stream TX (送入 MAC)
        .tx_axis_clk         ( tx_axis_clk      ),
        .tx_axis_mac_tdata   ( tx_axis_mac_tdata),
        .tx_axis_mac_tstrb   ( tx_axis_mac_tstrb),
        .tx_axis_mac_tvalid  ( tx_axis_mac_tvalid),
        .tx_axis_mac_tlast   ( tx_axis_mac_tlast),
        .tx_axis_mac_tuser   ( tx_axis_mac_tuser),
        .tx_axis_mac_tready  ( tx_axis_mac_tready),

        // RGMII DDR
        .rgmii_txd_HI        ( rgmii_txd_HI_o   ),
        .rgmii_txd_LO        ( rgmii_txd_LO_o   ),
        .rgmii_tx_ctl_HI     ( rgmii_tx_ctl_HI_o),
        .rgmii_tx_ctl_LO     ( rgmii_tx_ctl_LO_o),
        .rgmii_txc_HI        ( rgmii_txc_HI_o   ),
        .rgmii_txc_LO        ( rgmii_txc_LO_o   ),
        .rgmii_rxd_HI        ( rgmii_rxd_HI_i   ),
        .rgmii_rxd_LO        ( rgmii_rxd_LO_i   ),
        .rgmii_rx_ctl_HI     ( rgmii_rx_ctl_HI_i),
        .rgmii_rx_ctl_LO     ( rgmii_rx_ctl_LO_i),
        .rgmii_rxc           ( rgmii_rxc_i      ),

        // MDIO
        .Mdc                 ( phy_mdc_o        ),
        .Mdo                 ( phy_mdo_o        ),
        .MdoEn               ( phy_mdo_en_o     ),
        .Mdi                 ( phy_mdi_i        ),

        // 链路状态
        .eth_speed           ( eth_speed        )
    );

    assign eth_speed_o = eth_speed;

endmodule

`default_nettype wire
