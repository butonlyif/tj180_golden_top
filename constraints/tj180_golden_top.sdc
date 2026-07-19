# Efinity Timing Constraints for TJ180A484S Golden Top
# Stage 3 — SoC + DDR + MIPI CSI-2 RX + MIPI CSI-2 TX Loopback
# Target Speed Grade: C4/I3

# ============================================================================
# Clock Definitions
# ============================================================================

# System Clock - 50MHz input
create_clock -name clk_50m -period 20.000 [get_ports {clk_50m}]

# DDR Reference Clock - 33.33MHz
create_clock -name ddr_clk_ref -period 30.000 [get_ports {ddr_clk_ref}]

# MIPI Reference Clock
create_clock -name MIPI_REF_CLK -period 10.000 [get_ports {MIPI_REF_CLK}]

# JTAG Clock
create_clock -name jtag_tck -period 100.000 [get_ports {jtag_inst1_TCK}]

# ----------------------------------------------------------------------------
# Stage 2: MIPI DPHY RX 输出 byte HS 时钟
#   - 来自 DPHY RX 硬块端口 mipi_dphy_rx_clk_CLKOUT
#   - 2026-07-19 升级 4K60：TX 4-lane @ 2.5 Gbps/lane（peri.xml phy_bandwidth=2500）
#     ⇒ byte_clk = 2500/16 = 156.25 MHz（参考 Ti180J484_devkit/Ti180_mipi.sdc 同款）
#   - RX 是 listener，时钟实际频率由摄像头决定；此处约束到上限 156 MHz 保证 STA
#   - 与 sys_clk / ddr_clk_ref / MIPI_REF_CLK 完全异步，已声明异步时钟组
# ----------------------------------------------------------------------------
create_clock -name clk_byte_hs -period 6.400 \
    [get_ports {mipi_dphy_rx_clk_CLKOUT}]

# ----------------------------------------------------------------------------
# Stage 2/3 2026-07-19: Pixel PLL (pll_pixel @ PLL_TL1)
#   - 来自 pll_pixel 硬块 CLKOUT0
#   - 50 MHz ref x M=4 / N=1 / O=1 = 200 MHz 输出
#   - clk_pixel_rx / clk_pixel_tx 均使用此时钟（4K60 loopback 对称）
#   - 200 MHz x 4 pix/clk (64-bit YUV422) = 800 Mpix/s, 4K60 只需 498 Mpix/s
#   - 与 sys_clk / clk_byte_hs / ddr_clk_ref 完全异步（独立 PLL 源）
# ----------------------------------------------------------------------------
create_clock -name clk_pixel -period 5.000 \
    [get_ports {pll_pixel_CLKOUT0}]

# clk_pixel_rx / clk_pixel_tx 现在均由 pll_pixel_CLKOUT0 驱动（独立 PLL，
# 不再是 clk_byte_hs 简化）。async_pixel_fifo 是真异步 FIFO，两侧同源。

# ============================================================================
# Generated Clocks from PLLs
# ============================================================================
# TODO(Interface Designer): After PLL configuration, add generated clock:
# create_generated_clock -name sys_clk -source [get_ports clk_50m] \
#     -multiply_by 2 [get_pins <pll_sys>/CLKOUT0]
# create_generated_clock -name ddr_clk -source [get_ports ddr_clk_ref] \
#     -multiply_by 9 [get_pins <pll_ddr>/CLKOUT0]

# ============================================================================
# Clock Uncertainty / Jitter
# ============================================================================

set_clock_uncertainty 0.200 [get_clocks {clk_50m}]
set_clock_uncertainty 0.300 [get_clocks {ddr_clk_ref}]
set_clock_uncertainty 0.150 [get_clocks {MIPI_REF_CLK}]
set_clock_uncertainty 0.100 [get_clocks {jtag_tck}]
set_clock_uncertainty 0.200 [get_clocks {clk_byte_hs}]
set_clock_uncertainty 0.150 [get_clocks {clk_pixel}]

# ============================================================================
# MIPI DPHY RX 输入（源同步，由 DPHY 内部时序保证；相对 clk_byte_hs 加约束）
# ============================================================================
# 4-lane HS 数据 / valid / sync / skewcal — DPHY 内部已对齐 byte_hs，
# 仅给一个保守的相对输入延迟，便于时序工具报告（不影响 DPHY 硬块本身）。
set_input_delay -clock clk_byte_hs -max 2.000 \
    [get_ports {mipi_dphy_rx_inst2_HS_LAN0_DATA[*]}]
set_input_delay -clock clk_byte_hs -max 2.000 \
    [get_ports {mipi_dphy_rx_inst2_HS_LAN1_DATA[*]}]
set_input_delay -clock clk_byte_hs -max 2.000 \
    [get_ports {mipi_dphy_rx_inst2_HS_LAN2_DATA[*]}]
set_input_delay -clock clk_byte_hs -max 2.000 \
    [get_ports {mipi_dphy_rx_inst2_HS_LAN3_DATA[*]}]
set_input_delay -clock clk_byte_hs -max 2.000 \
    [get_ports {mipi_dphy_rx_inst2_HS_LAN0_VALID}]
set_input_delay -clock clk_byte_hs -max 2.000 \
    [get_ports {mipi_dphy_rx_inst2_HS_LAN1_VALID}]
set_input_delay -clock clk_byte_hs -max 2.000 \
    [get_ports {mipi_dphy_rx_inst2_HS_LAN2_VALID}]
set_input_delay -clock clk_byte_hs -max 2.000 \
    [get_ports {mipi_dphy_rx_inst2_HS_LAN3_VALID}]

# ============================================================================
# Input Delays
# ============================================================================

# UART inputs (async, relatively slow)
set_input_delay -clock clk_50m -max 10.000 [get_ports {system_uart_0_io_rxd}]

# GPIO inputs (slow, async)
set_input_delay -clock clk_50m -max 10.000 [get_ports {system_gpio_0_io_read[*]}]

# SD Card inputs (up to 50MHz SDIO)
set_input_delay -clock clk_50m -max 5.000 [get_ports {sd_cd_n}]
set_input_delay -clock clk_50m -max 5.000 [get_ports {sd_cmd_i}]
set_input_delay -clock clk_50m -max 5.000 [get_ports {sd_dat_i[*]}]

# I2C inputs — open-drain, self-timed by SCL at <=400 kHz (2.5 us period).
# No meaningful timing relationship to clk_50m -> false path (was 100 ns, caused -78 ns slack).
set_false_path -from [get_ports {system_i2c_0_io_scl_read}]
set_false_path -from [get_ports {system_i2c_0_io_sda_read}]

# SPI inputs
set_input_delay -clock clk_50m -max 20.000 [get_ports {system_spi_0_io_data_0_read}]
set_input_delay -clock clk_50m -max 20.000 [get_ports {system_spi_0_io_data_1_read}]

# JTAG inputs
set_input_delay -clock jtag_tck -max 20.000 [get_ports {jtag_inst1_TDI}]
set_input_delay -clock jtag_tck -max 20.000 [get_ports {jtag_inst1_TMS}]
set_input_delay -clock jtag_tck -max 20.000 [get_ports {jtag_inst1_CAPTURE}]
set_input_delay -clock jtag_tck -max 20.000 [get_ports {jtag_inst1_SHIFT}]
set_input_delay -clock jtag_tck -max 20.000 [get_ports {jtag_inst1_UPDATE}]
set_input_delay -clock jtag_tck -max 20.000 [get_ports {jtag_inst1_RESET}]
set_input_delay -clock jtag_tck -max 20.000 [get_ports {jtag_inst1_RUNTEST}]
set_input_delay -clock jtag_tck -max 20.000 [get_ports {jtag_inst1_SEL}]

# ============================================================================
# Output Delays
# ============================================================================

# UART outputs
set_output_delay -clock clk_50m -max 10.000 [get_ports {system_uart_0_io_txd}]

# GPIO outputs — user pushbuttons/LEDs, slow board-level signals.
# Board trace ~5-8 ns; 10 ns leaves ample margin (was 20 ns, caused -4.9 ns slack).
set_output_delay -clock clk_50m -max 10.000 [get_ports {system_gpio_0_io_write[*]}]
set_output_delay -clock clk_50m -max 10.000 [get_ports {system_gpio_0_io_writeEnable[*]}]

# SD Card outputs
set_output_delay -clock clk_50m -max 5.000 [get_ports {sd_clk_hi}]
set_output_delay -clock clk_50m -max 5.000 [get_ports {sd_cmd_o}]
set_output_delay -clock clk_50m -max 5.000 [get_ports {sd_cmd_oe}]
set_output_delay -clock clk_50m -max 5.000 [get_ports {sd_dat_o[*]}]
set_output_delay -clock clk_50m -max 5.000 [get_ports {sd_dat_oe[*]}]

# I2C outputs — open-drain writeEnable is a static control signal; SCL self-times the bus.
# (was 100 ns, caused -83 ns slack). False path on both write and writeEnable.
set_false_path -to [get_ports {system_i2c_0_io_scl_write}]
set_false_path -to [get_ports {system_i2c_0_io_scl_writeEnable}]
set_false_path -to [get_ports {system_i2c_0_io_sda_write}]
set_false_path -to [get_ports {system_i2c_0_io_sda_writeEnable}]

# SPI outputs
set_output_delay -clock clk_50m -max 10.000 [get_ports {system_spi_0_io_sclk_write}]
set_output_delay -clock clk_50m -max 10.000 [get_ports {system_spi_0_io_ss}]
set_output_delay -clock clk_50m -max 10.000 [get_ports {system_spi_0_io_data_0_writeEnable}]
set_output_delay -clock clk_50m -max 10.000 [get_ports {system_spi_0_io_data_0_write}]
set_output_delay -clock clk_50m -max 10.000 [get_ports {system_spi_0_io_data_1_writeEnable}]
set_output_delay -clock clk_50m -max 10.000 [get_ports {system_spi_0_io_data_1_write}]

# LED outputs — purely visual, no timing requirement.
# (was 50 ns output delay, caused -33 ns slack.)
set_false_path -to [get_ports {led[*]}]

# JTAG outputs
set_output_delay -clock jtag_tck -max 20.000 [get_ports {jtag_inst1_TDO}]

# ============================================================================
# False Paths
# ============================================================================

# Async reset signal
set_false_path -from [get_ports {arst_n}]

# PLL lock signals are not timing critical
set_false_path -from [get_ports {sys_pll_lock}]
set_false_path -from [get_ports {ddr_pll_lock}]
set_false_path -from [get_ports {sys_pll_rstn}]
set_false_path -from [get_ports {ddr_pll_rstn}]

# Interrupts and status signals
set_false_path -from [get_ports {ddr_inst_CFG_DONE}]
set_false_path -from [get_ports {ddr_inst_CTRL_BUSY}]
set_false_path -from [get_ports {ddr_inst_CTRL_INT}]
set_false_path -from [get_ports {ddr_inst_CTRL_REFRESH}]

# MIPI RX 控制信号 — Stage 2 起由 byte_hs 域同步寄存器驱动
# (FORCE_RX_MODE 经 byte_hs_rst_n 同步释放；RESET/RST0_N 跟随复位)
set_false_path -to   [get_ports {mipi_dphy_rx_inst2_FORCE_RX_MODE}]
set_false_path -to   [get_ports {mipi_dphy_rx_inst2_RESET}]
set_false_path -to   [get_ports {mipi_dphy_rx_inst2_RST0_N}]
# Stage 2 复位同步器首级
set_false_path -from [get_cells {u_rst_byte_hs/sync_r[*]}]
set_false_path -from [get_cells {u_rst_pixel/sync_r[*]}]
# Stage 2 CSI IRQ / pixel_valid CDC 同步链首级
set_false_path -from [get_cells {csi_irq_sync_reg[*]}]
set_false_path -from [get_cells {pixel_valid_sync_reg[*]}]
# Stage 3 CSI TX IRQ CDC 同步链首级
set_false_path -from [get_cells {ctxi_irq_sync_reg[*]}]
# Stage 3 复位同步器首级
set_false_path -from [get_cells {u_rst_pixel_tx/sync_r[*]}]
# Stage 3 async_pixel_fifo 指针 CDC 同步链首级（async_fifo 实例内）
set_false_path -from [get_cells {u_async_pixel_fifo/wr_gray_sync[*][0]}]
set_false_path -from [get_cells {u_async_pixel_fifo/rd_gray_sync[*][0]}]

# MIPI TX 控制信号 — Stage 3 起由 byte_hs 域同步寄存器驱动
# (RESET 跟随 byte_hs_rst_n 同步释放；PLL_UNLOCK/PLL_SSC_EN 静态)
set_false_path -to   [get_ports {mipi_dphy_tx_inst1_RESET}]
set_false_path -to   [get_ports {mipi_dphy_tx_inst1_PLL_UNLOCK}]
set_false_path -to   [get_ports {mipi_dphy_tx_inst1_PLL_SSC_EN}]
# ESC 层顶层输出（CSI TX IP 未驱动，Stage 3 留安全默认）
set_false_path -to   [get_ports {mipi_dphy_tx_inst1_TX_DATA_ESC[*]}]
set_false_path -to   [get_ports {mipi_dphy_tx_inst1_TX_TRIGGER_ESC[*]}]
set_false_path -to   [get_ports {mipi_dphy_tx_inst1_TX_LPDT_ESC}]
set_false_path -to   [get_ports {mipi_dphy_tx_inst1_TX_VALID_ESC}]
set_false_path -to   [get_ports {mipi_dphy_tx_inst1_TX_READY_ESC}]

# ============================================================================
# Clock-to-Clock Constraints (Asynchronous Groups)
# ============================================================================

# DDR clock domain crossing
set_clock_groups -asynchronous \
    -group [get_clocks {clk_50m}] \
    -group [get_clocks {ddr_clk_ref}]

set_clock_groups -asynchronous \
    -group [get_clocks {clk_50m}] \
    -group [get_clocks {MIPI_REF_CLK}]

set_clock_groups -asynchronous \
    -group [get_clocks {ddr_clk_ref}] \
    -group [get_clocks {MIPI_REF_CLK}]

set_clock_groups -asynchronous \
    -group [get_clocks {clk_50m}] \
    -group [get_clocks {jtag_tck}]

# Stage 2: MIPI byte_hs 域与 sys/DDR/REF 完全异步
set_clock_groups -asynchronous \
    -group [get_clocks {clk_50m}] \
    -group [get_clocks {clk_byte_hs}]

set_clock_groups -asynchronous \
    -group [get_clocks {ddr_clk_ref}] \
    -group [get_clocks {clk_byte_hs}]

set_clock_groups -asynchronous \
    -group [get_clocks {MIPI_REF_CLK}] \
    -group [get_clocks {clk_byte_hs}]

set_clock_groups -asynchronous \
    -group [get_clocks {clk_byte_hs}] \
    -group [get_clocks {jtag_tck}]

# 2026-07-19: clk_pixel (pll_pixel @ PLL_TL1, 200 MHz) 与所有其他时钟域异步
set_clock_groups -asynchronous \
    -group [get_clocks {clk_pixel}] \
    -group [get_clocks {clk_50m}]

set_clock_groups -asynchronous \
    -group [get_clocks {clk_pixel}] \
    -group [get_clocks {clk_byte_hs}]

set_clock_groups -asynchronous \
    -group [get_clocks {clk_pixel}] \
    -group [get_clocks {ddr_clk_ref}]

set_clock_groups -asynchronous \
    -group [get_clocks {clk_pixel}] \
    -group [get_clocks {MIPI_REF_CLK}]

set_clock_groups -asynchronous \
    -group [get_clocks {clk_pixel}] \
    -group [get_clocks {rgmii_rxc}]

set_clock_groups -asynchronous \
    -group [get_clocks {clk_pixel}] \
    -group [get_clocks {jtag_tck}]

# ============================================================================
# False path on reset synchronizer first stage
# ============================================================================
set_false_path -from [get_cells {u_rst_sys/sync_r[0]}]
set_false_path -from [get_cells {u_rst_ddr/sync_r[0]}]

# ============================================================================
# Stage 3: RX→TX Pixel CDC (async_pixel_fifo)
# ============================================================================
# 2026-07-19: clk_pixel_rx / clk_pixel_tx 均来自 pll_pixel_CLKOUT0 (200 MHz)，
# 同源同步（同一 PLL 输出）。async_pixel_fifo 两侧同频同相，无需 async group。
# 若后续拆分为独立 rx/tx pixel PLL（非对称），再加 set_clock_groups -asynchronous。
#
# async_pixel_fifo 指针同步链首级已 set_false_path（前面已声明）：
#   set_false_path -from [get_cells {u_async_pixel_fifo/wr_gray_sync[*][0]}]
#   set_false_path -from [get_cells {u_async_pixel_fifo/rd_gray_sync[*][0]}]

# ============================================================================
# Stage 4: RGMII Ethernet (TSE MAC) 时序约束
#   - RGMII 是源同步 DDR 接口：4-bit 数据在时钟上下沿各传 4-bit → 8-bit/clk
#   - 顶层端口已按 `_HI`/`_LO` 拆分（per Efinity peri.xml 约定），TSE IP 内部
#     用 DDIO 发射/采样，无需在 fabric 内再写 ODDR/IDDR。
#   - MAC 时钟 = sys_clk (50MHz)；rgmii_rxc 由 PHY 提供，与 sys_clk 完全异步。
#   - 参考约束：ip/test_tse/T120F324_devkit/timing.sdc（125MHz 全速场景）。
#     本工程 bring-up 跑 50MHz，时序余量更大；保留同款结构，仅周期不同。
# ============================================================================

# ----------------------------------------------------------------------------
# S4.1 RGMII RX 时钟（PHY 提供，源同步 DDR）
#   rgmii_rxc 物理频率典型 125MHz（千兆）；上板实测后可改 8ns。
# ----------------------------------------------------------------------------
create_clock -name rgmii_rxc -period 8.000 [get_ports {rgmii_rxc}]
set_clock_uncertainty 0.200 [get_clocks {rgmii_rxc}]

# ----------------------------------------------------------------------------
# S4.2 RGMII RX 输入延迟（相对 rgmii_rxc 源同步）
#   - 数据 _HI 在 rxc 上升沿采样；_LO 在下降沿采样（DDR）
#   - rx_ctl 同款 DDR
#   - max/min 数值参考 T120F324_devkit timing.sdc（板级 PHY 时序近似）
# ----------------------------------------------------------------------------
set_input_delay -clock rgmii_rxc -max 6.168 \
    [get_ports {rgmii_rxd_HI[*] rgmii_rxd_LO[*]}]
set_input_delay -clock rgmii_rxc -min 3.084 \
    [get_ports {rgmii_rxd_HI[*] rgmii_rxd_LO[*]}]
set_input_delay -clock rgmii_rxc -max 6.100 \
    [get_ports {rgmii_rx_ctl_HI rgmii_rx_ctl_LO}]
set_input_delay -clock rgmii_rxc -min 3.050 \
    [get_ports {rgmii_rx_ctl_HI rgmii_rx_ctl_LO}]

# ----------------------------------------------------------------------------
# S4.3 RGMII TX 输出延迟（相对 sys_clk；MAC TX 在 sys_clk 域 DDIO 输出）
#   - _HI 在 sys_clk 上升沿发射；_LO 在下降沿发射
#   - 注：参考设计在 125MHz 用 -clock_fall + 半周期 delay，本工程 sys_clk=50MHz
#     时序余量充足，统一用 sys_clk 域标准约束即可。
# ----------------------------------------------------------------------------
set_output_delay -clock clk_50m -max 4.000 \
    [get_ports {rgmii_txd_HI[*] rgmii_txd_LO[*]}]
set_output_delay -clock clk_50m -min 1.000 \
    [get_ports {rgmii_txd_HI[*] rgmii_txd_LO[*]}]
set_output_delay -clock clk_50m -max 4.000 \
    [get_ports {rgmii_txc_HI rgmii_txc_LO}]
set_output_delay -clock clk_50m -min 1.000 \
    [get_ports {rgmii_txc_HI rgmii_txc_LO}]
set_output_delay -clock clk_50m -max 4.000 \
    [get_ports {rgmii_tx_ctl_HI rgmii_tx_ctl_LO}]
set_output_delay -clock clk_50m -min 1.000 \
    [get_ports {rgmii_tx_ctl_HI rgmii_tx_ctl_LO}]

# ----------------------------------------------------------------------------
# S4.4 MDIO 接口（MDC 慢速，~2.5MHz；MDIO 双向）
#   MDC 由 MAC 在 sys_clk 域分频产生；Mdo/Mdo_en 同域。Mdi 输入慢速。
# ----------------------------------------------------------------------------
set_output_delay -clock clk_50m -max 5.000 \
    [get_ports {phy_mdc phy_mdo phy_mdo_en}]
set_output_delay -clock clk_50m -min 1.000 \
    [get_ports {phy_mdc phy_mdo phy_mdo_en}]
set_input_delay -clock clk_50m -max 10.000 [get_ports {phy_mdi}]
set_input_delay -clock clk_50m -min 1.000  [get_ports {phy_mdi}]

# ----------------------------------------------------------------------------
# S4.5 PHY 硬复位 — 异步静态
# ----------------------------------------------------------------------------
set_false_path -to [get_ports {phy_rstn}]

# ----------------------------------------------------------------------------
# S4.6 rgmii_rxc 与 sys_clk / ddr_clk / MIPI_REF_CLK 异步分组
# ----------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {clk_50m}] \
    -group [get_clocks {rgmii_rxc}]

set_clock_groups -asynchronous \
    -group [get_clocks {ddr_clk_ref}] \
    -group [get_clocks {rgmii_rxc}]

set_clock_groups -asynchronous \
    -group [get_clocks {MIPI_REF_CLK}] \
    -group [get_clocks {rgmii_rxc}]

set_clock_groups -asynchronous \
    -group [get_clocks {clk_byte_hs}] \
    -group [get_clocks {rgmii_rxc}]

set_clock_groups -asynchronous \
    -group [get_clocks {rgmii_rxc}] \
    -group [get_clocks {jtag_tck}]


# ============================================================================
# Stage 5: SoC↔DDR AXI 位宽转换桥（axi_dwidth_converter, u_axi_dwidth）
# ============================================================================
# 本桥为单时钟设计：M 侧（SoC 32-bit）与 S 侧（DDR 512-bit）均由 sys_clk 驱动，
# 与 Stage 1~4 的 SoC↔DDR 单时钟假设一致。桥内无 CDC，因此：
#   · 不新增 create_clock / set_clock_groups（两侧同属 sys_clk 域）。
#   · 桥内 FSM/累加器均寄存器化，路径在 sys_clk 域内由默认 STA 覆盖。
#
# ⚠ 已知前提（非本 Stage 引入）：sys_clk 与 DDR IP 的 i_axi0_mem_clk 当前假设
#   同源。若二者不同源（如 DDR 跑独立 mem_clk），需在 u_axi_dwidth 两侧外接
#   async AXI FIFO（或换用带 CDC 的 Efinity axi_dwidth_converter IP），届时
#   再补 set_clock_groups -asynchronous [sys_clk] [mem_clk]。
#   见 docs/设计说明书.md §5.4 备注。
# ============================================================================

