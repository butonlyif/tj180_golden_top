#!/usr/bin/env python3
"""
Add pll_pixel block to peri.xml at PLL_TL1 (the only free PLL slot on TJ180A484S).

Target: 148.5 MHz output on CLKOUT0 (CTA-861 4K UHD standard pixel clock).
Reference: clk_50m (same EXT_CLK1 ref as pll_sys).

After this, the top RTL needs to:
  - declare input wire pll_pixel_CLKOUT0
  - assign clk_pixel_rx/clk_pixel_tx = pll_pixel_CLKOUT0
  - SDC: declare clk_pixel create_clock + async clock group
"""
import os
import sys
import shutil
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")
BACKUP = GOLDEN.with_suffix(".peri.xml.bak_pre_pll_pixel")

shutil.copyfile(GOLDEN, BACKUP)
print(f"backup -> {BACKUP.name}")

d = DesignAPI(is_verbose=False)
d.load(str(GOLDEN))
print("load OK")

# Sanity: ensure PLL_TL1 is free
existing_plls = d.get_all_block_name("PLL")
print(f"existing PLLs: {existing_plls}")
assert "pll_pixel" not in existing_plls, "pll_pixel already exists"
assert "PLL_TL1" not in str(d.get_property("pll_sys", "RESOURCE", block_type="PLL")) \
    and "PLL_TL1" not in str(d.get_property("pll_ddr", "RESOURCE", block_type="PLL")) \
    and "PLL_TL1" not in str(d.get_property("pll_ethernet", "RESOURCE", block_type="PLL")), \
    "PLL_TL1 already in use"

# --- Create pll_pixel block ---
print("\n--- create_block('pll_pixel', 'PLL') ---")
try:
    oid = d.create_block("pll_pixel", "PLL")
    print(f"  created, oid = {oid}")
except Exception as e:
    print(f"  FAILED: {e}")
    raise

# --- Configure: match pll_sys pattern but at PLL_TL1 + 148.5 MHz CLKOUT0 ---
# Use dict form to set many properties at once
target_freq = "148.5"   # CTA-861 4K UHD pixel clock
props = {
    "RESOURCE":      "PLL_TL1",
    "REFCLK":        "EXT_CLK1",   # same external ref as pll_sys (= clk_50m)
    "REFCLK_FREQ":   "50.0",
    "REFCLK_SOURCE": "EXTERNAL",
    "FEEDBACK_MODE": "LOCAL",
    "FEEDBACK_CLK":  "CLK0",
    # CLKOUT0 — 148.5 MHz, the pixel clock output
    "CLKOUT0_EN":      "1",
    "CLKOUT0_FREQ":    target_freq,
    "CLKOUT0_PIN":     "pll_pixel_CLKOUT0",
    "CLKOUT0_CONN_TYPE": "GCLK",
    "CLKOUT0_PHASE":   "0.0",
    "CLKOUT0_INVERT_EN": "0",
    # Disable other CLKOUTs (single output is enough)
    "CLKOUT1_EN":      "0",
    "CLKOUT2_EN":      "0",
    "CLKOUT3_EN":      "0",
    "CLKOUT4_EN":      "0",
    # LOCKED output pin (top-level input)
    "LOCKED_PIN":      "pll_pixel_LOCKED",
}
print(f"\n--- set_property (target CLKOUT0_FREQ = {target_freq} MHz) ---")
for k, v in props.items():
    try:
        d.set_property("pll_pixel", k, v, block_type="PLL")
    except Exception as e:
        print(f"  {k:20} = {v:10}  -> FAIL: {e}")
print("  (all set_property calls attempted)")

# Verify the resource + frequency actually took
print("\n--- verify ---")
try:
    res = d.get_property("pll_pixel", "RESOURCE", block_type="PLL")
    print(f"  RESOURCE       = {res}")
except Exception as e:
    print(f"  RESOURCE FAIL: {e}")
try:
    f = d.get_property("pll_pixel", "CLKOUT0_FREQ", block_type="PLL")
    print(f"  CLKOUT0_FREQ   = {f}")
except Exception as e:
    print(f"  CLKOUT0_FREQ FAIL: {e}")
try:
    m = d.get_property("pll_pixel", "M", block_type="PLL")
    n = d.get_property("pll_pixel", "N", block_type="PLL")
    o = d.get_property("pll_pixel", "O", block_type="PLL")
    div = d.get_property("pll_pixel", "CLKOUT0_DIV", block_type="PLL")
    print(f"  M={m}  N={n}  O={o}  CLKOUT0_DIV={div}")
except Exception as e:
    print(f"  divider read FAIL: {e}")

# --- Save + validate ---
print("\n--- save ---")
d.save_as(str(GOLDEN), overwrite=True)
print(f"  saved -> {GOLDEN.name} ({GOLDEN.stat().st_size} bytes)")

print("\n--- reload validation ---")
d2 = DesignAPI(is_verbose=False)
d2.load(str(GOLDEN))
final_plls = d2.get_all_block_name("PLL")
print(f"  PLLs after: {final_plls}")
assert "pll_pixel" in final_plls, "pll_pixel missing after reload!"

print("\nDONE.")
print("Next: top RTL needs input wire pll_pixel_CLKOUT0 + assign clk_pixel_rx/tx = pll_pixel_CLKOUT0")
print("      SDC needs: create_clock + set_clock_groups -asynchronous for clk_pixel")
