#!/usr/bin/env python3
"""Generate a CSV of all combinations from `intent_plan.py` literal definitions.
Writes to `backend/docs/intent_plan_combinations.csv`.
"""
import re
import csv
from pathlib import Path
from itertools import product

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "helpershelp" / "query" / "intent_plan.py"
OUT_DIR = ROOT / "docs"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT = OUT_DIR / "intent_plan_combinations.csv"

text = SRC.read_text(encoding="utf-8")

def extract(name: str):
    # Capture the bracket contents of e.g. Domain = Literal[ ... ]
    m = re.search(rf"^{name}\s*=\s*Literal\[(.*?)\]", text, re.S | re.M)
    if not m:
        raise SystemExit(f"Failed to find {name} in {SRC}")
    block = m.group(1)
    # find all double-quoted string literals inside block
    items = re.findall(r'"([^"]+)"', block)
    return items

Domain = extract("Domain")
Operation = extract("Operation")
Mode = extract("Mode")
TimeScopeType = extract("TimeScopeType")
TimeScopeValue = extract("TimeScopeValue")

headers = [
    "domain",
    "mode",
    "operation",
    "time_scope_type",
    "time_scope_value",
]

rows = []
for d, m, o, ttype, tval in product(Domain, Mode, Operation, TimeScopeType, TimeScopeValue):
    rows.append([d, m, o, ttype, tval])

with OUT.open("w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(headers)
    writer.writerows(rows)

print(f"Wrote {len(rows)} rows to {OUT}")
