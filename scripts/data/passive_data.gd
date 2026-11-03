class_name PassiveData
extends Resource
## One passive item (GAME-DESIGN.md, "Passives") or Knödl upgrade. Each level adds `stats` once,
## scaled by the card's rarity; PlayerBuild sums them into the player's stats. The stat names are
## PlayerBuild.STATS.

enum Kind { PASSIVE, KNODL }

@export var id: StringName = &""
## Translation keys of the player-facing name and the deadpan one-liner on its card.
@export var name_key: String = ""
@export var desc_key: String = ""
## Passives take one of the six passive slots; Knödl upgrades sit beside them.
@export var kind: Kind = Kind.PASSIVE
@export var max_level: int = 5
## What one level adds, e.g. {&"armor": 1.0}. Fractions are percentages (0.1 = +10 %).
@export var stats: Dictionary[StringName, float] = {}
## Card and HUD icon (assets/icons).
@export var icon: Texture2D
## Card and HUD colour (never Krampus red: that is reserved for enemy attacks).
@export var color: Color = Color(0.55, 0.75, 0.45)
