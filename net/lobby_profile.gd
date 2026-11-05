class_name LobbyProfile
extends RefCounted
## What every player brings to a co-op room (docs/DECISIONS.md, M6): their name, the Knödlinger they
## play, their Stammtisch bonus (each player's own meta progress counts for them) and the characters
## their own Profile has unlocked (so the host can hand a free one to a late joiner). The host also
## puts the room's map and Grant level into its own profile. Everything arrives from the network, so
## it is cleaned before use.

const NAME_MAX: int = 16
const MAX_CHARACTERS: int = 32
## Stat bonuses beyond this are not believed (a Stammtisch maxes far below it).
const META_LIMIT: float = 10.0


static func make(player_name: String, character: String, meta: Dictionary, unlocked: Array) -> Dictionary:
	return sanitize({"name": player_name, "character": character, "meta": meta, "unlocked": unlocked})


## A clean copy: known keys and types only, short strings, finite numbers.
static func sanitize(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var clean: Dictionary = {}
	var player_name: String = str(source.get("name", "")).strip_edges().strip_escapes()
	for bad: String in ["[", "]", "{", "}", "<", ">"]:
		player_name = player_name.replace(bad, "")
	clean["name"] = player_name.substr(0, NAME_MAX) if player_name != "" else "Knödlinger"
	clean["character"] = _id(source.get("character", ""))
	var meta: Dictionary = {}
	var raw_meta: Variant = source.get("meta", {})
	if raw_meta is Dictionary:
		for key: Variant in raw_meta:
			var value: Variant = raw_meta[key]
			if (value is float or value is int) and is_finite(float(value)) and meta.size() < 32:
				meta[StringName(_id(key))] = clampf(float(value), -META_LIMIT, META_LIMIT)
	clean["meta"] = meta
	var unlocked: Array = []
	var raw_unlocked: Variant = source.get("unlocked", [])
	if raw_unlocked is Array:
		for id: Variant in raw_unlocked:
			if unlocked.size() < MAX_CHARACTERS:
				unlocked.append(_id(id))
	clean["unlocked"] = unlocked
	if source.has("map"):
		clean["map"] = _id(source["map"])
	if source.has("grant"):
		clean["grant"] = clampi(int(source["grant"]) if (source["grant"] is int or source["grant"] is float) else 1, 0, 9)
	return clean


static func _id(value: Variant) -> String:
	var text: String = str(value).substr(0, 32)
	var out: String = ""
	for c: String in text:
		if c == "_" or (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out
