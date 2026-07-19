"""Audit Pixel PLL availability + DDR state for 4K60 production path."""
import os
import sys
import re
from pathlib import Path

PT_HOME = os.environ['EFXPT_HOME']
sys.path.append(PT_HOME + "/bin")
from api_service.design import DesignAPI

GOLDEN = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.peri.xml")
txt = GOLDEN.read_text(encoding="utf-8")

print(f"=== peri.xml: {len(txt)} bytes ===\n")

# ---------- 1. PLL inventory ----------
print("=== 1. PLL inventory ===")
plls = re.findall(
    r'<efxpt:pll\s+name="([^"]+)"\s+pll_def="([^"]+)"[^>]*?'
    r'ref_clock_freq="([^"]+)"[^>]*?'
    r'multiplier="([^"]+)"[^>]*?'
    r'pre_divider="([^"]+)"[^>]*?'
    r'post_divider="([^"]+)"',
    txt
)
# Efinix TJ180A484S PLL resources: PLL_TL0, PLL_TL1, PLL_TL2 (left/bottom), PLL_TR0 (right)
ALL_PLL_DEFS = ["PLL_TL0", "PLL_TL1", "PLL_TL2", "PLL_TR0"]
used_defs = set()
for name, pll_def, refreq, mult, pre, post in plls:
    used_defs.add(pll_def)
    try:
        f = float(refreq) * float(mult) * float(pre) / float(post) if float(post) else 0
        out = f"{f:.2f} MHz"
    except Exception:
        out = "?"
    print(f"  {name:15} {pll_def:8}  ref={refreq}MHz  mult={mult}  pre={pre}  post={post}  -> {out}")

print(f"\n  All TJ180A484S PLL defs: {ALL_PLL_DEFS}")
print(f"  Used: {sorted(used_defs)}")
print(f"  FREE: {sorted(set(ALL_PLL_DEFS) - used_defs)}")

# ---------- 2. DDR state ----------
print("\n=== 2. DDR hard block state ===")
ddr_info_match = re.search(r'<efxpt:ddr_info>(.*?)</efxpt:ddr_info>', txt, re.DOTALL)
if not ddr_info_match:
    if re.search(r'<efxpt:ddr_info\s*/>', txt):
        print("  ddr_info: EMPTY (<efxpt:ddr_info/>) — DDR NOT configured")
    else:
        print("  ddr_info: tag not found")
else:
    inner = ddr_info_match.group(1)
    print(f"  ddr_info: PRESENT ({len(inner)} bytes)")
    # Find adv_ddr / ddr_inst
    adv = re.search(r'<efxpt:adv_ddr[^>]*>', inner)
    if adv:
        attrs = adv.group(0)
        for k in ("mem_type", "density", "width", "axi_target0_data_width",
                  "axi_target1_data_width", "ref_clock_freq", "pll_name"):
            m = re.search(rf'{k}="([^"]+)"', attrs)
            if m:
                print(f"    {k:30} = {m.group(1)}")
    # Count AXI port references
    axi0 = len(re.findall(r'axi0_', inner))
    axi1 = len(re.findall(r'axi1_', inner))
    print(f"    axi0_* references: {axi0}")
    print(f"    axi1_* references: {axi1}")

# ---------- 3. Top RTL: clock sources for pixel_clk and mem_clk ----------
print("\n=== 3. RTL clock sources ===")
top_v = Path(r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\tj180_golden_top.v").read_text(encoding="utf-8")
for pat, label in [
    (r'assign\s+clk_pixel_rx\s*=\s*([^;]+);',  'clk_pixel_rx'),
    (r'assign\s+clk_pixel_tx\s*=\s*([^;]+);',  'clk_pixel_tx'),
    (r'assign\s+clk_byte_hs\s*=\s*([^;]+);',   'clk_byte_hs'),
    (r'assign\s+sys_clk_o\s*=\s*([^;]+);',     'sys_clk (wrapper)'),
    (r'assign\s+ddr_clk_o\s*=\s*([^;]+);',     'ddr_clk (wrapper)'),
    (r'\.mem_clk_i\s*\(([^)]+)\)',             'ddr_ctrl mem_clk_i'),
    (r'\.clk_i\s*\(\s*(i_axi0_mem_clk|sys_clk)\)', 'axi_dwidth_converter clk_i'),
]:
    m = re.search(pat, top_v)
    if m:
        print(f"  {label:30} = {m.group(1).strip()}")

# ---------- 4. i_axi0_mem_clk / i_axi1_mem_clk top input declarations ----------
print("\n=== 4. Top input ports for mem_clk ===")
for sig in ("i_axi0_mem_clk", "i_axi1_mem_clk", "pll_ddr_CLKOUT0"):
    m = re.search(rf'\(\* syn_peri_port = 0 \*\)\s+input\s+wire\s+(\w+)\s+{sig}', top_v)
    if m:
        print(f"  {sig}: DECLARED as top input")
    else:
        print(f"  {sig}: NOT declared as top input")

# ---------- 5. DesignAPI load validation ----------
print("\n=== 5. DesignAPI validation ===")
d = DesignAPI(is_verbose=False)
d.load(str(GOLDEN))
print("  load() OK")
try:
    blocks = d.get_all_block_name("PLL")
    print(f"  PLL blocks via API: {blocks}")
except Exception as e:
    print(f"  PLL query failed: {e}")
try:
    blocks = d.get_all_block_name("DDR")
    print(f"  DDR blocks via API: {blocks}")
except Exception as e:
    print(f"  DDR query failed: {e}")

print("\nDONE.")
