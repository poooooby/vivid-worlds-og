# Vivid Worlds: OG: developer guide

Everything here is for working on the mod. Players only need the [README](README.md).

## Setup

```sh
# Copy Wilds of Kanto Revival's overworld art (needs a sibling ../overworld-spawn-mod checkout).
# Not committed (.gitignore): a fresh clone needs this before anything draws a sprite.
python3 tools/copy_wilds_assets.py

# Bake the HGSS / PokeMMO 18-frame sheets from those raw grids (forms: tools/form_art_map.py).
python3 tools/generate_true_size_18frame.py --report   # inspect detected column roles first
python3 tools/generate_true_size_18frame.py
```

`scripts/bootstrap.sh` links this repo into `../gen1recomp/mods/vivid_worlds_og`. That makes it
show up (enabled) in that install's Mod Manager, so only run it against a test checkout of the
engine, not one you play on.

## Tests

```sh
# Standalone unit tests (plain Lua, no engine needed); run under luajit too
for f in tests/*_unit_test.lua; do lua "$f" || echo "FAIL: $f"; done

# The real mod Loader on Red, Yellow, Gold and Crystal (from inside a gen1recomp checkout
# that has this repo linked at mods/vivid_worlds_og)
luajit mods/vivid_worlds_og/tests/modkit_boot_test.lua
```

In-game checks run the engine's own frame drivers (`POKEPORT_DRIVER`, `POKEPORT_VERSION`) on a
throwaway portable export of the engine: `git archive HEAD` without `mods/`, plus the game data
folders (`red/`, `gold/`, `crystal/` ...), a `portable.txt`, and this repo junctioned into
`mods/vivid_worlds_og`. That keeps your real saves and mod settings untouched.

The map's own Pokémon (`lib/static_mons.lua`): `tests/drivers/p7_static.lua` (`red` / `crystal`;
pre-create `<shots>/<version>-static`) warps next to Mewtwo, Zapdos, Snorlax ... / Lugia, the red
Gyarados, the big Snorlax, the beasts ..., checks each wears our art for its species, and takes a
screenshot. `tests/static_mons_unit_test.lua` also classifies every object of the six games' map
data when `../gen1recomp` is present.

Per-frame cost: `tests/drivers/p5_perf.lua` (`red` / `crystal`) walks a route with the partner out
and the garbage collector stopped, and prints KB allocated and ms spent a frame per hook
(`VWOG_PERF_DEEP=1`: per EnginePatch function and class method). At 1.0.0 the mod's hooks made
about 0.8-0.9 KB and 0.05 ms a frame, most of it spawn / partner effects and the reachable
area's one-off build on a map change.

## Layout

- `lib/engine_patch.lua`: the only module that touches the engine's world internals. One API in
  front of `lib/gb/gen1.lua` (Red / Blue / Yellow, `OverworldController`) and `lib/gb/gen2.lua`
  (Gold / Silver / Crystal, `World`). Each adapter declares the engine targets it wraps (probed
  first; a failed probe installs nothing) and the optional systems it carries (`FEATURES`).
  A Gen 2 adapter must only require Gen 2 or shared engine modules: on a Gold boot the Gen 1
  module names are answered by compatibility facades, and a Gen 1 boot refuses `src.*.gen2.*`.
- Drawing: our Pokémon and effects are actors (`collectActors`) that the engine layer turns into
  pooled proxies in the engine's own draw list for the length of its draw call, so they
  depth-sort with the player and NPCs and get the engine's grass over their feet.
- `lib/spawn_manager.lua`, `lib/behavior.lua`, `lib/wild_reactions.lua`, `lib/battle_trigger.lua`:
  the wild Pokémon. `lib/follower_adapter.lua`, `lib/companion.lua`, `lib/party_roles.lua`:
  the partner. `lib/overworld_battle.lua` + `lib/ow_combat.lua` + `lib/finisher_fx.lua`: the
  Battler. `lib/forager.lua` + `lib/forage_*.lua`: the Forager.
- Sprites: HGSS only (`lib/sprite_source.lua`, `lib/actor_renderer.lua`), served from the atlas
  in a release (`lib/sprite_atlas.lua`). `lib/HGSS_scale.lua` sizes the 3D cards
  (`lib/voxel_sheets.lua`, `lib/compat/`) and the sheets WoobleView (`gen3-hd-sprites`) draws at
  window resolution on the flat field (`lib/hd_field.lua`: the species' factor x
  `Config.gbSizeRatio`, a GSC sheet at 1). Gen 1's palette modes colour the world canvas after it
  is drawn, which a window-resolution sprite never reaches, so the sheets are untagged there
  (`HdField.setPlain`, set each frame in `buildProxies`); only ADVANCED keeps them sharp.
- `lib/partner_emote.lua`: the partner's mood while you talk to it (no portraits).

## Release

```sh
python3 tools/check_modkitignore.py --write   # after adding a file under tests/, tools/, scripts/, docs/
python3 tools/validate_option_labels.py       # option labels <= 14 chars, ASCII
python3 tools/validate_release_version.py     # manifest.json and main.lua agree
python3 tools/line_budget.py                  # the shipped Lua stays within 25,000 lines
python3 scripts/build-mod.py                  # -> dist/vivid-worlds-og-v<ver>.zip (<= 4 MB)
```

Pre-1.0 versions ship as GitHub prereleases only (never an auto-update).
