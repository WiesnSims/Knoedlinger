class_name GameContent
extends Resource
## What the menus list: the Knödlinger family and the maps, in menu order. Adding a character or a
## map = its .tres plus a line here, no code (CLAUDE.md, "Adding content must not require code
## changes"). The Speisekarte's weapons and stat upgrades live in data/catalog/catalog.tres.

const PATH: String = "res://data/content.tres"

@export var characters: Array[CharacterData] = []
@export var maps: Array[MapInfo] = []
## The meta (Profile): Stammtisch upgrades, Gemeindeamt quests, Grant levels from easy to hard.
@export var upgrades: Array[MetaUpgradeData] = []
@export var quests: Array[QuestData] = []
@export var grants: Array[GrantData] = []
## The Almanach's bestiary, in order.
@export var enemies: Array[EnemyTypeData] = []


static func load_default() -> GameContent:
	return load(PATH) as GameContent


func character(id: StringName) -> CharacterData:
	for entry: CharacterData in characters:
		if entry.id == id:
			return entry
	return null


func map_info(id: StringName) -> MapInfo:
	for entry: MapInfo in maps:
		if entry.id == id:
			return entry
	return null
