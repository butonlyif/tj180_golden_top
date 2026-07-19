`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: mac_rx2tx
// 功能描述: TSE MAC 的 RX→TX 内环回 FIFO，带可关断控制。
//           - 接收 TSE IP 的 rx_axis_*（来自 RGMII RX 解包后的以太网帧）
//           - 经 10-bit × 2048 同步 FIFO（{tuser,tlast,tdata[7:0]}）跨拍缓冲
//           - 输出 tx_axis_* 送回 TSE IP → RGMII TX 发出
//           - 复位（rst_n_i）与 axis_clk 同步同源（= mac_clk_i，本 wrapper 内
//             rx_axis_clk == tx_axis_clk == mac_clk_i，因此 FIFO 单时钟运行；
//             同源退化用项目自研 async_fifo 即 OK）
//           - loopback_en_i = 0：TX 端 tvalid=0 沉默（不向 MAC 灌数据）；
//                                FIFO rd_en 持续拉高清残留 → 自动清空
//           - loopback_en_i = 1：正常环回（rd_en 由 tx_axis_mac_tready 仲裁）
//           - loopback_flush_i：单拍脉冲，把 FIFO 写指针同步复位，立即清空
// 接口说明:
//   • clk_i / rst_n_i    — mac_clk_i / mac_rst_n_int（与 TSE IP 一致）
//   • loopback_en_i      — 来自 LOOPBACK_CTRL[0]，reset 默认 = 1（上电开启）
//   • loopback_flush_i   — 来自 LOOPBACK_CTRL[1]，WO 脉冲，软件触发
//   • rx_axis_*_i/o      — 从 TSE IP 的 RX AXIS 输出
//   • tx_axis_*_o/i      — 送回 TSE IP 的 TX AXIS 输入
// 设计约束:
//   • 单时钟域（rx_axis_clk == tx_axis_clk == clk_i），无 CDC
//   • DW=10 = {tuser, tlast, tdata[7:0]}；AW=11 → 深度 2048
//   • 2048 × 10bit = 20 Kbit ≈ 5 BRAM（Efinity BRAM 9Kbit 单元）
//   • 关断路径不丢弃 RGMII 物理层（PHY 仍上报 link），仅停送 AXIS 数据
//============================================================================
module mac_rx2tx #(
    parameter FIFO_AW = 11     // 深度 2^AW = 2048；与 devkit mac_rx2tx 一致
)(
    // -- 时钟 / 复位 --
    input  wire        clk_i,
    input  wire        rst_n_i,

    // -- 环回控制（来自 LOOPBACK_CTRL 寄存器） --
    input  wire        loopback_en_i,     // 1=环回开启, 0=TX 沉默
    input  wire        loopback_flush_i,  // 1=脉冲清空 FIFO（单拍自清）

    // -- RX AXIS（来自 TSE IP） --
    input  wire [7:0]  rx_axis_mac_tdata_i,
    input  wire        rx_axis_mac_tvalid_i,
    input  wire        rx_axis_mac_tlast_i,
    input  wire        rx_axis_mac_tuser_i,
    output wire        rx_axis_mac_tready_o,

    // -- TX AXIS（送回 TSE IP） --
    output wire [7:0]  tx_axis_mac_tdata_o,
    output wire        tx_axis_mac_tvalid_o,
    output wire        tx_axis_mac_tlast_o,
    output wire        tx_axis_mac_tuser_o,
    input  wire        tx_axis_mac_tready_i
);

    //==================================================================
    // 1. flush 控制：loopback_flush_i 单拍脉冲 → FIFO 复位 8 拍
    //    async_fifo 的 wr_rst_n_i/rd_rst_n_i 拉低即可复位双指针
    //==================================================================
    reg        flush_pending;
    reg [3:0]  flush_cnt;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            flush_pending <= 1'b0;
            flush_cnt     <= 4'h0;
        end else begin
            if (loopback_flush_i) begin
                flush_pending <= 1'b1;
                flush_cnt     <= 4'd8;       // 8 拍足以让 CDC 同步链稳定
            end else if (flush_cnt != 4'h0) begin
                flush_cnt     <= flush_cnt - 1'b1;
                flush_pending <= 1'b1;
            end else begin
                flush_pending <= 1'b0;
            end
        end
    end
    wire fifo_rst_n = rst_n_i & ~flush_pending;

    //==================================================================
    // 2. FIFO I/O
    //==================================================================
    wire        wr_en;
    wire        rd_en;
    wire [9:0]  wr_data;
    wire [9:0]  rd_data;
    wire        wr_full;
    wire        rd_empty;

    // -- 写侧：valid & ready 握手 --
    assign wr_en   = rx_axis_mac_tvalid_i & ~wr_full;
    assign wr_data = {rx_axis_mac_tuser_i, rx_axis_mac_tlast_i, rx_axis_mac_tdata_i};
    assign rx_axis_mac_tready_o = ~wr_full;       // FIFO 不满即 ready

    // -- 读侧：loopback_en=0 时强制 rd_en=1 清残留；en=1 时按 tready 仲裁 --
    assign rd_en = ~rd_empty & (~loopback_en_i | tx_axis_mac_tready_i);

    // -- TX 输出：loopback_en=0 → 全部 IDLE；en=1 → 正常输出 --
    assign tx_axis_mac_tvalid_o = loopback_en_i & ~rd_empty;
    assign tx_axis_mac_tdata_o  = rd_data[7:0];
    assign tx_axis_mac_tlast_o  = rd_data[8];
    assign tx_axis_mac_tuser_o  = rd_data[9];

    //==================================================================
    // 3. 同步 FIFO（DW=10, AW=11, 深度 2048；同源退化）
    //    注：项目自研 async_fifo 同源时钟运行时，Gray 码 CDC 链无副作用，
    //    行为退化为标准同步 FIFO。
    //==================================================================
    async_fifo #(
        .DW         (10),
        .AW         (FIFO_AW),
        .AWIDTH     (1),          // 无独立 sideband（tuser/tlast 已打包进 DW）
        .SYNC_DEPTH (2)
    ) u_fifo (
        .wr_clk_i   (clk_i),
        .wr_rst_n_i (fifo_rst_n),
        .wr_en_i    (wr_en),
        .wr_data_i  (wr_data),
        .wr_side_i  (1'b0),       // 占位（AWIDTH=1）
        .wr_full_o  (wr_full),
        .wr_level_o (),           // 未使用

        .rd_clk_i   (clk_i),
        .rd_rst_n_i (fifo_rst_n),
        .rd_en_i    (rd_en),
        .rd_data_o  (rd_data),
        .rd_side_o  (),
        .rd_empty_o (rd_empty),
        .rd_level_o ()
    );

    //==================================================================
    // 4. 未使用信号抑制
    //==================================================================
    wire _unused = &{1'b0, 1'b0};

endmodule

`default_nettype wire
