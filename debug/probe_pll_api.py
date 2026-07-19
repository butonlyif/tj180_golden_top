"""Probe PLL block properties via DesignAPI so we can replicate for pll_pixel."""
import os
import sys
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")

d = DesignAPI(is_verbose=False)
d.load(str(GOLDEN))

# List PLL properties on existing pll_sys
print("=== get_all_property(block_type='PLL') ===")
try:
    ap = d.get_all_property(block_type="PLL")
    if isinstance(ap, dict):
        for k, v in ap.items():
            print(f"  {k}")
    else:
        print(f"  type={type(ap).__name__} value={str(ap)[:200]}")
except Exception as e:
    print(f"  FAILED: {e}")

# Read all properties of existing pll_sys to use as template
print("\n=== pll_sys properties (template for pll_pixel) ===")
try:
    p = d.get_property("pll_sys", list(d.get_all_property(block_type="PLL").keys()) if isinstance(d.get_all_property(block_type="PLL"), dict) else None, block_type="PLL")
    for k, v in p.items():
        print(f"  {k:30} = {v}")
except Exception as e:
    print(f"  FAILED: {e}")

# Probe create_block signature
print("\n=== create_block signature ===")
import inspect
sig = inspect.signature(d.create_block)
print(f"  create_block{sig}")

# List available PLL defs for TJ180A484S
print("\n=== Try get_all_block_name('PLL') ===")
print(f"  PLLs: {d.get_all_block_name('PLL')}")
