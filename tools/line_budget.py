#!/usr/bin/env python3
"""Keeps Vivid Worlds: OG lightweight: the shipped Lua (lib/ + main.lua + options.lua) must stay
within BUDGET lines. Prints the total and the largest modules; exits 1 over budget.

Usage:
  python3 tools/line_budget.py          # check (scripts/build-mod.py runs this)
  python3 tools/line_budget.py --top 20 # also list the 20 largest modules
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUDGET = 20_000


def count(path: Path) -> int:
    with path.open("rb") as f:
        return sum(1 for _ in f)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=5, help="how many of the largest modules to list")
    args = ap.parse_args()
    files = sorted((ROOT / "lib").rglob("*.lua")) + [ROOT / "main.lua", ROOT / "options.lua"]
    sizes = [(count(p), p.relative_to(ROOT).as_posix()) for p in files if p.is_file()]
    total = sum(n for n, _ in sizes)
    for n, name in sorted(sizes, reverse=True)[: args.top]:
        print(f"  {n:6d}  {name}")
    status = "ok" if total <= BUDGET else "OVER BUDGET"
    print(f"line budget: {total} / {BUDGET} ({status})")
    return 0 if total <= BUDGET else 1


if __name__ == "__main__":
    sys.exit(main())
