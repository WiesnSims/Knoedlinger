class_name CharacterData
extends Resource
## One member of the Knödlinger family (GAME-DESIGN.md, "Characters"): start weapon, Knödl sort,
## look, and the passive trait as data (stats on top of the build, extra cards, a slope bonus, a
## bigger start Knödl, and named rules in `trait_effects` that RunWorld knows).

@export var id: StringName = &""
## Translation key of the player-facing name.
@export var name_key: String = ""
## Translation keys: the role in the family (one line) and the passive trait.
@export var role_key: String = ""
@export var trait_key: String = ""
@export var start_weapon: WeaponData
@export var knodl_sort: KnodlSortData
## Jumps on top of balance.player_jumps (Cousin Toni starts with a double jump).
@export var extra_jumps: int = 0
@export_group("Trait")
## Stats on top of the build like the Stammtisch bonus (PlayerBuild.STATS), e.g. {&"max_hp": 20.0}.
@export var trait_stats: Dictionary[StringName, float] = {}
## More cards on every Speisekarte.
@export var extra_cards: int = 0
## Faster on slopes by this fraction (Cousin Toni).
@export var slope_speed: float = 0.0
## The Knödl starts this much heavier (fraction, on top of the sort and the Stammtisch).
@export var knodl_start: float = 0.0
## Rules of their own, name -> number: &"grant" (damage per hit taken, up to balance.grant_cap),
## &"coffee_break" (seconds between enemies pausing for a coffee), &"free_banish" (seconds per free
## banish), &"jump_wave" (every n-th jump makes a shockwave).
@export var trait_effects: Dictionary[StringName, float] = {}

@export_group("Look")
@export var coat_color: Color = Color(0.2, 0.32, 0.55)
@export var trouser_color: Color = Color(0.3, 0.24, 0.18)
@export var hat_color: Color = Color(0.22, 0.35, 0.2)
