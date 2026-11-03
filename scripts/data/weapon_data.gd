class_name WeaponData
extends Resource
## One auto-firing weapon (GAME-DESIGN.md, "Weapons"): a pattern plus its numbers. Levels 2..max
## raise damage, area and the fire rate by the *_per_level fractions and add one more of it at each
## entry of `amount_levels`. A weapon at max level plus its `evolves_with` passive can become its
## `evolution` (a weapon of its own with `is_evolution`, never offered as a normal card).

## ARC: melee arc in facing direction. PROJECTILE: shots in facing direction that pierce.
## RING: a shockwave around the player. AURA: damages everything close, all the time.
## ORBIT: things circling the player.
enum Pattern { ARC, PROJECTILE, RING, AURA, ORBIT }
## How ORBIT pieces and projectiles look.
enum Look { BALL, PIN, SPEAR }

@export var id: StringName = &""
## Translation keys of the player-facing name and the deadpan one-liner on its card.
@export var name_key: String = ""
@export var desc_key: String = ""
@export var pattern: Pattern = Pattern.ARC
@export var look: Look = Look.BALL
@export var max_level: int = 8
## Seconds between attacks; AURA: between its damage ticks (ORBIT: unused, it hits all the time).
@export var cooldown: float = 1.2
@export var damage: float = 3.0
@export var crit_chance: float = 0.0
@export var crit_multiplier: float = 2.0
## Knockback speed given to every enemy hit.
@export var knockback: float = 9.0
## ARC: reach from the player's centre and the full opening angle. RING / AURA: radius.
@export var reach: float = 3.2
@export var arc_degrees: float = 140.0
## Only enemies whose feet are within this height of the player's are hit.
@export var height_reach: float = 2.0
## Shots or orbiting pieces per attack.
@export var amount: int = 1

@export_group("Projectiles")
@export var projectile_speed: float = 20.0
@export var projectile_lifetime: float = 0.8
## Enemies a shot passes through before it is used up (0 = stops at the first).
@export var pierce: int = 2
## Hit radius of a shot or an orbiting piece.
@export var projectile_radius: float = 0.35
## Angle between neighbouring shots when several fly at once.
@export var spread_degrees: float = 8.0

@export_group("Orbit")
@export var orbit_radius: float = 2.6
## Radians per second.
@export var orbit_speed: float = 3.0
## The radius swings in and out by this fraction (0 = a steady circle).
@export var orbit_wobble: float = 0.0
## Spins faster with the move speed bonus: speed * (1 + this * move_speed).
@export var orbit_speed_from_move_speed: float = 0.0
## ORBIT: each piece hits the same enemy at most this often.
@export var hit_interval: float = 0.4

@export_group("Levels")
@export var damage_per_level: float = 0.2
@export var cooldown_per_level: float = 0.03
@export var area_per_level: float = 0.05
## Levels at which it gains one more shot / piece.
@export var amount_levels: PackedInt32Array = PackedInt32Array()

@export_group("Evolution")
@export var evolves_with: PassiveData
@export var evolution: WeaponData
@export var is_evolution: bool = false

@export_group("Look")
## Effect colour (never Krampus red: that is reserved for enemy attacks).
@export var color: Color = Color(0.85, 0.95, 1.0)
