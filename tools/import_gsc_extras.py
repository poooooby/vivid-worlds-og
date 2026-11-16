#!/usr/bin/env python3
"""Fill gaps in the Poke Followers / GSC sheets (assets/wilds_generated/gsc/) from two more
sources, each pinned to one commit and fetched once into a gitignored cache:

  PokeWilds (SheerSt/pokewilds, pokemon/pokemon/<name>/overworld[-shiny].png): already
    coloured 96x16 strips. Urshifu and the regional / alternate forms
    WoobleDex adds on the Game Boy games (Alolan Muk, Hisuian Growlithe, Rotom's ...).
  Pokemon Ambrosia (AndrewC101/PokemonAmbrosia, gfx/followers/<name>.png): 16x96 sheets
    in four greys (the game colours them), for species PokeWilds has no art for (Ferroseed,
    Kingambit, Xerneas ...). Coloured here from the species' own Crystal palettes: the
    normal one = the two middle colours of gfx/pokemon/<name>/front.png, the shiny one =
    its shiny.pal. Two forms have no palette there (Alolan Ninetales, Bloodmoon Ursaluna):
    their colours come from our own HGSS sheet of that form.
  Shinies made here (MADE_SHINY), for GSC sheets whose source drew no shiny: the sheet's main
    colour moved the way the same part of the species' HGSS art moves in its HGSS shiny
    (hgss_shiny). Where that hardly shows, one colour swapped toward the species' shiny
    palette (PokeWilds' or Ambrosia's shiny.pal) the way PokeWilds makes its own shinies
    (palette_shiny); fainter still, none is made and the HGSS shiny shows.

Only writes a <key>-<variant>.png that is missing (--force rewrites ours too), in this
mod's frame order (stand down / up / left, walk down / up / left). Run it after
tools/copy_wilds_assets.py and before tools/generate_true_size_18frame.py (which cuts the
swimming / hovering sheets of the new ones).

Usage:
    python3 tools/import_gsc_extras.py [--force] [--offline]
"""
from __future__ import annotations

import argparse
import colorsys
import math
import re
import sys
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GSC_DIR = ROOT / "assets/wilds_generated/gsc"
HGSS_DIR = ROOT / "assets/wilds_generated/true_size18/hgss"
CACHE = ROOT / "assets/enhanced_overworld/gsc_extras"

POKEWILDS = ("SheerSt/pokewilds", "83133ed40be8b7c7dff5f9058eef16dd8916be6a")
AMBROSIA = ("AndrewC101/PokemonAmbrosia", "3f2e88c95520e387bbae6f71cd3226be870386de")

# our frame i = the source strip's frame ORDER[i] (pixel-exact over 145 shared PokeWilds
# species and 24 shared Ambrosia ones)
PW_ORDER = (5, 3, 1, 4, 2, 0)
AMB_ORDER = (0, 3, 5, 1, 2, 4)
FRAME, FRAMES = 16, 6

# art key -> PokeWilds folder. The keys are FormSource.keyOf's (WoobleDex form names,
# lowercase), the same as the HGSS form sheets'.
PW_ART = {
    "892": "urshifu_singlestrike",
    "892-rapid_strike": "urshifu_rapidstrike",
    "026-alola": "raichu_alolan",
    "088-alola": "grimer_alolan",
    "089-alola": "muk_alolan",
    "105-alola": "marowak_alolan",
    "077-galar": "ponyta_galarian",
    "078-galar": "rapidash_galarian",
    "083-galar": "farfetch_d_galarian",
    "122-galar": "mrmime_galarian",
    "222-galar": "corsola_galarian",
    "554-galar": "darumaka_galarian",
    "555-galar_standard": "darmanitan_galarian",
    "562-galar": "yamask_galarian",
    "058-hisui": "growlithe_hisuian",
    "100-hisui": "voltorb_hisuian",
    "101-hisui": "electrode_hisuian",
    "157-hisui": "typhlosion_hisuian",
    "503-hisui": "samurott_hisuian",
    "628-hisui": "braviary_hisuian",
    "724-hisui": "decidueye_hisuian",
    "413-sandy": "wormadam_sand",
    "413-trash": "wormadam_trash",
    "422-east": "shellos_east",
    "479-fan": "rotom_fan",
    "479-frost": "rotom_frost",
    "479-heat": "rotom_heat",
    "479-mow": "rotom_mow",
    "479-wash": "rotom_wash",
}

# art key -> (Ambrosia follower file, its gfx/pokemon folder for the palettes, or None to
# take the colours from our HGSS sheet of that key)
AMB_ART = {
    "597": ("ferroseed", "ferroseed"),
    "598": ("ferrothorn", "ferrothorn"),
    "649": ("genesect", "genesect"),
    "716": ("xerneas", "xerneas"),
    "717": ("yveltal", "yveltal"),
    "718": ("zygarde", "zygarde"),
    "809": ("melmetal", "melmetal"),
    "855": ("poltegeist", "poltegeist"),  # Polteageist, so spelled there
    "881": ("arctozolt", "arctozolt"),
    "882": ("dracovish", "dracovish"),
    "903": ("sneasler", "sneasler"),
    "983": ("kingambit", "kingambit"),
    "996": ("frigibax", "frigibax"),
    "997": ("arctibax", "arctibax"),
    "998": ("baxcalibur", "baxcalibur"),
    "038-alola": ("ninetales_a", None),
    "901-bloodmoon": ("ursaluna_b", None),
}

# Shinies made here, for GSC sheets whose source drew no shiny (made_shiny): art key ->
# (source, its species folder) holding that species' normal palette (front.pal or front.png)
# and shiny.pal for the palette fallback, or None when neither source has one. An explicit
# list, so --force never rewrites a shiny somebody drew.
MADE_SHINY = {
    "531": None, "548": None, "549": None, "622": None, "623": None, "674": None, "675": None,
    "677": None, "678": None, "707": None, "725": None, "736": None, "737": None, "738": None,
    "815": None, "824": None, "841": None, "865": None, "868": None, "876": None, "878": None,
    "530": ("amb", "excadrill"), "554": ("pw", "darumaka"), "554-galar": ("pw", "darumaka_galarian"),
    "555": ("pw", "darmanitan"), "555-galar_standard": ("pw", "darmanitan_galarian"),
    "556": ("pw", "maractus"), "557": ("pw", "dwebble"), "558": ("pw", "crustle"),
    "561": ("pw", "sigilyph"), "562-galar": ("pw", "yamask_galarian"), "574": ("pw", "gothita"),
    "575": ("pw", "gothorita"), "576": ("pw", "gothitelle"), "605": ("pw", "elgyem"),
    "618": ("pw", "stunfisk"), "633": ("pw", "deino"), "634": ("pw", "zweilous"),
    "635": ("pw", "hydreigon"), "636": ("pw", "larvesta"), "637": ("pw", "volcarona"),
    "656": ("pw", "froakie"), "657": ("pw", "frogadier"), "658": ("pw", "greninja"),
    "679": ("pw", "honedge"), "684": ("pw", "swirlix"), "700": ("pw", "sylveon"),
    "702": ("pw", "dedenne"), "703": ("pw", "carbink"), "708": ("pw", "phantump"),
    "709": ("pw", "trevenant"), "710": ("pw", "pumpkaboo"), "711": ("pw", "gourgeist"),
    "728": ("pw", "popplio"), "742": ("pw", "cutiefly"), "743": ("pw", "ribombee"),
    "760": ("pw", "bewear"), "769": ("pw", "sandygast"), "770": ("pw", "palossand"),
    "774": ("pw", "minior"), "789": ("pw", "cosmog"), "790": ("pw", "cosmoem"),
    "813": ("pw", "scorbunny"), "840": ("pw", "applin"), "842": ("pw", "appletun"),
    "870": ("pw", "falinks"), "872": ("pw", "snom"), "873": ("pw", "frosmoth"),
    "874": ("pw", "stonjourner"), "894": ("pw", "regieleki"), "895": ("pw", "regidrago"),
}
# PokeWilds' walker colours (every sheet's colours sit on or near these); ORANGE is the shared
# skin / accent tone, kept by a shiny unless it is the only colour
ORANGE = (248, 152, 80)
TINY_ACCENT = 0.05  # an accent this small a share of the sprite is not what turns shiny
# how visible a made shiny is: the share of the sprite's colour that changes x how far (0..1)
PALETTE_BELOW = 0.10  # an HGSS-led shiny fainter than this takes the palette one, if bolder
VISIBLE_MIN = 0.06    # fainter than this either way: no GSC shiny (the HGSS shiny shows)
SET_COLOURS = (ORANGE, (80, 72, 248), (232, 16, 160), (248, 56, 8), (56, 184, 24), (120, 80, 24), (48, 56, 40))


def fetch(repo: tuple[str, str], path: str, offline: bool) -> Path | None:
    """The cached copy of `path` in `repo` at its pinned commit (fetched once); None when
    the source has no such file."""
    name, sha = repo
    dest = CACHE / name.split("/")[1].lower() / path
    if dest.is_file():
        return dest
    if offline:
        return None
    url = f"https://raw.githubusercontent.com/{name}/{sha}/{path}"
    try:
        data = urllib.request.urlopen(url, timeout=60).read()
    except Exception:  # noqa: BLE001 -- a 404 is "no such file"
        return None
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return dest


def pixels(im: Image.Image):
    """Every pixel of `im` (Pillow 12 renamed getdata)."""
    return im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata()


def lum(c) -> float:
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def reorder(frames: list[Image.Image], order) -> Image.Image:
    out = Image.new("RGBA", (FRAME, FRAME * FRAMES), (0, 0, 0, 0))
    for i, src in enumerate(order):
        out.paste(frames[src], (0, i * FRAME))
    return out


def pw_sheet(path: Path) -> Image.Image | None:
    """None for a strip of another size (Minior's shiny there is a cut-off 95x15)."""
    im = Image.open(path).convert("RGBA")
    if im.size == (FRAME * FRAMES, FRAME):
        frames = [im.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(FRAMES)]
    elif im.size == (FRAME, FRAME * FRAMES):
        frames = [im.crop((0, i * FRAME, FRAME, (i + 1) * FRAME)) for i in range(FRAMES)]
    else:
        print(f"skip {path.relative_to(CACHE)}: {im.size[0]}x{im.size[1]}, not a 6-frame strip", file=sys.stderr)
        return None
    return reorder(frames, PW_ORDER)


def grey_levels(im: Image.Image):
    """An Ambrosia sheet's shades, lightest first. The lightest is the background (white,
    or near-white: Ferrothorn's is 249) and is cut out."""
    cs = {p[:3] for p in pixels(im) if p[3] > 0}
    return sorted(cs, key=lum, reverse=True)


def colour(path: Path, light, dark) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    if im.size != (FRAME, FRAME * FRAMES):
        raise ValueError(f"{path}: unexpected size {im.size}")
    levels = grey_levels(im)
    bg, rest = levels[0], levels[1:]
    black = rest[-1] if rest else None
    mids = rest[:-1]
    lut = {bg: None}
    if black is not None:
        lut[black] = (0, 0, 0)
    for i, c in enumerate(mids):  # lightest grey -> the light colour, the rest -> the dark one
        lut[c] = light if i == 0 else dark
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    src, dst = im.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            p = src[x, y]
            c = lut.get(p[:3]) if p[3] > 0 else None
            if c is not None:
                dst[x, y] = c + (255,)
    frames = [out.crop((0, i * FRAME, FRAME, (i + 1) * FRAME)) for i in range(FRAMES)]
    return reorder(frames, AMB_ORDER)


def front_palette(path: Path):
    """The two middle colours of a Crystal front.png (white, light, dark, black)."""
    cs = sorted({p[:3] for p in pixels(Image.open(path).convert("RGBA"))}, key=lum, reverse=True)
    mid = [c for c in cs if c not in ((255, 255, 255), (0, 0, 0))]
    return (mid[0], mid[-1]) if mid else None


def read_pal(path: Path):
    """A shiny.pal's two colours (RGB 0..31 -> 0..248, the way the GSC sheets are coloured)."""
    vals = [tuple(int(v) * 8 for v in m.groups())
            for m in re.finditer(r"RGB\s+(\d+),\s*(\d+),\s*(\d+)", path.read_text(errors="replace"))]
    return (vals[0], vals[-1]) if vals else None


def hgss_palette(key: str, variant: str):
    """The most used light and dark colour of our HGSS sheet of `key` (outline left out)."""
    path = HGSS_DIR / f"{key}-{variant}.png"
    if not path.is_file():
        return None
    counts = {}
    for p in pixels(Image.open(path).convert("RGBA")):
        if p[3] > 0 and lum(p) >= 40:
            counts[p[:3]] = counts.get(p[:3], 0) + 1
    if not counts:
        return None
    ranked = sorted(counts, key=lum)
    cut = lum(ranked[len(ranked) // 2])
    light = max((c for c in counts if lum(c) >= cut), key=counts.get)
    dark = max((c for c in counts if lum(c) < cut), key=counts.get, default=light)
    return light, dark


def palettes_of(source: str, folder: str, offline: bool):
    """(normal palette, shiny palette) of a species in PokeWilds ("pw") or Ambrosia, or None."""
    if source == "pw":
        base = f"pokemon/pokemon/{folder}"
        p = fetch(POKEWILDS, f"{base}/front.pal", offline)
        normal = p and read_pal(p)
        if not normal:
            p = fetch(POKEWILDS, f"{base}/front.png", offline)
            normal = p and front_palette(p)
        p = fetch(POKEWILDS, f"{base}/shiny.pal", offline)
    else:
        p = fetch(AMBROSIA, f"gfx/pokemon/{folder}/front.png", offline)
        normal = p and front_palette(p)
        p = fetch(AMBROSIA, f"gfx/pokemon/{folder}/shiny.pal", offline)
    shiny = p and read_pal(p)
    return (normal, shiny) if normal and shiny else None


def d2(a, b) -> int:
    return sum((x - y) ** 2 for x, y in zip(a, b))


def hue_distance(a, b) -> float:
    """How far apart two colours look: hue first (weighted by saturation), then saturation
    and value."""
    ha, sa, va = colorsys.rgb_to_hsv(*(x / 255 for x in a))
    hb, sb, vb = colorsys.rgb_to_hsv(*(x / 255 for x in b))
    dh = min(abs(ha - hb), 1 - abs(ha - hb))
    return (dh * 2) ** 2 * max(sa, sb) + 0.3 * (sa - sb) ** 2 + 0.3 * (va - vb) ** 2


def snap(c):
    return min(SET_COLOURS, key=lambda s: d2(s, c))


def palette_shiny(path: Path, normal_pal, shiny_pal) -> Image.Image:
    """Our sheet with one colour swapped the way PokeWilds makes a shiny: its most used
    colour other than the orange skin tone (orange itself when the rest is under
    TINY_ACCENT of the sprite, or the shiny would hardly show) becomes the walker colour
    nearest (by hue) to the shiny palette's entry for it (the normal palette's entry nearest
    that colour), never one the sprite already uses (it would merge into it; PokeWilds' artists
    did so in 67 of 568 swaps). Scored on PokeWilds' own 422 one-colour shinies: the very
    colour its artist chose in 238 (56%), a near one otherwise."""
    im = Image.open(path).convert("RGBA")
    used = {}
    for p in pixels(im):
        if p[3] > 0 and lum(p) >= 20:  # not the outline
            used[snap(p[:3])] = used.get(snap(p[:3]), 0) + 1
    ranked = sorted(used, key=used.get, reverse=True)
    total = sum(used.values())
    accent = next((c for c in ranked if c != ORANGE), None)
    pick = accent if accent and used[accent] >= TINY_ACCENT * total else ranked[0]
    entry = min(range(len(normal_pal)), key=lambda i: d2(normal_pal[i], pick))
    target = shiny_pal[min(entry, len(shiny_pal) - 1)]
    free = [s for s in SET_COLOURS if s not in used] or [s for s in SET_COLOURS if s != pick]
    new = min(free, key=lambda s: hue_distance(s, target))
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            p = px[x, y]
            if p[3] > 0 and lum(p) >= 20 and snap(p[:3]) == pick:
                px[x, y] = new + (p[3],)
    return out


def hsv(c):
    return colorsys.rgb_to_hsv(*(x / 255 for x in c))


def hue_gap(a: float, b: float) -> float:
    d = abs(a - b)
    return min(d, 1 - d)


def mean_hsv(colours):
    """Mean HSV of `colours` (hue averaged round the circle, weighted by saturation)."""
    hs = [hsv(c) for c in colours]
    x = sum(math.cos(2 * math.pi * h) * s for h, s, _ in hs)
    y = sum(math.sin(2 * math.pi * h) * s for h, s, _ in hs)
    return ((math.atan2(y, x) / (2 * math.pi)) % 1, sum(s for _, s, _ in hs) / len(hs),
            sum(v for *_, v in hs) / len(hs))


def hsv_change(n, s) -> float:
    return (hue_gap(n[0], s[0]) * 2) ** 2 * max(n[1], s[1]) + (n[1] - s[1]) ** 2 + (n[2] - s[2]) ** 2


def shifted(colour, n, s):
    """`colour` moved the way an HGSS part moves from its normal (n) to its shiny (s) HSV:
    the hue turned by the same amount, saturation and value scaled by the same ratios."""
    h, sa, v = hsv(colour)
    nh = (h + s[0] - n[0]) % 1
    ns = min(1.0, sa * s[1] / n[1]) if n[1] > 0.05 else s[1]
    nv = min(1.0, v * s[2] / n[2]) if n[2] > 0.05 else v
    return tuple(round(x * 255) for x in colorsys.hsv_to_rgb(nh, max(0.0, ns), max(0.0, nv)))


def gsc_colours(im: Image.Image) -> dict:
    """A GSC sheet's colours (snapped to SET_COLOURS, outline left out) -> pixel count."""
    used = {}
    for p in pixels(im):
        if p[3] > 0 and lum(p) >= 20:
            used[snap(p[:3])] = used.get(snap(p[:3]), 0) + 1
    return used


def recoloured(im: Image.Image, pick, new) -> Image.Image:
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            p = px[x, y]
            if p[3] > 0 and lum(p) >= 20 and snap(p[:3]) == pick:
                px[x, y] = new + (p[3],)
    return out


def hgss_part(hn: Image.Image, hs: Image.Image, colour):
    """The HGSS pixels in `colour`'s family (its hue, or greys for a grey): their mean
    normal and shiny HSV, or None when the HGSS art has none."""
    h0, s0, _ = hsv(colour)
    normal, shiny = [], []
    for a, b in zip(pixels(hn), pixels(hs)):
        if a[3] == 0 or lum(a) < 30:
            continue
        ha, sa, _ = hsv(a[:3])
        if (s0 > 0.25 and (sa < 0.2 or hue_gap(ha, h0) > 0.09)) or (s0 <= 0.25 and sa > 0.25):
            continue
        normal.append(a[:3])
        shiny.append(b[:3])
    return (mean_hsv(normal), mean_hsv(shiny)) if normal else None


def hgss_most_changed(hn: Image.Image, hs: Image.Image):
    """The part of the HGSS art its shiny changes most (pixels grouped by normal hue, or
    by brightness for greys; change x size): its mean normal and shiny HSV, or None."""
    groups = {}
    for a, b in zip(pixels(hn), pixels(hs)):
        if a[3] == 0 or lum(a) < 30 or a[:3] == b[:3]:
            continue
        ha, sa, va = hsv(a[:3])
        groups.setdefault(int(ha * 12) % 12 if sa > 0.2 else ("grey", int(va * 4)), []).append((a[:3], b[:3]))
    best = None
    for pairs in groups.values():
        n, s = mean_hsv([a for a, _ in pairs]), mean_hsv([b for _, b in pairs])
        score = hsv_change(n, s) * len(pairs)
        if best is None or score > best[0]:
            best = (score, n, s)
    return best[1:] if best else None


def hgss_shiny(im: Image.Image, hn: Image.Image, hs: Image.Image) -> Image.Image | None:
    """Our GSC sheet's main colour (the most used besides the orange skin tone; orange itself
    when the rest is under TINY_ACCENT) moved the way the matching part of the species' HGSS
    art moves in its HGSS shiny. When that part does not change there, the GSC colour nearest
    the part the HGSS shiny changes most moves instead."""
    used = gsc_colours(im)
    if not used:
        return None
    ranked = sorted(used, key=used.get, reverse=True)
    total = sum(used.values())
    accent = next((c for c in ranked if c != ORANGE), None)
    pick = accent if accent and used[accent] >= TINY_ACCENT * total else ranked[0]
    part = hgss_part(hn, hs, pick)
    if part and hsv_change(*part) >= 0.004:
        new = shifted(pick, *part)
        if d2(new, pick) > 600:
            return recoloured(im, pick, new)
    moved = hgss_most_changed(hn, hs)
    if not moved:
        return None
    n, s = moved
    cands = [c for c in used if used[c] >= 0.03 * total] or list(used)

    def distance(c):
        h, sa, v = hsv(c)
        if n[1] < 0.2:
            return abs(sa - n[1]) + abs(v - n[2])
        return hue_gap(h, n[0]) * 2 + abs(sa - n[1]) * 0.3

    pick = min(cands, key=distance)
    return recoloured(im, pick, shifted(pick, n, s))


def visibility(normal: Image.Image, shiny: Image.Image | None) -> float:
    """Share of the sprite's colour a shiny changes x how far (capped), 0..1."""
    if shiny is None:
        return 0.0
    coloured = changed = 0
    dist = 0.0
    for a, b in zip(pixels(normal), pixels(shiny)):
        if a[3] > 0 and lum(a) >= 20:
            coloured += 1
            if a[:3] != b[:3]:
                changed += 1
                dist += math.sqrt(d2(a[:3], b[:3]))
    if not changed:
        return 0.0
    return changed / coloured * min(dist / changed, 150) / 150


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true", help="rewrite sheets that already exist")
    ap.add_argument("--offline", action="store_true", help="use the cache only, fetch nothing")
    args = ap.parse_args()
    if not GSC_DIR.is_dir():
        print(f"no {GSC_DIR.relative_to(ROOT)}: run tools/copy_wilds_assets.py first", file=sys.stderr)
        return 1
    written = skipped = missing = 0

    def want(key, variant):
        return args.force or not (GSC_DIR / f"{key}-{variant}.png").is_file()

    def save(img, key, variant):
        nonlocal written
        img.save(GSC_DIR / f"{key}-{variant}.png", "PNG", optimize=True)
        written += 1

    for key, folder in PW_ART.items():
        for variant, fname in (("normal", "overworld.png"), ("shiny", "overworld-shiny.png")):
            if not want(key, variant):
                skipped += 1
                continue
            src = fetch(POKEWILDS, f"pokemon/pokemon/{folder}/{fname}", args.offline)
            if src is None:
                missing += 1
                continue
            sheet = pw_sheet(src)
            if sheet is None:
                missing += 1
                continue
            save(sheet, key, variant)

    for key, (follower, palettes) in AMB_ART.items():
        todo = [v for v in ("normal", "shiny") if want(key, v)]
        skipped += 2 - len(todo)
        if not todo:
            continue
        src = fetch(AMBROSIA, f"gfx/followers/{follower}.png", args.offline)
        if src is None:
            missing += len(todo)
            continue
        for variant in todo:
            if palettes:
                if variant == "normal":
                    p = fetch(AMBROSIA, f"gfx/pokemon/{palettes}/front.png", args.offline)
                    pal = p and front_palette(p)
                else:
                    p = fetch(AMBROSIA, f"gfx/pokemon/{palettes}/shiny.pal", args.offline)
                    pal = p and read_pal(p)
            else:
                pal = hgss_palette(key, variant)
            if not pal:
                missing += 1
                continue
            save(colour(src, *pal), key, variant)

    faint = []
    for key, palette in MADE_SHINY.items():
        sheet = GSC_DIR / f"{key}-normal.png"
        if not sheet.is_file() or not want(key, "shiny"):
            skipped += 1
            continue
        im = Image.open(sheet).convert("RGBA")
        made, score = None, 0.0
        hn, hs = HGSS_DIR / f"{key}-normal.png", HGSS_DIR / f"{key}-shiny.png"
        if hn.is_file() and hs.is_file():
            hn_im, hs_im = Image.open(hn).convert("RGBA"), Image.open(hs).convert("RGBA")
            if hn_im.size == hs_im.size:
                made = hgss_shiny(im, hn_im, hs_im)
                score = visibility(im, made)
        if score < PALETTE_BELOW and palette:
            pal = palettes_of(*palette, args.offline)
            if pal:
                other = palette_shiny(sheet, *pal)
                other_score = visibility(im, other)
                if other_score > score:
                    made, score = other, other_score
        if made is None or score < VISIBLE_MIN:
            faint.append(key)
            missing += 1
            continue
        save(made, key, "shiny")
    if faint:
        print("no GSC shiny made (too faint, the HGSS shiny shows): " + ", ".join(faint))

    print(f"import_gsc_extras: wrote {written}, kept {skipped} existing, {missing} not available")
    return 0


if __name__ == "__main__":
    sys.exit(main())
