---
kind: project
id: tj180_golden_top
board: tj180-core
carrier: awesom-base
jackets: []
ips:
  - hard_csi_rx        # MIPI CSI-2 RX (D-PHY), from MIPI_RX_sc850 / TJ180MIPI_loopback
  - hard_csi_tx        # MIPI CSI-2 TX (D-PHY), from TJ180MIPI_loopback
  - mipi_csi_tx_2p5g   # MIPI CSI-2 TX 2.5G for 4K, from TJ180J484_CSI_4k_2370Ma
  - sapphire_soc       # RISC-V Sapphire SoC
  - tj180a484s_sdhost  # SD Host controller (SDIO + ADMA2), from TJ180A484S_SDHOST
  - apb3_2_axi4_lite_sdhost  # APB3 → AXI4-Lite bridge, from TJ180A484S_SDHOST
  - i2c_master         # I2C master
  - async_fifo_16      # Async FIFO (16-bit), from TJ180J484_CSI_4k_2370Ma
  - test_tse           # Triple Speed Ethernet MAC v4.3 (RGMII), from TJ180A484_TSE
  # DDR3/LPDDR4x: Hard IP — see docs/DDR-硬核配置参考.md (enable via Efinity GUI)
---

# tj180_golden_top

Project assembled by `awesom new-project`.

## Composition

- **Board:** `tj180-core` — md docs in `board/`
- **Carrier:** `awesom-base` — md docs in `carrier/`
- **Jackets:** none — full directories in `jackets/<id>/`
- **IPs (9 soft IPs in `ip/`):** `hard_csi_rx`, `hard_csi_tx`, `mipi_csi_tx_2p5g`,
  `sapphire_soc`, `tj180a484s_sdhost`, `apb3_2_axi4_lite_sdhost`, `i2c_master`,
  `async_fifo_16`, `test_tse` (TSEMAC v4.3, RGMII)
- **Hard IP (in `tj180_golden_top.peri.xml`, tool-emitted, DesignAPI-validated):**
  - **DDR3/LPDDR4x** (`ddr_inst`, DDR_0) — `mem_type=LPDDR4x, density=4G, width=16`,
    AXI Target0 512-bit enable, + `pll_ddr` (PLL_TL2). (from SDHOST seed)
  - **MIPI D-PHY TX** (`mipi_dphy_tx_inst1`, MIPI_TX0) + **RX** (`mipi_dphy_rx_inst2`,
    MIPI_RX0) hard blocks. (mipi_info from TJ180MIPI_loopback; 2-lane @1200Mbps,
    tunable to 4-lane later)
  - **RGMII Ethernet** — 13 GPIO (rgmii_txc/rxd/txd/tx_ctl/rx_ctl + phy_mdc/mdio) with
    DDIO resync, + `pll_ethernet` (PLL_TR0) generating `clk_125m`/`clk_125m_90deg`.
    Pins match `项目总结.md` (GPIOR_N_42, GPIOL_29, etc.). (from TJ180A484_TSE)
  - JTAG (`jtag_inst1`, JTAG_USER1).
  - Emitted by `debug/configure_ddr.py` + `merge_mipi.py` + `merge_rgmii.py` via
    Efinity `DesignAPI`.
  - ⚠️ SoC peripheral PINS (UART/SPI/I2C/SD) currently inherit the SDHOST seed —
    the self-invented `constraints/*.peri.isf` has 59 pin conflicts and mis-models hard
    IPs as GPIO (`debug/audit_isf.py`); board-specific pins need a real Python ISF.
    See `docs/DDR-硬核配置参考.md` §6.

## Starting point

Each jacket directory under `jackets/` contains a complete Efinity project. The main project file was renamed to `tj180_golden_top.xml` and the `${PROJECT_NAME}` / `${PROJECT_DIR}` placeholders inside it were substituted, so the project opens directly in Efinity.

Each jacket is an independent copy under `jackets/<id>/` — pick whichever one you want to open in Efinity.
