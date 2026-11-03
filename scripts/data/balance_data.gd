class_name BalanceData
extends Resource
## Every balance number lives in data/balance.tres (CLAUDE.md). Code reads them from here and never
## hard-codes them. Values here are the defaults; balance.tres overrides whatever has been tuned.

@export_group("Arena")
## Half the side length of the stress-test square, in metres. Real maps bring their own (MapData).
@export var arena_half_size: float = 150.0
## Spatial hash cell size in metres (GAME-DESIGN.md: 2 m cells).
@export var grid_cell_size: float = 2.0

@export_group("Camera")
## Megabonk-style view (docs/DECISIONS.md): close, low, wide, the mouse looks around.
## Degrees above the horizon the camera starts at (the mouse moves it between min and max).
@export var camera_pitch_degrees: float = 20.0
@export var camera_min_pitch_degrees: float = 2.0
@export var camera_max_pitch_degrees: float = 70.0
## Start distance; the mouse wheel zooms between min and max in steps.
@export var camera_distance: float = 8.0
@export var camera_min_distance: float = 4.5
@export var camera_max_distance: float = 16.0
@export var camera_zoom_step: float = 1.0
@export var camera_fov: float = 80.0
## Extra distance per metre of Knödl radius above its start radius, so a huge Knödl stays in view.
@export var camera_distance_per_knodl_radius: float = 1.6
## The camera looks at this point above the player's feet (a bit above the head: the player sits
## below the middle of the screen and you see further ahead).
@export var camera_focus_height: float = 2.0
## How fast the camera catches up with the player (1/s, exponential; high = tight).
@export var camera_follow_speed: float = 20.0
## Seconds of look smoothing for mouse and keys (0 = raw).
@export var camera_look_smoothing: float = 0.05
## Radians per second the camera swings toward the running direction without the mouse (0 = off).
@export var camera_auto_turn_speed: float = 0.0
## Radians per second for the camera keys (Q/E).
@export var camera_key_turn_speed: float = 2.4
## Radians per pixel of mouse movement.
@export var camera_mouse_sensitivity: float = 0.0035
## The camera stays this far in front of terrain it would otherwise clip into.
@export var camera_collision_margin: float = 0.4

@export_group("Player")
@export var player_speed: float = 7.0
@export var player_radius: float = 0.5
## Host validation: a player pose further than this from the last one per second is rejected.
@export var player_max_speed_tolerance: float = 1.5
## Ground acceleration in m/s^2; in the air it is scaled by player_air_control.
@export var player_acceleration: float = 60.0
@export var player_air_control: float = 0.55
@export var player_gravity: float = 26.0
## Jump take-off speed; the height is v^2 / (2 g), about 1.7 m with the defaults.
@export var player_jump_velocity: float = 9.5
## Jumps before landing again: 1 = single, 2 = double jump (an upgrade or Cousin Toni).
@export var player_jumps: int = 1
## Seconds after leaving a ledge in which a ground jump still works, and how early a press counts.
@export var player_coyote_time: float = 0.12
@export var player_jump_buffer: float = 0.12
## Steepest walkable slope in degrees.
@export var player_max_slope_degrees: float = 46.0
@export var player_max_hp: float = 100.0
## Invulnerability after a hit.
@export var player_hurt_cooldown: float = 0.5
## M1 has no death screen yet: a player who drops to 0 HP is back at the spawn after this.
@export var player_respawn_seconds: float = 3.0
## Brösel this close to the player fly to their Knödl (GAME-DESIGN.md: 1 m).
@export var player_pickup_range: float = 1.0

@export_group("Knödl")
## radius = base * (1 + mass / mass_scale) ^ exponent, capped (GAME-DESIGN.md).
@export var knodl_base_radius: float = 0.5
@export var knodl_mass_scale: float = 50.0
@export var knodl_radius_exponent: float = 0.3333
@export var knodl_max_radius: float = 4.0
@export var knodl_start_mass: float = 0.0
## Mass added per XP of an absorbed Brösel.
@export var knodl_mass_per_xp: float = 1.0
## The Spagat: slack up to the rest length, an elastic pull beyond it, never longer than max.
@export var knodl_rest_length: float = 3.0
@export var knodl_max_length: float = 6.0
## Pull per metre beyond the rest length (m/s^2 per m) and damping along the string (1/s).
@export var knodl_spring: float = 28.0
@export var knodl_spring_damping: float = 3.0
## The string ends at the player's hand, this high above their feet.
@export var knodl_hand_height: float = 0.9
## Contact damage = base * speed * radius (GAME-DESIGN.md), only above the minimum speed.
@export var knodl_contact_damage: float = 1.0
@export var knodl_min_hit_speed: float = 1.5
## Seconds before the Knödl can hurt the same enemy again.
@export var knodl_hit_cooldown: float = 0.3
## Knockback speed per metre of radius per (m/s) of Knödl speed, capped.
@export var knodl_knockback: float = 0.9
@export var knodl_max_knockback: float = 14.0
@export var knodl_max_speed: float = 32.0
@export var knodl_linear_damp: float = 0.2
@export var knodl_angular_damp: float = 0.8
@export var knodl_friction: float = 0.9
## Schupfn: throw speed along the running direction, plus a little lift.
@export var knodl_throw_speed: float = 18.0
@export var knodl_throw_lift: float = 2.5
@export var knodl_reel_time: float = 1.5
@export var knodl_cooldown: float = 4.0
## Share of its mass a detached Knödl loses per second, dropped as loose Brösel.
@export var knodl_shed_per_second: float = 0.03
## A detached Knödl slower than this for knodl_stuck_seconds comes back on its own.
@export var knodl_stuck_speed: float = 0.4
@export var knodl_stuck_seconds: float = 3.0
## A thrown Knödl further away than this is reeled in.
@export var knodl_max_throw_distance: float = 45.0
## Player speed lost per metre of Knödl radius above the start radius, and the floor of that loss.
@export var knodl_drag_per_radius: float = 0.12
@export var knodl_min_speed_factor: float = 0.6

@export_group("Brösel")
@export var brosel_cap: int = 1500
## XP of the four Brösel sizes: small, medium, large (elites), golden Kaiserschmarrn bit (bosses).
@export var brosel_values: PackedInt32Array = PackedInt32Array([1, 5, 25, 100])
## Speed of a Brösel flying from the player to their Knödl.
@export var brosel_fly_speed: float = 14.0
## A Knödl absorbs Brösel within its radius plus this.
@export var brosel_pickup_margin: float = 0.3
## Shed Brösel cannot be picked up again for this long (or the Knödl would eat its own trail).
@export var brosel_shed_pickup_delay: float = 1.2
## Drops land up to this far from where the enemy died.
@export var brosel_scatter: float = 0.6

@export_group("XP")
## XP from level n to n + 1 = base + linear * n + quadratic * n^2 (GAME-DESIGN.md).
@export var xp_base: float = 5.0
@export var xp_linear: float = 8.0
@export var xp_quadratic: float = 0.4

@export_group("Enemies")
@export var enemy_spawn_ring_min: float = 30.0
@export var enemy_spawn_ring_max: float = 45.0
## Seconds a dead slot waits before it respawns (stress test: 0 keeps the count constant).
@export var enemy_respawn_delay: float = 0.0
## Enemies further than this from every player update only every enemy_far_update_interval frames.
@export var enemy_far_distance: float = 25.0
@export var enemy_far_update_interval: int = 3
@export var enemy_separation_strength: float = 6.0
## Neighbours looked at per enemy for separation; caps the cost inside dense crowds.
@export var enemy_separation_max_neighbors: int = 6
## Enemies only touch a player whose feet are within this height of their own.
@export var enemy_contact_height: float = 1.6
## Walkers slow down on ground steeper than this (rise per metre) and scramble up walls at the floor.
@export var enemy_climb_slope: float = 0.9
@export var enemy_climb_min_factor: float = 0.3
## How fast knockback dies away (1/s).
@export var enemy_knockback_decay: float = 7.0

@export_group("Spawning (run)")
## Runs spawn closer than the stress test, just beyond what the camera shows.
@export var spawn_ring_min: float = 18.0
@export var spawn_ring_max: float = 28.0
## The first wave starts closer, so the first level-up comes within 10 s (GAME-DESIGN.md pillar 2).
@export var spawn_first_ring_min: float = 9.0
@export var spawn_first_ring_max: float = 15.0
@export var spawn_start_count: int = 20
@export var spawn_count_per_minute: float = 40.0
@export var spawn_max_count: int = 300
@export var spawn_respawn_delay: float = 0.4

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
