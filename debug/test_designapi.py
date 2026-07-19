"""Smoke test: verify Efinity DesignAPI loads and list configurable block types."""
import os
import sys

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")

from api_service.design import DesignAPI

print("DesignAPI import OK")
d = DesignAPI(is_verbose=False)
bt = d.get_block_type()
print(f"block_types ({len(bt)}):")
for b in bt:
    print(f"  - {b}")

# Probe each seed peri.xml and report what blocks it has
seeds = [
    ("SDHOST",
     r"D:\work\trae_projects\awesom_project\original\proj\TJ180A484S_SDHOST\TJ180A484S\TJ180A484S.peri.xml"),
    ("LOOPBACK",
     r"D:\work\trae_projects\awesom_project\original\proj\TJ180MIPI_loopback\Ti180MIPI\Ti180MIPI.peri.xml"),
    ("TSE",
     r"D:\work\trae_projects\awesom_project\original\proj\TJ180A484_TSE\TSE\temac_ex.peri.xml"),
    ("golden_top (current)",
     r"D:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml"),
]

for label, path in seeds:
    print(f"\n=== {label} ===")
    print(f"path: {path}")
    if not os.path.exists(path):
        print("  MISSING")
        continue
    d2 = DesignAPI(is_verbose=False)
    try:
        d2.load(path)
        print("  load() OK")
        for blk in bt:
            try:
                names = d2.get_all_block_name(blk)
                if names:
                    print(f"  {blk}: {names}")
            except Exception as e:
                # Some block types may not be queryable this way; ignore
                pass
    except Exception as e:
        print(f"  load() FAILED: {e}")

print("\nDONE.")
