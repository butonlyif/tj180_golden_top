#!/usr/bin/env python3
"""
Tool-driven DDR configuration for tj180_golden_top.

Uses Efinity's DesignAPI (the same API the GUI / efx_run_pt_import_isf.py use)
to produce a peri.xml with the DDR hard block + pll_ddr configured for the
TJ180A484S chip.

Strategy:
  1. Seed from TJ180A484S_SDHOST peri.xml (same chip, working LPDDR4x DDR_0).
  2. Query the DDR preset actually applied (reproducibility / audit).
  3. Rename the design_db to the golden_top project name.
  4. Save as <golden_top>/tj180_golden_top.peri.xml (tool-emitted, not hand-written).
"""
import os
import sys
import shutil
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

EFX_VER = "2026.1.132.1.15"
SDHOST_PERI = Path(r"D:\work\trae_projects\awesom_project\original\proj\TJ180A484S_SDHOST\TJ180A484S\TJ180A484S.peri.xml")
GOLDEN_PERI = Path(r"D:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")

design = DesignAPI(is_verbose=True)

print(f"INFO: Loading seed peri.xml: {SDHOST_PERI}")
design.load(str(SDHOST_PERI))
print("INFO: Load done.")

# --- Audit the DDR configuration that is already valid for TJ180A484S ---
print("\n=== DDR audit ===")
try:
    preset_id, preset_desc = design.get_preset("ddr_inst", "DDR")
    print(f"ddr_inst PRESET id   = {preset_id}")
    print(f"ddr_inst PRESET desc = {preset_desc}")
except Exception as e:
    print(f"WARN: get_preset('ddr_inst') failed: {e}")

# List available presets for reference (so the choice is auditable)
try:
    all_presets = design.get_all_preset_info("ddr_inst", "DDR")
    print(f"\nAvailable DDR presets for ddr_inst ({len(all_presets)} total):")
    for pid, pdesc in all_presets[:20]:
        mark = "  <== APPLIED" if pid == preset_id else ""
        print(f"  {pid}  |  {pdesc}{mark}")
except Exception as e:
    print(f"WARN: get_all_preset_info failed: {e}")

# --- pll_ddr audit ---
print("\n=== PLL audit ===")
try:
    for pll_name in ("pll_ddr", "pll_sys"):
        try:
            pid, pdesc = design.get_preset(pll_name, "PLL")
            print(f"{pll_name} preset: {pid} | {pdesc}")
        except Exception:
            # PLL may not use presets; just confirm block exists
            print(f"{pll_name}: (no preset API / present in design)")
except Exception as e:
    print(f"WARN: PLL audit failed: {e}")

# --- Emit golden_top peri.xml ---
print(f"\nINFO: Saving as: {GOLDEN_PERI}")
GOLDEN_PERI.parent.mkdir(parents=True, exist_ok=True)
design.save_as(str(GOLDEN_PERI), overwrite=True)
print("INFO: Save done.")

# Patch the design_db name attribute to match the golden_top project.
# Target the opening tag unambiguously (device_def="TJ180A484S" must NOT be touched).
txt = GOLDEN_PERI.read_text(encoding="utf-8")
before = '<efxpt:design_db name="TJ180A484S"'
after = '<efxpt:design_db name="tj180_golden_top"'
assert before in txt, "design_db opening tag not found — seed format changed?"
txt = txt.replace(before, after, 1)
GOLDEN_PERI.write_text(txt, encoding="utf-8")
print(f"INFO: Patched design_db name -> 'tj180_golden_top'")

# Sanity: confirm DDR section present in emitted file
emitted = GOLDEN_PERI.read_text(encoding="utf-8")
print("\n=== Emitted file sanity ===")
print(f"size              = {len(emitted)} bytes")
checks = {
    "contains ddr_info": "<efxpt:ddr_info>" in emitted,
    "contains adv_ddr": "<efxpt:adv_ddr" in emitted,
    "mem_type LPDDR4x": 'mem_type="LPDDR4x"' in emitted,
    "contains pll_ddr": '<efxpt:pll name="pll_ddr"' in emitted,
}
for label, ok in checks.items():
    print(f"  {label:22} = {ok}")
print("\nDONE.")
