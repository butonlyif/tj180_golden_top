`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: hard_csi_tx_wrapper
// 功能描述: MIPI CSI-2 TX 硬 IP (hard_csi_tx v5.14) 包装模块。
//           封装 IP 的扁平端口为分组总线（时钟/复位、AXI-Lite、Pixel、
//           DPHY TX 驱动/反馈、IRQ），便于顶层连线。
//           Stage 3 关键策略（IP 已固化 NUM_DATA_LANE=2, HS_DATA_WIDTH=16,
//           PIXEL_FIFO_DEPTH=2048, FRAME_MODE=GENERIC）：
//             · axi_clk       = sys_clk  (CLOCK_FREQ_MHZ=100)
//             · clk_byte_HS   = DPHY TX 输出 byte 时钟（与 RX 共享或独立）
//             · clk_pixel     = clk_pixel_tx（顶层提供，建议 PLL 生成）
//             · clk_esc       = clk_byte_HS（ESC 与 byte HS 同源，简化）
//             · 多 VC vsync/hsync 仅 vc0 使用，vc1..15 拉零
//           内部仅做端口转发与位宽适配，无业务逻辑。
// 接口说明: 详见各分组端口注释
// 设计约束: 三时钟域 (sys/byte_HS/pixel)；复位各域独立同步释放（顶层提供）
//============================================================================
module hard_csi_tx_wrapper (
    //==========================================================
    // 时钟与复位（三域）
    //==========================================================
    input  wire        axi_clk_i,         // = sys_clk  (CLOCK_FREQ_MHZ=100)
    input  wire        axi_rst_n_i,       // sys_clk 域同步释放复位
    input  wire        clk_byte_hs_i,     // DPHY TX byte HS 时钟
    input  wire        rst_byte_hs_n_i,   // byte_HS 域同步释放复位
    input  wire        clk_pixel_i,       // TX pixel 时钟（= clk_pixel_tx）
    input  wire        rst_pixel_n_i,     // pixel 域同步释放复位
    input  wire        rst_n_global_i,    // CSI IP 全局异步复位（直接进 reset_n）

    //==========================================================
    // AXI4-Lite Slave (来自顶层 APB→AXI-Lite 桥或 SoC，sys_clk 域)
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
    // Pixel 输入（pixel 时钟域，来自 loopback_ctrl）
    //==========================================================
    input  wire        pixel_data_valid_i,
    input  wire [63:0] pixel_data_i,
    input  wire [5:0]  datatype_i,
    input  wire [15:0] line_num_i,
    input  wire [15:0] haddr_i,
    input  wire [15:0] frame_num_i,
    input  wire        vsync_vc0_i,
    input  wire        hsync_vc0_i,

    //==========================================================
    // DPHY TX 驱动输出（IP 驱动 → 顶层 peri 端口，2-lane 启用）
    //==========================================================
    output wire [15:0] tx_data_hs0_o,    // lane0 数据 → HS_LAN0_DATA
    output wire [15:0] tx_data_hs1_o,    // lane1 数据 → HS_LAN1_DATA
    output wire [1:0]  tx_request_hs_o,  // {lane1_req, lane0_req}
    output wire        tx_request_hsc_o, // clk lane HS request
    output wire [1:0]  tx_req_valid_hs0_o,  // lane0 valid (DDR 2-bit)
    output wire [1:0]  tx_req_valid_hs1_o,  // lane1 valid (DDR 2-bit)
    output wire [1:0]  tx_skew_cal_hs_o,
    output wire [1:0]  tx_ulps_esc_o,
    output wire [1:0]  tx_ulps_exit_o,
    output wire [1:0]  tx_request_esc_o,
    output wire        tx_ulps_clk_o,
    output wire        tx_ulps_exit_clk_o,

    //==========================================================
    // DPHY TX 反馈输入（顶层 peri 端口 → IP）
    //==========================================================
    input  wire [1:0]  tx_ready_hs_i,    // {lane1_ready, lane0_ready}
    input  wire [1:0]  tx_stop_state_d_i,// {lane1_stop, lane0_stop}
    input  wire        tx_stop_state_c_i,// clk lane stop state
    input  wire [1:0]  tx_ulps_active_not_i,
    input  wire        tx_ulps_active_clk_not_i,

    //==========================================================
    // IRQ (pixel 时钟域，原始电平 — 顶层负责 CDC 到 sys_clk)
    //==========================================================
    output wire        irq_raw_o
);

    //==================================================================
    // 多 VC 同步信号内部 wire（仅 vc0 来自外部；vc1..15 拉零）
    //==================================================================
    wire        vsync_vc1_w,  vsync_vc2_w,  vsync_vc3_w,  vsync_vc4_w;
    wire        vsync_vc5_w,  vsync_vc6_w,  vsync_vc7_w,  vsync_vc8_w;
    wire        vsync_vc9_w,  vsync_vc10_w, vsync_vc11_w, vsync_vc12_w;
    wire        vsync_vc13_w, vsync_vc14_w, vsync_vc15_w;
    wire        hsync_vc1_w,  hsync_vc2_w,  hsync_vc3_w,  hsync_vc4_w;
    wire        hsync_vc5_w,  hsync_vc6_w,  hsync_vc7_w,  hsync_vc8_w;
    wire        hsync_vc9_w,  hsync_vc10_w, hsync_vc11_w, hsync_vc12_w;
    wire        hsync_vc13_w, hsync_vc14_w, hsync_vc15_w;

    //==================================================================
    // IP 输出 wire
    //==================================================================
    wire        irq_w;
    wire [31:0] axi_rdata_w;
    wire        axi_rvalid_w, axi_arready_w, axi_awready_w;
    wire        axi_wready_w, axi_bvalid_w;

    wire [15:0] tx_data_hs0_w, tx_data_hs1_w, tx_data_hs2_w, tx_data_hs3_w;
    wire [15:0] tx_data_hs4_w, tx_data_hs5_w, tx_data_hs6_w, tx_data_hs7_w;
    wire [1:0]  tx_req_valid_hs0_w, tx_req_valid_hs1_w;
    wire [1:0]  tx_req_valid_hs2_w, tx_req_valid_hs3_w;
    wire [1:0]  tx_req_valid_hs4_w, tx_req_valid_hs5_w;
    wire [1:0]  tx_req_valid_hs6_w, tx_req_valid_hs7_w;
    wire [1:0]  tx_request_hs_w, tx_skew_cal_hs_w;
    wire [1:0]  tx_ulps_esc_w, tx_ulps_exit_w, tx_request_esc_w;
    wire        tx_request_hsc_w, tx_ulps_clk_w, tx_ulps_exit_clk_w;

    //==================================================================
    // IP 实例化
    //==================================================================
    hard_csi_tx u_hard_csi_tx (
        // -- 时钟与复位 --
        .reset_byte_HS_n   (rst_byte_hs_n_i),
        .clk_byte_HS       (clk_byte_hs_i),
        .reset_pixel_n     (rst_pixel_n_i),
        .clk_pixel         (clk_pixel_i),

        // -- Pixel 输入 (vc0 + 计数) --
        .pixel_data_valid  (pixel_data_valid_i),
        .pixel_data        (pixel_data_i),
        .datatype          (datatype_i),
        .line_num          (line_num_i),
        .haddr             (haddr_i),
        .frame_num         (frame_num_i),

        // -- 多 VC 同步信号 (仅 vc0 启用) --
        .vsync_vc0         (vsync_vc0_i),
        .vsync_vc1         (1'b0),
        .vsync_vc2         (1'b0),
        .vsync_vc3         (1'b0),
        .vsync_vc4         (1'b0),
        .vsync_vc5         (1'b0),
        .vsync_vc6         (1'b0),
        .vsync_vc7         (1'b0),
        .vsync_vc8         (1'b0),
        .vsync_vc9         (1'b0),
        .vsync_vc10        (1'b0),
        .vsync_vc11        (1'b0),
        .vsync_vc12        (1'b0),
        .vsync_vc13        (1'b0),
        .vsync_vc14        (1'b0),
        .vsync_vc15        (1'b0),
        .hsync_vc0         (hsync_vc0_i),
        .hsync_vc1         (1'b0),
        .hsync_vc2         (1'b0),
        .hsync_vc3         (1'b0),
        .hsync_vc4         (1'b0),
        .hsync_vc5         (1'b0),
        .hsync_vc6         (1'b0),
        .hsync_vc7         (1'b0),
        .hsync_vc8         (1'b0),
        .hsync_vc9         (1'b0),
        .hsync_vc10        (1'b0),
        .hsync_vc11        (1'b0),
        .hsync_vc12        (1'b0),
        .hsync_vc13        (1'b0),
        .hsync_vc14        (1'b0),
        .hsync_vc15        (1'b0),

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

        // -- ESC 层时钟/复位（与 byte HS 同源，简化）--
        .clk_esc           (clk_byte_hs_i),
        .reset_esc_n       (rst_byte_hs_n_i),

        // -- DPHY TX 反馈输入 --
        .TxUlpsActiveClkNot(tx_ulps_active_clk_not_i),
        .TxStopStateD      (tx_stop_state_d_i),
        .TxStopStateC      (tx_stop_state_c_i),
        .TxUlpsActiveNot   (tx_ulps_active_not_i),
        .TxReadyHS         (tx_ready_hs_i),

        // -- DPHY TX 驱动输出 --
        .TxUlpsClk         (tx_ulps_clk_w),
        .TxUlpsExitClk     (tx_ulps_exit_clk_w),
        .TxUlpsEsc         (tx_ulps_esc_w),
        .TxSkewCalHS       (tx_skew_cal_hs_w),
        .TxUlpsExit        (tx_ulps_exit_w),
        .TxRequestEsc      (tx_request_esc_w),
        .TxRequestHS       (tx_request_hs_w),
        .TxRequestHSc      (tx_request_hsc_w),
        .TxDataHS0         (tx_data_hs0_w),
        .TxDataHS1         (tx_data_hs1_w),
        .TxDataHS2         (tx_data_hs2_w),
        .TxDataHS3         (tx_data_hs3_w),
        .TxDataHS4         (tx_data_hs4_w),
        .TxDataHS5         (tx_data_hs5_w),
        .TxDataHS6         (tx_data_hs6_w),
        .TxDataHS7         (tx_data_hs7_w),
        .TxReqValidHS0     (tx_req_valid_hs0_w),
        .TxReqValidHS1     (tx_req_valid_hs1_w),
        .TxReqValidHS2     (tx_req_valid_hs2_w),
        .TxReqValidHS3     (tx_req_valid_hs3_w),
        .TxReqValidHS4     (tx_req_valid_hs4_w),
        .TxReqValidHS5     (tx_req_valid_hs5_w),
        .TxReqValidHS6     (tx_req_valid_hs6_w),
        .TxReqValidHS7     (tx_req_valid_hs7_w),

        // -- IRQ --
        .irq               (irq_w)
    );

    //==================================================================
    // 输出转发
    //==================================================================
    assign axi_awready_o       = axi_awready_w;
    assign axi_wready_o        = axi_wready_w;
    assign axi_bvalid_o        = axi_bvalid_w;
    assign axi_arready_o       = axi_arready_w;
    assign axi_rdata_o         = axi_rdata_w;
    assign axi_rvalid_o        = axi_rvalid_w;

    assign irq_raw_o           = irq_w;

    // 2-lane 启用：lane0/lane1 引出
    assign tx_data_hs0_o       = tx_data_hs0_w;
    assign tx_data_hs1_o       = tx_data_hs1_w;
    assign tx_request_hs_o     = tx_request_hs_w;
    assign tx_request_hsc_o    = tx_request_hsc_w;
    assign tx_req_valid_hs0_o  = tx_req_valid_hs0_w;
    assign tx_req_valid_hs1_o  = tx_req_valid_hs1_w;
    assign tx_skew_cal_hs_o    = tx_skew_cal_hs_w;
    assign tx_ulps_esc_o       = tx_ulps_esc_w;
    assign tx_ulps_exit_o      = tx_ulps_exit_w;
    assign tx_request_esc_o    = tx_request_esc_w;
    assign tx_ulps_clk_o       = tx_ulps_clk_w;
    assign tx_ulps_exit_clk_o  = tx_ulps_exit_clk_w;

    //==================================================================
    // 防未使用 warning（IP 输出 lane2..7，2-lane 配置下未启用）
    //==================================================================
    wire _unused = &{1'b0,
        tx_data_hs2_w, tx_data_hs3_w,
        tx_data_hs4_w, tx_data_hs5_w, tx_data_hs6_w, tx_data_hs7_w,
        tx_req_valid_hs2_w, tx_req_valid_hs3_w,
        tx_req_valid_hs4_w, tx_req_valid_hs5_w, tx_req_valid_hs6_w, tx_req_valid_hs7_w,
        vsync_vc1_w,  vsync_vc2_w,  vsync_vc3_w,  vsync_vc4_w,
        vsync_vc5_w,  vsync_vc6_w,  vsync_vc7_w,  vsync_vc8_w,
        vsync_vc9_w,  vsync_vc10_w, vsync_vc11_w, vsync_vc12_w,
        vsync_vc13_w, vsync_vc14_w, vsync_vc15_w,
        hsync_vc1_w,  hsync_vc2_w,  hsync_vc3_w,  hsync_vc4_w,
        hsync_vc5_w,  hsync_vc6_w,  hsync_vc7_w,  hsync_vc8_w,
        hsync_vc9_w,  hsync_vc10_w, hsync_vc11_w, hsync_vc12_w,
        hsync_vc13_w, hsync_vc14_w, hsync_vc15_w,
        1'b0};

endmodule

`default_nettype wire
