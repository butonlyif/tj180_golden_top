#!/usr/bin/env python3
"""
Merge RGMII (TSE MAC <-> PHY) into tj180_golden_top peri.xml.

Source: TJ180A484_TSE/TSE/temac_ex.peri.xml  (real Efinity-generated TJ180A484S,
        RGMII pins match 项目总结.md pin table: phy_mdc/mdio, rgmii_txc/txd/tx_ctl,
        rgmii_rxc/rxd/rx_ctl on GPIOR_*/GPIOL_29).

Brings in:
  1. RGMII + MDIO comp_gpio blocks (DDIO resync, pin assignments) -> gpio_info
  2. bus declarations (rgmii_txd, rgmii_rxd) -> gpio_info
  3. Ethernet 125MHz PLL (clk_125m / clk_125m_90deg / clk_25m) -> pll_info
     Uses PLL_TR0 (PLL_TL0 is taken by pll_sys, PLL_TL2 by pll_ddr).

Note: NOT using the self-invented constraints/*.peri.isf — its RGMII pins (AB20 etc.)
are untrustworthy (see debug/audit_isf.py). Pin values come from the real TSE peri.xml.
"""
import os
import sys
import re
from pathlib import Path
import xml.etree.ElementTree as ET

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")
TSE = Path(r"D:\work\trae_projects\awesom_project\original\proj\TJ180A484_TSE\TSE\temac_ex.peri.xml")

NS = "{http://www.efinixinc.com/peri_design_db}"
ET.register_namespace("efxpt", "http://www.efinixinc.com/peri_design_db")

RGMII_NAMES = {
    "phy_mdc", "phy_mdio",
    "rgmii_rx_ctl", "rgmii_rxc",
    "rgmii_rxd[0]", "rgmii_rxd[1]", "rgmii_rxd[2]", "rgmii_rxd[3]",
    "rgmii_tx_ctl", "rgmii_txc",
    "rgmii_txd[0]", "rgmii_txd[1]", "rgmii_txd[2]", "rgmii_txd[3]",
}

# --- 1. Extract RGMII comp_gpio blocks + buses + pll_0 from TSE (string ops on raw text) ---
tse_txt = TSE.read_text(encoding="utf-8")

def extract_blocks(text, tag, name_attr, names):
    """Return list of raw XML strings for <tag name=...> ... </tag> whose name in names."""
    out = []
    # match opening tag with the name attr
    pat = re.compile(rf'(<efxpt:{tag}\s+name="([^"]+)"[^>]*>)(.*?)(</efxpt:{tag}>)', re.DOTALL)
    for m in pat.finditer(text):
        nm = m.group(2)
        if nm in names:
            out.append(m.group(0))
    return out

rgmii_gpio_blocks = extract_blocks(tse_txt, "comp_gpio", "name", RGMII_NAMES)
print(f"INFO: extracted {len(rgmii_gpio_blocks)} RGMII/MDIO comp_gpio blocks from TSE")
assert len(rgmii_gpio_blocks) == len(RGMII_NAMES), f"expected {len(RGMII_NAMES)} blocks"

# buses
bus_blocks = re.findall(r'<efxpt:bus name="rgmii_[^"]*"[^/]*/>', tse_txt)
bus_names = [re.search(r'name="([^"]+)"', b).group(1) for b in bus_blocks]
print(f"INFO: extracted {len(bus_blocks)} rgmii bus declarations: {bus_names}")

# pll_0 block (the 125MHz PLL) -> rename to pll_ethernet on PLL_TR0
pll_m = re.search(r'(<efxpt:pll name="pll_0"[^>]*>.*?</efxpt:pll>)', tse_txt, re.DOTALL)
assert pll_m, "TSE pll_0 not found"
pll_block = pll_m.group(1)
pll_block = pll_block.replace('name="pll_0"', 'name="pll_ethernet"', 1)
pll_block = pll_block.replace('pll_def="PLL_TL0"', 'pll_def="PLL_TR0"', 1)
pll_block = pll_block.replace('locked_name="pll_0_locked"', 'locked_name="pll_ethernet_locked"', 1)
print(f"INFO: extracted + adapted pll_0 -> pll_ethernet (PLL_TR0), {len(pll_block)} bytes")

# --- 2. Splice into golden_top ---
g_txt = GOLDEN.read_text(encoding="utf-8")

# 2a. RGMII comp_gpio blocks -> insert before <efxpt:global_unused_config (inside gpio_info)
#     (XSD order in gpio_info: comp_gpio*, global_unused_config, bus*)
gpio_insert = "\n        <!-- RGMII Ethernet (from TSE temac_ex, TJ180A484S) -->\n        " + \
              "\n        ".join(rgmii_gpio_blocks) + "\n    "
marker = "<efxpt:global_unused_config"
assert marker in g_txt, "gpio_info global_unused_config marker not found"
g_txt = g_txt.replace(marker, gpio_insert + marker, 1)
print("INFO: spliced RGMII comp_gpio blocks into gpio_info (before global_unused_config)")

# 2b. RGMII buses -> insert AFTER global_unused_config, before </efxpt:gpio_info>
bus_insert = "\n        " + "\n        ".join(bus_blocks) + "\n    "
marker_bus = "</efxpt:gpio_info>"
assert marker_bus in g_txt, "gpio_info close tag not found"
g_txt = g_txt.replace(marker_bus, bus_insert + marker_bus, 1)
print("INFO: spliced rgmii bus declarations (after global_unused_config)")

# 2b. Ethernet PLL -> insert before </efxpt:pll_info>
pll_insert = "\n        " + pll_block + "\n    "
marker2 = "</efxpt:pll_info>"
assert marker2 in g_txt, "pll_info close tag not found"
g_txt = g_txt.replace(marker2, pll_insert + marker2, 1)
print("INFO: spliced pll_ethernet (PLL_TR0) into pll_info")

GOLDEN.write_text(g_txt, encoding="utf-8")

# --- 3. Validate: load with DesignAPI ---
print("\n=== Validation: load with Efinity DesignAPI ===")
from api_service.design import DesignAPI
design = DesignAPI(is_verbose=False)
design.load(str(GOLDEN))
print("INFO: DesignAPI.load() OK — Efinity accepts the merged peri.xml")

# --- 4. Confirm ---
emitted = GOLDEN.read_text(encoding="utf-8")
checks = {
    "rgmii_txc pin GPIOR_N_42": 'rgmii_txc" gpio_def="GPIOR_N_42"' in emitted,
    "rgmii_rxc pin GPIOL_29": 'rgmii_rxc" gpio_def="GPIOL_29"' in emitted,
    "phy_mdio inout": 'phy_mdio" gpio_def="GPIOR_N_35"' in emitted,
    "rgmii_txd bus": '<efxpt:bus name="rgmii_txd"' in emitted,
    "rgmii_rxd bus": '<efxpt:bus name="rgmii_rxd"' in emitted,
    "pll_ethernet PLL_TR0": 'name="pll_ethernet" pll_def="PLL_TR0"' in emitted,
    "clk_125m output": 'name="clk_125m"' in emitted,
    "clk_125m_90deg output": 'name="clk_125m_90deg"' in emitted,
    "ddr still present": "<efxpt:ddr_info>" in emitted,
    "mipi still present": "<efxpt:mipi_info>" in emitted,
}
print("\n=== Final peri.xml content ===")
for k, v in checks.items():
    print(f"  {k:32} = {v}")
print(f"\n  file size = {len(emitted)} bytes")
print("DONE.")
