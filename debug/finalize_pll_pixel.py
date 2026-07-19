"""Finalize pll_pixel via direct XML edit (DesignAPI set_property is buggy for RESOURCE).

Sets:
  - RESOURCE: "" -> "PLL_TL1"   (bind to physical PLL slot)
  - ref_clock_name: "" -> "clk_50m"  (so it shares the clk_50m pad with pll_sys)
  - REFCLK source alignment (ensure it uses the same ext clk as pll_sys)

Default 200 MHz output is kept (sufficient for 4K60 YUV422: 200×4=800 Mpix/s vs 498 needed).
"""
import os
import sys
import shutil
import re
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")
BACKUP = GOLDEN.with_suffix(".peri.xml.bak_pre_pll_pixel_xml")

shutil.copyfile(GOLDEN, BACKUP)
print(f"backup -> {BACKUP.name}")

txt = GOLDEN.read_text(encoding="utf-8")
orig_len = len(txt)

# Find pll_pixel block
m = re.search(r'(<efxpt:pll\s+name="pll_pixel"[^>]*?>)', txt)
if not m:
    print("ERROR: pll_pixel opening tag not found")
    sys.exit(1)
opening = m.group(1)
print(f"original opening tag ({len(opening)} bytes):")
print(f"  {opening}")

# Parse current attributes
attrs = dict(re.findall(r'(\w+)="([^"]*)"', opening))
print(f"\ncurrent pll_def: {attrs.get('pll_def', '<missing>')}")
print(f"current ref_clock_name: '{attrs.get('ref_clock_name', '<missing>')}'")

# Apply fixes
new_opening = opening

# 1. Insert pll_def="PLL_TL1" if missing, or replace empty
if 'pll_def' not in attrs or not attrs.get('pll_def'):
    if 'pll_def=""' in new_opening:
        new_opening = new_opening.replace('pll_def=""', 'pll_def="PLL_TL1"', 1)
    else:
        # Insert after name="pll_pixel"
        new_opening = new_opening.replace(
            'name="pll_pixel"',
            'name="pll_pixel" pll_def="PLL_TL1"',
            1
        )
    print("\n  + added pll_def=\"PLL_TL1\"")

# 2. Set ref_clock_name to clk_50m (shares the clk_50m input pad)
if 'ref_clock_name=""' in new_opening:
    new_opening = new_opening.replace('ref_clock_name=""', 'ref_clock_name="clk_50m"', 1)
    print("  + set ref_clock_name=\"clk_50m\"")
elif 'ref_clock_name="clk_50m"' not in new_opening:
    # Insert ref_clock_name attribute
    new_opening = new_opening.replace(
        'name="pll_pixel"',
        'name="pll_pixel" ref_clock_name="clk_50m"',
        1
    )
    print("  + inserted ref_clock_name=\"clk_50m\"")

print(f"\nnew opening tag ({len(new_opening)} bytes):")
print(f"  {new_opening}")

# Splice back
txt = txt.replace(opening, new_opening, 1)

# Save
GOLDEN.write_text(txt, encoding="utf-8")
print(f"\nsaved: {orig_len} -> {len(txt)} bytes")

# Validate with DesignAPI
print("\n=== DesignAPI validation ===")
d = DesignAPI(is_verbose=False)
d.load(str(GOLDEN))
print("load() OK")

# Re-extract pll_pixel attributes from saved file
txt2 = GOLDEN.read_text(encoding="utf-8")
m2 = re.search(r'<efxpt:pll\s+name="pll_pixel"[^>]*>', txt2)
final_attrs = dict(re.findall(r'(\w+)="([^"]*)"', m2.group(0)))
print(f"\nFinal pll_pixel attributes:")
for k in ("name", "pll_def", "ref_clock_name", "ref_clock_freq",
         "multiplier", "locked_name"):
    print(f"  {k:20} = {final_attrs.get(k, '<missing>')}")

# PLL slot allocation overview
print("\n=== Final PLL allocation ===")
for m in re.finditer(r'<efxpt:pll\s+name="([^"]+)"[^>]*pll_def="([^"]+)"', txt2):
    print(f"  {m.group(1):15} -> {m.group(2)}")

print("\nDONE.")
