# Changelog

Vivid Worlds: OG starts from Wilds of Hoenn's code (its Game Boy port) with pieces of Wilds of
Kanto Revival; `docs/PROVENANCE.md` records where each part comes from. Its history begins
here.

## Unreleased

### Added

- **Vivid Worlds: OG**, a lightweight Gen 1 / Gen 2 wilds mod: visible wild Pokémon on Red,
  Blue, Yellow, Gold, Silver and Crystal, HGSS-style sprites at true size from one small
  atlas, and a partner Pokémon that follows you.
- On Red, Blue and Yellow the partner can battle wild Pokémon on the field and forage for
  items, and you can Pet, Play with and Talk to it; its mood shows as an emote above its head
  (no portraits).
- **Sprite Style**: HGSS sprites at true size (the default), or Poke Followers' one-tile GSC
  sprites; a species with no GSC sprite, or a shiny with no GSC shiny sprite, shows its HGSS
  one, and swimmers always use HGSS's swimming art.
- Wild Pokémon only appear on land you can reach, by each game's own movement rules: one-way
  ledges, cave edges, holes, and Gold, Silver and Crystal's one-way cave edges.
- Gold, Silver and Crystal: the tall grass rustles under walking wild Pokémon.
- The Battler leaves Safari Zone Pokémon be; no visible spawns during the Bug-Catching Contest.
- Battle Art (Gen 1 and Gen 2) 3D worlds show wild Pokémon and your partner as cards of their own
  size.
- Psychic-type battle effects show as Psychic (the Game Boy data's PSYCHIC_TYPE).
- Gold, Silver and Crystal: Pet / Play / Talk with your partner (Gold's own menus), raising its
  real happiness; wild Pokémon react when you bike close by, with the game's own "!" and "?".
- A partner that evolves keeps its role and friendship (it is known by its trainer and stats,
  not its species).
- Classic Enc turns off only the step encounters: the Bug-Catching Contest, Sweet Scent and
  fishing stay as the game has them.
- **Shiny Rate** (Off to Always, 1/4096 by default) for every wild Pokémon on all six games. A
  shiny is a matter of its DVs (Gold's rule, which Red, Blue and Yellow follow too), so the shiny
  you see in the grass is the shiny you battle and catch; a shiny partner shows its shiny sprite.
  Red, Blue and Yellow battles play a sparkle and chime for a shiny.
- The partner's mood shows in each game's own emote bubbles: Red and Blue's smile, Yellow's
  eight (heart, smile, Zs, bolt, skull ...), Gold, Silver and Crystal's eight (heart, happy, sad,
  sleep, bolt ...); a mood a game has no bubble for keeps its drawn effect.
- In a 3D world mod (TERRARIUM, Battle Art) the mod's emotes, sparkles, health bars, hit effects
  and pop-up text draw in the 3D scene, over the Pokémon they belong to.
- Gold, Silver and Crystal: the partner's Battler and Forager roles (the ROLE row in the party
  menu, the Battler button). Fights use Gold's own damage, type chart and critical hits; a win
  gives EXP the way Gold counts it, with its level-up moves and evolution screens; finds go
  into the right pocket (TMs into the TM pocket).
- A wild Pokémon your Battler wore down starts its real battle with the HP it has left, and is
  the very same Pokémon (the same stats) on both games.
- The Battler's hit and knockout sounds, Exp. Share (Gold) / EXP.ALL (Red, Blue, Yellow) and
  Gold's held items dropped by a knocked-out wild Pokémon.
- The "+" of a "+5 EXP" label shows (the Game Boy fonts have no "+").
- Gold, Silver and Crystal: Raikou, Entei and Suicune turn up among the visible wild Pokémon on
  the route they roam, at the game's own odds, one of each at most; touching one starts the
  game's own roaming battle (its kept HP and DVs, the flee, the move afterwards). A visible beast
  leaves when it moves on, and with Classic Enc off none jumps you on a step either.
- Gold, Silver and Crystal: each Unown in the Ruins of Alph wears the letter its DVs make (HGSS and
  GSC letter sprites), the same letter you battle.
- Red, Blue and Yellow: without the Silph Scope every wild Pokémon in the Pokémon Tower wears the
  ghost sprite (no shiny twinkle, no silhouette), battles as a GHOST and is never picked by the
  Battler; no battle sparkle gives a shiny ghost away.
- Red, Blue and Yellow: Safari Zone Pokémon may run when you walk within three tiles, at the odds
  of the game's own Safari flee check (2 x Speed of 256); none chase.
- Modern Spawns on Red / Blue / Yellow and Gold / Silver / Crystal: the visible spawns roll from
  its generated tables (a swarm in progress is kept), with its legendaries (never a second copy of
  a roaming beast still out) and its shiny chain's species.
