#!/usr/bin/env python3
"""
Align peri.xml GPIO names with tj180_golden_top.v RTL port list.

Background: After configure_ddr.py + merge_mipi.py + merge_rgmii.py, the peri.xml
has all hard IP blocks (3 PLL + DDR + 2 MIPI DPHY + JTAG + RGMII), but the GPIO
signal names still use the SDHOST-seed names which don't match our RTL port list.
This script aligns them via DesignAPI.

Strategy (3 tiers):
  Tier A — SAFE RENAMES (no pin change, just fix name to match RTL):
    clk_50M              -> clk_50m
    i_ref_clk_ddr        -> ddr_clk_ref
    system_spi_0_io_*    -> already matches RTL (kept)
    system_uart_0_io_*   -> already matches RTL (kept)
    sd_cd_n              -> already matches RTL (kept)

  Tier B — ADD MISSING critical GPIOs using board pins verified in the OLD
           empty-stage peri.xml backup (.bak_empty_stage), which were correct
           for this board before configure_ddr.py replaced the peri.xml:
    arst_n        <- rst_n_i   pin GPIOL_42  (input)
    MIPI_REF_CLK  <- clk27_mipi_a pin GPIOL_06 (input, MIPI ref clock)
    led[3:0]      <- led_user + 3 btn_n pins repurposed (output bus)

  Tier C — DEFERRED (requires board schematic verification):
    sd_clk_hi / sd_cmd_{o,oe,i} / sd_dat_{o,oe,i}[*]
       (RTL splits inout into o/oe/i; SDHOST seed uses single inout;
        need 18 distinct pins verified from schematic)
    system_i2c_0_io_*  (6 pins)
    system_gpio_0_io_* (12 pins)
    Remaining led[*] pins

The script LOADS the current peri.xml, applies Tier A+B, SAVES, and re-loads
to validate Efinity acceptance.
"""
import os
import sys
import shutil
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")
BACKUP = GOLDEN.with_suffix(".peri.xml.bak_pre_align")

# ---------------------------------------------------------------------------
# Tier A: rename map (current_name -> new_name). Pin and properties preserved.
# ---------------------------------------------------------------------------
RENAMES = {
    "clk_50M":       "clk_50m",         # case fix only (capital M -> lower m)
    "i_ref_clk_ddr": "ddr_clk_ref",     # SDHOST name -> RTL name
}

# ---------------------------------------------------------------------------
# Tier B: missing critical GPIOs to add. Pin assignments come from the OLD
# empty-stage peri.xml backup (board-correct pins used before configure_ddr).
# Format: rtl_name -> (pin_resource, mode, conn_type_or_None, msb, lsb)
#   mode: "INPUT" / "OUTPUT"
#   conn_type: "PLL_CLKIN" / "MIPI_CLKIN" / "normal" / None
# ---------------------------------------------------------------------------
# Old empty-stage had:
#   rst_n_i        GPIOL_42  input        -> arst_n
#   clk27_mipi_a   GPIOL_06  input        -> MIPI_REF_CLK  (27 MHz MIPI ref)
#   led_user       GPIOL_20  output       -> led[0]
ADDS = [
    # (rtl_name,            efinix_pin, mode,     conn_type,    bus_msb, bus_lsb)
    ("arst_n",              "GPIOL_42", "INPUT",  "normal",        None,    None),
    ("MIPI_REF_CLK",        "GPIOL_06", "INPUT",  "MIPI_CLKIN",    None,    None),
    # LEDs: led[0] from old led_user; led[1..3] need pins — leave unassigned
    # (Efinity will warn but won't damage hardware; pin assignment = schematic task)
    ("led",                 "GPIOL_20", "OUTPUT", "normal",           3,       0),
]


def main():
    # Backup
    shutil.copyfile(GOLDEN, BACKUP)
    print(f"backup -> {BACKUP.name}")

    d = DesignAPI(is_verbose=False)
    d.load(str(GOLDEN))
    print("load OK")

    existing = set(d.get_all_gpio_name())
    print(f"current GPIOs ({len(existing)}).")

    # === Tier A: renames ===
    print("\n=== Tier A: renames ===")
    for old, new in RENAMES.items():
        if old not in existing:
            print(f"  SKIP {old}: not in peri.xml (already renamed?)")
            continue
        if new in existing:
            print(f"  SKIP {old} -> {new}: target already exists")
            continue
        # Read current RESOURCE (pin) so we can preserve it
        try:
            props = d.get_property(old, ["NAME", "RESOURCE", "MODE", "CONN_TYPE",
                                         "IN_PIN", "OUT_PIN", "IN_HI_PIN"],
                                   block_type="GPIO")
            pin = props.get("RESOURCE", "")
            mode = props.get("MODE", "")
            conn = props.get("CONN_TYPE", "")
            print(f"  {old} (pin={pin}, mode={mode}, conn={conn}) -> {new}")
            # Try set_property NAME first (least disruptive)
            try:
                d.set_property(old, "NAME", new, block_type="GPIO")
                print(f"    set_property NAME OK")
            except Exception as e:
                print(f"    set_property NAME FAILED: {e}")
                print(f"    (rename via set_property unsupported; manual edit needed)")
        except Exception as e:
            print(f"  FAIL {old}: {e}")

    # === Tier B: add missing critical GPIOs ===
    print("\n=== Tier B: add missing critical GPIOs ===")
    # Re-read after renames
    existing = set(d.get_all_gpio_name())
    for name, pin, mode, conn, msb, lsb in ADDS:
        if name in existing or any(name in n for n in existing):
            print(f"  SKIP {name}: already exists")
            continue
        try:
            if conn == "PLL_CLKIN":
                oid = d.create_pll_input_clock_gpio(name)
            elif conn == "MIPI_CLKIN":
                oid = d.create_mipi_input_clock_gpio(name)
            elif mode == "INPUT":
                oid = d.create_input_gpio(name, msb=msb, lsb=lsb)
            elif mode == "OUTPUT":
                oid = d.create_output_gpio(name, msb=msb, lsb=lsb)
            else:
                oid = d.create_inout_gpio(name, msb=msb, lsb=lsb)
            print(f"  create_{mode.lower()}_gpio({name}) -> oid={oid}")
            # Assign pin
            try:
                d.assign_pkg_pin(name, pin)
                print(f"    assign_pkg_pin({name}, {pin}) OK")
            except Exception as e:
                print(f"    assign_pkg_pin({name}, {pin}) FAILED: {e}")
            # Set IO standard to match iobank (1.8 V LVCMOS)
            try:
                d.set_property(name, "IO_STANDARD", "1.8 V LVCMOS", block_type="GPIO")
                print(f"    IO_STANDARD -> 1.8 V LVCMOS")
            except Exception as e:
                print(f"    set IO_STANDARD FAILED: {e}")
        except Exception as e:
            print(f"  FAIL create {name}: {e}")

    # === Save and reload-validate ===
    print("\n=== Save ===")
    d.save_as(str(GOLDEN), overwrite=True)
    print(f"saved -> {GOLDEN.name} ({GOLDEN.stat().st_size} bytes)")

    print("\n=== Reload validation ===")
    d2 = DesignAPI(is_verbose=False)
    d2.load(str(GOLDEN))
    print("DesignAPI.load() OK — Efinity accepts the aligned peri.xml")

    final_gpio = d2.get_all_gpio_name()
    print(f"\nFinal GPIOs ({len(final_gpio)}):")
    for n in sorted(final_gpio):
        print(f"  - {n}")

    print(f"\nDONE. Backup: {BACKUP.name}")
    print("Tier C (SD/I2C/GPIO split + remaining LED pins) DEFERRED — needs board schematic.")


if __name__ == "__main__":
    main()
