class_name ItemData
extends Resource
## One piece of Kirtagsware (GAME-DESIGN.md, "Items"): passive gear that only chests give. No slot
## limit, items stack; each copy adds `stats` once (PlayerBuild.STATS names, fractions are
## percentages) and its `effect`, a named rule the game knows (see PlayerBuild.EFFECTS), with
## `effect_value` per copy. The Knödl upgrades are items too.

@export var id: StringName = &""
## Translation keys of the name and the deadpan one-liner.
@export var name_key: String = ""
@export var desc_key: String = ""
## Gewöhnlich, Fein, Edel, Hofratswürdig: which chests can hold it (the chest's rolled rarity).
@export_range(0, 3) var rarity: int = 0
## What one copy adds, e.g. {&"luck": 0.1}.
@export var stats: Dictionary[StringName, float] = {}
## A special rule by name (&"" = none), e.g. &"free_chest", and how much one copy adds to it.
@export var effect: StringName = &""
@export var effect_value: float = 0.0
## Most copies one player can hold (0 = no limit).
@export var max_stacks: int = 0
## Knödl upgrades are listed apart in the inventory.
@export var knodl: bool = false
## An item evolution (GAME-DESIGN.md: Riesenknödl der Apokalypse): no chest gives it; the host
## hands it out once a player holds `evolves_from` and has `evolves_with` at its evolution level.
@export var evolves_from: ItemData
@export var evolves_with: PassiveData
## Tile and chest icon (assets/icons).
@export var icon: Texture2D
@export var color: Color = Color(0.85, 0.75, 0.5)
