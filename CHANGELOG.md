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
