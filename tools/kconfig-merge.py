#!/usr/bin/env python3
"""Merge a second kconfig-frag pass into src/mainline/pmos.config (later values win, order kept)."""
import re, sys
cfg, extra = sys.argv[1], sys.argv[2]
head, vals = [], {}
for l in open(cfg).read().splitlines():
    m = re.match(r"(?:# )?(CONFIG_\w+)[= ]", l)
    if m:
        vals[m.group(1)] = l
    else:
        head.append(l)
for l in open(extra).read().splitlines():
    m = re.match(r"(?:# )?(CONFIG_\w+)[= ]", l)
    if m:
        vals[m.group(1)] = l
open(cfg, "w").write("\n".join(head + list(vals.values())) + "\n")
