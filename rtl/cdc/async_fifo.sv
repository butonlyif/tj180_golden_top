`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: async_fifo
// 功能描述: 标准 dual-clock 异步 FIFO — Stage 3 RX→TX pixel 跨时钟域桥。
//           - 双口 BRAM 存储，深度 = 2^AW
//           - 写/读指针用 Gray 码跨域同步（ASYNC_REG 链 2~3 级）
//           - 输出寄存器（BRAM 免费寄存器）+ FWFT (First-Word Fall-Through)
//           - 保守判断 full / empty，杜绝满写空读
// 接口说明: 写侧 _wr_*_i/_o (RX 域)；读侧 _rd_*_o/_i (TX 域)
// 设计约束: DW=64 (pixel_data), AW=11 (depth 2048), AWIDTH=6 (sideband)
//           见 RTL 规范 §7 CDC + §8 BRAM
//============================================================================
module async_fifo #(
    parameter DW    = 64,        // 数据位宽
    parameter AW    = 11,        // 地址位宽 → 深度 = 2^AW = 2048
    parameter AWIDTH = 6,        // sideband 宽度 (datatype[5:0] 或 ctrl)
    parameter SYNC_DEPTH = 2     // 指针同步链级数
)(
    //==========================================================
    // 写侧（RX 域 clk_pixel_rx）
    //==========================================================
    input  wire                wr_clk_i,
    input  wire                wr_rst_n_i,
    input  wire                wr_en_i,
    input  wire [DW-1:0]       wr_data_i,
    input  wire [AWIDTH-1:0]   wr_side_i,
    output wire                wr_full_o,
    output wire [AW:0]         wr_level_o,       // 写侧剩余容量（写域安全）

    //==========================================================
    // 读侧（TX 域 clk_pixel_tx）
    //==========================================================
    input  wire                rd_clk_i,
    input  wire                rd_rst_n_i,
    input  wire                rd_en_i,
    output wire [DW-1:0]       rd_data_o,
    output wire [AWIDTH-1:0]   rd_side_o,
    output wire                rd_empty_o,
    output wire [AW:0]         rd_level_o       // 用于半满/拥塞判断
);

    //==================================================================
    // 1. BRAM 存储体（强制 block_ram，输出寄存器免费用）
    //==================================================================
    (* ram_style = "block" *) reg [DW-1:0]      mem [0:(1<<AW)-1];
    (* ram_style = "block" *) reg [AWIDTH-1:0]  side_mem [0:(1<<AW)-1];

    //==================================================================
    // 2. 写指针（二进制 + Gray）— RX 域
    //==================================================================
    reg  [AW:0] wr_bin;
    reg  [AW:0] wr_gray;
    wire [AW:0] wr_bin_next;
    wire [AW:0] wr_gray_next;
    wire        do_write;

    assign do_write   = wr_en_i & ~wr_full_o;
    assign wr_bin_next  = wr_bin + (do_write ? 1'b1 : 1'b0);
    assign wr_gray_next = wr_bin_next ^ (wr_bin_next >> 1);

    always @(posedge wr_clk_i or negedge wr_rst_n_i) begin
        if (!wr_rst_n_i) begin
            wr_bin  <= {(AW+1){1'b0}};
            wr_gray <= {(AW+1){1'b0}};
        end else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end
    end

    // 双口 BRAM 写
    always @(posedge wr_clk_i) begin
        if (do_write) begin
            mem[wr_bin[AW-1:0]]      <= wr_data_i;
            side_mem[wr_bin[AW-1:0]] <= wr_side_i;
        end
    end

    //==================================================================
    // 3. 读指针（二进制 + Gray）— TX 域
    //==================================================================
    reg  [AW:0] rd_bin;
    reg  [AW:0] rd_gray;
    wire [AW:0] rd_bin_next;
    wire [AW:0] rd_gray_next;
    wire        do_read;

    assign do_read   = rd_en_i & ~rd_empty_o;
    assign rd_bin_next  = rd_bin + (do_read ? 1'b1 : 1'b0);
    assign rd_gray_next = rd_bin_next ^ (rd_bin_next >> 1);

    always @(posedge rd_clk_i or negedge rd_rst_n_i) begin
        if (!rd_rst_n_i) begin
            rd_bin  <= {(AW+1){1'b0}};
            rd_gray <= {(AW+1){1'b0}};
        end else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    //==================================================================
    // 4. 指针 CDC 同步（Gray 码 → 多级 FF 链）
    //==================================================================
    // 写指针 → 读时钟域
    (* ASYNC_REG = "TRUE" *) reg [AW:0] wr_gray_sync [0:SYNC_DEPTH-1];
    always @(posedge rd_clk_i or negedge rd_rst_n_i) begin
        integer i;
        if (!rd_rst_n_i) begin
            for (i = 0; i < SYNC_DEPTH; i = i + 1)
                wr_gray_sync[i] <= {(AW+1){1'b0}};
        end else begin
            wr_gray_sync[0] <= wr_gray;
            for (i = 1; i < SYNC_DEPTH; i = i + 1)
                wr_gray_sync[i] <= wr_gray_sync[i-1];
        end
    end
    wire [AW:0] wr_gray_in_rd = wr_gray_sync[SYNC_DEPTH-1];

    // 读指针 → 写时钟域
    (* ASYNC_REG = "TRUE" *) reg [AW:0] rd_gray_sync [0:SYNC_DEPTH-1];
    always @(posedge wr_clk_i or negedge wr_rst_n_i) begin
        integer j;
        if (!wr_rst_n_i) begin
            for (j = 0; j < SYNC_DEPTH; j = j + 1)
                rd_gray_sync[j] <= {(AW+1){1'b0}};
        end else begin
            rd_gray_sync[0] <= rd_gray;
            for (j = 1; j < SYNC_DEPTH; j = j + 1)
                rd_gray_sync[j] <= rd_gray_sync[j-1];
        end
    end
    wire [AW:0] rd_gray_in_wr = rd_gray_sync[SYNC_DEPTH-1];

    //==================================================================
    // 5. full / empty 判断（保守）
    //   empty : rd_gray == wr_gray_synced
    //   full  : 高位取反相等 + 其余相同 (MSB / 次高位不同模式)
    //==================================================================
    // empty 比较的是同步过来的写指针
    assign rd_empty_o = (rd_gray == wr_gray_in_rd);

    // full: 写指针追上读指针一圈，二进制最高位不同，其余相同
    //       等价 Gray 比较：wr_bin[AW] != rd_bin[AW] 且 wr_bin[AW-1:0] == rd_bin[AW-1:0]
    //       Gray 码下 = wr_gray == {~rd_gray[AW:AW-1], rd_gray[AW-2:0]}
    wire [AW:0] full_cmp = {~rd_gray_in_wr[AW:AW-1], rd_gray_in_wr[AW-2:0]};
    assign wr_full_o = (wr_gray == full_cmp);

    //==================================================================
    // 6. BRAM 读 + 输出寄存器（FWFT 模式）
    //   读地址用 rd_bin_next（提前一拍，配输出寄存器实现 FWFT）
    //==================================================================
    reg [DW-1:0]      rd_data_r;
    reg [AWIDTH-1:0]  rd_side_r;

    always @(posedge rd_clk_i) begin
        // 用下一拍地址读，结果落到输出寄存器
        rd_data_r <= mem[rd_bin_next[AW-1:0]];
        rd_side_r <= side_mem[rd_bin_next[AW-1:0]];
    end

    assign rd_data_o = rd_data_r;
    assign rd_side_o = rd_side_r;

    //==================================================================
    // 7. 读侧 level (占用数) — 供 loopback_ctrl 拥塞判断
    //   注意: 这是基于同步后指针的近似值，瞬间误差 ≤ SYNC_DEPTH 个；
    //         仅用于半满门限判断（保守），不用作精确计数。
    //==================================================================
    // 把同步后的 Gray 还原回二进制近似计数
    // Gray→Bin 函数式
    function [AW:0] g2b;
        input [AW:0] g;
        integer k;
        begin
            g2b[AW] = g[AW];
            for (k = AW-1; k >= 0; k = k - 1)
                g2b[k] = g2b[k+1] ^ g[k];
        end
    endfunction

    wire [AW:0] wr_bin_in_rd = g2b(wr_gray_in_rd);
    wire [AW:0] rd_level_raw = wr_bin_in_rd - rd_bin;
    assign rd_level_o = rd_level_raw;

    //==================================================================
    // 8. 写侧 level (已写入但未读出) — 写域安全，供 RX 端拥塞判断
    //==================================================================
    wire [AW:0] rd_bin_in_wr = g2b(rd_gray_in_wr);
    wire [AW:0] wr_level_raw = wr_bin - rd_bin_in_wr;
    assign wr_level_o = wr_level_raw;

endmodule

`default_nettype wire
