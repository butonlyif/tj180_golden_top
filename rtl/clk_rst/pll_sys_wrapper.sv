`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: pll_sys_wrapper
// 功能描述: System PLL 包装模块。
//
//   2026-07-19 更新：peri.xml 已通过 DesignAPI 配置 pll_sys 硬块
//   （PLL_TL0, ref_clock=50MHz, M=2 → CLKOUT0=100MHz，CLKOUT3=i_axi0_mem_clk）。
//   本 wrapper 现在同步真实的 pll_sys_LOCKED 信号（来自硬块），
//   并使用 pll_sys_CLKOUT0（100 MHz）作为 sys_clk —— 不再穿透 clk_50m_i。
//
//   ⚠ 重要：sys_clk 现在跑 100 MHz（不是之前的 50 MHz）。
//   这让 sys_clk = i_axi0_mem_clk = 100 MHz（同源于 pll_sys），
//   axi_dwidth_converter 的单时钟假设自动成立，**DDR CDC 问题消失**。
//   副作用：sys_clk 域时序余量减半，需要重新跑 STA 验证。
//
// 接口说明:
//   · clk_50m_i     — 50MHz 参考时钟（仅用于 lock_sync 同步链，不用于 sys_clk_o）
//   · pll_clkout_i  — 来自 pll_sys 硬块的 CLKOUT0（100 MHz，异步采样进本模块）
//   · pll_locked_i  — 来自 pll_sys 硬块的 LOCKED（异步高有效电平）
//   · arst_n_i      — 异步复位（低有效）
//   · sys_clk_o     — 系统时钟（= pll_clkout_i，100 MHz）
//   · pll_locked_o  — PLL 锁定指示（同步后，高有效）
//============================================================================
module pll_sys_wrapper (
    input  wire clk_50m_i,       // 50MHz 参考时钟（仅用于 lock_sync FF 时钟）
    input  wire pll_clkout_i,    // pll_sys 硬块 CLKOUT0（100 MHz）— sys_clk 真源
    input  wire pll_locked_i,    // pll_sys 硬块 LOCKED（异步）
    input  wire arst_n_i,        // 异步复位（低有效）
    output wire sys_clk_o,       // 系统时钟（= pll_clkout_i，100 MHz）
    output wire pll_locked_o     // PLL 锁定指示（同步后）
);

    // ------------------------------------------------------------------
    // sys_clk 直接取自 pll_sys CLKOUT0（100 MHz）。
    // clk_50m_i 仅作为 lock_sync 同步链的时钟（同步链是静态信号，频率任意）。
    // ------------------------------------------------------------------
    assign sys_clk_o = pll_clkout_i;

    // ------------------------------------------------------------------
    // PLL LOCKED 经 2 级同步（ASYNC_REG），避免异步采样亚稳态。
    // 同步源是真实的 pll_locked_i（来自硬块），不是 1'b1 占位。
    // ------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [1:0] lock_sync;

    always @(posedge clk_50m_i or negedge arst_n_i) begin
        if (!arst_n_i)
            lock_sync <= 2'b00;
        else
            lock_sync <= {lock_sync[0], pll_locked_i};
    end

    assign pll_locked_o = lock_sync[1];

endmodule

`default_nettype wire
