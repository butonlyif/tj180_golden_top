`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// ⚠️ DEPRECATED — 此文件不再参与编译，请勿使用。
//
// 模块名称: top  (Stage 0 占位，已被 tj180_golden_top 替代)
// 状态:     已废弃 (Stage 1 起 tj180_golden_top.v 为唯一顶层)
// 说明:
//   - Efinity 工程 (tj180_golden_top.xml) 的 <top_module> 为 tj180_golden_top，
//     <design_file> 列表中只包含 tj180_golden_top.v，本文件未被引用。
//   - 保留此文件仅作为 Stage 0 → Stage 1 演进的历史记录。
//   - 如需板卡模板参考，请查看 tj180_golden_top.v 中的 LED 慢闪逻辑。
//============================================================================
module top (
    input  wire        clk50_in,      // 50MHz 主时钟
    input  wire        rst_n_i,       // 底板 KEY0 复位按钮（低有效）
    input  wire [3:1]  btn_n,         // 底板 KEY1-KEY3 用户按键（低有效）
    output wire        led_user       // 核心板 D4 用户 LED（高电平点亮）
);

    // ------------------------------------------------------------------
    // 时钟：Stage 0 直接用 50MHz，PLL 占位（Stage 2 会切换到 PLL 输出）
    // ------------------------------------------------------------------
    wire sys_clk = clk50_in;

    // 异步复位，同步释放（AweSOM RTL rules §4 强制模式）
    reg [2:0] rst_sync;
    always @(posedge sys_clk or negedge rst_n_i) begin
        if (!rst_n_i)
            rst_sync <= 3'b000;
        else
            rst_sync <= {rst_sync[1:0], 1'b1};
    end
    wire rst_n = rst_sync[2];

    // ------------------------------------------------------------------
    // Stage 0 占位：26 位计数器分频，让 LED 慢闪证明工程可工作
    // 50MHz / 2^26 ≈ 0.745 Hz 翻转（~1.34s 周期）
    // Stage 1 起此处替换为 counter_top 例化
    // ------------------------------------------------------------------
    reg [25:0] blink_cnt;
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n)
            blink_cnt <= 26'd0;
        else
            blink_cnt <= blink_cnt + 1'b1;
    end

    assign led_user = blink_cnt[25];   // 慢闪

endmodule

`default_nettype wire
