#!/usr/bin/env python3
"""Architecture enforcement: block imports of removed shim modules.

Usage (from backend/):
  python3 tools/enforce_architecture.py

This script only treats explicitly listed shim modules as violations.
It does not blanket-block entire namespaces like helpershelp.assistant.*.
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

from shim_policy import canonical_for, is_shim_module

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "helpershelp"

if not SRC.exists():
    print("Error: expected path src/helpershelp to exist", file=sys.stderr)
    raise SystemExit(2)


def iter_py_files(base: Path):
    for path in sorted(base.rglob("*.py")):
        yield path


def module_name_from_path(path: Path) -> str:
    rel = path.relative_to(ROOT / "src")
    return ".".join(rel.with_suffix("").parts)


def collect_imports(path: Path):
    text = path.read_text(encoding="utf-8")
    tree = ast.parse(text, filename=str(path))
    imports: list[tuple[int, str]] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append((node.lineno, alias.name))
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.append((node.lineno, node.module))
            for alias in node.names:
                if alias.name == "*":
                    continue
                imports.append((node.lineno, f"{node.module}.{alias.name}"))
    return imports


def main() -> int:
    violations: list[tuple[str, int, str, str, Path]] = []
    for py in iter_py_files(SRC):
        importer = module_name_from_path(py)
        for lineno, imported in collect_imports(py):
            if not imported.startswith("helpershelp."):
                continue
            if not is_shim_module(imported):
                continue
            suggestion = canonical_for(imported) or "no replacement"
            violations.append((importer, lineno, imported, suggestion, py))

    if not violations:
        print("No architecture violations found.")
        return 0

    print("Architecture violations:")
    for importer, lineno, imported, suggestion, path in violations:
        print(
            f" - {importer}:{lineno} imports {imported} "
            f"(use {suggestion}) ({path})"
        )
    print(f"Found {len(violations)} violations.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
