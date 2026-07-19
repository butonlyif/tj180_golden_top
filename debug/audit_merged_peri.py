"""Final audit: enumerate every hard IP block and GPIO in the merged peri.xml."""
import os
import sys
import re
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")
txt = GOLDEN.read_text(encoding="utf-8")

print(f"=== File: {GOLDEN.name}  ({len(txt)} bytes) ===\n")

# Hard IP block summary by regex (faster than full DesignAPI enumeration)
block_patterns = [
    ("PLL",         r'<efxpt:pll\s+name="([^"]+)"\s+pll_def="([^"]+)"'),
    ("DDR",         r'<efxpt:ddr\s+name="([^"]+)"'),
    ("MIPI DPHY",   r'<efxpt:mipi\s+name="([^"]+)"\s+mipi_def="([^"]+)"'),
    ("JTAG",        r'<efxpt:jtag\s+name="([^"]+)"\s+jtag_def="([^"]+)"'),
]
for label, pat in block_patterns:
    matches = re.findall(pat, txt)
    print(f"{label:12} ({len(matches)}):")
    for m in matches:
        print(f"  - {m}")
print()

# GPIO summary
gpio_names = re.findall(r'<efxpt:comp_gpio\s+name="([^"]+)"', txt)
print(f"GPIO total ({len(gpio_names)}):")
for n in gpio_names:
    print(f"  - {n}")
print()

# PLL CLKOUT outputs that will appear as top-level input ports
clkouts = re.findall(r'clock_name="(pll_\w+_CLKOUT\d)"', txt)
print(f"PLL CLKOUT outputs (top-level input ports): {sorted(set(clkouts))}")

locked_sigs = re.findall(r'locked_name="(pll_\w+_locked)"', txt)
print(f"PLL LOCKED outputs (top-level input ports): {sorted(set(locked_sigs))}")

# DesignAPI final validation
print("\n=== Efinity DesignAPI final acceptance test ===")
d = DesignAPI(is_verbose=False)
d.load(str(GOLDEN))
print("DesignAPI.load() OK — Efinity accepts the merged peri.xml")

# Compare with backup (empty stage) for delta
backup = GOLDEN.with_suffix(".peri.xml.bak_empty_stage")
if backup.exists():
    btxt = backup.read_text(encoding="utf-8")
    print(f"\n=== Delta vs backup ({backup.name}, {len(btxt)} bytes) ===")
    print(f"  size: {len(btxt)} -> {len(txt)} bytes ({(len(txt)/len(btxt)-1)*100:.0f}% growth)")
    for label, pat in block_patterns:
        before = len(re.findall(pat, btxt))
        after  = len(re.findall(pat, txt))
        print(f"  {label:12} blocks: {before} -> {after}")

print("\nDONE.")
