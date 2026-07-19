`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: pll_ddr_wrapper
// 功能描述: DDR PLL 包装模块。
//
//   2026-07-19 更新：peri.xml 已通过 DesignAPI 配置 pll_ddr 硬块
//   （PLL_TL2, ref_clock=33.33MHz, multiplier=4）。
//   本 wrapper 现在同步真实的 pll_ddr_LOCKED 信号（来自硬块）。
//
//   ddr_clk 仍直通 ddr_clk_ref_i（保持 33.3MHz），等 DDR 实际启动需要时
//   再切换到 ddr_clk_o = pll_clkout_i（顶层已有 input wire pll_ddr_CLKOUT0）。
//
// 接口说明:
//   · ddr_clk_ref_i — 33.33MHz DDR 参考时钟（当前直通为 ddr_clk）
//   · pll_locked_i  — 来自 pll_ddr 硬块的 LOCKED（异步高有效）
//   · arst_n_i      — 异步复位
//   · ddr_clk_o     — DDR 时钟（PLL CLKOUT0）
//   · pll_locked_o  — PLL 锁定指示（同步后）
//============================================================================
module pll_ddr_wrapper (
    input  wire ddr_clk_ref_i,    // 33.33MHz DDR 参考时钟
    input  wire pll_locked_i,     // pll_ddr 硬块 LOCKED（异步）
    input  wire arst_n_i,         // 异步复位（低有效）
    output wire ddr_clk_o,        // DDR 时钟（PLL CLKOUT0）
    output wire pll_locked_o      // PLL 锁定指示（同步后）
);

    // ------------------------------------------------------------------
    // ddr_clk 暂直通 ddr_clk_ref_i，待 DDR 启动时切换为 PLL CLKOUT0：
    //   assign ddr_clk_o = pll_ddr_CLKOUT0;  // 顶层已有此 input port
    // ------------------------------------------------------------------
    assign ddr_clk_o = ddr_clk_ref_i;

    // ------------------------------------------------------------------
    // PLL LOCKED 经 2 级同步（ASYNC_REG）。
    // 同步源是真实的 pll_locked_i（来自硬块）。
    // ------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [1:0] lock_sync;

    always @(posedge ddr_clk_ref_i or negedge arst_n_i) begin
        if (!arst_n_i)
            lock_sync <= 2'b00;
        else
            lock_sync <= {lock_sync[0], pll_locked_i};
    end

    assign pll_locked_o = lock_sync[1];

endmodule

`default_nettype wire
