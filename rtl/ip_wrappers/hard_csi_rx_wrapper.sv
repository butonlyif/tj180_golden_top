`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: hard_csi_rx_wrapper
// 功能描述: MIPI CSI-2 RX 硬 IP (hard_csi_rx v5.5.1) 包装模块。
//           封装 IP 的扁平端口为分组总线（时钟/复位、AXI-Lite、DPHY RX、
//           Pixel、IRQ），便于顶层连线。内部仅做端口转发，无业务逻辑。
//           Stage 2 关键策略：
//             · axi_clk       = sys_clk  (CLOCK_FREQ_MHZ=100)
//             · clk_byte_HS   = mipi_dphy_rx_clk_CLKOUT (DPHY 输出)
//             · clk_pixel     = clk_byte_HS (Stage 2 简化，后续可由 PLL 生成)
//             · 仅启用 lane0..3 (NUM_DATA_LANE=4)，lane4..7 拉零
// 接口说明: 详见各分组端口注释
// 设计约束: 三时钟域 (sys/byte_HS/pixel)；复位需各域独立同步释放（由顶层提供）
//============================================================================
module hard_csi_rx_wrapper (
    //==========================================================
    // 时钟与复位（三域）
    //==========================================================
    input  wire        axi_clk_i,         // = sys_clk  (CLOCK_FREQ_MHZ=100)
    input  wire        axi_rst_n_i,       // sys_clk 域同步释放复位
    input  wire        clk_byte_hs_i,     // = mipi_dphy_rx_clk_CLKOUT
    input  wire        rst_byte_hs_n_i,   // byte_HS 域同步释放复位
    input  wire        clk_pixel_i,       // Stage 2 = clk_byte_hs_i
    input  wire        rst_pixel_n_i,     // pixel 域同步释放复位
    input  wire        rst_n_global_i,    // CSI IP 全局异步复位（直接进 reset_n）

    //==========================================================
    // AXI4-Lite Slave (来自 apb_to_axilite 桥，sys_clk 域)
    //==========================================================
    input  wire [5:0]  axi_awaddr_i,
    input  wire        axi_awvalid_i,
    output wire        axi_awready_o,
    input  wire [31:0] axi_wdata_i,
    input  wire        axi_wvalid_i,
    output wire        axi_wready_o,
    input  wire        axi_bready_i,
    output wire        axi_bvalid_o,
    input  wire [5:0]  axi_araddr_i,
    input  wire        axi_arvalid_i,
    output wire        axi_arready_o,
    output wire [31:0] axi_rdata_o,
    output wire        axi_rvalid_o,
    input  wire        axi_rready_i,

    //==========================================================
    // MIPI DPHY RX 输入（顶层 peri 端口直接转发，4-lane 启用）
    //==========================================================
    input  wire        rx_ulps_clk_not_i,        // RxUlpsClkNot
    input  wire        rx_ulps_active_clk_not_i, // RxUlpsActiveClkNot
    input  wire [3:0]  rx_clk_esc_i,             // RxClkEsc
    input  wire [3:0]  rx_err_esc_i,             // RxErrEsc
    input  wire [3:0]  rx_err_control_i,         // RxErrControl
    input  wire [3:0]  rx_err_sot_sync_hs_i,     // RxErrSotSyncHS
    input  wire [3:0]  rx_ulps_esc_i,            // RxUlpsEsc
    input  wire [3:0]  rx_ulps_active_not_i,     // RxUlpsActiveNot
    input  wire [3:0]  rx_skew_cal_hs_i,         // RxSkewCalHS
    input  wire [3:0]  rx_stop_state_i,          // RxStopState
    input  wire [3:0]  rx_sync_hs_i,             // RxSyncHS
    // 4-lane HS 数据（每 lane 16-bit DDR）
    input  wire [15:0] rx_data_hs0_i,
    input  wire [15:0] rx_data_hs1_i,
    input  wire [15:0] rx_data_hs2_i,
    input  wire [15:0] rx_data_hs3_i,
    // 4-lane HS valid
    input  wire [1:0]  rx_valid_hs0_i,
    input  wire [1:0]  rx_valid_hs1_i,
    input  wire [1:0]  rx_valid_hs2_i,
    input  wire [1:0]  rx_valid_hs3_i,

    //==========================================================
    // Pixel 输出 (pixel 时钟域) — Stage 2 仅观测，Stage 3 接 TX
    //==========================================================
    output wire        pixel_data_valid_o,
    output wire [63:0] pixel_data_o,
    output wire [3:0]  pixel_per_clk_o,
    output wire [5:0]  datatype_o,
    output wire [15:0] word_count_o,
    output wire [15:0] shortpkt_data_field_o,
    output wire [1:0]  vc_o,
    output wire [1:0]  vcx_o,
    // 多 VC 同步信号（VC0 主要使用）
    output wire        vsync_vc0_o,
    output wire        hsync_vc0_o,

    //==========================================================
    // IRQ (pixel 时钟域，原始电平 — 顶层负责 CDC 到 sys_clk)
    //==========================================================
    output wire        irq_raw_o
);

    //==================================================================
    // 信号宽度说明：
    //   · CSI IP 端口 RxDataHS4..7 / RxValidHS4..7 因 NUM_DATA_LANE=4
    //     不使用，本模块内部拉零，简化上层连线。
    //   · 多 VC vsync/hsync (vc1..15) 当前未引出，留 IP 内部驱动；
    //     仅 vc0 同步信号作为代表输出供 Stage 2 观测。
    //==================================================================

    // -- IP 内部多 VC 同步信号（仅留必要 wire，其余忽略） --
    wire        vsync_vc1,  vsync_vc2,  vsync_vc3,  vsync_vc4;
    wire        vsync_vc5,  vsync_vc6,  vsync_vc7,  vsync_vc8;
    wire        vsync_vc9,  vsync_vc10, vsync_vc11, vsync_vc12;
    wire        vsync_vc13, vsync_vc14, vsync_vc15;
    wire        hsync_vc1,  hsync_vc2,  hsync_vc3,  hsync_vc4;
    wire        hsync_vc5,  hsync_vc6,  hsync_vc7,  hsync_vc8;
    wire        hsync_vc9,  hsync_vc10, hsync_vc11, hsync_vc12;
    wire        hsync_vc13, hsync_vc14, hsync_vc15;

    // -- IP 输出 wire（pixel/irq）--
    wire        irq_w;
    wire        pixel_data_valid_w;
    wire [63:0] pixel_data_w;
    wire [3:0]  pixel_per_clk_w;
    wire [5:0]  datatype_w;
    wire [15:0] shortpkt_data_field_w;
    wire [15:0] word_count_w;
    wire [1:0]  vcx_w;
    wire [1:0]  vc_w;

    // -- AXI-Lite IP 端口（输出方向）--
    wire        axi_awready_w;
    wire        axi_wready_w;
    wire        axi_bvalid_w;
    wire        axi_arready_w;
    wire [31:0] axi_rdata_w;
    wire        axi_rvalid_w;

    //==================================================================
    // IP 实例化 — 直接端口连接
    //==================================================================
    hard_csi_rx u_hard_csi_rx (
        // -- 时钟与复位 --
        .reset_n           (rst_n_global_i),
        .clk               (axi_clk_i),
        .reset_byte_HS_n   (rst_byte_hs_n_i),
        .clk_byte_HS       (clk_byte_hs_i),
        .reset_pixel_n     (rst_pixel_n_i),
        .clk_pixel         (clk_pixel_i),

        // -- AXI-Lite Slave --
        .axi_clk           (axi_clk_i),
        .axi_reset_n       (axi_rst_n_i),
        .axi_awaddr        (axi_awaddr_i),
        .axi_awvalid       (axi_awvalid_i),
        .axi_awready       (axi_awready_w),
        .axi_wdata         (axi_wdata_i),
        .axi_wvalid        (axi_wvalid_i),
        .axi_wready        (axi_wready_w),
        .axi_bready        (axi_bready_i),
        .axi_bvalid        (axi_bvalid_w),
        .axi_araddr        (axi_araddr_i),
        .axi_arvalid       (axi_arvalid_i),
        .axi_arready       (axi_arready_w),
        .axi_rdata         (axi_rdata_w),
        .axi_rvalid        (axi_rvalid_w),
        .axi_rready        (axi_rready_i),

        // -- DPHY RX 输入 --
        .RxUlpsClkNot      (rx_ulps_clk_not_i),
        .RxUlpsActiveClkNot(rx_ulps_active_clk_not_i),
        .RxClkEsc          (rx_clk_esc_i),
        .RxErrEsc          (rx_err_esc_i),
        .RxErrControl      (rx_err_control_i),
        .RxErrSotSyncHS    (rx_err_sot_sync_hs_i),
        .RxUlpsEsc         (rx_ulps_esc_i),
        .RxUlpsActiveNot   (rx_ulps_active_not_i),
        .RxSkewCalHS       (rx_skew_cal_hs_i),
        .RxStopState       (rx_stop_state_i),
        .RxSyncHS          (rx_sync_hs_i),
        .RxDataHS0         (rx_data_hs0_i),
        .RxDataHS1         (rx_data_hs1_i),
        .RxDataHS2         (rx_data_hs2_i),
        .RxDataHS3         (rx_data_hs3_i),
        .RxDataHS4         (16'h0),
        .RxDataHS5         (16'h0),
        .RxDataHS6         (16'h0),
        .RxDataHS7         (16'h0),
        .RxValidHS0        (rx_valid_hs0_i),
        .RxValidHS1        (rx_valid_hs1_i),
        .RxValidHS2        (rx_valid_hs2_i),
        .RxValidHS3        (rx_valid_hs3_i),
        .RxValidHS4        (2'b00),
        .RxValidHS5        (2'b00),
        .RxValidHS6        (2'b00),
        .RxValidHS7        (2'b00),

        // -- Pixel 输出 --
        .pixel_data_valid  (pixel_data_valid_w),
        .pixel_data        (pixel_data_w),
        .pixel_per_clk     (pixel_per_clk_w),
        .datatype          (datatype_w),
        .shortpkt_data_field(shortpkt_data_field_w),
        .word_count        (word_count_w),
        .vc                (vc_w),
        .vcx               (vcx_w),

        // -- 多 VC 同步信号（IP 输出，本模块仅引出 vc0）--
        .vsync_vc0         (vsync_vc0_o),
        .vsync_vc1         (vsync_vc1),
        .vsync_vc2         (vsync_vc2),
        .vsync_vc3         (vsync_vc3),
        .vsync_vc4         (vsync_vc4),
        .vsync_vc5         (vsync_vc5),
        .vsync_vc6         (vsync_vc6),
        .vsync_vc7         (vsync_vc7),
        .vsync_vc8         (vsync_vc8),
        .vsync_vc9         (vsync_vc9),
        .vsync_vc10        (vsync_vc10),
        .vsync_vc11        (vsync_vc11),
        .vsync_vc12        (vsync_vc12),
        .vsync_vc13        (vsync_vc13),
        .vsync_vc14        (vsync_vc14),
        .vsync_vc15        (vsync_vc15),
        .hsync_vc0         (hsync_vc0_o),
        .hsync_vc1         (hsync_vc1),
        .hsync_vc2         (hsync_vc2),
        .hsync_vc3         (hsync_vc3),
        .hsync_vc4         (hsync_vc4),
        .hsync_vc5         (hsync_vc5),
        .hsync_vc6         (hsync_vc6),
        .hsync_vc7         (hsync_vc7),
        .hsync_vc8         (hsync_vc8),
        .hsync_vc9         (hsync_vc9),
        .hsync_vc10        (hsync_vc10),
        .hsync_vc11        (hsync_vc11),
        .hsync_vc12        (hsync_vc12),
        .hsync_vc13        (hsync_vc13),
        .hsync_vc14        (hsync_vc14),
        .hsync_vc15        (hsync_vc15),

        // -- IRQ --
        .irq               (irq_w)
    );

    //==================================================================
    // 输出转发
    //==================================================================
    assign axi_awready_o          = axi_awready_w;
    assign axi_wready_o           = axi_wready_w;
    assign axi_bvalid_o           = axi_bvalid_w;
    assign axi_arready_o          = axi_arready_w;
    assign axi_rdata_o            = axi_rdata_w;
    assign axi_rvalid_o           = axi_rvalid_w;

    assign pixel_data_valid_o     = pixel_data_valid_w;
    assign pixel_data_o           = pixel_data_w;
    assign pixel_per_clk_o        = pixel_per_clk_w;
    assign datatype_o             = datatype_w;
    assign word_count_o           = word_count_w;
    assign shortpkt_data_field_o  = shortpkt_data_field_w;
    assign vc_o                   = vc_w;
    assign vcx_o                  = vcx_w;
    assign irq_raw_o              = irq_w;

    //==================================================================
    // 防未使用 warning
    //==================================================================
    wire _unused = &{1'b0,
        vsync_vc1,  vsync_vc2,  vsync_vc3,  vsync_vc4,
        vsync_vc5,  vsync_vc6,  vsync_vc7,  vsync_vc8,
        vsync_vc9,  vsync_vc10, vsync_vc11, vsync_vc12,
        vsync_vc13, vsync_vc14, vsync_vc15,
        hsync_vc1,  hsync_vc2,  hsync_vc3,  hsync_vc4,
        hsync_vc5,  hsync_vc6,  hsync_vc7,  hsync_vc8,
        hsync_vc9,  hsync_vc10, hsync_vc11, hsync_vc12,
        hsync_vc13, hsync_vc14, hsync_vc15,
        1'b0};

endmodule

`default_nettype wire
