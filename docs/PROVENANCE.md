# Provenance

Vivid Worlds: OG is a fresh repository (no shared git history). Its first commit is built from:

| Source | Commit | What came over |
|---|---|---|
| Wilds of Hoenn `master` | `b30447f` plus its uncommitted working tree of 2026-11-11 (Exp. Share split, fight chaining, `lib/holder_ready.lua`) | spawning, behaviour, battle trigger, partner, Battler, Forager, effects, emotes, atlas, tests, tools |
| Wilds of Hoenn `feature/allgens` | `145fe16` (merged onto the above; conflicts in `main.lua`, `lib/config.lua` and two tests resolved by keeping both sides) | the Game Boy engine layer (`lib/engine_gb.lua`, renamed `lib/engine_patch.lua`), `lib/gb/gen1.lua`, `lib/gb/gen2.lua`, `lib/gb_color.lua`, `lib/gb_friendship.lua`, `lib/voxel_sheets.lua`, `lib/compat/*` |
| Wilds of Kanto Revival | `2f682519` | (planned) roaming legendaries, Shiny Rate, Pokémon Tower ghosts, Safari flee, cave reachability, Battle Art adapters |

Removed from the Wilds of Hoenn base: everything Gen 3 (its `engine_patch.lua` seam, sky,
Water Life, Local Scenes, perches, grass cover, reflections, eaves, Sweet Scent lure, options
page), PMDCollab sprites and portraits, and the translations (`lib/i18n.lua` is an English-only
stand-in with the same interface).

Because file paths match Wilds of Hoenn's, a fix there can be carried over with
`git format-patch` / `git am -3`.
