#!/usr/bin/env python3
"""Turn `pmbootstrap kconfig check` errors into a config fragment.
Usage: kfrag.py errors.txt pass(1|2) > fragment
Pass 1 prefers =m for optional categories (keeps the Image small); pass 2 forces the preferred value."""
import re, sys

MOD_CATS = {"input", "containers", "netmount", "filesystems", "nftables", "wireguard", "accessibility",
            "waydroid", "iwd", "usb", "community_various", "wine", "immutable", "netboot", "zram"}
lines = open(sys.argv[1]).read().splitlines()
second = sys.argv[2] == "2"
out = []
for l in lines:
    l = re.sub(r"\x1b\[[0-9;]*m", "", l)
    m = re.match(r"(CONFIG_\w+) (.*) \[(\w+)\]$", l)
    if not m:
        continue
    sym, rule, cat = m.groups()
    r = re.match(r"should be enabled and preferably set to '(\w)'", rule)
    if r:
        val = r.group(1)
        if val == "y" and cat in MOD_CATS and not second:
            val = "m"
        out.append(f"{sym}={val}")
        continue
    if rule.startswith("should *not* be set"):
        out.append(f"# {sym} is not set")
        continue
    r = re.match(r'should be set to "(.*)"', rule) or re.match(r"should be set to (\S+)", rule)
    if r:
        v = r.group(1)
        out.append(f'{sym}="{v}"' if not re.fullmatch(r"-?\d+|0x[0-9a-fA-F]+", v) else f"{sym}={v}")
        continue
    r = re.match(r'should contain "(.*)"', rule)
    if r:
        out.append(f'{sym}="{r.group(1)}"')
        continue
    sys.stderr.write("sin regla: " + l + "\n")
print("\n".join(out))
