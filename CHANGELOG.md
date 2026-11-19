# Changelog

Vivid Worlds: OG starts from Wilds of Hoenn's code (its Game Boy port) with pieces of Wilds of
Kanto Revival; `docs/PROVENANCE.md` records where each part comes from. Its history begins
here.

## Unreleased

### Changed

- **Switching partners:** changing your lead Pokémon from the party menu now drops a single
  Poké Ball: the old partner disappears as it pops and the new one comes out of it, instead
  of one ball to put the old one away and a second to send the new one out.
- **The Poké Ball opens:** when the ball lands it opens up, the partner grows out of it and
  the open ball fades away. Calling a partner back (with no one to replace it), the ball drops
  at its feet, opens, the partner shrinks inside, the ball closes and then fades.

### Fixed

- **Pokémon on the water at their land size:** Dewgong swimming and Dugtrio over the water
  were drawn about a quarter bigger than on land (HGSS sprites); they now match.
- **The grass rustles where your partner runs:** in Gold, Silver and Crystal, while your
  partner ran off to dig up an item, the grass behind you kept rustling as if it were still
  following you, and the grass it ran through stayed still. Now the grass it runs through
  rustles, and the grass behind you doesn't. The same goes for the Battler out at a wild Pokémon.

## 1.0.17 — 2026-11-16

### New

- **Running shoes mods:** a player moving faster than a walk on foot (a running shoes mod)
  now counts as running: wild Pokémon react to it the way they react to the bike (Wild
  Reacts), and with HGSS sprites the partner uses its run frames.

## 1.0.16 — 2026-11-15

### New

- **More GSC sprites:** with Sprite Style on GSC, these now have GSC sprites (and shinies)
  instead of falling back to HGSS: Ferroseed, Ferrothorn, Genesect, Xerneas, Yveltal, Zygarde,
  Melmetal, Polteageist, Arctozolt, Dracovish, Sneasler, Kingambit, the Frigibax line and
  Urshifu (both styles), and, with WoobleDex, the regional and alternate forms: Alolan Raichu,
  Grimer, Muk, Marowak and Ninetales; Galarian Ponyta, Rapidash, Farfetch'd, Mr. Mime, Corsola,
  Darumaka, Darmanitan and Yamask; Hisuian Growlithe, Voltorb, Electrode, Typhlosion, Samurott,
  Braviary and Decidueye; Rotom's five forms, Wormadam's Sandy and Trash Cloaks, East Sea Shellos
  and Bloodmoon Ursaluna. They swim and hover on the water like the others.
- **GSC shinies:** 69 more species with a GSC sprite but no GSC shiny (Volcarona, the Froakie
  line, Sylveon, Phantump, Milcery, the Deino line, Flapple, Meowstic, Golett ...) now have one:
  their main colour changes the way the same part of their HGSS sprite changes when it is
  shiny. Before, they showed their HGSS shiny; Pangoro and Klefki, whose shinies barely differ,
  still do.

### Fixes

- HGSS shiny sprites no longer carry a fixed blue sparkle in every frame (often drawn across
  the Pokémon itself). The mod's own twinkle still marks a shiny on the field.
- HGSS shiny Pokémon walk with the same steps as their normal look: about a hundred of them
  had their walking frames picked differently from the normal sprite.
- Your partner's wings (and legs) beat properly when you move faster than walking, with a mod
  that adds running: a flier going up or down used to look frozen, or blur, because its
  stand frame dropped out of the cycle at the faster pace. It now flaps through the same
  wing beat as when you walk, a little quicker, in every direction and both Sprite Styles.

## 1.0.15 — 2026-11-15

### Fixes

- A Forager no longer pours out a run of finds when you leave a town: every 60 steps walked
  in town counted toward another find, all of them dug up one after another on the next route
  (Goldenrod City to Route 34 was the worst). Only one find now waits for the next route; the
  one after it takes 60 steps of its own. Friendship never changed how often it finds things,
  only what it finds.

## 1.0.14 — 2026-11-15

### New

- **GSC fliers on the water:** with Sprite Style on GSC, a Pokémon that flies or floats over
  the water (Zubat, Gastly, Butterfree, Dragonite, Lugia ...) now keeps its GSC sprite, cut low
  over the water in a ring of foam the way the HGSS ones hover. Before, it switched to its HGSS
  sprite. Shinies keep their GSC shiny colours there too.

## 1.0.13 — 2026-11-15

### New

- **Rainbow level-up:** when your Battler grows a level, its "Lv.12!" now rises over it in
  rainbow letters that wave and shift colour over a soft glow, as in Vivid Worlds. Before, it
  was a plain label on the Game Boy games.

### Fixes

- In a 3D world mod (Battle Art and the others), Play with your partner now has it run after the
  ball it is thrown and bring it back, as on the flat field. Before, it stood still and only the
  ball flew.
- In a 3D world mod, "New move ready!", "Ready to evolve!" and the partner's other labels, emotes
  and sparkles sit just over its head. Over a small partner they used to float well above it.

## 1.0.12 — 2026-11-15

### New

- **GSC swimmers:** with Sprite Style on GSC, a Pokémon swimming in the water keeps its GSC
  sprite, cut at the waterline in a ring of foam the way the HGSS swimmers are drawn. Before,
  every swimmer switched to its HGSS sprite. Pokémon that hover over the water keep their HGSS
  art.

## 1.0.11 — 2026-11-15

### Fixes

- In a 3D world mod (Battle Art and the others) on a phone or tablet, your partner and the wild
  Pokémon showed only pieces of their sprites: the screen's pixel density stretched the sprite
  sheets made for the 3D world. They are made at their real size now.
- In a 3D world mod, your partner stayed visible after going into its ball (Follower off, a
  bike, a rest, a cutscene). It disappears now, like on the flat field.

## 1.0.10 — 2026-11-14

### New

- **Over Grass** option (off by default): wild Pokémon stand on top of tall grass, drawn whole,
  instead of the grass covering their feet. It works on the flat field and in Battle Art's 3D
  world, where they stand on top of the grass tufts. In Gold, Silver and Crystal the grass
  still rustles under them as they step.

## 1.0.9 — 2026-11-14

### Fixes

- Battle Art in Red, Blue and Yellow: **Species Sizes** now sizes the wild Pokémon and your
  partner in its 3D world, as it already did in Gold, Silver and Crystal. Before, every
  Pokémon there stood at its art's full size, so a Rattata was nearly twice as big as it
  should be.

## 1.0.8 — 2026-11-14

### Fixes

- Wild Pokémon no longer walk onto each other: one wandering or swimming never steps onto a
  tile another stands on or is stepping into, so two of them never end up overlapping.
- **Wild Reacts** weighs your lead Pokémon's species again, not just its level: on these games
  its base stats were never found, so a strong species at a low level was treated like a weak
  one when deciding whether wild Pokémon flee from it or chase it.

## 1.0.7 — 2026-11-14

### Fixes

- Your partner turns to face you when you talk to it (press A on it), and keeps facing you
  until you are done, instead of looking whichever way it last walked.

## 1.0.6 — 2026-11-13

### Added

- **VIVID WORLDS** in the game's own **OPTION** menu: one entry that opens a page with all of
  this mod's options, so you can change them while you play instead of going through the Mod
  Manager. A change there is the same as one made in the Mod Manager.

## 1.0.5 — 2026-11-13

### Changes

- Your partner comes out of a real **Poké Ball**: it drops behind you, bounces once and the
  Pokémon pops out with the ball's sound. Going back in, a ball drops onto it and it shrinks
  inside before the ball fades away. This is for switching partners, the **Follower** option,
  Recall and a Battler resting; on the bike, in cutscenes and at the Pokémon Center it still
  shrinks quickly into you, as before.

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
