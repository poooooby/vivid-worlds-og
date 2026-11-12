# Third-party notices

This mod's own code is MIT-licensed (see `LICENSE`). The art below is not.

## Where the code comes from

Vivid Worlds: OG starts from **Wilds of Hoenn** (`poooooby/wilds-of-hoenn`, MIT, the same
author): its spawning, partner, Battler, Forager, effects and Game Boy engine layer
(`docs/PROVENANCE.md` records the exact commits).

## Code adapted from Wilds of Kanto Revival

`lib/json_decode.lua`, `lib/HGSS_scale.lua` (the per-species overworld size table), the 3D world
adapters under `lib/compat/`, `tools/generate_sprite_atlases.py` and
`tools/validate_sprite_atlases.py` are copied or adapted from
**Wilds of Kanto Revival** (`poooooby/wilds-of-kanto-gen-3`), which is
released under the MIT License:

> Copyright (c) 2026 YoDrehDenSwagAuf
>
> Modifications Copyright (c) 2026 poooooby
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions: The above copyright
> notice and this permission notice shall be included in all copies or
> substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS",
> WITHOUT WARRANTY OF ANY KIND (the full MIT terms are in `LICENSE`).

## Inspiration

- **TTiN** and **Untamed Tohjo**: the idea of weighting a Forager's finds by its friendship (a fonder
  Pokemon finds better and rarer items) comes from their foraging. No code or assets were copied; the
  Forager here (`lib/forager.lua`, `lib/forage_items.lua`) is this mod's own implementation.
- **TTiN** and **Untamed Tohjo**: the shiny chain -- beat or catch one species in a row and it turns up
  more, is more likely to be shiny and has better stats -- comes from their work, used with permission.
  No code or assets were copied; the chain here is our own implementation (Modern Spawns'
  `src/chain.lua`, and `lib/shiny.lua` here).

## Overworld sprites

The HGSS / PokeMMO art under `assets/enhanced_overworld/` and
`assets/wilds_generated/` is a read-only copy of **Wilds of Kanto Revival**'s
HGSS / PokeMMO Sprite Style sources (`tools/copy_wilds_assets.py`, run against
a sibling `poooooby/wilds-of-kanto-gen-3` checkout). Originally sourced from
https://www.pokecommunity.com/threads/generation-9-resource-pack-v21-1.527398/
This mod does not modify that art and does not share a runtime dependency with 
Wilds of Kanto Revival -- the two repos may diverge over time. 

- **HGSS / PokeMMO** (raw sources in `assets/enhanced_overworld/followsprites/`
  and `water_sprites/`, baked here into `assets/wilds_generated/true_size18/`):
  a large multi-author gap-filling set credited to numerous
  individual artists in Wilds of Kanto Revival's own
  `THIRD_PARTY_NOTICES.md` (MissingLukey, Kymoyonian, Getsuei-H, and many
  others listed there), plus the Pokemon Tower ghost sprite by
  Nuclear-Blizzard. Full credits list [here](https://docs.google.com/spreadsheets/d/1T-KC-4XDOeFKq0Z6tfN6Sz4JIlpaK7B8A0lbmBg9fNY/edit?usp=sharing).

See Wilds of Kanto Revival's `THIRD_PARTY_NOTICES.md` and `README.md` for
the complete, authoritative credit list for this art.

- **Zygarde 100% (Complete Forme)** -- its HGSS / PokeMMO land and swimming sheets
  (`718-complete-*`) are baked from the overworld follower sprite and its normal / shiny
  palettes in [pokeemerald-expansion](https://github.com/rh-hideout/pokeemerald-expansion)
  (`graphics/pokemon/zygarde/complete/`): the follower sprites added by **Liamjd14**
  ([#5336](https://github.com/rh-hideout/pokeemerald-expansion/pull/5336)) and redrawn
  asymmetrical by **kittenchilly**
  ([#9792](https://github.com/rh-hideout/pokeemerald-expansion/pull/9792)), with thanks to the
  rh-hideout contributors. `tools/generate_true_size_18frame.py` here lays it out as an 18-frame
  sheet, enlarges it (nearest neighbour) to Zygarde 50%'s size and draws the swimming sheet's foam
  line.

## Engine

Built against [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp),
which this mod does not redistribute.
