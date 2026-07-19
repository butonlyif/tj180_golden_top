"""Final validation after Pixel PLL + DDR sys_clk fix."""
import os, sys
from pathlib import Path
PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")

d = DesignAPI(is_verbose=False)
d.load(str(GOLDEN))
print("DesignAPI.load() OK")
print(f"PLLs: {d.get_all_block_name('PLL')}")
print(f"DDR : {d.get_all_block_name('DDR')}")

# Summary table
import re
txt = GOLDEN.read_text(encoding="utf-8")
print("\n=== PLL summary ===")
for m in re.finditer(r'<efxpt:pll\s+name="([^"]+)"[^>]*pll_def="([^"]+)"[^>]*ref_clock_freq="([^"]+)"[^>]*multiplier="([^"]+)"', txt):
    name, pll_def, refreq, mult = m.groups()
    try:
        # Approximate output freq
        fout = float(refreq) * float(mult)
        print(f"  {name:15} {pll_def:8}  ref={refreq}MHz mult={mult}  ~{fout:.0f} MHz out")
    except Exception:
        print(f"  {name:15} {pll_def:8}  ref={refreq} mult={mult}")

print("\nDONE.")
