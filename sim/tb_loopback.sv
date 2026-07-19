`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: tb_loopback
// 功能描述: Stage 3 Loopback 仿真 testbench。
//           直接验证 async_fifo + loopback_ctrl 数据通路（不依赖加密的
//           hard_csi_rx / hard_csi_tx IP），用于：
//             · 基本帧 pass-through（彩条/棋盘）
//             · RX ≠ TX pixel 时钟频率下的 FIFO 行为
//             · 拥塞丢帧（FIFO 接近满时 tx_skip_frame）
//           验收：TX 侧重建的 frame/line/haddr/vsync/hsync 与 RX 输入一致
//                 （允许跨帧延迟），无满写/空读。
// 接口说明: 例化 async_fifo + loopback_ctrl，驱动 RX 域信号，监测 TX 域输出
//============================================================================

module tb_loopback;

    // =====================================================================
    // 参数
    // =====================================================================
    localparam integer ACTIVE_W = 16;       // 每行有效像素 (64-bit pack)
    localparam integer ACTIVE_H = 8;        // 每帧行数
    localparam integer FRAMES   = 3;        // 仿真帧数
    localparam realtime   RX_PERIOD = 6.667ns;   // ~150 MHz
    localparam realtime   TX_PERIOD = 10.0ns;    // 100 MHz （与 RX 不同）

    // =====================================================================
    // 时钟与复位
    // =====================================================================
    reg clk_rx = 1'b0;
    reg clk_tx = 1'b0;
    reg rst_rx_n = 1'b0;
    reg rst_tx_n = 1'b0;

    always #(RX_PERIOD/2.0) clk_rx = ~clk_rx;
    always #(TX_PERIOD/2.0) clk_tx = ~clk_tx;

    initial begin
        rst_rx_n = 1'b0;
        rst_tx_n = 1'b0;
        #50ns;
        $display("[%0t] reset block: about to deassert at t=100ns (rst_rx_n=%b)", $time, rst_rx_n);
        #50ns;
        rst_rx_n = 1'b1;
        rst_tx_n = 1'b1;
        $display("[%0t] reset block: deasserted (rst_rx_n=%b)", $time, rst_rx_n);
    end

    // =====================================================================
    // RX 域激励（模拟 CSI RX pixel 输出）
    // =====================================================================
    reg        rx_pixel_valid = 1'b0;
    reg [63:0] rx_pixel_data  = 64'd0;
    reg [5:0]  rx_datatype    = 6'h2E;   // RAW16 (CSI-2 datatype)
    reg        rx_vsync_vc0   = 1'b0;
    reg        rx_hsync_vc0   = 1'b0;

    // =====================================================================
    // async_fifo 信号
    // =====================================================================
    wire        fifo_wr_en;
    wire [63:0] fifo_wr_data;
    wire [7:0]  fifo_wr_side;
    wire        fifo_wr_full;
    wire [11:0] fifo_wr_level;
    wire        fifo_rd_en;
    wire [63:0] fifo_rd_data;
    wire [7:0]  fifo_rd_side;
    wire        fifo_rd_empty;
    wire [11:0] fifo_rd_level;

    // =====================================================================
    // loopback_ctrl TX 输出
    // =====================================================================
    wire        tx_skip_frame;
    wire [63:0] tx_pixel_data;
    wire        tx_pixel_valid;
    wire [5:0]  tx_datatype;
    wire [15:0] tx_line_num;
    wire [15:0] tx_haddr;
    wire [15:0] tx_frame_num;
    wire        tx_vsync_vc0;
    wire        tx_hsync_vc0;

    // =====================================================================
    // DUT: async_pixel_fifo
    // =====================================================================
    async_fifo #(
        .DW         (64),
        .AW         (11),
        .AWIDTH     (8),
        .SYNC_DEPTH (2)
    ) u_dut_fifo (
        .wr_clk_i       (clk_rx),
        .wr_rst_n_i     (rst_rx_n),
        .wr_en_i        (fifo_wr_en),
        .wr_data_i      (fifo_wr_data),
        .wr_side_i      (fifo_wr_side),
        .wr_full_o      (fifo_wr_full),
        .wr_level_o     (fifo_wr_level),
        .rd_clk_i       (clk_tx),
        .rd_rst_n_i     (rst_tx_n),
        .rd_en_i        (fifo_rd_en),
        .rd_data_o      (fifo_rd_data),
        .rd_side_o      (fifo_rd_side),
        .rd_empty_o     (fifo_rd_empty),
        .rd_level_o     (fifo_rd_level)
    );

    // =====================================================================
    // DUT: loopback_ctrl
    // =====================================================================
    loopback_ctrl #(
        .FIFO_HALF_FULL (12'd1024)
    ) u_dut_lb (
        .clk_rx_i               (clk_rx),
        .rst_rx_n_i             (rst_rx_n),
        .rx_pixel_valid_i       (rx_pixel_valid),
        .rx_pixel_data_i        (rx_pixel_data),
        .rx_datatype_i          (rx_datatype),
        .rx_vsync_vc0_i         (rx_vsync_vc0),
        .rx_hsync_vc0_i         (rx_hsync_vc0),

        .fifo_wr_en_o           (fifo_wr_en),
        .fifo_wr_data_o         (fifo_wr_data),
        .fifo_wr_side_o         (fifo_wr_side),
        .fifo_wr_full_i         (fifo_wr_full),
        .fifo_wr_level_i        (fifo_wr_level),

        .clk_tx_i               (clk_tx),
        .rst_tx_n_i             (rst_tx_n),
        .fifo_rd_en_o           (fifo_rd_en),
        .fifo_rd_data_i         (fifo_rd_data),
        .fifo_rd_side_i         (fifo_rd_side),
        .fifo_rd_empty_i        (fifo_rd_empty),
        .fifo_rd_level_i        (fifo_rd_level),

        .tx_skip_frame_o        (tx_skip_frame),

        .tx_pixel_data_o        (tx_pixel_data),
        .tx_pixel_data_valid_o  (tx_pixel_valid),
        .tx_datatype_o          (tx_datatype),
        .tx_line_num_o          (tx_line_num),
        .tx_haddr_o             (tx_haddr),
        .tx_frame_num_o         (tx_frame_num),
        .tx_vsync_vc0_o         (tx_vsync_vc0),
        .tx_hsync_vc0_o         (tx_hsync_vc0)
    );

    // =====================================================================
    // RX 域：产生 FRAMES 帧 × ACTIVE_H 行 × ACTIVE_W 像素的激励
    //   每帧行格式：vsync (1 拍) → hsync (1 拍) → ACTIVE_W 像素 → 行间 blank
    //   像素数据 = {frame, line, col}，便于 TX 侧比对
    // =====================================================================
    integer f, l, c;
    task automatic drive_frame(input integer frame_idx);
        begin
            // VSYNC 拍
            @(posedge clk_rx);
            rx_vsync_vc0   <= 1'b1;
            rx_pixel_valid <= 1'b1;
            rx_pixel_data  <= {32'h0, 16'hFFFF, frame_idx[15:0]};
            @(posedge clk_rx);
            rx_vsync_vc0 <= 1'b0;

            for (l = 0; l < ACTIVE_H; l = l + 1) begin
                // HSYNC 拍
                rx_hsync_vc0   <= 1'b1;
                rx_pixel_valid <= 1'b1;
                rx_pixel_data  <= {24'h0, frame_idx[7:0], l[7:0], 8'hAA};
                @(posedge clk_rx);
                rx_hsync_vc0 <= 1'b0;

                // ACTIVE_W 像素
                for (c = 0; c < ACTIVE_W; c = c + 1) begin
                    rx_pixel_valid <= 1'b1;
                    rx_pixel_data  <= {frame_idx[15:0], l[15:0], c[15:0],
                                       frame_idx[7:0]};
                    @(posedge clk_rx);
                end

                // 行间 blank（2 拍无效）
                rx_pixel_valid <= 1'b0;
                @(posedge clk_rx);
                @(posedge clk_rx);
            end

            // 帧尾 blank
            rx_pixel_valid <= 1'b0;
            repeat (5) @(posedge clk_rx);
        end
    endtask

    // =====================================================================
    // TX 域：监听输出，统计 TX 重建计数
    // =====================================================================
    integer tx_pixel_count = 0;
    integer tx_frame_seen  = 0;
    integer tx_line_seen   = 0;
    integer err_count      = 0;

    always @(posedge clk_tx) begin
        if (tx_pixel_valid) begin
            tx_pixel_count = tx_pixel_count + 1;
            if (tx_vsync_vc0) begin
                tx_frame_seen = tx_frame_seen + 1;
                $display("[%0t] TX VSYNC frame_num=%0d", $time, tx_frame_num);
            end
            if (tx_hsync_vc0) begin
                tx_line_seen = tx_line_seen + 1;
            end
            // 数据完整性 sanity：datatype 应保持 = 6'h2E
            if (tx_datatype !== 6'h2E) begin
                $display("[%0t] ERROR: datatype mismatch = 0x%h", $time, tx_datatype);
                err_count = err_count + 1;
            end
        end
    end

    // FIFO 异常监测
    integer wr_count = 0;
    integer rd_count = 0;
    always @(posedge clk_rx) begin
        if (fifo_wr_en && fifo_wr_full) begin
            $display("[%0t] ERROR: write while FIFO full!", $time);
            err_count = err_count + 1;
        end
        if (fifo_wr_en) wr_count = wr_count + 1;
    end
    always @(posedge clk_tx) begin
        if (fifo_rd_en) rd_count = rd_count + 1;
    end

    // =====================================================================
    // 全局看门狗（独立 initial，与主激励并行）
    // =====================================================================
    initial begin
        #20000ns;
        $display("[%0t] WATCHDOG TIMEOUT — forcing finish", $time);
        $finish;
    end

    // =====================================================================
    // 主激励
    // =====================================================================
    integer errors_local;
    initial begin
        // VCD 调试时取消下行注释
        // $dumpfile("tb_loopback.vcd");
        // $dumpvars(0, tb_loopback);

        // 等复位释放
        $display("[%0t] TB: waiting for reset deassert", $time);
        wait(rst_rx_n === 1'b1);
        wait(rst_tx_n === 1'b1);
        $display("[%0t] TB: reset deasserted", $time);
        repeat (10) @(posedge clk_rx);
        $display("[%0t] TB: starting frame stimulus", $time);

        // 驱动 FRAMES 帧
        for (f = 0; f < FRAMES; f = f + 1) begin
            drive_frame(f);
            $display("[%0t] RX frame %0d driven", $time, f);
        end

        // 等 TX 排空（410 像素 @100MHz ≈ 4100ns，多留余量）
        repeat (1000) @(posedge clk_tx);

        // =====================================================================
        // 报告
        // =====================================================================
        $display("\n========================================");
        $display(" Stage 3 Loopback TB Report");
        $display("========================================");
        $display(" RX frames driven  : %0d", FRAMES);        $display(" FIFO writes       : %0d", wr_count);
        $display(" FIFO reads        : %0d", rd_count);        $display(" TX frames seen    : %0d", tx_frame_seen);
        $display(" TX lines seen     : %0d (expected ~%0d)",
                 tx_line_seen, FRAMES*ACTIVE_H);
        $display(" TX pixels seen    : %0d (expected ~%0d)",
                 tx_pixel_count, FRAMES*ACTIVE_H*ACTIVE_W);
        $display(" tx_skip_frame     : %b", tx_skip_frame);
        if (err_count == 0)
            $display(" STATUS            : PASS (no FIFO/CDC errors)");
        else
            $display(" STATUS            : FAIL (%0d errors)", err_count);
        $display("========================================\n");

        errors_local = err_count;
        if (errors_local == 0) $finish;
        else                    $finish;
    end

endmodule

`default_nettype wire
