class_name KnodlSortData
extends Resource
## One Knödl sort (GAME-DESIGN.md, "Knödl sorts"). Multipliers on top of the Knödl numbers in
## balance.tres; 1.0 everywhere is the Semmelknödl.

@export var id: StringName = &""
## Translation key of the player-facing name.
@export var name_key: String = ""
@export var contact_damage_mult: float = 1.0
@export var roll_speed_mult: float = 1.0
@export var throw_distance_mult: float = 1.0
## 0 = rolls dead, 1 = bounces fully off walls (Germknödl).
@export var bounce: float = 0.0
## HP healed per this much absorbed mass, 0 = none (Marillenknödl: 1 HP per 25 mass).
@export var heal_per_mass: float = 0.0
## Start mass as a multiple of balance.knodl_start_mass (characters can raise it further).
@export var start_mass_mult: float = 1.0
## Kaspressknödl: cuts through a line of enemies instead of pushing them aside.
@export var pierce: bool = false
## Height of the look against its width (Kaspressknödl: a flat disc). Only the look; it still rolls.
@export var flatness: float = 1.0
## Grammelknödl: enemies near its greasy trail slow down to (1 - trail_slow) of their speed.
@export var trail_slow: float = 0.0
## Sweet dough: Wespen go for it (EnemyTypeData.sweet_tooth).
@export var sweet: bool = false
## Too heavy for Der Sturm to pull in (BossData.pull_radius).
@export var heavy: bool = false
@export var color: Color = Color(0.8, 0.66, 0.44)
@export var crumb_color: Color = Color(0.7, 0.5, 0.28)
## Little flecks in the dough (parsley in a Semmelknödl).
@export var fleck_color: Color = Color(0.3, 0.52, 0.2)
