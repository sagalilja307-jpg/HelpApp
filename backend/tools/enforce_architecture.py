#!/usr/bin/env python3
"""Simple architecture enforcement: detect imports into deprecated shim packages.

Usage: run from repository root (or from backend) e.g.

  python3 backend/tools/enforce_architecture.py

It scans `src/helpershelp` and reports any module that imports `helpershelp.assistant`
unless the importer itself lives under `helpershelp.assistant` (allow shims to import
the application modules).
"""
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # repo root -> backend/..
SRC = ROOT / "backend" / "src" / "helpershelp"

if not SRC.exists():
    print("Error: expected path backend/src/helpershelp to exist", file=sys.stderr)
    sys.exit(2)


def iter_py_files(base: Path):
    for p in base.rglob("*.py"):
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
                # package or module imported from
                imports.add(node.module)
    return imports


def main() -> int:
    violations = []
    for py in iter_py_files(SRC):
        mod = module_name_from_path(py)
        imported = collect_imports(py)
        for imp in imported:
            if not imp.startswith("helpershelp."):
                continue
            # If importer is not a shim module, it must not import shim packages
            if not mod.startswith("helpershelp.assistant") and imp.startswith("helpershelp.assistant"):
                violations.append((mod, imp, py))
            # Also treat legacy top-level names (llm, mail) as shims
            if not mod.startswith("helpershelp.llm") and imp.startswith("helpershelp.llm"):
                violations.append((mod, imp, py))
            if not mod.startswith("helpershelp.mail") and imp.startswith("helpershelp.mail"):
                violations.append((mod, imp, py))

    if not violations:
        print("No architecture violations found.")
        return 0

    print("Architecture violations:")
    for mod, imp, path in violations:
        print(f" - {mod} imports {imp}  ({path})")

    print(f"Found {len(violations)} violations.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
