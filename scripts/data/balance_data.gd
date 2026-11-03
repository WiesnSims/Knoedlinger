class_name BalanceData
extends Resource
## Every balance number lives in data/balance.tres (CLAUDE.md). Code reads them from here and never
## hard-codes them. M0 only needs the stress-test and network numbers; later milestones add theirs.

@export_group("Arena")
## Half the side length of the playable square, in metres (maps are about 300 x 300 m).
@export var arena_half_size: float = 150.0
## Spatial hash cell size in metres (GAME-DESIGN.md: 2 m cells).
@export var grid_cell_size: float = 2.0

@export_group("Player")
@export var player_speed: float = 7.0
@export var player_radius: float = 0.5
## Host validation: a player pose further than this from the last one per second is rejected.
@export var player_max_speed_tolerance: float = 1.5

@export_group("Enemies")
@export var enemy_spawn_ring_min: float = 30.0
@export var enemy_spawn_ring_max: float = 45.0
## Seconds a dead slot waits before it respawns (keeps the stress count constant).
@export var enemy_respawn_delay: float = 0.0
## Enemies further than this from every player update only every enemy_far_update_interval frames.
@export var enemy_far_distance: float = 25.0
@export var enemy_far_update_interval: int = 3
@export var enemy_separation_strength: float = 6.0
## Neighbours looked at per enemy for separation; caps the cost inside dense crowds.
@export var enemy_separation_max_neighbors: int = 6

@export_group("Projectiles (stress weapon)")
@export var projectile_speed: float = 22.0
@export var projectile_lifetime: float = 1.4
@export var projectile_damage: float = 1.0
@export var projectile_radius: float = 0.25
## Shots per second over all players, more than the pool can hold: the pool stays full (stress test).
@export var projectile_fire_rate: float = 600.0

@export_group("Network")
@export var snapshot_rate_hz: float = 15.0
@export var pose_rate_hz: float = 20.0
@export var interpolation_delay_ms: int = 100
## A slot that moves further than this between two snapshots was respawned: snap, do not lerp.
@export var interpolation_snap_distance: float = 5.0
## Budget per client at 500 enemies (CLAUDE.md).
@export var client_bandwidth_budget_kbps: float = 60.0
