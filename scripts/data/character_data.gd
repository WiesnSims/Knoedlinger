class_name CharacterData
extends Resource
## One member of the Knödlinger family (GAME-DESIGN.md, "Characters"). M1 uses the start weapon,
## the Knödl sort and the look; traits come with the rest of the family in M4.

@export var id: StringName = &""
## Translation key of the player-facing name.
@export var name_key: String = ""
@export var start_weapon: WeaponData
@export var knodl_sort: KnodlSortData
## Jumps on top of balance.player_jumps (Cousin Toni starts with a double jump).
@export var extra_jumps: int = 0
@export var coat_color: Color = Color(0.2, 0.32, 0.55)
@export var trouser_color: Color = Color(0.3, 0.24, 0.18)
@export var hat_color: Color = Color(0.22, 0.35, 0.2)
