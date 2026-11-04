class_name PassiveData
extends Resource
## One stat upgrade (GAME-DESIGN.md, "Stat upgrades / passives"): it takes one of the stat slots and
## levels up from the Speisekarte. Each level adds `stats` once, scaled by the card's rarity;
## PlayerBuild sums them into the player's stats. The stat names are PlayerBuild.STATS.

@export var id: StringName = &""
## Translation keys of the player-facing name and the deadpan one-liner on its card.
@export var name_key: String = ""
@export var desc_key: String = ""
## Highest level (0 = open-ended, Megabonk-style; counted stats like extra jumps need a cap).
@export var max_level: int = 0
## What one level adds, e.g. {&"armor": 1.0}. Fractions are percentages (0.1 = +10 %).
@export var stats: Dictionary[StringName, float] = {}
## Card and HUD icon (assets/icons).
@export var icon: Texture2D
## Card and HUD colour (never Krampus red: that is reserved for enemy attacks).
## How far the camera sways per level (Jagatee: "die Welt wackelt a bissl"), 0..1 of
## balance.camera_wobble_degrees in all; the "Bildschirm wackeln" setting turns it off.
@export var screen_wobble: float = 0.0
@export var color: Color = Color(0.55, 0.75, 0.45)


func can_level(level: int) -> bool:
	return max_level <= 0 or level < max_level
