#!/usr/bin/env python3
"""Audit the invented-format golden_top .peri.isf for correctness.

Checks:
  1. Duplicate pin assignments (same pin used by >1 port)
  2. Duplicate port names
  3. Per-peripheral pin counts
  4. Ports that look like HARD-IP pins (MIPI D-PHY / DDR) mis-modelled as GPIO
"""
import re
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

ISF = r"d:\work\trae_projects\awesom_project\original\proj\tj180_golden_top\constraints\tj180_golden_top.peri.isf"

tree = ET.parse(ISF)
root = tree.getroot()

pin_to_ports = defaultdict(list)
port_to_pin = {}
port_counts = Counter()
periph_pins = defaultdict(list)
hardip_ports = []

HARDIP_PATTERNS = ("mipi_dphy", "axi0_", "ddr_inst_", "rgmii_")  # rgmii is borderline (MAC+DDIO)

for peri in root.findall("peripheral"):
    pname = peri.get("name")
    ptype = peri.get("type")
    for port in peri.findall("port"):
        name = port.get("name")
        pin = port.get("pin")
        if not pin:
            continue
        pin_to_ports[pin].append((pname, name))
        port_to_pin[(pname, name)] = pin
        port_counts[name] += 1
        periph_pins[(pname, ptype)].append(pin)
        if name.startswith(HARDIP_PATTERNS):
            hardip_ports.append((pname, name, pin))

print("=" * 70)
print("PERIPHERAL SUMMARY")
print("=" * 70)
for (pname, ptype), pins in sorted(periph_pins.items()):
    print(f"  {pname:14} ({ptype:18}) {len(pins):4} pins")

print("\n" + "=" * 70)
print("DUPLICATE PIN ASSIGNMENTS (pin used by >1 port)")
print("=" * 70)
dups = {p: v for p, v in pin_to_ports.items() if len(v) > 1}
print(f"  {len(dups)} pins are multiply-assigned")
for pin, ports in sorted(dups.items())[:40]:
    print(f"  {pin:6} <- " + "; ".join(f"{pn}/{nm}" for pn, nm in ports))

print("\n" + "=" * 70)
print("DUPLICATE PORT NAMES")
print("=" * 70)
dport = {n: c for n, c in port_counts.items() if c > 1}
print(f"  {len(dport)} port names reused")
for n, c in sorted(dport.items())[:20]:
    print(f"  {n}  x{c}")

print("\n" + "=" * 70)
print("PORTS THAT LOOK LIKE HARD-IP PINS (should NOT be modelled as GPIO)")
print("=" * 70)
print(f"  {len(hardip_ports)} ports match hard-IP patterns")
bykind = Counter()
for pname, name, pin in hardip_ports:
    if name.startswith("mipi_dphy"):
        bykind["mipi_dphy"] += 1
    elif name.startswith("axi0_") or name.startswith("ddr_inst_"):
        bykind["ddr_axi"] += 1
    elif name.startswith("rgmii_"):
        bykind["rgmii"] += 1
for k, v in bykind.items():
    print(f"  {k:12} {v}")

total = sum(len(v) for v in periph_pins.values())
print("\n" + "=" * 70)
print(f"TOTAL ports: {total} | unique pins: {len(pin_to_ports)} | dup pins: {len(dups)}")
print("=" * 70)
