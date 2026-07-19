"""Quick check: mipi_dphy_tx_inst1 lane config + PLL allocation in current peri.xml."""
import os, sys, re
from pathlib import Path
PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")
txt = GOLDEN.read_text(encoding="utf-8")

# mipi_dphy_tx_inst1 block
m = re.search(r'(<efxpt:mipi name="mipi_dphy_tx_inst1".*?</efxpt:mipi>)', txt, re.DOTALL)
if m:
    blk = m.group(1)
    print(f"=== mipi_dphy_tx_inst1 ({len(blk)} bytes) ===")
    print(blk[:600])
    # Count lane references inside
    lane_count = len(re.findall(r'LAN[0-3]', blk))
    print(f"\n  LAN0..3 references: {lane_count}")
    # Look for lane_num / num_lane properties
    for prop in ("lane_num", "num_lane", "data_lane", "NUM_DATA_LANE", "ops_type"):
        if prop.lower() in blk.lower():
            for line in blk.split("\n"):
                if prop.lower() in line.lower():
                    print(f"  {line.strip()[:140]}")

# PLL allocation
print("\n=== PLL allocation ===")
for m in re.finditer(r'<efxpt:pll\s+name="([^"]+)"\s+pll_def="([^"]+)"', txt):
    print(f"  {m.group(1):18} -> {m.group(2)}")

# All PLL defs supported by TJ180A484S (informational — would need device query)
print("\n=== mipi_dphy_rx_inst2 block (lane info) ===")
m2 = re.search(r'(<efxpt:mipi name="mipi_dphy_rx_inst2".*?</efxpt:mipi>)', txt, re.DOTALL)
if m2:
    blk2 = m2.group(1)
    print(f"  size: {len(blk2)} bytes")
    # Count lanes
    for ln in range(4):
        n = len(re.findall(rf'LAN{ln}', blk2))
        print(f"  LAN{ln} refs: {n}")
