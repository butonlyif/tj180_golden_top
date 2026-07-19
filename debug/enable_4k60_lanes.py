"""Enable 4-lane + 2.5 Gbps/lane on mipi_dphy_tx_inst1 (and RX) for 4K60.

Current state (from LOOPBACK seed merge):
  mipi_dphy_tx_inst1: 2-lane @ 1200 Mbps/lane = 2.4 Gbps  (1080p60 max)
  mipi_dphy_rx_inst2: 4-lane @ 1200 Mbps/lane = 4.8 Gbps  (4K30 YUV422 tight)

Target for 4K60:
  mipi_dphy_tx_inst1: 4-lane @ 2500 Mbps/lane = 10 Gbps   (4K60 YUV422 = 7.96 Gbps)
  mipi_dphy_rx_inst2: keep 4-lane, bump to 2500 Mbps/lane = 10 Gbps

This script edits the peri.xml directly:
  1. mipi_dphy_tx_inst1: enable lane_id 2 & 3, set phy_bandwidth 1200 -> 2500
  2. mipi_dphy_rx_inst2: bump phy_bandwidth 1200 -> 2500 (lanes already enabled)

Then validates via DesignAPI.load().
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
BACKUP = GOLDEN.with_suffix(".peri.xml.bak_pre_4k60")

shutil.copyfile(GOLDEN, BACKUP)
print(f"backup -> {BACKUP.name}")

txt = GOLDEN.read_text(encoding="utf-8")
orig_len = len(txt)

# --- Step 1: mipi_dphy_tx_inst1 — enable lane 2 and lane 3 ---
# Current (LOOPBACK seed, 2-lane):
#   <efxpt:data_lane lane_id="0" enable="true" is_pn_swap="false"/>
#   <efxpt:data_lane lane_id="1" enable="true" is_pn_swap="false"/>
#   <efxpt:data_lane lane_id="-1" enable="false" is_pn_swap="false"/>
#   <efxpt:data_lane lane_id="-1" enable="false" is_pn_swap="false"/>

# Isolate the TX block
m_tx = re.search(r'(<efxpt:mipi name="mipi_dphy_tx_inst1".*?</efxpt:mipi>)', txt, re.DOTALL)
assert m_tx, "mipi_dphy_tx_inst1 block not found"
tx_block = m_tx.group(1)
tx_block_orig = tx_block

# Enable lanes 2 and 3 (replace first two lane_id="-1" enable="false")
# Do this sequentially to target the disabled ones
def enable_next_lane(block, lane_id):
    pat = re.compile(r'<efxpt:data_lane lane_id="-1" enable="false"([^/]*)/>')
    repl = f'<efxpt:data_lane lane_id="{lane_id}" enable="true"\\1/>'
    new_block, n = pat.subn(repl, block, count=1)
    return new_block, n

tx_block, n1 = enable_next_lane(tx_block, 2)
tx_block, n2 = enable_next_lane(tx_block, 3)
print(f"TX: enabled lane 2 ({n1} replacement), lane 3 ({n2} replacement)")

# Bump TX phy_bandwidth 1200 -> 2500
tx_block_new = re.sub(r'(phy_bandwidth=")1200(")',
                      r'\g<1>2500\g<2>',
                      tx_block, count=1)
bw_changed_tx = (tx_block_new != tx_block)
tx_block = tx_block_new
print(f"TX: phy_bandwidth 1200 -> 2500 ({'OK' if bw_changed_tx else 'FAIL'})")

# Splice back
txt = txt.replace(tx_block_orig, tx_block, 1)

# --- Step 2: mipi_dphy_rx_inst2 — bump phy_bandwidth ---
m_rx = re.search(r'(<efxpt:mipi name="mipi_dphy_rx_inst2".*?</efxpt:mipi>)', txt, re.DOTALL)
assert m_rx, "mipi_dphy_rx_inst2 block not found"
rx_block = m_rx.group(1)
rx_block_orig = rx_block

# RX may use a different attribute (e.g., on mipi_hard_dphy_rx_info). Try multiple patterns.
rx_block_new = rx_block
patterns_rx = [
    (r'(phy_bandwidth=")1200(")', r'\g<1>2500\g<2>'),
    (r'(phy_bandwidth=")1500(")', r'\g<1>2500\g<2>'),
    (r'(phy_bandwidth=")800(")',  r'\g<1>2500\g<2>'),
]
rx_bw_changed = False
for pat, repl in patterns_rx:
    new = re.sub(pat, repl, rx_block_new, count=1)
    if new != rx_block_new:
        rx_block_new = new
        rx_bw_changed = True
        print(f"RX: phy_bandwidth matched pattern {pat!r}, bumped to 2500")
        break

if not rx_bw_changed:
    # Find current phy_bandwidth to report
    cur = re.search(r'phy_bandwidth="([^"]+)"', rx_block)
    print(f"RX: phy_bandwidth not bumped (current={cur.group(1) if cur else 'N/A'})")

rx_block = rx_block_new
txt = txt.replace(rx_block_orig, rx_block, 1)

# --- Save ---
GOLDEN.write_text(txt, encoding="utf-8")
print(f"\nrewrote {GOLDEN.name}: {orig_len} -> {len(txt)} bytes")

# --- Validate ---
print("\n=== Reload validation ===")
d = DesignAPI(is_verbose=False)
d.load(str(GOLDEN))
print("DesignAPI.load() OK — Efinity accepts the 4K60 peri.xml")

# Re-check lane states
m_tx2 = re.search(r'(<efxpt:mipi name="mipi_dphy_tx_inst1".*?</efxpt:mipi>)', txt, re.DOTALL)
tx_lanes = re.findall(r'<efxpt:data_lane lane_id="([^"]+)" enable="([^"]+)"', m_tx2.group(1))
bw_tx = re.search(r'phy_bandwidth="([^"]+)"', m_tx2.group(1))
print(f"\nFinal TX state:")
print(f"  phy_bandwidth = {bw_tx.group(1) if bw_tx else 'N/A'} Mbps/lane")
for lid, en in tx_lanes:
    print(f"  lane_id={lid}  enable={en}")

print(f"\nDONE. Backup: {BACKUP.name}")
print("NOTE: clk_byte_hs SDC constraint still 75 MHz; update to 156 MHz in tj180_golden_top.sdc")
