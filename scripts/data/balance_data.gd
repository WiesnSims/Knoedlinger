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
## Degrees the view widens at full momentum (twice the run speed), so speed reads as speed.
@export var camera_speed_fov: float = 8.0
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
## Gravity while rising; falling uses player_fall_gravity_mult on top (docs/DECISIONS.md, movement).
@export var player_gravity: float = 22.0
## Jump take-off speed; the rise is v^2 / (2 g), about 2.3 m and 0.9 s in the air with the defaults.
@export var player_jump_velocity: float = 10.0
## Letting go of jump while still rising keeps this much of the upward speed (a short hop).
@export var player_jump_cut: float = 0.45
## Falling pulls harder than rising: snappy instead of floaty.
@export var player_fall_gravity_mult: float = 1.5
## Holding jump around the top of the arc (|vertical speed| below apex_speed) hangs a moment.
@export var player_apex_gravity_mult: float = 0.5
@export var player_apex_speed: float = 2.0
@export var player_max_fall_speed: float = 35.0
## Momentum (Megabonk): a jump while moving adds this much speed forward (m/s) ...
@export var player_jump_forward_boost: float = 1.5
## ... up to this many times the run speed. The air keeps it; on the ground it fades (m/s^2).
@export var player_momentum_max: float = 2.0
@export var player_momentum_decay: float = 16.0
## Running downhill gains speed: gravity times the slope's steepness times this (no slide button).
@export var player_slope_gain: float = 0.6
## Glide stat (items): holding jump while falling divides gravity and the fall speed by
## (1 + glide * strength); at most player_glide_fall_speed / that.
@export var player_glide_strength: float = 4.0
@export var player_glide_fall_speed: float = 6.0
## Players never rise higher than this above the ground.
@export var player_height_ceiling: float = 30.0
## Jumps before landing again: 1 = single, 2 = double jump (an upgrade or Cousin Toni).
@export var player_jumps: int = 1
## Seconds after leaving a ledge in which a ground jump still works, and how early a press counts.
@export var player_coyote_time: float = 0.12
@export var player_jump_buffer: float = 0.12
## Steepest walkable slope in degrees.
@export var player_max_slope_degrees: float = 46.0
## Ground up to this steep still lets the player jump off it (hop up a hillside); walls do not.
@export var player_slope_jump_degrees: float = 80.0
@export var player_max_hp: float = 100.0
## Invulnerability after a hit.
@export var player_hurt_cooldown: float = 0.5
## 1.4.1 (A5): after a boss's hit (its body or a mark) the player takes no damage for this long instead
## of player_hurt_cooldown: time to get out of its reach before the boss or its crowd hits again.
@export var boss_hit_grace: float = 1.1
## 1.4.1 (C6): a big hit – a mark, a boss, or at least this share of max HP – pushes the player away from
## where it came from at this speed (m/s, fading fast: about 2.5 m) and gets the heavy cues.
@export var hit_big_share: float = 0.15
@export var hit_knock_speed: float = 20.0
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
## 1.4.1 (A4): a big kept Knödl hits hard. Above the tier-L radius the radius counts to this power
## (radius_L * (radius / radius_L) ^ p), so an XL Knödl hits about twice as hard as an L one.
@export var knodl_big_exponent: float = 2.5
## Knödl contacts on elites and bosses count this many times; one hit takes at most this share of a
## boss's max HP, so a merged co-op Riesenknödl does not erase a boss in two passes.
@export var knodl_elite_mult: float = 2.0
@export var knodl_boss_mult: float = 3.0
@export var knodl_boss_hit_cap: float = 0.04
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
## Fliers with an air_reach rise toward an airborne target from this far away (metres, flat).
@export var enemy_air_climb_range: float = 4.0
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
## Spawns ahead of a player (where they run, or look while standing) lie this much farther out: the
## camera sees the ground far ahead, so they come from the distance (EnemyManager.ring_ahead).
@export var spawn_ring_ahead: float = 24.0
## A player counts as running (heading = where they move, not where they face) above this speed.
@export var spawn_heading_min_speed: float = 2.0
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
## The Kirtag lasts until Sperrstund' (15:00). That settles the result (won with the Hofrat beaten,
## else "Sperrstund' erlebt"); then the Nachspielzeit runs until everyone is down.
@export var run_seconds: float = 900.0
@export var riesen_wirt_speed: float = 5.0

@export_group("Nachspielzeit")
## Past Sperrstund' the Stammgast-Geister come (the wave's entries from minute 15): this many at
## first, more every minute, up to spawn_max_count (co-op: times the co-op count).
@export var overtime_start_count: int = 80
## From Sperrstund' on the Kirtag guests go home: any ordinary enemy (not a boss, not a ghost) farther
## than this from every player leaves, unseen and without drops, so the ghosts get their slots.
@export var overtime_leave_distance: float = 25.0
@export var overtime_count_per_minute: float = 60.0
## Every overtime_step_seconds every enemy gets this much faster (up to overtime_pace_max), hits this
## much harder and new ones bring this much more HP (on top of spawn_hp_per_minute).
@export var overtime_step_seconds: float = 30.0
@export var overtime_pace_per_step: float = 0.06
@export var overtime_pace_max: float = 2.0
@export var overtime_damage_per_step: float = 0.1
@export var overtime_hp_per_step: float = 0.1
## Schilling per second of Nachspielzeit (before the Grant and co-op multipliers).
@export var schilling_per_overtime_second: float = 1.0
## When the last player falls: slow motion at this speed, for this many real seconds, then the end
## screen. Not in automated runs.
@export var overtime_slowmo: float = 0.3
@export var overtime_end_seconds: float = 2.5
## The Nachspielzeit ends by itself after this long (a run nobody can lose, e.g. god mode); the
## Ehrentafel accepts runs up to run_seconds + this (board/board.js MAX_RUN_SECONDS).
@export var overtime_max_seconds: float = 600.0

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
## Armor this high takes half of every hit (Formulas.armor_share): 3 armor -23 %, 8 -44 %, 20 -67 %.
@export var armor_half: float = 6.0
## A revive from an item (Marterl-Kerze) brings the player back with this share of their max HP.
@export var item_revive_hp: float = 0.5

@export_group("Meta")
## Schilling a run pays (GAME-DESIGN.md: gold, cash-ins, 25 % of the Knödl when knocked out):
## per gold picked up, per cash-in by tier S..XL, the Knödl share, a win bonus, +10 % per extra player.
@export var schilling_per_gold: float = 0.1
@export var schilling_per_cash_in: PackedFloat32Array = PackedFloat32Array([5.0, 15.0, 40.0, 100.0])
@export var schilling_knodl_share: float = 0.25
@export var schilling_win_bonus: float = 100.0
@export var coop_schilling_per_player: float = 0.1
## Grant modifiers: Föhn pushes every Knödl this hard (m/s^2, in gusts), Kontrolle multiplies elites.
@export var foehn_force: float = 3.0
## The Weinbergschnecke's slime trail (SlimeTrail): seconds a spot lasts, seconds between two spots
## of one snail, spot radius in metres.
@export var slime_seconds: float = 5.0
@export var slime_interval: float = 0.5
@export var slime_radius: float = 0.9
@export var kontrolle_elite_mult: float = 2.0

@export_group("Stats")
## Most of a slowing ground's slow the sure_footing stat (Gummistiefel) can take away.
@export var sure_footing_cap: float = 0.8

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
## Opa Hias's "Hat eh Zeit": standing still (slower than idle_speed m/s) this long gives the
## attack speed in his trait_effects[&"idle_rate"].
@export var idle_speed: float = 0.4
@export var idle_seconds: float = 1.0
## Cousine Mitzi's "Trab": running straight at trot_min_speed of the run speed or more for
## trot_seconds gives trait_effects[&"trot"] as speed and Knödl damage; turning further than
## trot_turn_degrees from the line resets it (the line follows a curve at trot_follow per second).
@export var trot_seconds: float = 2.0
@export var trot_min_speed: float = 0.6
@export var trot_turn_degrees: float = 35.0
@export var trot_follow: float = 1.5

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
## Die Hausmeisterin locks stairs and ramps at least this high (StairLock); her gates are this tall.
@export var stair_lock_min_height: float = 6.0
@export var stair_gate_height: float = 3.2

@export_group("Loot")
## Map chests per run (out of the map's chest spots), what one costs and how many items it gives.
@export var map_chest_count: int = 15
@export var map_chest_price: int = 20
## Every map chest a player buys makes their next one this much dearer (times; free chests do not count).
@export var map_chest_price_growth: float = 1.22
@export var map_chest_items: int = 1
## 1.4.1 (A2): a second batch of map chests at this time, more per extra player, at free chest spots.
@export var map_chest_late_time: float = 600.0
@export var map_chest_late_count: int = 5
@export var map_chest_late_per_player: int = 2
@export var chest_pickup_radius: float = 2.0
## Gold per coin, plus this much for every minute on the clock (rounded); any kill drops a coin with this
## chance (elites and bosses drop theirs for sure).
@export var coin_value: int = 1
@export var coin_value_per_minute: float = 0.33
@export var coin_drop_chance: float = 0.01
## 1.4.1 (A2): a player whose gold already pays for their next map chest this many times over gets kill
## coins at this share of the chance (elite, boss and Fassl coins unchanged; the closest player counts).
@export var coin_rich_factor: float = 2.0
@export var coin_rich_mult: float = 0.3
## No new kill coins while this many loot items lie around (boss chests and Stempel always find room).
@export var coin_loot_cap: int = 400
## Fassl: barrels the player or the Knödl smashes for coins. This many stand around the players
## (closer than fassl_far to someone), a new one every fassl_respawn seconds, fassl_min..fassl_max m off.
@export var fassl_count: int = 5
@export var fassl_respawn: float = 8.0
@export var fassl_min: float = 14.0
@export var fassl_max: float = 40.0
@export var fassl_far: float = 90.0
## Coins in a Fassl (each worth what a kill coin is worth at that time) and how close breaks it.
@export var fassl_coins: int = 2
@export var fassl_break_radius: float = 1.6
## Coins this close fly to the player (times the Wanderkarte bonus); picked up within the radius.
@export var coin_magnet_range: float = 4.0
@export var coin_pickup_radius: float = 1.2
## A Gulasch drops with this chance per kill and heals this much.
@export var heal_drop_chance: float = 0.0015
@export var heal_amount: float = 35.0
## 1.4.1 (A3): Lebkuchenherzerl, small hearts. Per kill one drops with heart_drop_chance times how much
## HP the closest player is missing (nothing at full HP, the full chance from heart_full_below of their
## max HP down); it heals heart_amount and flies to a hurt player from heart_magnet_range metres.
@export var heart_drop_chance: float = 0.02
@export var heart_full_below: float = 0.4
@export var heart_amount: float = 5.0
@export var heart_magnet_range: float = 8.0

@export_group("Item effects (1.4)")
## Most item procs one frame handles (all players) and most proc effects it shows.
@export var item_proc_budget: int = 40
@export var item_cue_budget: int = 6
## What item effects with their own damage (wisps, shock rings, the Spagat cut) start from, times
## the effect's value and the player's damage.
@export var item_base_damage: float = 20.0
## Rodel: downhill push on the string (m/s² per copy's value).
@export var rodel_push: float = 14.0
## "Knödl folgt brav": the pull toward the nearest Brösel (m/s²) within the string's reach of the player.
@export var knodl_follow_pull: float = 18.0
## The pop shown where a proc hit (RunEventCodec.Cue.SPARK).
@export var spark_radius: float = 1.4

@export_group("Tageskarte (Daily Kirtag)")
## The day's Grant level is drawn from this range (indices into GameContent.grants; 1 = Normal).
@export var daily_grant_min: int = 1
@export var daily_grant_max: int = 2

@export_group("Der Standler")
## He sets up near the players at these minutes and stays this long; walking up to his stall (within
## standler_radius) opens his shop: standler_items items per player (their own offer in co-op).
@export var standler_minutes: PackedFloat32Array = PackedFloat32Array([3.0, 9.0])
@export var standler_stay: float = 75.0
@export var standler_radius: float = 3.0
@export var standler_items: int = 3
## He sets up this far from one of the players.
@export var standler_distance: float = 10.0
## Co-op: the shop closes after this long (solo pauses, no limit).
@export var standler_shop_seconds: float = 12.0
## An item's price by rarity (Gewöhnlich .. Hofratswürdig), times standler_price_growth for every item
## the player already bought from him this run, times (1 + standler_price_per_minute * minute).
@export var standler_prices: PackedInt32Array = PackedInt32Array([30, 45, 70, 110])
@export var standler_price_growth: float = 1.3
@export var standler_price_per_minute: float = 0.04

@export_group("Marterl")
## Wayside shrines per run (on chest spots no chest took), used once each by standing within
## marterl_radius for marterl_pray_seconds.
@export var marterl_count: int = 3
@export var marterl_radius: float = 2.5
@export var marterl_pray_seconds: float = 1.5
## Mutprobe: this long, a ring of marterl_ring_count enemies marterl_ring_radius out every
## marterl_ring_every seconds; then a free chest.
@export var marterl_mutprobe_seconds: float = 30.0
@export var marterl_ring_every: float = 5.0
@export var marterl_ring_count: int = 16
@export var marterl_ring_radius: float = 14.0
## Gier: this long, the crowd and the gold from coins times marterl_gier_mult.
@export var marterl_gier_seconds: float = 60.0
@export var marterl_gier_mult: float = 2.0
## Segen: free Speisekarte rounds for the one who prays.
@export var marterl_segen_levels: int = 1

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
## The same over the relay (browsers): the Cloudflare hop and the relay's batching jitter more.
@export var relay_interpolation_delay_ms: int = 150
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
## The jolt of a heavy Knödl hit (1.4.1, A4): degrees at full strength, and how fast it fades (1/s).
@export var camera_nudge_degrees: float = 1.6
@export var camera_nudge_fade: float = 5.0

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

@export_group("Enemy voices")
## EnemyVoices (Berghittn's Gredn, far less chatty): one line overall every voice_gap_min..max
## seconds at most (never over the one before), plus up to voice_idle_wait for a moment's line
## (an attack, last words ...) before an idle one is picked. One line per enemy type every
## voice_type_gap; only enemies within voice_reach of a player talk.
@export var voice_gap_min: float = 2.5
@export var voice_gap_max: float = 4.0
@export var voice_idle_wait: float = 1.0
@export var voice_type_gap: float = 10.0
@export var voice_reach: float = 20.0
## Bosses (and the Kontrolleur, the Riesen-Wirt) skip the overall gap, but say one line every
## voice_boss_gap at most; their attacks only now and then.
@export var voice_boss_gap: float = 6.0
@export var voice_chance_boss_attack: float = 0.5
## Chance per moment that a line is said when it comes (VoiceLineData.chance overrides it).
@export var voice_chance_attack: float = 0.35
@export var voice_chance_death: float = 0.15
@export var voice_chance_crushed: float = 0.3
@export var voice_chance_eat: float = 0.4
## The text over the head: shown this far from the camera at most, at least this long (or the
## voice's length), then fading.
@export var voice_show_reach: float = 25.0
@export var voice_min_seconds: float = 1.6
@export var voice_fade_seconds: float = 0.4
