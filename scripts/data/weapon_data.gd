class_name WeaponData
extends Resource
## One auto-firing weapon. M1 has a single pattern (a melee arc in facing direction); more patterns
## come with the weapon set in M2, still as data.

enum Pattern { ARC }

@export var id: StringName = &""
## Translation key of the player-facing name.
@export var name_key: String = ""
@export var pattern: Pattern = Pattern.ARC
## Seconds between attacks.
@export var cooldown: float = 1.2
@export var damage: float = 3.0
## Reach from the player's centre in metres, and the full opening angle of the arc.
@export var reach: float = 3.2
@export var arc_degrees: float = 140.0
## Knockback speed given to every enemy hit.
@export var knockback: float = 9.0
## Only enemies whose feet are within this height of the player's are hit.
@export var height_reach: float = 2.0
## Swing effect colour (never Krampus red: that is reserved for enemy attacks).
@export var color: Color = Color(0.85, 0.95, 1.0)
