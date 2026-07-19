#!/usr/bin/env python3
"""
Fix the rename that set_property(NAME) didn't actually do.

align_gpio.py reported "set_property NAME OK" but get_all_gpio_name() still
returned the old names. The DesignAPI set_property updates an internal dict
but doesn't re-key the instance. The reliable way is direct XML text replace
on the peri.xml — the rename targets are unique strings.

Renames (substring -> replacement):
  clk_50M        -> clk_50m         (case fix; affects name attrs + derived _PIN)
  i_ref_clk_ddr  -> ddr_clk_ref     (SDHOST name -> RTL name)

Both strings are unique enough that global replace is safe (they appear in
<efxpt:comp_gpio name="...">, <efxpt:input_config name="...">, IN_PIN,
IN_HI_PIN, *_PULL_UP_ENA, *_DLY_*, etc. — all should rename together).
"""
import os
import sys
import shutil
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")

RENAMES = [
    ("clk_50M",       "clk_50m"),
    ("i_ref_clk_ddr", "ddr_clk_ref"),
]

# Backup
bak = GOLDEN.with_suffix(".peri.xml.bak_pre_rename_fix")
shutil.copyfile(GOLDEN, bak)
print(f"backup -> {bak.name}")

# Read
txt = GOLDEN.read_text(encoding="utf-8")
orig_len = len(txt)

# Count occurrences before replace (sanity)
for old, new in RENAMES:
    n = txt.count(old)
    print(f"  '{old}' appears {n} times")

# Apply replacements
for old, new in RENAMES:
    txt = txt.replace(old, new)

# Write
GOLDEN.write_text(txt, encoding="utf-8")
print(f"\nrewrote {GOLDEN.name}: {orig_len} -> {len(txt)} bytes")

# Validate: load with DesignAPI
print("\n=== Reload validation ===")
d = DesignAPI(is_verbose=False)
d.load(str(GOLDEN))
print("DesignAPI.load() OK")

gpio = d.get_all_gpio_name()
print(f"\nFinal GPIOs ({len(gpio)}):")
for n in sorted(gpio):
    mark = " <== RENAMED" if n in ("clk_50m", "ddr_clk_ref") else ""
    mark = " <== ADDED" if n in ("arst_n", "MIPI_REF_CLK") or n.startswith("led[") else mark
    print(f"  - {n}{mark}")

# Sanity check: confirm old names gone, new names present
remaining_old = [old for old, _ in RENAMES if old in gpio]
present_new   = [new for _, new in RENAMES if new in gpio]
print(f"\nOld names still present: {remaining_old} (should be [])")
print(f"New names now present:   {present_new} (should match {dict(RENAMES).values()})")

print("\nDONE.")
