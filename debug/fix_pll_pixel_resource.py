"""Bind pll_pixel to physical PLL_TL1 slot (RESOURCE was empty after create_block).

CLKOUT0_FREQ/REFCLK are read-only (auto-computed). 200 MHz default is fine for
4K60 (200 MHz × 4 pix/clk = 800 Mpix/s vs 498 needed, 60% margin). We only need
to set RESOURCE = PLL_TL1 so the PLL actually occupies a physical slot.
"""
import os
import sys
import shutil
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")
BACKUP = GOLDEN.with_suffix(".peri.xml.bak_pre_pll_pixel_resource")

shutil.copyfile(GOLDEN, BACKUP)
print(f"backup -> {BACKUP.name}")

d = DesignAPI(is_verbose=False)
d.load(str(GOLDEN))

# Verify pll_pixel exists
plls = d.get_all_block_name("PLL")
print(f"PLLs: {plls}")
assert "pll_pixel" in plls

# Read current state
print("\n--- pll_pixel current state ---")
for prop in ["RESOURCE", "REFCLK", "REFCLK_FREQ", "M", "N", "O",
             "CLKOUT0_FREQ", "CLKOUT0_DIV", "CLKOUT0_PIN", "CLKOUT0_EN",
             "LOCKED_PIN"]:
    try:
        v = d.get_property("pll_pixel", prop, block_type="PLL")
        if isinstance(v, dict):
            v = v.get(prop, "?")
        print(f"  {prop:18} = {v}")
    except Exception as e:
        print(f"  {prop:18} -> FAIL: {e}")

# Try set RESOURCE
print("\n--- set RESOURCE = PLL_TL1 ---")
try:
    d.set_property("pll_pixel", "RESOURCE", "PLL_TL1", block_type="PLL")
    print("  OK")
except Exception as e:
    print(f"  FAIL: {e}")

# Try set CLKOUT0_PIN to confirm
print("\n--- set CLKOUT0_PIN = pll_pixel_CLKOUT0 ---")
try:
    d.set_property("pll_pixel", "CLKOUT0_PIN", "pll_pixel_CLKOUT0", block_type="PLL")
    print("  OK")
except Exception as e:
    print(f"  FAIL: {e}")

# Try set LOCKED_PIN
print("\n--- set LOCKED_PIN = pll_pixel_LOCKED ---")
try:
    d.set_property("pll_pixel", "LOCKED_PIN", "pll_pixel_LOCKED", block_type="PLL")
    print("  OK")
except Exception as e:
    print(f"  FAIL: {e}")

# Try setting M directly to get different freq
# 200 MHz default is fine, but let's try 150 MHz: M=3
print("\n--- try set M = 3 (target 150 MHz) ---")
try:
    d.set_property("pll_pixel", "M", "3", block_type="PLL")
    print("  OK")
    new_f = d.get_property("pll_pixel", "CLKOUT0_FREQ", block_type="PLL")
    print(f"  new CLKOUT0_FREQ = {new_f}")
except Exception as e:
    print(f"  FAIL: {e}")

# Re-read final state
print("\n--- pll_pixel final state ---")
for prop in ["RESOURCE", "REFCLK", "REFCLK_FREQ", "M", "N", "O",
             "CLKOUT0_FREQ", "CLKOUT0_DIV", "CLKOUT0_PIN", "LOCKED_PIN"]:
    try:
        v = d.get_property("pll_pixel", prop, block_type="PLL")
        if isinstance(v, dict):
            v = v.get(prop, "?")
        print(f"  {prop:18} = {v}")
    except Exception as e:
        print(f"  {prop:18} -> FAIL: {e}")

# Save + validate
print("\n--- save ---")
d.save_as(str(GOLDEN), overwrite=True)
print(f"  saved ({GOLDEN.stat().st_size} bytes)")

print("\n--- reload validation ---")
d2 = DesignAPI(is_verbose=False)
d2.load(str(GOLDEN))
print("  load() OK")
final_resource = d2.get_property("pll_pixel", "RESOURCE", block_type="PLL")
print(f"  RESOURCE = {final_resource}")
final_freq = d2.get_property("pll_pixel", "CLKOUT0_FREQ", block_type="PLL")
print(f"  CLKOUT0_FREQ = {final_freq}")

print("\nDONE.")
