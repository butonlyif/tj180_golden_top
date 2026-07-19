#!/usr/bin/env python3
"""
Merge MIPI hard D-PHY blocks into tj180_golden_top peri.xml.

Source: TJ180MIPI_loopback/Ti180MIPI/Ti180MIPI.peri.xml  (real Efinity-generated,
        TJ180A484S, has BOTH mipi_dphy_tx_inst1 + mipi_dphy_rx_inst2).

The golden_top peri.xml (seeded from SDHOST) has an empty <efxpt:mipi_info/>.
We copy loopback's full mipi_info block into that slot, then VALIDATE by loading
the result with Efinity's DesignAPI (the real test that Efinity accepts it).

Caveat: loopback is 2-lane RX + 2-lane TX @1200 Mbps. Golden_top may want 4-lane
(see 项目总结.md). Lane count / data rate are tunable later via design.set_property
or Efinity GUI; this brings the hard D-PHY blocks online with a known-good config.
"""
import os
import sys
import re
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")
LOOPBACK = Path(r"D:\work\trae_projects\awesom_project\original\proj\TJ180MIPI_loopback\Ti180MIPI\Ti180MIPI.peri.xml")

# --- 1. Extract mipi_info block from loopback ---
lp_txt = LOOPBACK.read_text(encoding="utf-8")
m = re.search(r"<efxpt:mipi_info>.*?</efxpt:mipi_info>", lp_txt, re.DOTALL)
assert m, "loopback mipi_info not found"
mipi_block = m.group(0)
n_blocks = mipi_block.count("<efxpt:mipi ")
print(f"INFO: extracted mipi_info ({len(mipi_block)} bytes, {n_blocks} MIPI blocks) from loopback")

# --- 2. Splice into golden_top peri.xml ---
g_txt = GOLDEN.read_text(encoding="utf-8")
# golden_top (SDHOST seed) has empty <efxpt:mipi_info/> — replace it.
patterns = [r"<efxpt:mipi_info\s*/>",
            r"<efxpt:mipi_info\s*>\s*</efxpt:mipi_info>"]
spliced = False
for pat in patterns:
    if re.search(pat, g_txt):
        g_txt = re.sub(pat, mipi_block, g_txt, count=1)
        spliced = True
        break
assert spliced, "golden_top has neither empty mipi_info/> nor <mipi_info></mipi_info> — already populated?"
GOLDEN.write_text(g_txt, encoding="utf-8")
print(f"INFO: spliced mipi_info into {GOLDEN.name}")

# --- 3. Validate: load with DesignAPI (the real Efinity acceptance test) ---
print("\n=== Validation: load with Efinity DesignAPI ===")
from api_service.design import DesignAPI
design = DesignAPI(is_verbose=False)
design.load(str(GOLDEN))
print("INFO: DesignAPI.load() OK — Efinity accepts the merged peri.xml")

# Confirm blocks present
emitted = GOLDEN.read_text(encoding="utf-8")
checks = {
    "mipi_info present": "<efxpt:mipi_info>" in emitted,
    "tx inst1": '<efxpt:mipi name="mipi_dphy_tx_inst1"' in emitted,
    "rx inst2": '<efxpt:mipi name="mipi_dphy_rx_inst2"' in emitted,
    "ddr_info still present": "<efxpt:ddr_info>" in emitted,
    "pll_ddr still present": '<efxpt:pll name="pll_ddr"' in emitted,
    "jtag_info present": "<efxpt:jtag_info>" in emitted,
}
print("\n=== Final peri.xml content ===")
for k, v in checks.items():
    print(f"  {k:28} = {v}")
print(f"\n  file size = {len(emitted)} bytes")
print("DONE.")
