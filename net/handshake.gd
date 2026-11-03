class_name Handshake
extends RefCounted
## The lobby filter (CLAUDE.md): every handshake carries game=knoedlinger and ver=<version>; anything
## else is turned away. The build id must match too, so a browser with a stale cached build of the
## same version is told to reload instead of desyncing (as in Berghittn).

const GAME_ID: String = "knoedlinger"
const OK_REASON: String = ""
const REASON_GAME: String = "game"
const REASON_VERSION: String = "version"
const REASON_BUILD: String = "build"


static func query(version: String, build: String) -> String:
	return "game=%s&ver=%s&build=%s" % [GAME_ID, version.uri_encode(), build.uri_encode()]


static func parse_query(text: String) -> Dictionary[String, String]:
	var values: Dictionary[String, String] = {}
	for pair: String in text.trim_prefix("?").split("&", false):
		var at: int = pair.find("=")
		if at > 0:
			values[pair.substr(0, at)] = pair.substr(at + 1).uri_decode()
	return values


## Empty when the joiner may play with us, otherwise the reason it is refused.
static func check(game: String, version: String, build: String, my_version: String, my_build: String) -> String:
	if game != GAME_ID:
		return REASON_GAME
	if version != my_version:
		return REASON_VERSION
	if build != my_build:
		return REASON_BUILD
	return OK_REASON
