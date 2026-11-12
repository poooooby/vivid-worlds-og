# Manual test checklist

Unit tests and `tests/modkit_boot_test.lua` prove the code holds together; these prove it looks
and plays right. Tick each per release, per game. Scripted versions live in `tests/drivers/`.

## Red / Blue

- [ ] Route 1: visible wild Pokémon wander the grass; walking into one battles that exact species
      and level; a beaten / caught one is gone and another appears elsewhere.
- [ ] Classic Enc off: no step encounters in grass, caves or on Surf. Fishing still works.
- [ ] Biking past: weaker Pokémon run off ("!"), stronger ones chase (anger mark) and catching
      you starts the battle. Walking disturbs nobody.
- [ ] Partner: follows behind, spaced by size; Pet / Play / Talk with A, mood emote above its head.
- [ ] Party menu ROLE row: FOLLOW / FORAGE / FIGHT / BACK.
- [ ] Battler: charges a nearby wild Pokémon, hit sparks, knockout, "12 EXP" label; a worn-down
      one keeps its lost HP in the real battle.
- [ ] Forager: glint, dash, dig, "Found X!", the item is in the bag.
- [ ] Colour modes: redpp, SGB and DMG all read (effects by shape and motion where colour is gone).
- [ ] TERRARIUM: wild Pokémon and the partner stand as cards of their own size.

## Yellow

- [ ] The starter Pikachu still talks the native way; a non-Pikachu partner works too.
- [ ] All eight emote bubbles show where used.

## Gold / Silver / Crystal

- [ ] Route 29 / 30: day and night tables; the exact species / level battles.
- [ ] The grass rustles under walking wild Pokémon; they sink into tall grass.
- [ ] Classic Enc off: no step encounters, but the Bug-Catching Contest and Sweet Scent still work.
- [ ] Partner follows; switching the party lead changes it.
