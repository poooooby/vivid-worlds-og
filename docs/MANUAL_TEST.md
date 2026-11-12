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
- [ ] TERRARIUM: wild Pokémon and the partner stand as cards of their own size; emotes, bars and
      hit effects draw over them.
- [ ] Shiny Rate Always: shiny art + twinkle in the grass, sparkle + chime in battle, a shiny
      partner shows its shiny sprite.
- [ ] Pokémon Tower without the Silph Scope: every spawn is the ghost, the battle opens "GHOST
      appeared!", the Battler ignores them; with the scope they show as themselves.
- [ ] Safari Zone: walking near, some Pokémon run ("!"), none chase; the Battler ignores them.

## Yellow

- [ ] The starter Pikachu still talks the native way; a non-Pikachu partner works too.
- [ ] All eight emote bubbles show where used.

## Gold / Silver / Crystal

- [ ] Route 29 / 30: day and night tables; the exact species / level battles.
- [ ] The grass rustles under walking wild Pokémon; they sink into tall grass.
- [ ] Classic Enc off: no step encounters, but the Bug-Catching Contest and Sweet Scent still work.
- [ ] Partner follows; switching the party lead changes it.
- [ ] Pet / Play / Talk through Gold's own menu; the emote matches; happiness goes up.
- [ ] Party menu ROLE row; Battler: KO, EXP, a level-up move offer and an evolution screen;
      Forager: a TM lands in the TM pocket.
- [ ] Roaming beast (after the Burned Tower): shows up now and then on its route as itself,
      battles as the roaming battle (HP kept), leaves when it moves on; Classic Enc off: never
      on a step.
- [ ] Ruins of Alph: each Unown's letter matches the one battled; only unlocked letters.
- [ ] Bug-Catching Contest: no visible spawns, the contest's encounters run.
- [ ] Crystal at night: emote colours read; the grass splits around wild Pokémon.

## Every game

- [ ] Modern Spawns on: the visible species follow its tables; off: the game's own.
- [ ] Ten minutes of walking: no stutter (`tests/drivers/p5_perf.lua`: the mod's hooks stay
      well under 1 KB and 0.1 ms a frame).
