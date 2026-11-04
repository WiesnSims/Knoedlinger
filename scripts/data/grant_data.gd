class_name GrantData
extends Resource
## One Grant level (GAME-DESIGN.md, "difficulty"): multiplies enemy HP, speed and damage and the
## Schilling a run pays, and may add one modifier: &"foehn" (wind pushes the Knödl), &"streik" (one
## Wirtshaus fewer), &"kontrolle" (elites come twice as often). Winning a run unlocks the next level.

@export var name_key: String = ""
@export var desc_key: String = ""
@export var enemy_hp: float = 1.0
@export var enemy_speed: float = 1.0
@export var enemy_damage: float = 1.0
@export var schilling: float = 1.0
@export var modifier: StringName = &""
