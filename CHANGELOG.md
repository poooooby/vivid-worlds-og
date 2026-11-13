# Changelog

Vivid Worlds: OG starts from Wilds of Hoenn's code (its Game Boy port) with pieces of Wilds of
Kanto Revival; `docs/PROVENANCE.md` records where each part comes from. Its history begins
here.

## 1.0.4 — 2026-11-13

### Fixes

- Gold, Silver and Crystal: with the **Follower** option off (or while your partner is in its
  ball on the bike, in a cutscene ...), the grass behind you no longer rustles as if an
  invisible partner walked through it. Nor does a shadow hop down a ledge after you.

## 1.0.3 — 2026-11-13

### Added

- **The map's own Pokémon** in this mod's art, in your Sprite Style: Mewtwo, Articuno, Zapdos,
  Moltres, Snorlax, the Power Plant's Voltorb and Electrode, Lugia, Ho-Oh, Raikou, Entei and
  Suicune, the red Gyarados (shiny), Sudowoodo, the Rocket base's Electrode, Lance's Dragonite,
  and the town and house Pokémon (Slowpoke, Clefairy, Miltank, Chansey ...). Each one is shown
  as the species it really is: the games drew many of them with a few stand-in sprites (a
  generic "monster" for Mewtwo, a bird for Zapdos, Moltres' sprite for a Murkrow). The Day-Care's
  Pokémon on Route 34 show too. Dolls stay as they are.

## 1.0.2 — 2026-11-12

### Fixes

- **Type Aura** works: your partner now gives off its puffs of type (embers, droplets, leaves
  ...) now and then with the option on, and while you Pet, Play or Talk with it. Before, it never
  found its own type, so no puff ever showed.

- Red, Blue and Yellow: a Forager no longer sets out inside houses, Marts and Pokémon Centers
  (every indoor map counted as a cave). Caves, Viridian Forest, Pokémon Tower and the like still
  count.

### Changes

- **Foraging** comes every 60 steps you take, instead of after one to three minutes of walking on
  a route. Steps in towns count too (the item is dug up on the next route or in a cave), and
  every 20 steps your partner sniffs the air with a "?" over its head, so you can see it at work.
- The **Smooth Follow** option is gone. On these games a partner's art is barely wider than a
  tile, so the spacing it eased on a turn was a few pixels at most; your partner keeps the glide
  it had by default.
- Less work every frame: the wild Pokémon and your partner make far less garbage for the game
  to clean up, most of all in Red, Blue and Yellow.

## 1.0.1 — 2026-11-12

### Fixes

- Picking a role (Follow, Forage, Fight) or Recall from your partner's own menu no longer
  softlocks the game: its mood line ("... is beaming with joy!") came back after the role's line
  and could not be closed. The same went for the "already doing that" and "wants some space"
  lines.
- Red and Blue: pressing A at your partner while it is mid-step no longer crashes the game.

## 1.0.0 — 2026-11-12

The first release: visible wild Pokémon and a partner Pokémon for Red, Blue, Yellow, Gold, Silver
and Crystal, in a light package (one small sprite atlas, no portraits).

### Wild Pokémon

- Areas with wild encounters fill with visible Pokémon wandering the grass and swimming the water;
  walking into one battles that very Pokémon, species, level and stats.
- They only appear on land you can reach, by each game's own movement rules: one-way ledges, cave
  edges and holes, and Gold, Silver and Crystal's one-way cave edges.
- They rise out of the grass, surface from the water or fade in on bare ground, and leave the same
  way. In Gold, Silver and Crystal the tall grass rustles under them.
- **Wild Reacts**: biking close by startles weaker Pokémon (they run, with the game's own "!") and
  angers stronger ones (they chase you down and start the battle).
- **Classic Enc** turns off only the step encounters in grass, caves and on Surf: fishing, the
  Bug-Catching Contest and Sweet Scent stay as the game has them.
- **Shiny Rate** (Off to Always, 1/4096 by default) for every wild Pokémon on all six games. A
  shiny is a matter of its DVs (Gold's rule, which Red, Blue and Yellow follow too), so the shiny
  you see in the grass is the shiny you battle and catch. Red, Blue and Yellow battles play a
  sparkle and chime for a shiny.
- **Silhouette**: uncaught species, or all of them, as dark shapes.

### True to the games

- Gold, Silver and Crystal: Raikou, Entei and Suicune turn up among the visible wild Pokémon on
  the route they roam, at the game's own odds, one of each at most; touching one starts the
  game's own roaming battle (its kept HP and DVs, the flee, the move afterwards). A visible beast
  leaves when it moves on, and with Classic Enc off none jumps you on a step either.
- Gold, Silver and Crystal: each Unown in the Ruins of Alph wears the letter its DVs make, the same
  letter you battle; only unlocked letters appear.
- Red, Blue and Yellow: without the Silph Scope every wild Pokémon in the Pokémon Tower wears the
  ghost sprite and battles as a GHOST; no twinkle, silhouette or battle sparkle gives a shiny
  ghost away.
- Red, Blue and Yellow: Safari Zone Pokémon may run when you walk within three tiles, at the odds
  of the game's own Safari flee check (2 x Speed of 256); none chase.
- No visible spawns during the Bug-Catching Contest; its own encounters run as in the game.

### Your partner

- Your lead Pokémon walks behind you, spaced out by its size. A partner that evolves keeps its
  role and friendship.
- **Roles** from the party menu's ROLE row: Follow, Forage or Battle; the Battler button sends it
  into battle and calls it back.
- **Battler**: it charges nearby wild Pokémon and fights them on the field with its real moves and
  each game's own damage, type chart and critical hits. A win gives EXP the game's way, with the
  level-up moves and evolution screens, Exp. Share (Gold) / EXP.ALL (Red, Blue, Yellow) and Gold's
  held items dropped by the loser. A wild Pokémon it wore down starts its real battle with the HP
  it has left. It leaves Safari Pokémon, roaming legends and Tower ghosts alone.
- **Forager**: it spots a glint, dashes over, digs and brings back an item; the fonder it is of
  you, the better its finds. Gold's finds go into the right pocket (TMs into the TM pocket).
- **Pet, Play, Talk**: turn to it and press A. Its mood shows in each game's own emote bubbles
  (Red and Blue's smile, Yellow's eight, Gold, Silver and Crystal's eight), with drawn effects for
  the moods a game has no bubble for. In Gold, Silver and Crystal this raises its real happiness.
  Yellow's starter Pikachu keeps its own talk.

### Looks

- **Sprite Style**: HGSS sprites at true size (the default), or Poke Followers' one-tile GSC
  sprites; a species with no GSC sprite, or a shiny with no GSC shiny sprite, shows its HGSS one,
  and swimmers always use HGSS's swimming art.
- 3D world mods (TERRARIUM, Battle Art, Potato, Dramaless, Stadium 2): wild Pokémon and your
  partner stand as cards of their own size (**Species Sizes**), and the mod's emotes, sparkles,
  health bars, hit effects and pop-up text draw in the 3D scene.

### Works with

- WoobleView: with its Field HD on, your partner and the wild Pokémon are drawn sharp at the
  screen's resolution, glide smoothly between pixels and stand at their species' true sizes
  (**Species Sizes**) on the regular overworld too. Red, Blue and Yellow need the ADVANCED
  colours for it; their other colour modes draw the sprites at their art's own size.
- Modern Spawns on all six games: the visible spawns roll from its generated tables (a swarm in
  progress is kept), with its legendaries (never a second copy of a roaming beast still out) and
  its shiny chain's species.
