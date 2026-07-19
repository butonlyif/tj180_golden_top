`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: mipi_csi_tx_2p5g_wrapper
// 功能描述: MIPI CSI-2 TX 4K-capable 硬 IP (mipi_csi_tx_2p5g v5.14) 包装模块。
//           与 hard_csi_tx_wrapper 同构，但启用 4-lane @ 2.5 Gbps/lane = 10 Gbps
//           （4K60 YUV422 需 7.96 Gbps，余量 26%）。
//
//           参数（IP 内固化的不可改）：
//             NUM_DATA_LANE      = 4
//             HS_BYTECLK_MHZ     = 125     （byte HS 时钟 125 MHz）
//             HS_DATA_WIDTH      = 16
//             PIXEL_FIFO_DEPTH   = 2048
//             FRAME_MODE         = "GENERIC"
//
//           与 hard_csi_tx_wrapper 的差异（仅端口宽度）：
//             · tx_request_hs_o / tx_skew_cal_hs_o / tx_ulps_esc_o /
//               tx_ulps_exit_o   / tx_request_esc_o : [1:0] -> [3:0]
//             · tx_data_hsN_o    / tx_req_valid_hsN_o  : 新增 N=2,3
//             · tx_ready_hs_i / tx_stop_state_d_i / tx_ulps_active_not_i : [1:0] -> [3:0]
//
// 接口说明: 详见各分组端口注释（与 hard_csi_tx_wrapper 一一对应，仅宽度变化）
// 设计约束: 三时钟域 (sys/byte_HS/pixel)；复位各域独立同步释放（顶层提供）
//============================================================================
module mipi_csi_tx_2p5g_wrapper (
    //==========================================================
    // 时钟与复位（三域）
    //==========================================================
    input  wire        axi_clk_i,         // = sys_clk  (CLOCK_FREQ_MHZ=100)
    input  wire        axi_rst_n_i,       // sys_clk 域同步释放复位
    input  wire        clk_byte_hs_i,     // DPHY TX byte HS 时钟 (4K60: 125 MHz)
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
    // DPHY TX 驱动输出（IP 驱动 → 顶层 peri 端口，4-lane 全启用）
    //==========================================================
    output wire [15:0] tx_data_hs0_o,    // lane0 数据 → HS_LAN0_DATA
    output wire [15:0] tx_data_hs1_o,    // lane1 数据 → HS_LAN1_DATA
    output wire [15:0] tx_data_hs2_o,    // lane2 数据 → HS_LAN2_DATA (4K60 新增)
    output wire [15:0] tx_data_hs3_o,    // lane3 数据 → HS_LAN3_DATA (4K60 新增)
    output wire [3:0]  tx_request_hs_o,  // {lane3_req..lane0_req}
    output wire        tx_request_hsc_o, // clk lane HS request
    output wire [1:0]  tx_req_valid_hs0_o,  // lane0 valid (DDR 2-bit)
    output wire [1:0]  tx_req_valid_hs1_o,  // lane1 valid (DDR 2-bit)
    output wire [1:0]  tx_req_valid_hs2_o,  // lane2 valid (4K60 新增)
    output wire [1:0]  tx_req_valid_hs3_o,  // lane3 valid (4K60 新增)
    output wire [3:0]  tx_skew_cal_hs_o,
    output wire [3:0]  tx_ulps_esc_o,
    output wire [3:0]  tx_ulps_exit_o,
    output wire [3:0]  tx_request_esc_o,
    output wire        tx_ulps_clk_o,
    output wire        tx_ulps_exit_clk_o,

    //==========================================================
    // DPHY TX 反馈输入（顶层 peri 端口 → IP）— 4-lane
    //==========================================================
    input  wire [3:0]  tx_ready_hs_i,    // {lane3_ready..lane0_ready}
    input  wire [3:0]  tx_stop_state_d_i,// {lane3_stop..lane0_stop}
    input  wire        tx_stop_state_c_i,// clk lane stop state
    input  wire [3:0]  tx_ulps_active_not_i,
    input  wire        tx_ulps_active_clk_not_i,

    //==========================================================
    // IRQ (pixel 时钟域，原始电平 — 顶层负责 CDC 到 sys_clk)
    //==========================================================
    output wire        irq_raw_o
);

    //==================================================================
    // IP 输出 wire（与 hard_csi_tx IP 一致；TxDataHS0..7 都引出，
    // 4-lane 配置下 lane0..3 走到顶层，lane4..7 进 _unused）
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
    wire [3:0]  tx_request_hs_w, tx_skew_cal_hs_w;
    wire [3:0]  tx_ulps_esc_w, tx_ulps_exit_w, tx_request_esc_w;
    wire        tx_request_hsc_w, tx_ulps_clk_w, tx_ulps_exit_clk_w;

    //==================================================================
    // IP 实例化 — mipi_csi_tx_2p5g (4-lane @ 2.5 Gbps/lane)
    //   IP 端口与 hard_csi_tx 完全一致（已逐端口对照 .sv），只是参数
    //   NUM_DATA_LANE=4 / HS_BYTECLK_MHZ=125 在 IP 内固化。
    //==================================================================
    mipi_csi_tx_2p5g u_mipi_csi_tx_2p5g (
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

        // -- 多 VC 同步信号 (仅 vc0 启用；vc1..15 拉零) --
        .vsync_vc0         (vsync_vc0_i),
        .vsync_vc1         (1'b0),  .vsync_vc2  (1'b0),  .vsync_vc3  (1'b0),
        .vsync_vc4         (1'b0),  .vsync_vc5  (1'b0),  .vsync_vc6  (1'b0),
        .vsync_vc7         (1'b0),  .vsync_vc8  (1'b0),  .vsync_vc9  (1'b0),
        .vsync_vc10        (1'b0),  .vsync_vc11 (1'b0),  .vsync_vc12 (1'b0),
        .vsync_vc13        (1'b0),  .vsync_vc14 (1'b0),  .vsync_vc15 (1'b0),
        .hsync_vc0         (hsync_vc0_i),
        .hsync_vc1         (1'b0),  .hsync_vc2  (1'b0),  .hsync_vc3  (1'b0),
        .hsync_vc4         (1'b0),  .hsync_vc5  (1'b0),  .hsync_vc6  (1'b0),
        .hsync_vc7         (1'b0),  .hsync_vc8  (1'b0),  .hsync_vc9  (1'b0),
        .hsync_vc10        (1'b0),  .hsync_vc11 (1'b0),  .hsync_vc12 (1'b0),
        .hsync_vc13        (1'b0),  .hsync_vc14 (1'b0),  .hsync_vc15 (1'b0),

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
    // 输出转发 — 4-lane 全启用
    //==================================================================
    assign axi_awready_o       = axi_awready_w;
    assign axi_wready_o        = axi_wready_w;
    assign axi_bvalid_o        = axi_bvalid_w;
    assign axi_arready_o       = axi_arready_w;
    assign axi_rdata_o         = axi_rdata_w;
    assign axi_rvalid_o        = axi_rvalid_w;

    assign irq_raw_o           = irq_w;

    // 4-lane 数据 + 控制
    assign tx_data_hs0_o       = tx_data_hs0_w;
    assign tx_data_hs1_o       = tx_data_hs1_w;
    assign tx_data_hs2_o       = tx_data_hs2_w;
    assign tx_data_hs3_o       = tx_data_hs3_w;
    assign tx_request_hs_o     = tx_request_hs_w;       // [3:0]
    assign tx_request_hsc_o    = tx_request_hsc_w;
    assign tx_req_valid_hs0_o  = tx_req_valid_hs0_w;
    assign tx_req_valid_hs1_o  = tx_req_valid_hs1_w;
    assign tx_req_valid_hs2_o  = tx_req_valid_hs2_w;
    assign tx_req_valid_hs3_o  = tx_req_valid_hs3_w;
    assign tx_skew_cal_hs_o    = tx_skew_cal_hs_w;      // [3:0]
    assign tx_ulps_esc_o       = tx_ulps_esc_w;         // [3:0]
    assign tx_ulps_exit_o      = tx_ulps_exit_w;        // [3:0]
    assign tx_request_esc_o    = tx_request_esc_w;      // [3:0]
    assign tx_ulps_clk_o       = tx_ulps_clk_w;
    assign tx_ulps_exit_clk_o  = tx_ulps_exit_clk_w;

    //==================================================================
    // 防未使用 warning（IP 输出 lane4..7，4-lane 配置下未启用；
    // IP 内部多 VC 同步信号 vc1..15 在 IP 端口已直接拉零，无悬空 wire）
    //==================================================================
    wire _unused = &{1'b0,
        tx_data_hs4_w, tx_data_hs5_w, tx_data_hs6_w, tx_data_hs7_w,
        tx_req_valid_hs4_w, tx_req_valid_hs5_w,
        tx_req_valid_hs6_w, tx_req_valid_hs7_w,
        1'b0};

endmodule

`default_nettype wire
