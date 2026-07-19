`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// ⚠️ DEPRECATED — 此文件不再参与编译，请勿使用。
//
// 模块名称: pll_top  (Stage 0 占位，已被 pll_sys_wrapper 替代)
// 状态:     已废弃 (Stage 1 起 PLL 包装改用 rtl/clk_rst/pll_sys_wrapper.sv)
// 说明:
//   - Efinity 工程 (tj180_golden_top.xml) 的 <design_file> 列表不包含本文件。
//   - 当前 PLL 包装模块为 rtl/clk_rst/pll_sys_wrapper.sv 和
//     rtl/clk_rst/pll_ddr_wrapper.sv，由 tj180_golden_top.v 例化。
//   - 保留此文件仅作为历史参考。
//============================================================================
module pll_top (
    input  wire clk50_in,
    input  wire ext_rst_n,
    output wire sys_clk,
    output wire pll_locked
);

    // Stage 0：直通，不走硬 PLL
    assign sys_clk    = clk50_in;
    assign pll_locked = ext_rst_n;

endmodule

`default_nettype wire
