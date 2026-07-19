# =====================================================================
# tj180_golden_top — base SDC
# 由 SDK 向导合并生成
# =====================================================================

# Base SDC for AweSOM Tj180 Core Module (TJ180A484S)
# 来源：核心板规格 v0.0.1
# new-project 合成器会把 jacket SDC 附加到本文件末尾

# 50 MHz 主参考时钟 (U13 → FPGA pin T18)
create_clock -name clk50    -period 20.000 [get_ports clk50_in]

# 33.33 MHz DDR 参考时钟 (U14 → FPGA pin Y14)
create_clock -name clk33    -period 30.003 [get_ports clk33_ddr]

# 27 MHz MIPI 参考时钟 (U15 → AA10, AA15)
create_clock -name clk27_a  -period 37.037 [get_ports clk27_mipi_a]
create_clock -name clk27_b  -period 37.037 [get_ports clk27_mipi_b]

# 用户 LED — 异步输出，不做时序分析
set_false_path -to [get_ports led_user]

# 用户按键（rst_n_i / btn_n）的 false_path 由底板 SDC 片段提供

# AweSOM Base Board — SDC 约束片段
# 此文件由 CLI _merge_sdc() 合并到核心板的 base.sdc 中。
# 仅包含底板外设的时序约束。

# 用户按键 — 异步输入，false-path
set_false_path -from [get_ports rst_n_i]
set_false_path -from [get_ports {btn_n[*]}]
