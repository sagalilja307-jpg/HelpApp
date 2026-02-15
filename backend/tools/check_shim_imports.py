"""Local developer script to enforce shim import policy.

Usage:
  python tools/check_shim_imports.py

This script fails (exit code != 0) if any Python file (under src/ or tests/) imports
from the deprecated shim paths:
  - from helpershelp.assistant.
  - from helpershelp.llm.
  - from helpershelp.mail.

The script allows `tests/test_shim_deprecation.py` to import shims.
"""
import sys
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = ["from helpershelp.assistant.", "from helpershelp.llm.", "from helpershelp.mail."]
EXEMPT = [Path("tests/test_shim_deprecation.py")]


def find_forbidden_imports():
    matches = []
    for p in list(ROOT.glob("**/*.py")):
        rel = p.relative_to(ROOT)
        if rel in EXEMPT:
            continue
        try:
            text = p.read_text(encoding="utf8")
        except Exception:
            continue
        for pat in PATTERNS:
            if pat in text:
                # find line numbers
                for i, line in enumerate(text.splitlines(), start=1):
                    if pat in line:
                        matches.append(f"{rel}:{i}:{line.strip()}")
    return matches


def main():
    matches = find_forbidden_imports()
    if matches:
        print("Forbidden shim imports detected:")
        for m in matches:
            print(m)
        sys.exit(1)
    print("No forbidden shim imports found.")


if __name__ == '__main__':
    main()
