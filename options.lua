-- Mod Manager option schema for vivid_worlds_og.
-- Labels are limited to 14 characters (tools/validate_option_labels.py), ASCII only.
--
-- Wandering is Idle or Roam; Wild Reacts adds fleeing / chasing when the player bikes close
-- by (lib/wild_reactions.lua). Sprite Style: HGSS at each species' own size, or GSC (one tile).

return {
  {
    key = "enabled",
    label = "Show Wild Mons",
    type = "toggle",
    default = true,
    description = "Spawn visible wild Pokemon in eligible grass/water encounter areas.",
  },
  {
    key = "spawn_amount",
    label = "Spawn Amount",
    type = "choice",
    default = "normal",
    choices = {
      { "LOW", "low" },
      { "NORMAL", "normal" },
      { "HIGH", "high" },
    },
    description = "How many wild Pokemon are out at once, for grass and water each, growing with the size of the area. Low: about half (up to 4). Normal: up to 8. High: about one and a half times (up to 12).",
  },
  {
    key = "sprite_style",
    label = "Sprite Style",
    type = "choice",
    default = "pokemmo",
    choices = {
      { "HGSS", "pokemmo" },
      { "GSC", "followers" },
    },
    description = "How wild Pokemon and your partner look. HGSS: HeartGold / SoulSilver-style sprites, each species at its own size (a Snorlax towers over a Rattata). GSC: Poke Followers' Gold / Silver / Crystal-style sprites, one tile each like the original games; a species they have no sprite for, or no shiny sprite for, uses its HGSS one.",
  },
  {
    key = "wild_reacts",
    label = "Wild Reacts",
    type = "toggle",
    default = true,
    description = "Bike close to wild Pokemon and they react: weaker ones than your lead Pokemon are startled and run off, stronger ones get angry and chase you (catching you starts the battle). Walking past disturbs nobody. Off: they just wander.",
  },
  {
    key = "show_follower",
    label = "Follower",
    type = "toggle",
    default = true,
    description = "Your partner Pokemon walks behind you. Off: it stays in its Poke Ball (its Battle and Forage jobs and Pet / Play / Talk wait until it is out again). Changing your party order still changes who your partner is.",
  },
  {
    key = "role_pad",
    label = "Battler: Pad",
    type = "choice",
    default = "off",
    choices = {
      { "R", "r" },
      { "L", "l" },
      { "OFF", "off" },
    },
    description = "A controller shoulder button that switches your partner between Battle and Follow while you walk around -- you call it out like a trainer in battle ('Go! Pikachu!', 'Come back, Pikachu!').",
  },
  {
    key = "role_key",
    label = "Battler: Key",
    type = "choice",
    default = "off",
    choices = {
      { "E (R)", "e" },
      { "Q (L)", "q" },
      { "R", "r" },
      { "OFF", "off" },
    },
    description = "The keyboard key that switches your partner between Battle and Follow while you walk around. E and Q are the R and L buttons; R is a free key.",
  },
  {
    key = "smooth_follow",
    label = "Smooth Follow",
    type = "toggle",
    default = true,
    description = "Your partner is always spaced out behind you by its size. On: it glides round when you turn. Off: it snaps straight to its place behind you, step for step like the original games.",
  },
  {
    key = "type_aura",
    label = "Type Aura",
    type = "toggle",
    default = false,
    description = "Now and then your partner gives off a little puff of its type: embers from a Fire type, droplets from a Water type, leaves, sparks, snow, wisps ... Off: only while you Pet, Play or Talk with it.",
  },
  {
    key = "classic_enc",
    label = "Classic Enc",
    type = "toggle",
    default = true,
    description = "Classic Encounters: the original step-based random encounters in grass, caves and water (Surf). Visible wild Pokemon stay active either way. Fishing, the Bug-Catching Contest and Sweet Scent are unaffected.",
  },
  {
    key = "wild_silhouettes",
    label = "Silhouette",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off" },
      { "UNDISCOVERED", "undiscovered" },
      { "ALL", "all" },
    },
    description = "Off keeps normal colours. Undiscovered silhouettes species not yet caught in your Pokedex. All silhouettes every visible wild Pokemon.",
  },
  {
    key = "species_sizes",
    label = "Species Sizes",
    type = "toggle",
    default = true,
    description = "In a 3D world mod (TERRARIUM, Battle Art, Potato, Dramaless, Stadium 2), draw each species at its own size next to you: small ones knee-high, giants towering over you. The flat 2D field always draws each sprite at its own art size.",
  },
}
