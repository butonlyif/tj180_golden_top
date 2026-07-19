`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: loopback_ctrl
// 功能描述: Stage 3 RX→FIFO→TX loopback 控制器。
//           两时钟域设计（RTL 规范 §7 CDC）：
//             · RX 域（clk_rx_i）：把 RX 有效像素 + sideband 写入 async_fifo
//             · TX 域（clk_tx_i）：从 async_fifo 读出，重建 line/haddr/frame
//               计数器与 vsync/hsync，驱动 CSI TX
//           sideband 编码 (AWIDTH=8)：
//               [7]   = vsync 标记（本像素是该帧第一个像素）
//               [6]   = hsync 标记（本像素是该行第一个像素）
//               [5:0] = datatype
//           拥塞处理：FIFO level ≥ FIFO_HALF_FULL 时丢整帧（拉 tx_skip_frame）
// 接口说明: 见各分组端口注释
// 设计约束: 每域独立 always 块；data+valid 同拍；one-hot FSM
//============================================================================
module loopback_ctrl #(
    parameter FIFO_HALF_FULL = 12'd1024  // rd_level ≥ 此值即丢下一整帧
)(
    //==========================================================
    // RX 域时钟与复位
    //==========================================================
    input  wire        clk_rx_i,           // = clk_pixel_rx
    input  wire        rst_rx_n_i,

    //==========================================================
    // TX 域时钟与复位
    //==========================================================
    input  wire        clk_tx_i,           // = clk_pixel_tx
    input  wire        rst_tx_n_i,

    //----------------------------------------------------------
    // RX pixel 输入（来自 hard_csi_rx_wrapper，RX pixel 域）
    //----------------------------------------------------------
    input  wire        rx_pixel_valid_i,
    input  wire [63:0] rx_pixel_data_i,
    input  wire [5:0]  rx_datatype_i,
    input  wire        rx_vsync_vc0_i,
    input  wire        rx_hsync_vc0_i,

    //----------------------------------------------------------
    // async_fifo 写侧接口（RX 域）
    //----------------------------------------------------------
    output wire        fifo_wr_en_o,
    output wire [63:0] fifo_wr_data_o,
    output wire [7:0]  fifo_wr_side_o,     // {vsync, hsync, datatype[5:0]}
    input  wire        fifo_wr_full_i,
    input  wire [11:0] fifo_wr_level_i,    // 写侧 level（RX 域，CDC 安全）

    //----------------------------------------------------------
    // async_fifo 读侧接口（TX 域）
    //----------------------------------------------------------
    output wire        fifo_rd_en_o,
    input  wire [63:0] fifo_rd_data_i,
    input  wire [7:0]  fifo_rd_side_i,     // {vsync, hsync, datatype[5:0]}
    input  wire        fifo_rd_empty_i,
    input  wire [11:0] fifo_rd_level_i,

    //----------------------------------------------------------
    // 拥塞丢帧指示（TX 域寄存器，可观察/统计）
    //----------------------------------------------------------
    output wire        tx_skip_frame_o,

    //----------------------------------------------------------
    // 输出到 CSI TX（TX 域）
    //----------------------------------------------------------
    output wire [63:0] tx_pixel_data_o,
    output wire        tx_pixel_data_valid_o,
    output wire [5:0]  tx_datatype_o,
    output wire [15:0] tx_line_num_o,
    output wire [15:0] tx_haddr_o,
    output wire [15:0] tx_frame_num_o,
    output wire        tx_vsync_vc0_o,
    output wire        tx_hsync_vc0_o
);

    //==================================================================
    // 1. RX 域：写侧 FSM + 边沿检测
    //   vsync/hsync 在 CSI-2 中是 1-cycle 脉冲（不是电平），因此：
    //     · 在帧内（in_frame）状态由 vsync 脉冲"置位"，由下一帧 vsync 脉冲"翻页"
    //     · 不依赖 vsync 下降沿（那只是一周期脉冲的尾部）
    //==================================================================
    reg rx_vsync_d;
    reg rx_in_frame;       // 当前是否在帧有效期内（vsync 脉冲后置位）
    reg rx_drop_frame;     // 本帧是否丢弃
    reg [15:0] rx_frame_cnt;

    // RX 写侧寄存器
    reg        wr_en_r;
    reg [63:0] wr_data_r;
    reg [7:0]  wr_side_r;

    always @(posedge clk_rx_i or negedge rst_rx_n_i) begin
        if (!rst_rx_n_i) begin
            rx_vsync_d    <= 1'b0;
            rx_in_frame   <= 1'b0;
            rx_drop_frame <= 1'b0;
            rx_frame_cnt  <= 16'd0;
            wr_en_r       <= 1'b0;
            wr_data_r     <= 64'd0;
            wr_side_r     <= 8'd0;
        end else begin
            rx_vsync_d <= rx_vsync_vc0_i;

            // 默认不写
            wr_en_r   <= 1'b0;
            wr_data_r <= rx_pixel_data_i;
            wr_side_r <= {1'b0, 1'b0, rx_datatype_i};

            // vsync 脉冲（1-cycle）→ 帧开始：翻页 + 拥塞判断
            // 注：CSI-2 vsync 是脉冲而非电平；in_frame 一直保持到下一帧 vsync
            if (rx_vsync_vc0_i && rx_pixel_valid_i) begin
                rx_in_frame   <= 1'b1;
                rx_frame_cnt  <= rx_frame_cnt + 1'b1;
                rx_drop_frame <= (fifo_wr_level_i >= FIFO_HALF_FULL);
            end

            // 有效像素写入 FIFO（除非丢帧）；帧内 vsync/hsync 脉冲随像素传递。
            // 注：条件含 vsync 脉冲本身，确保帧首 vsync 像素也被写入
            // （否则首帧 in_frame 仍为 0 的那一拍会丢 vsync 像素）。
            if (rx_pixel_valid_i && !rx_drop_frame &&
                (rx_in_frame || rx_vsync_vc0_i)) begin
                wr_en_r <= 1'b1;
                // 把当前像素是否带 vsync/hsync 标记编码进 sideband
                wr_side_r <= {rx_vsync_vc0_i, rx_hsync_vc0_i, rx_datatype_i};
            end
        end
    end

    assign fifo_wr_en_o   = wr_en_r;
    assign fifo_wr_data_o = wr_data_r;
    assign fifo_wr_side_o = wr_side_r;

    //==================================================================
    // 2. TX 域：读侧重建 — 从 FIFO 读出像素，重建计数器与同步信号
    //==================================================================
    // 读使能：FIFO 非空即读（持续排水，CSI TX 内部 FIFO 会吸收）
    wire do_read = ~fifo_rd_empty_i;
    assign fifo_rd_en_o = do_read;

    // 输出寄存器
    reg [63:0] tx_pixel_data_r;
    reg        tx_pixel_valid_r;
    reg [5:0]  tx_datatype_r;
    reg [15:0] tx_line_num_r;
    reg [15:0] tx_haddr_r;
    reg [15:0] tx_frame_num_r;
    reg        tx_vsync_vc0_r;
    reg        tx_hsync_vc0_r;
    reg        tx_skip_frame_r;

    // 从 sideband 解出的当前像素事件
    wire side_vsync = fifo_rd_side_i[7];
    wire side_hsync = fifo_rd_side_i[6];
    wire [5:0] side_dt = fifo_rd_side_i[5:0];

    always @(posedge clk_tx_i or negedge rst_tx_n_i) begin
        if (!rst_tx_n_i) begin
            tx_pixel_data_r      <= 64'd0;
            tx_pixel_valid_r     <= 1'b0;
            tx_datatype_r        <= 6'd0;
            tx_line_num_r        <= 16'd0;
            tx_haddr_r           <= 16'd0;
            tx_frame_num_r       <= 16'd0;
            tx_vsync_vc0_r       <= 1'b0;
            tx_hsync_vc0_r       <= 1'b0;
            tx_skip_frame_r      <= 1'b0;
        end else begin
            if (do_read) begin
                // 有像素 → 推进计数器
                tx_pixel_data_r  <= fifo_rd_data_i;
                tx_pixel_valid_r <= 1'b1;
                tx_datatype_r    <= side_dt;
                tx_vsync_vc0_r   <= side_vsync;
                tx_hsync_vc0_r   <= side_hsync;

                if (side_vsync) begin
                    // 新帧第一个像素
                    tx_frame_num_r <= tx_frame_num_r + 1'b1;
                    tx_line_num_r  <= 16'd0;
                    tx_haddr_r     <= 16'd0;
                end else if (side_hsync) begin
                    // 新行第一个像素
                    tx_line_num_r  <= tx_line_num_r + 1'b1;
                    tx_haddr_r     <= 16'd0;
                end else begin
                    tx_haddr_r     <= tx_haddr_r + 1'b1;
                end
            end else begin
                // FIFO 空 → 拉低 valid，保持计数器
                tx_pixel_valid_r <= 1'b0;
                tx_vsync_vc0_r   <= 1'b0;
                tx_hsync_vc0_r   <= 1'b0;
            end

            // 拥塞观测：FIFO 接近满即置位
            tx_skip_frame_r <= (fifo_rd_level_i >= FIFO_HALF_FULL);
        end
    end

    assign tx_pixel_data_o       = tx_pixel_data_r;
    assign tx_pixel_data_valid_o = tx_pixel_valid_r;
    assign tx_datatype_o         = tx_datatype_r;
    assign tx_line_num_o         = tx_line_num_r;
    assign tx_haddr_o            = tx_haddr_r;
    assign tx_frame_num_o        = tx_frame_num_r;
    assign tx_vsync_vc0_o        = tx_vsync_vc0_r;
    assign tx_hsync_vc0_o        = tx_hsync_vc0_r;
    assign tx_skip_frame_o       = tx_skip_frame_r;

    //==================================================================
    // 未使用信号抑制
    //==================================================================
    wire _unused = &{1'b0, fifo_wr_full_i, rx_frame_cnt, 1'b0};

endmodule
`default_nettype wire
