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

    //----------------------------------------------------------------
    // LOOPBACK_CTRL 旁路寄存器（@ APB offset 0x3F0）
    //   bit[0]   = loopback_en   (RW, reset=1)  -- 1=环回开启, 0=环回关断
    //   bit[1]   = loopback_flush (WO 脉冲)    -- 1=清空环回 FIFO 残留
    //   bit[31:2] = reserved
    // 命中 0x3F0 时拦截 AXI-Lite 事务由旁路寄存器应答；其他地址透传 TSE IP。
    //----------------------------------------------------------------
    localparam [9:0] LOOPBACK_REG_ADDR = 10'h3F0;

    // TSE IP 侧的 AXI-Lite 信号（wrapper 路由/屏蔽后）
    wire        tse_awready;
    wire        tse_wready;
    wire        tse_bvalid;
    wire        tse_arready;
    wire        tse_rvalid;
    wire [31:0] tse_rdata;
    wire        tse_bresp_unused;
    wire [1:0]  tse_rresp_unused;

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
    // 3b. AXI-Lite 路由 + LOOPBACK_CTRL 旁路寄存器
    //   - 命中 0x3F0：旁路寄存器应答（1 拍 ready/valid），TSE 看不到事务
    //   - 其他地址：透传到 TSE IP
    //   - 简化：TSE 永远 ready（避免阻塞），旁路 hit 时由 §3b 寄存器产生 bvalid/rvalid
    //==================================================================
    wire hit_w = axi_awvalid && axi_awready && (axi_awaddr == LOOPBACK_REG_ADDR);
    wire hit_r = axi_arvalid && axi_arready && (axi_araddr == LOOPBACK_REG_ADDR);

    reg [31:0] loopback_ctrl;
    always @(posedge mac_clk_i or negedge mac_rst_n_int) begin
        if (!mac_rst_n_int)
            loopback_ctrl <= 32'h0000_0001;       // bit0 reset=1 (默认开启环回)
        else if (hit_w)
            loopback_ctrl <= axi_wdata;
    end
    wire loopback_en    = loopback_ctrl[0];
    wire loopback_flush = loopback_ctrl[1];

    // bvalid/rvalid 在 hit 后下一拍拉高（与 AXI-Lite 协议匹配）
    reg bvalid_pending;
    reg rvalid_pending;
    reg hit_w_d1;        // hit_w 延迟一拍，用于屏蔽 wvalid
    always @(posedge mac_clk_i or negedge mac_rst_n_int) begin
        if (!mac_rst_n_int) begin
            bvalid_pending <= 1'b0;
            rvalid_pending <= 1'b0;
            hit_w_d1       <= 1'b0;
        end else begin
            bvalid_pending <= hit_w;
            rvalid_pending <= hit_r;
            hit_w_d1       <= hit_w;
        end
    end

    // 桥侧 ready/valid/data 仲裁
    assign axi_awready = 1'b1;        // 永远 ready（tse 永远 ready，命中时旁路也立刻响应）
    assign axi_arready = 1'b1;
    assign axi_wready  = 1'b1;
    assign axi_bvalid  = bvalid_pending | tse_bvalid;
    assign axi_rvalid  = rvalid_pending | tse_rvalid;
    assign axi_rdata   = rvalid_pending ? loopback_ctrl : tse_rdata;
    assign axi_bready  = 1'b1;
    assign axi_rready  = 1'b1;

    //==================================================================
    // 4. AXI4-Stream 端接 + 可关断 RX→TX 内环回（mac_rx2tx）
    //   默认 loopback_en=1（上电即开启环回，便于 bring-up 自检 PHY 通路）：
    //     PHY RX → RGMII → TSE 解包 → mac_rx2tx FIFO → TSE 打包 → RGMII TX → PHY
    //   等 SoC DMA/AXIS 控制器就绪后，软件写 LOOPBACK_CTRL[0]=0 关断：
    //     • TX 端 tvalid=0 沉默，RX 端 tready=1 持续排空（mac_rx2tx 内部自动处理）
    //     • 环回 FIFO 仍 rd_en=1 → 自动清残留
    //   软件可脉冲写 LOOPBACK_CTRL[1]=1 强制同步复位 FIFO（立即清空，不等自然消费）
    //   旁路寄存器 reset=1：上电即环回（bring-up 默认）
    //==================================================================
    mac_rx2tx #(
        .FIFO_AW ( 11 )                  // 深度 2048
    ) u_mac_rx2tx (
        .clk_i                 ( axis_clk       ),
        .rst_n_i               ( mac_rst_n_int  ),

        .loopback_en_i         ( loopback_en    ),
        .loopback_flush_i      ( loopback_flush ),

        // RX AXIS（来自 TSE IP，wrapper 内部 wire rx_axis_mac_t*）
        .rx_axis_mac_tdata_i   ( rx_axis_mac_tdata ),
        .rx_axis_mac_tvalid_i  ( rx_axis_mac_tvalid ),
        .rx_axis_mac_tlast_i   ( rx_axis_mac_tlast ),
        .rx_axis_mac_tuser_i   ( rx_axis_mac_tuser ),
        .rx_axis_mac_tready_o  ( rx_axis_mac_tready ),

        // TX AXIS（送回 TSE IP）
        .tx_axis_mac_tdata_o   ( tx_axis_mac_tdata ),
        .tx_axis_mac_tvalid_o  ( tx_axis_mac_tvalid ),
        .tx_axis_mac_tlast_o   ( tx_axis_mac_tlast ),
        .tx_axis_mac_tuser_o   ( tx_axis_mac_tuser ),
        .tx_axis_mac_tready_i  ( tx_axis_mac_tready )
    );

    assign tx_axis_mac_tstrb = 1'b0;    // TSE IP tstrb 1-bit 输入，固定 0

    //==================================================================
    // 5. TSE MAC IP 例化
    //   AXI-Lite 路由：命中 0x3F0 → 旁路寄存器（已在 §3b 应答），TSE 屏蔽
    //==================================================================
    test_tse u_tse (
        .mac_reset           ( mac_reset        ),
        .proto_reset         ( proto_reset      ),

        // AXI4-Lite Slave (CSR) — 0x3F0 已在 §3b 拦截，tse_axi_*_valid 屏蔽
        .s_axi_aclk          ( mac_clk_i        ),
        .s_axi_awaddr        ( axi_awaddr       ),
        .s_axi_awvalid       ( axi_awvalid && (axi_awaddr != LOOPBACK_REG_ADDR) ),  // 屏蔽 0x3F0
        .s_axi_awready       ( tse_awready      ),
        .s_axi_wdata         ( axi_wdata        ),
        .s_axi_wvalid        ( axi_wvalid && ~hit_w_d1 ),                            // 屏蔽 0x3F0 写数据
        .s_axi_wready        ( tse_wready       ),
        .s_axi_bresp         ( tse_bresp_unused ),
        .s_axi_bvalid        ( tse_bvalid       ),
        .s_axi_bready        ( axi_bready       ),
        .s_axi_araddr        ( axi_araddr       ),
        .s_axi_arvalid       ( axi_arvalid && (axi_araddr != LOOPBACK_REG_ADDR) ),
        .s_axi_arready       ( tse_arready      ),
        .s_axi_rdata         ( tse_rdata        ),
        .s_axi_rresp         ( tse_rresp_unused ),
        .s_axi_rvalid        ( tse_rvalid       ),
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
