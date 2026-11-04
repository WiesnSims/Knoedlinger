class_name MetaUpgradeData
extends Resource
## One Stammtisch upgrade (GAME-DESIGN.md, "Meta progression"): bought with Schilling between runs,
## a few ranks, each rank adding `per_rank` to its `stat` for every run from then on. `stat` is a
## PlayerBuild.STATS name, or one of the specials the run reads itself: &"weapon_slots", &"rerolls",
## &"banishes", &"knodl_start" (start mass, fraction), &"revives".

const SPECIALS: Array[StringName] = [&"weapon_slots", &"rerolls", &"banishes", &"knodl_start", &"revives"]

@export var id: StringName = &""
@export var name_key: String = ""
@export var desc_key: String = ""
@export var icon: Texture2D
@export var stat: StringName = &"max_hp"
@export var per_rank: float = 1.0
@export var max_rank: int = 5
## Schilling for the first rank; every further rank costs `cost_growth` times the one before.
@export var cost_base: int = 50
@export var cost_growth: float = 1.4


## What the next rank costs when `rank` ranks are owned.
func cost(rank: int) -> int:
	return roundi(cost_base * pow(cost_growth, rank))
