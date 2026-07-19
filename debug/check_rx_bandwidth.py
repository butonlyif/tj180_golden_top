"""Find RX DPHY rate config + compare to TX after the 4K60 lane enable."""
import re
from pathlib import Path

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")
txt = GOLDEN.read_text(encoding="utf-8")

for inst in ("mipi_dphy_tx_inst1", "mipi_dphy_rx_inst2"):
    m = re.search(rf'(<efxpt:mipi name="{inst}".*?</efxpt:mipi>)', txt, re.DOTALL)
    if not m:
        print(f"{inst}: NOT FOUND\n")
        continue
    blk = m.group(1)
    print(f"=== {inst} ({len(blk)} bytes) ===")
    # Find any rate / bandwidth / freq attribute
    for line in blk.split("\n"):
        s = line.strip()
        if any(k in s.lower() for k in ("bandwidth", "_freq", "ref_clock", "data_lane",
                                         "byte_clk", "esc_clk", "phy_")):
            print(f"  {s[:150]}")
    print()
