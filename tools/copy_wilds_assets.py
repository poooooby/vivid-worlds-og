#!/usr/bin/env python3
"""Copy Wilds of Kanto Revival's overworld sprite sheets into this repo.

Source of truth stays the sibling `overworld-spawn-mod` checkout. This mod
never edits that art; it only takes a read-only copy at build/dev time so
the two repos can diverge (Wilds keeps updating its art independently).

Full coverage is copied (not capped at Gen 3's native 386 species): a
National Dex expansion mod for Gen 3 (gen1recomp's `national_dex_gen3`,
the Gen 3 counterpart to the Gen 1/2 dex-expansion mods Wilds of Kanto
Revival supports) can make species beyond dex 386 appear in a real RSE
save, and this mod's species-id -> national-dex conversion
(EnginePatch.nationalFor) makes no assumption about the cap either -- so
there is no reason to throw away art for a dex this mod might legitimately
be asked to draw later. Everything ships inside assets/atlas/ shards at
release time (see tools/generate_sprite_atlases.py), so having more of it
on disk does not mean a bigger release ZIP.

(Wilds of Kanto's Poke Followers / GSC 16x16 sheets, its Pokewilds extension
and its old 6-frame HGSS bake are deliberately NOT copied: the first two are
Kanto-only styles and the last is superseded by tools/generate_true_size_18frame.py.)

RAW 4x4-grid SOURCE art (one PNG per species+form+variant, not yet baked into a
walker sheet -- see tools/generate_true_size_18frame.py, which bakes this into
assets/wilds_generated/true_size18/{hgss,swimming,levitates}/):
    assets/enhanced_overworld/followsprites/%03d-%s-%s.png            (land)
    assets/enhanced_overworld/water_sprites/swimming/{normal,shiny}/  (water, swim)
    assets/enhanced_overworld/water_sprites/levitates/{normal,shiny}/ (water, hover)

Usage:
    python3 tools/copy_wilds_assets.py [--source ../overworld-spawn-mod] [--max-dex 1025]
"""
import argparse
import pathlib
import re
import shutil
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent

WATER_SPRITE_KINDS = ("swimming", "levitates")

# Matches "001-b-n.png" and "swimming_001-b-n_female.png" alike -- the dex
# number is always the first run of digits right before a "-".
DEX_PREFIX_RE = re.compile(r"(?:^|_)(\d+)-")


def copy_followsprites(source_root, dest_root, max_dex):
    """Raw 4x4-grid land source art (`001-b-n.png`, one row per direction,
    one column per candidate pose) -- read by tools/generate_true_size_18frame.py.
    Untouched by any generator; copied verbatim like the other source folders."""
    src_dir = source_root / "assets" / "enhanced_overworld" / "followsprites"
    if not src_dir.is_dir():
        print(f"warn: missing source folder {src_dir}", file=sys.stderr)
        return 0, 0
    dst_dir = dest_root / "assets" / "enhanced_overworld" / "followsprites"
    dst_dir.mkdir(parents=True, exist_ok=True)
    copied, skipped_over_cap = 0, 0
    for src_file in sorted(src_dir.glob("*.png")):
        m = DEX_PREFIX_RE.search(src_file.name)
        if not m:
            # the Pokemon Tower's ghost is no species (tools/form_art_map.py GB_FORM_ART)
            if src_file.name in EXTRA_GRIDS:
                shutil.copy2(src_file, dst_dir / src_file.name)
                copied += 1
            continue
        dex = int(m.group(1))
        if dex > max_dex:
            skipped_over_cap += 1
            continue
        shutil.copy2(src_file, dst_dir / src_file.name)
        copied += 1
    return copied, skipped_over_cap


EXTRA_GRIDS = ("TOWER_GHOST.png",)


def copy_water_sprites(source_root, dest_root, max_dex):
    """Raw 4x4-grid water source art (swimming_001-b-n.png /
    levitates_001-b-n.png), same grid convention as followsprites, read by
    tools/generate_true_size_18frame.py. Two kinds, each with its own
    normal/ and shiny/ subfolder in the source."""
    copied, skipped_over_cap = 0, 0
    for kind in WATER_SPRITE_KINDS:
        for variant in ("normal", "shiny"):
            src_dir = source_root / "assets" / "enhanced_overworld" / "water_sprites" / kind / variant
            if not src_dir.is_dir():
                print(f"warn: missing source folder {src_dir}", file=sys.stderr)
                continue
            dst_dir = dest_root / "assets" / "enhanced_overworld" / "water_sprites" / kind / variant
            dst_dir.mkdir(parents=True, exist_ok=True)
            for src_file in sorted(src_dir.glob("*.png")):
                m = DEX_PREFIX_RE.search(src_file.name)
                if not m:
                    continue
                dex = int(m.group(1))
                if dex > max_dex:
                    skipped_over_cap += 1
                    continue
                shutil.copy2(src_file, dst_dir / src_file.name)
                copied += 1
    return copied, skipped_over_cap


# Poke Followers / GSC (the Sprite Style option's GSC choice): 16x96 sheets, six 16x16 frames
# in the engine's SpriteRenderer order (stand down/up/left, walk down/up/left). Wilds of Kanto
# Revival's own set covers dex 1-251; its PokeWilds conversion fills in dex 252+ (and any gap).
# Copied under the HGSS sheets' naming, <key>-<normal|shiny>.png, so the atlas pairs normal
# and shiny like it does for HGSS. A species / shiny with no GSC art falls back to HGSS at
# runtime (lib/sprite_source.lua), so nothing is synthesized here.
GSC_SOURCES = ("poke_followers", "Pokewilds")  # first one that has a file wins
GSC_RE = re.compile(r"^follower_(\d+)_(normal|shiny)\.png$")
# Poke Followers' Unown letters: follower_201-b-n-<n>.png (normal) and follower_201-<nn>_shiny.png,
# n = 1 for B .. 25 for Z (26 / 27 are "!" / "?", which the Game Boy games do not have)
GSC_UNOWN = {}
for _n, _letter in enumerate("bcdefghijklmnopqrstuvwxyz", start=1):
    GSC_UNOWN[f"follower_201-b-n-{_n}.png"] = (_letter, "normal")
    GSC_UNOWN[f"follower_201-{_n:02d}_shiny.png"] = (_letter, "shiny")


def copy_gsc(source_root, dest_root, max_dex):
    dst_dir = dest_root / "assets" / "wilds_generated" / "gsc"
    dst_dir.mkdir(parents=True, exist_ok=True)
    taken, copied, skipped_over_cap = set(), 0, 0
    for folder in GSC_SOURCES:
        src_dir = source_root / "assets" / "enhanced_overworld" / folder
        if not src_dir.is_dir():
            print(f"warn: missing source folder {src_dir}", file=sys.stderr)
            continue
        for src_file in sorted(src_dir.glob("follower_*.png")):
            m = GSC_RE.match(src_file.name)
            letter = GSC_UNOWN.get(src_file.name)
            if letter:
                # Unown's letters B..Z, under the HGSS sheets' form keys ("201-b-normal.png")
                name = f"201-{letter[0]}-{letter[1]}.png"
                if name not in taken:
                    taken.add(name)
                    shutil.copy2(src_file, dst_dir / name)
                    copied += 1
                continue
            if not m:
                continue  # other forms (Castform ...) are not mapped
            dex, variant = int(m.group(1)), m.group(2)
            if dex > max_dex:
                skipped_over_cap += 1
                continue
            name = f"{dex:03d}-{variant}.png"
            if name in taken:
                continue
            taken.add(name)
            shutil.copy2(src_file, dst_dir / name)
            copied += 1
    return copied, skipped_over_cap


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=str(REPO_ROOT.parent / "overworld-spawn-mod"),
                     help="path to the overworld-spawn-mod (Wilds of Kanto Revival) checkout")
    ap.add_argument("--max-dex", type=int, default=1025,
                     help="highest national dex number to copy (1025 = Wilds's own full coverage)")
    args = ap.parse_args()

    source_root = pathlib.Path(args.source)
    if not source_root.is_dir():
        print(f"source not found: {source_root}", file=sys.stderr)
        return 1

    fs_copied, fs_skipped = copy_followsprites(source_root, REPO_ROOT, args.max_dex)
    print(f"followsprites (raw):  copied {fs_copied} files"
          + (f" (skipped {fs_skipped} beyond dex {args.max_dex})" if fs_skipped else ""))

    w_copied, w_skipped = copy_water_sprites(source_root, REPO_ROOT, args.max_dex)
    print(f"water_sprites (raw):  copied {w_copied} files"
          + (f" (skipped {w_skipped} beyond dex {args.max_dex})" if w_skipped else ""))
    g_copied, g_skipped = copy_gsc(source_root, REPO_ROOT, args.max_dex)
    print(f"gsc (Poke Followers): copied {g_copied} files"
          + (f" (skipped {g_skipped} beyond dex {args.max_dex})" if g_skipped else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
