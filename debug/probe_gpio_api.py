"""Probe DesignAPI GPIO manipulation interface on the current merged peri.xml.

Discovers:
  - Whether `set_property(inst, "name", new_name)` works as rename
  - How to read current pin assignment
  - What block_type string GPIO uses
  - Sample property names for a GPIO
"""
import os
import sys
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")

d = DesignAPI(is_verbose=False)
d.load(str(GOLDEN))
print("load OK")

# 1. Try get_all_gpio_name
try:
    names = d.get_all_gpio_name()
    print(f"\nget_all_gpio_name() -> {len(names)} GPIOs:")
    for n in names[:10]:
        print(f"  - {n}")
except Exception as e:
    print(f"get_all_gpio_name FAILED: {e}")

# 2. Try get_gpio to get object id, then get_property
if names:
    target = "clk_50M" if "clk_50M" in names else names[0]
    print(f"\n--- probe '{target}' ---")
    try:
        oid = d.get_gpio(target)
        print(f"get_gpio('{target}') -> object_id = {oid}")
    except Exception as e:
        print(f"get_gpio FAILED: {e}")
        oid = None

    if oid is not None:
        # List ALL properties on this GPIO
        try:
            props = d.get_property(target, list(d.get_all_property(block_type="GPIO").keys()) if isinstance(d.get_all_property(block_type="GPIO"), dict) else None, block_type="GPIO")
            print(f"get_property (all): {props}")
        except Exception as e:
            print(f"get_property (all) FAILED: {e}")

        # Try individual property reads
        for prop in ["name", "gpio_def", "pin_name", "mode", "io_standard", "out_pin_type", "in_pin_type"]:
            try:
                v = d.get_property(target, prop, block_type="GPIO")
                print(f"  {prop:18} = {v}")
            except Exception as e:
                print(f"  {prop:18} -> FAIL: {e}")

        # Try get_pkg_pin
        try:
            pin = d.get_pkg_pin(target)
            print(f"  get_pkg_pin        = {pin}")
        except Exception as e:
            print(f"  get_pkg_pin FAIL: {e}")

# 3. Try get_all_property for block_type=GPIO to enumerate property names
print("\n--- get_all_property(block_type='GPIO') ---")
try:
    ap = d.get_all_property(block_type="GPIO")
    if isinstance(ap, dict):
        for k, v in list(ap.items())[:20]:
            print(f"  {k}: {v}")
    else:
        print(f"  returned: {type(ap).__name__}: {str(ap)[:200]}")
except Exception as e:
    print(f"  FAILED: {e}")

# 4. block_type strings
print("\n--- get_block_type (after load) ---")
try:
    bt = d.get_block_type()
    print(f"  {bt}")
except Exception as e:
    print(f"  FAILED: {e}")

print("\nDONE.")
