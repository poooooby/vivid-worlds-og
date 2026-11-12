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
  (`lib/voxel_sheets.lua`, `lib/compat/`).
- `lib/partner_emote.lua`: the partner's mood while you talk to it (no portraits).

## Release

```sh
python3 tools/check_modkitignore.py --write   # after adding a file under tests/, tools/, scripts/, docs/
python3 tools/validate_option_labels.py       # option labels <= 14 chars, ASCII
python3 tools/validate_release_version.py     # manifest.json and main.lua agree
python3 tools/line_budget.py                  # the shipped Lua stays within 20,000 lines
python3 scripts/build-mod.py                  # -> dist/vivid-worlds-og-v<ver>.zip (<= 4 MB)
```

Pre-1.0 versions ship as GitHub prereleases only (never an auto-update).
