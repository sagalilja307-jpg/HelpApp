"""Local developer script to enforce removed shim import policy.

Usage:
  python tools/check_shim_imports.py

The check scans Python files in:
  - src/
  - tests/
  - tools/

and fails if any file imports removed shim module paths.
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

from shim_policy import canonical_for, is_shim_module

ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = (ROOT / "src", ROOT / "tests", ROOT / "tools")


def _iter_imports(path: Path):
    text = path.read_text(encoding="utf8")
    tree = ast.parse(text, filename=str(path))
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                yield node.lineno, alias.name
        elif isinstance(node, ast.ImportFrom):
            if not node.module:
                continue
            yield node.lineno, node.module
            # Catch imports like: from helpershelp.llm import embedding_service
            for alias in node.names:
                if alias.name == "*":
                    continue
                yield node.lineno, f"{node.module}.{alias.name}"


def find_forbidden_imports() -> list[str]:
    matches: list[str] = []
    for scan_dir in SCAN_DIRS:
        if not scan_dir.exists():
            continue
        for py in sorted(scan_dir.rglob("*.py")):
            rel = py.relative_to(ROOT).as_posix()
            try:
                for lineno, module_name in _iter_imports(py):
                    if not module_name.startswith("helpershelp."):
                        continue
                    if not is_shim_module(module_name):
                        continue
                    suggestion = canonical_for(module_name) or "no replacement"
                    matches.append(
                        f"{rel}:{lineno}: shim import '{module_name}' -> use '{suggestion}'"
                    )
            except Exception as exc:
                matches.append(f"{rel}:0: parse_error: {exc}")
    return matches


def main() -> int:
    matches = find_forbidden_imports()
    if matches:
        print("Forbidden shim imports detected:")
        for match in matches:
            print(match)
        return 1
    print("No forbidden shim imports found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
