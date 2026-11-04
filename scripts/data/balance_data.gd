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
## Radians per second at full right-stick tilt, sideways and up/down (times the Gamepad setting).
@export var camera_pad_yaw_speed: float = 3.2
@export var camera_pad_pitch_speed: float = 1.6
## Radians per UI pixel a finger drags on the touch screen (times the Maus-Tempo setting).
@export var camera_touch_sensitivity: float = 0.008
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
## Share of the mass Bröselfresser bite off that falls to the ground as loose Brösel (the rest is eaten).
@export var knodl_bite_spill: float = 0.5
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

## Crumbs from the family's Knödl stand lie around the spawn at the start: the first level-up comes
## from rolling over them (GAME-DESIGN.md pillar 2: within 10 s), and it shows what the Knödl does.
@export var start_brosel_count: int = 14
@export var start_brosel_ring_min: float = 2.5
@export var start_brosel_ring_max: float = 6.0

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

## Enemy HP grows over the run: max HP * (1 + this * minutes).
@export var spawn_hp_per_minute: float = 0.35
## A gentler start while the build is thin (playtest: the first minutes were the hardest part): the
## crowd, enemy HP and enemy contact damage start at these shares and ease (smoothstep) up to the
## full curve by spawn_ease_minutes. A thinner crowd was tried (count 0.6): fewer Brösel, slower
## levels, a weaker run overall (docs/DECISIONS.md), so the crowd stays full and the enemies soft.
@export var spawn_ease_minutes: float = 3.0
@export var spawn_ease_count: float = 1.0
@export var spawn_ease_hp: float = 0.5
@export var spawn_ease_damage: float = 0.5
## Co-op scaling per extra player (GAME-DESIGN.md: +60 % count, +40 % HP, +1 Wirtshaus).
@export var coop_count_per_player: float = 0.6
@export var coop_hp_per_player: float = 0.4
@export var coop_wirtshaus_per_player: int = 1

@export_group("Run")
## The Kirtag lasts until Sperrstund' (15:00); then the Riesen-Wirt sweeps everyone out.
@export var run_seconds: float = 900.0
## How long the Riesen-Wirt sweeps before the run ends as a win.
@export var sperrstund_seconds: float = 6.0
@export var riesen_wirt_speed: float = 5.0

@export_group("Build")
## Two weapon and four stat slots (GAME-DESIGN.md pillar 4); weapon slots 3 and 4 come from the meta.
## Items take no slot.
@export var weapon_slots: int = 2
@export var passive_slots: int = 4
## A weapon this many levels up, with its partner stat held, can evolve.
@export var evolution_level: int = 8
## Which mod a weapon level card rolls (among the weapon's level_mods), by weight.
@export var weapon_mod_weights: Dictionary[StringName, float] = {
	&"damage": 3.0, &"rate": 2.0, &"area": 2.0, &"crit": 1.5, &"amount": 1.0,
}
## Hard floor for any weapon's seconds between attacks, however fast it got.
@export var weapon_min_cooldown: float = 0.08
## Cards on the Speisekarte, and the per-run reroll ("Nochmal bitte") and banish ("Des mog i ned").
@export var card_count: int = 3
@export var rerolls_per_run: int = 3
@export var banishes_per_run: int = 3
## Gold for "Danke, passt eh" (skip).
@export var skip_gold: int = 10
## Fallback cards when nothing is left to offer: HP healed, gold given.
@export var fallback_heal: float = 30.0
@export var fallback_gold: int = 25
## Weights in the card pool: new weapon, weapon level, new stat upgrade, stat level.
@export var card_weight_new_weapon: float = 1.0
@export var card_weight_weapon_level: float = 1.6
@export var card_weight_new_passive: float = 0.9
@export var card_weight_passive_level: float = 1.2
## Rarity: Gewöhnlich, Fein, Edel, Hofratswürdig. Multiplies what a level gives (a stat level, a
## weapon mod's roll; one more piece becomes two only at Hofratswürdig).
@export var rarity_bonus: PackedFloat32Array = PackedFloat32Array([1.0, 1.25, 1.5, 2.0])
@export var rarity_weights: PackedFloat32Array = PackedFloat32Array([70.0, 20.0, 8.0, 2.0])
## A chest's rarity (it decides which items it can hold), by weight; luck raises it like card rarity.
@export var chest_rarity_weights: PackedFloat32Array = PackedFloat32Array([55.0, 30.0, 12.0, 3.0])
## Boss chests and XL cash-ins roll at least this rarity.
@export var boss_chest_min_rarity: int = 1
## Co-op: the game runs on while someone chooses; after this a random card is picked for them.
@export var card_seconds_coop: float = 8.0
## A hit always does at least this much, whatever the armor.
@export var min_hit_damage: float = 1.0
## A revive from an item (Marterl-Kerze) brings the player back with this share of their max HP.
@export var item_revive_hp: float = 0.5

@export_group("Meta")
## Schilling a run pays (GAME-DESIGN.md: gold, cash-ins, 25 % of the Knödl when knocked out):
## per gold picked up, per cash-in by tier S..XL, the Knödl share, a win bonus, +10 % per extra player.
@export var schilling_per_gold: float = 0.5
@export var schilling_per_cash_in: PackedFloat32Array = PackedFloat32Array([5.0, 15.0, 40.0, 100.0])
@export var schilling_knodl_share: float = 0.25
@export var schilling_win_bonus: float = 100.0
@export var coop_schilling_per_player: float = 0.1
## Grant modifiers: Föhn pushes every Knödl this hard (m/s^2, in gusts), Kontrolle multiplies elites.
@export var foehn_force: float = 3.0
@export var kontrolle_elite_mult: float = 2.0

@export_group("Character traits")
## Onkel Ferdl's Grant stops at this much extra damage.
@export var grant_cap: float = 0.3
## Kommerzialrat Gustl's coffee break: enemies this close to him pause for this long.
@export var coffee_range: float = 15.0
@export var coffee_seconds: float = 3.0
@export var coffee_enemies: int = 6
## Kevin's shockwave: radius, damage (times the damage stat), knockback.
@export var jump_wave_radius: float = 4.5
@export var jump_wave_damage: float = 6.0
@export var jump_wave_knockback: float = 14.0

@export_group("Kontrolleur")
## From this minute on, a Kontrolleur stands at every open Wirtshaus that has not served yet; it
## blocks the door while it stands within guard_radius of the door mat.
@export var kontrolleur_minute: float = 4.0
@export var guard_radius: float = 4.5

@export_group("Item effects")
## Powidl-Füllung: when a Schupfn ends, a blast (radius = Knödl radius + this, damage per metre of
## Knödl radius) that costs this share of the Knödl's mass.
@export var powidl_radius: float = 2.5
@export var powidl_damage: float = 18.0
@export var powidl_cost: float = 0.1
## Schweizerkracher: a kill blows up with this chance per copy (radius, damage).
@export var kracher_radius: float = 2.5
@export var kracher_damage: float = 12.0
## Kirchenglocke: a ring around the player every this many seconds (fewer with more copies).
@export var bell_seconds: float = 10.0
@export var bell_radius: float = 5.0
@export var bell_damage: float = 10.0

@export_group("Wirtshaus")
## Open Wirtshäuser per run (each serves once) out of the map's spots; +1 per extra player.
@export var wirtshaus_count: int = 3
## The Knödl is eaten when it touches this circle in front of the door.
@export var wirtshaus_door_radius: float = 2.5
## Knödl mass needed for the tiers S, M, L, XL (below S the Wirt sends it back).
@export var wirtshaus_tier_mass: PackedFloat32Array = PackedFloat32Array([30.0, 120.0, 350.0, 900.0])
## S: gold per mass. M: chest with 1 item. L: chest with 3 items + reroll tokens. XL: evolution chest.
@export var wirtshaus_gold_per_mass: float = 0.5
@export var wirtshaus_chest_items: PackedInt32Array = PackedInt32Array([0, 1, 3, 5])
@export var wirtshaus_l_rerolls: int = 2

@export_group("Bosses and the gate")
## Boss HP per extra player (GAME-DESIGN.md: +50 %).
@export var coop_boss_hp_per_player: float = 0.5
## Enemy slots kept free beyond the crowd for bosses, escorts, summons and splits.
@export var spawn_extra_slots: int = 64
## Stempel to find for the Formular, and how close a player must get to one.
@export var stempel_count: int = 3
@export var stempel_pickup_radius: float = 2.2
## A player this close to the open gate brings the Hofrat out.
@export var portal_radius: float = 4.5
## A player whose feet are higher than this above the ground jumps over an attack mark.
@export var hazard_dodge_height: float = 1.1

@export_group("Loot")
## Map chests per run (out of the map's chest spots), what one costs and how many items it gives.
@export var map_chest_count: int = 6
@export var map_chest_price: int = 25
## Every map chest a player opens makes their next one this much dearer.
@export var map_chest_price_step: int = 15
@export var map_chest_items: int = 1
@export var chest_pickup_radius: float = 2.0
## Gold per coin; any kill drops a coin with this chance (elites and bosses drop theirs for sure).
@export var coin_value: int = 1
@export var coin_drop_chance: float = 0.006
## Coins this close fly to the player (times the Wanderkarte bonus); picked up within the radius.
@export var coin_magnet_range: float = 4.0
@export var coin_pickup_radius: float = 1.2
## A Gulasch drops with this chance per kill and heals this much.
@export var heal_drop_chance: float = 0.0015
@export var heal_amount: float = 35.0

@export_group("Death")
## Solo: knocked down = the run is over, the end screen comes after this pause.
@export var death_screen_delay: float = 2.5
## Co-op: a knocked-down player ("umgfoin") waits this long for a teammate, then is out until the
## next Wirtshaus cash-in (which wakes everyone). The run is lost when everyone is down at once.
@export var coop_down_seconds: float = 30.0
## Share of the Knödl's mass paid out as Schilling when a run is lost (GAME-DESIGN.md: 25 %).
@export var death_schilling_share: float = 0.25

@export_group("Co-op (Familienausflug)")
## Standing this close to a knocked-down teammate for revive_seconds wakes them; a teammate's Knödl
## rolling over them wakes them at once ("Aufgweckt!"). They come back with this share of their HP
## and a moment without hits.
@export var revive_radius: float = 2.2
@export var revive_seconds: float = 3.0
@export var revive_hp: float = 0.5
@export var revive_grace: float = 2.0
## Progress a revive loses per second when nobody stands by.
@export var revive_decay: float = 0.5
## Shared XP: every other player within this many metres gets this share of the XP (no mass).
@export var shared_xp_radius: float = 25.0
@export var shared_xp_share: float = 0.5
## Knödl-Pass: a Schupfn aims at a teammate within this cone (degrees either side) and range; a
## teammate it reaches within the catch radius takes its mass into their own Knödl. A throw only
## counts as a pass after pass_min_seconds in the air (no catching it out of your own hands).
@export var pass_cone_degrees: float = 30.0
@export var pass_range: float = 30.0
@export var pass_catch_radius: float = 1.2
@export var pass_min_seconds: float = 0.25
## Riesenknödl: two Knödl that meet this fast (relative m/s) merge, held by both strings, for
## merge_seconds (or until one of the two presses Schupfn). The same pair waits merge_cooldown
## before it can merge again.
@export var merge_min_speed: float = 4.5
@export var merge_seconds: float = 30.0
@export var merge_cooldown: float = 8.0
## Familienstreit (co-op event): at this minute one random player's Knödl tears loose and rolls
## off on its own for streit_seconds (this fast); a teammate touching it brings it back.
@export var streit_minute: float = 7.0
@export var streit_seconds: float = 10.0
@export var streit_speed: float = 9.0
## Doppelportion: the second Knödl is this big next to the first and hangs on a string this long.
@export var second_knodl_scale: float = 0.6
@export var second_knodl_rest: float = 2.2

@export_group("Bot")
## The bot walks its Knödl to a Wirtshaus once it is this heavy.
@export var bot_cash_in_mass: float = 350.0

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

@export_group("Riesenknödl and camera sway")
## Riesenknödl der Apokalypse: the Knödl's radius times this, past the usual cap.
@export var riesenknodl_size: float = 2.0
## Degrees the camera rolls at full sway (Jagatee), and how fast it sways.
@export var camera_wobble_degrees: float = 2.5
@export var camera_wobble_speed: float = 0.9

@export_group("Quality")
## QualityScaler (GAME-DESIGN.md, performance item 6), per level Hoch / Mittel / Niedrig.
## Render resolution factor: in the browser times the screen's pixel ratio (the whole canvas, UI
## included, docs/DECISIONS.md M5), natively Godot's 3D scale.
@export var quality_render_scale: PackedFloat32Array = PackedFloat32Array([1.0, 0.8, 0.65])
## Browser pixel ratio at most (a phone screen is about 2.6x; more than 2x is not worth its cost).
@export var quality_max_pixel_ratio: PackedFloat32Array = PackedFloat32Array([2.0, 1.5, 1.0])
## Metres of sun shadow on Hoch and Mittel (Niedrig has none).
@export var quality_shadow_distance: PackedFloat32Array = PackedFloat32Array([45.0, 28.0])
## Niedrig in a solo game keeps this share of the enemy crowd.
@export var quality_low_enemy_factor: float = 0.7
## "Automatisch": frames per second it keeps (desktop budget 60, phones 30), checked once a second.
@export var quality_target_fps: float = 50.0
@export var quality_target_fps_mobile: float = 27.0
## Seconds in a row below the target before one step down (the design's 3 s).
@export var quality_drop_seconds: int = 3
## Seconds in a row above target x margin before one step up again, and never sooner than the
## cooldown after a step down.
@export var quality_raise_seconds: int = 20
@export var quality_raise_margin: float = 1.5
@export var quality_raise_cooldown: float = 60.0
## Seconds after the start before it measures (shader compiles, the first spawns).
@export var quality_warmup_seconds: float = 5.0
