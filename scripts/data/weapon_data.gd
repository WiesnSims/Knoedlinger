class_name WeaponData
extends Resource
## One auto-firing weapon (GAME-DESIGN.md, "Weapons"): a pattern plus its numbers. Levels are
## open-ended (Megabonk-style): every level card rolls one of the weapon's `level_mods` (more damage,
## a faster rate, more area, one more piece, more crit), its rarity scaling the gain. A weapon at
## balance.evolution_level with its `evolves_with` stat held can become its `evolution` (a weapon of
## its own with `is_evolution`, never offered as a normal card); it keeps its level and its mods.

## ARC: melee arc (or cone) in facing direction. PROJECTILE: shots in facing direction that pierce
## (a boomerang comes back). RING: a shockwave around the player. AURA: damages everything close, all
## the time. ORBIT: things circling the player. DROP: impacts on enemies near the player (stamps,
## hail, snow globes). MINE: blasts where the player stood, a moment later. CHAIN: a hit that jumps
## from enemy to enemy.
enum Pattern { ARC, PROJECTILE, RING, AURA, ORBIT, DROP, MINE, CHAIN }
## How ORBIT pieces and projectiles look; FLAME: an ARC weapon shows a flame stream, not a swing.
enum Look { BALL, PIN, SPEAR, FLAME }

@export var id: StringName = &""
## Translation keys of the player-facing name and the deadpan one-liner on its card.
@export var name_key: String = ""
@export var desc_key: String = ""
@export var pattern: Pattern = Pattern.ARC
@export var look: Look = Look.BALL
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

@export_group("On hit")
## Sets hit enemies on fire: burn_share of the hit's damage per second, for burn_seconds.
@export var burn_share: float = 0.0
@export var burn_seconds: float = 0.0
## Slows hit enemies to slow_mult of their speed (0 = frozen / stunned) for slow_seconds.
@export var slow_mult: float = 1.0
@export var slow_seconds: float = 0.0

## A hit the player takes comes back as this share of it to every enemy inside the weapon's reach
## (Watschn-Baum), growing with the weapon's damage like its own hits.
@export var reflect_share: float = 0.0

@export_group("Drops, mines, chains")
## DROP / MINE: radius of one impact. CHAIN: how far the hit jumps to the next enemy.
@export var impact_radius: float = 1.5
@export var chain_range: float = 6.0
## MINE: seconds until a laid mine goes off.
@export var mine_delay: float = 1.0
## PROJECTILE: the shot flies back to where it came from after half its lifetime (Tablett-Wurf).
@export var boomerang: bool = false

@export_group("Levels")
## What a level card can roll, mod -> gain per level on a Gewöhnlich card (rarity multiplies it):
## &"damage", &"rate" (attacks per second), &"area", &"crit" as fractions (0.15 = +15 %), &"amount" in
## pieces. Which one a card rolls is drawn by balance.weapon_mod_weights.
@export var level_mods: Dictionary[StringName, float] = {&"damage": 0.15, &"rate": 0.08, &"area": 0.1}
## Most shots / pieces it can reach through &"amount" cards.
@export var max_amount: int = 1

@export_group("Evolution")
@export var evolves_with: PassiveData
@export var evolution: WeaponData
@export var is_evolution: bool = false

@export_group("Look")
## Card and HUD icon (assets/icons).
@export var icon: Texture2D
## Effect colour (never Krampus red: that is reserved for enemy attacks).
@export var color: Color = Color(0.85, 0.95, 1.0)
