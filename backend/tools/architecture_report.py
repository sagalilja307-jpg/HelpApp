#!/usr/bin/env python3
"""Produce JSON and CSV reports of architecture violations found in src/helpershelp.

Run from repo root:
  python3 backend/tools/architecture_report.py

Outputs:
  backend/reports/architecture_violations.json
  backend/reports/architecture_violations.csv
"""
import ast
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "backend" / "src" / "helpershelp"
OUTDIR = ROOT / "backend" / "reports"

if not SRC.exists():
    print("Error: expected path backend/src/helpershelp to exist", file=sys.stderr)
    sys.exit(2)

OUTDIR.mkdir(parents=True, exist_ok=True)


def iter_py_files(base: Path):
    for p in sorted(base.rglob("*.py")):
        yield p


def module_name_from_path(path: Path) -> str:
    rel = path.relative_to(ROOT / "backend" / "src")
    return ".".join(rel.with_suffix("").parts)


def collect_imports(path: Path):
    text = path.read_text(encoding="utf-8")
    tree = ast.parse(text)
    imports = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.add(alias.name)
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                imports.add(node.module)
    return imports


def find_violations():
    violations = []
    for py in iter_py_files(SRC):
        mod = module_name_from_path(py)
        imported = collect_imports(py)
        for imp in sorted(imported):
            if not imp.startswith("helpershelp."):
                continue
            # define shim namespaces
            shim_prefixes = ["helpershelp.assistant", "helpershelp.llm", "helpershelp.mail"]
            for shim in shim_prefixes:
                if imp.startswith(shim) and not mod.startswith(shim):
                    violations.append({
                        "importer_module": mod,
                        "imported_module": imp,
                        "file_path": str(py),
                    })
    return violations


def main():
    violations = find_violations()
    json_path = OUTDIR / "architecture_violations.json"
    csv_path = OUTDIR / "architecture_violations.csv"

    with json_path.open("w", encoding="utf-8") as fh:
        json.dump(violations, fh, indent=2, ensure_ascii=False)

    with csv_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["importer_module", "imported_module", "file_path"])
        writer.writeheader()
        for row in violations:
            writer.writerow(row)

    print(f"Wrote {len(violations)} violations to:")
    print(f" - {json_path}")
    print(f" - {csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
