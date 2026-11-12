#!/usr/bin/env python3
"""Builds the release ZIP for vivid_worlds_og.

Packs manifest.json, main.lua, options.lua, lib/, assets/ and the notices at the ZIP root
(manifest.json at the root, not in a wrapping folder -- required for a clean Mod Manager
import). Excludes tests/, tools/, scripts/, docs/, .git* and any dev-only file.

Atlas mode (default): bakes the HGSS / PokeMMO sheets (tools/generate_sprite_atlases.py)
into a handful of shard PNGs under assets/atlas/, validates the bake is lossless and complete
(tools/validate_sprite_atlases.py), and ships THOSE instead of the per-file sheets; see
lib/sprite_atlas.lua. The ZIP must stay within the size budget (MAX_ZIP_MB).

Usage:
  python3 scripts/build-mod.py              # atlas mode -> dist/vivid-worlds-og-v<ver>.zip
  python3 scripts/build-mod.py --no-atlas   # per-file layout (debugging)
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

INCLUDE_ROOTS = ["manifest.json", "main.lua", "options.lua", "lib", "assets"]
OPTIONAL_FILES = ["LICENSE", "THIRD_PARTY_NOTICES.md", "README.md", "CHANGELOG.md"]

# Raw per-file sprite sheets (tools/copy_wilds_assets.py, tools/generate_true_size_18frame.py),
# left out of an atlas-mode build since assets/atlas/ ships in their place.
RAW_SPRITE_DIRS = [
    "assets/enhanced_overworld",
    "assets/wilds_generated/true_size18/hgss",
    "assets/wilds_generated/true_size18/swimming",
    "assets/wilds_generated/true_size18/levitates",
    "assets/wilds_generated/gsc",
]
ATLAS_FAMILIES = "hgss18,swimming18,levitates18,gsc"
MAX_ZIP_MB = 4.0

# Never ship, even if present under an included root.
FORBIDDEN_SUFFIXES = (".pyc", ".pyo")
FORBIDDEN_NAMES = {"wilds_dev.flag", ".DS_Store", "Thumbs.db"}


def run_tool(*args: str) -> None:
    result = subprocess.run([sys.executable, *args], cwd=ROOT)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def iter_files(skip_dirs: set[Path]):
    for root_name in INCLUDE_ROOTS:
        root = ROOT / root_name
        if root.is_file():
            yield root, root.relative_to(ROOT)
        elif root.is_dir():
            for p in sorted(root.rglob("*")):
                if p.is_file() and not any(skip in p.parents or skip == p for skip in skip_dirs):
                    yield p, p.relative_to(ROOT)
    for name in OPTIONAL_FILES:
        p = ROOT / name
        if p.is_file():
            yield p, p.relative_to(ROOT)


def build(args, version: str, mod_id: str, out_dir: Path) -> Path | None:
    """Builds the release ZIP. Returns its path, or None after printing why not."""
    skip_dirs: set[Path] = set()
    if args.no_atlas:
        atlas_dir = ROOT / "assets" / "atlas"
        if atlas_dir.is_dir():
            skip_dirs.add(atlas_dir)
        for d in RAW_SPRITE_DIRS:
            if not (ROOT / d).is_dir():
                print(f"ERROR: --no-atlas needs the real sheets at {d} (run tools/copy_wilds_assets.py)",
                      file=sys.stderr)
                return None
    else:
        run_tool("tools/generate_sprite_atlases.py", "--families", ATLAS_FAMILIES)
        run_tool("tools/validate_sprite_atlases.py")
        for d in RAW_SPRITE_DIRS:
            if (ROOT / d).is_dir():
                skip_dirs.add(ROOT / d)
        if not (ROOT / "assets" / "atlas" / "index.json").is_file():
            print("ERROR: atlas build did not produce assets/atlas/index.json", file=sys.stderr)
            return None

    zip_path = out_dir / f"vivid-worlds-og-v{version}.zip"
    forbidden_hits = []
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        seen = set()
        for abs_path, rel_path in iter_files(skip_dirs):
            rel_str = rel_path.as_posix()
            if rel_str in seen:
                continue
            seen.add(rel_str)
            if abs_path.name in FORBIDDEN_NAMES or rel_path.suffix in FORBIDDEN_SUFFIXES:
                forbidden_hits.append(rel_str)
                continue
            z.write(abs_path, rel_str)

    if forbidden_hits:
        for hit in forbidden_hits:
            print(f"ERROR: forbidden file would have shipped: {hit}", file=sys.stderr)
        zip_path.unlink(missing_ok=True)
        return None

    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()
    problems = []
    if "manifest.json" not in names:
        problems.append("manifest.json not at ZIP root")
    if not args.no_atlas:
        leaked = [n for n in names if n.startswith("assets/enhanced_overworld/")
                  or n.startswith("assets/wilds_generated/true_size18/")
                  or n.startswith("assets/wilds_generated/gsc/")]
        if leaked:
            problems.append(f"atlas mode but {len(leaked)} raw sprite files leaked into the ZIP (first: {leaked[0]})")
    size = zip_path.stat().st_size / 1e6
    if not args.no_atlas and size > MAX_ZIP_MB:
        problems.append(f"the ZIP is {size:.2f} MB, over the {MAX_ZIP_MB} MB budget")
    if problems:
        for p in problems:
            print(f"ERROR: {p}", file=sys.stderr)
        zip_path.unlink(missing_ok=True)
        return None

    mode = "per-file" if args.no_atlas else "atlas"
    print(f"wrote {zip_path}  ({len(names)} files, {size:.1f} MB, {mode} mode, mod id {mod_id})")
    return zip_path


def lower_priority() -> None:
    """Runs this process (and, on Windows, every process it starts) at below-normal priority,
    so a build never competes with the rest of the machine. Best effort."""
    try:
        if sys.platform == "win32":
            import ctypes
            from ctypes import wintypes
            BELOW_NORMAL_PRIORITY_CLASS = 0x4000
            k32 = ctypes.WinDLL("kernel32", use_last_error=True)
            k32.GetCurrentProcess.restype = wintypes.HANDLE
            k32.SetPriorityClass.argtypes = (wintypes.HANDLE, wintypes.DWORD)
            k32.SetPriorityClass.restype = wintypes.BOOL
            k32.SetPriorityClass(k32.GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS)
        else:
            os.nice(10)
    except Exception:
        pass


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-atlas", action="store_true", help="ship the raw per-file sheets instead of a baked atlas")
    ap.add_argument("--out-dir", default="dist", help="directory (relative to the repo root) for the ZIP")
    args = ap.parse_args()
    lower_priority()

    # .modkitignore must list every test / tool / script / doc (modkit matches exact paths)
    check = subprocess.run([sys.executable, str(ROOT / "tools" / "check_modkitignore.py")])
    if check.returncode != 0:
        print("ERROR: .modkitignore is out of date -- run: python3 tools/check_modkitignore.py --write",
              file=sys.stderr)
        return 1
    budget = subprocess.run([sys.executable, str(ROOT / "tools" / "line_budget.py")])
    if budget.returncode != 0:
        return 1

    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    out_dir = (ROOT / args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    path = build(args, manifest["version"], manifest["id"], out_dir)
    return 0 if path else 1


if __name__ == "__main__":
    raise SystemExit(main())
