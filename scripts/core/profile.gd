extends Node
## The player's progress between runs (autoload Profile; GAME-DESIGN.md, "Meta progression"):
## Schilling, Stammtisch ranks, quests done, what is unlocked, lifetime counters for the quests, the
## records per character and map, the Grant level reached, and what the Almanach has seen. Saved as
## JSON in user://profile.json (IndexedDB in the browser) and exportable as a code ("KNDL1.<data>.<check>")
## so a cleared browser cache loses nothing. Automated runs keep it in memory only (like Settings).
## The data lists (upgrades, quests, Grant levels) come from GameContent.

signal changed

const PATH: String = "user://profile.json"
const VERSION: int = 1
const CODE_PREFIX: String = "KNDL1."
const MAX_CODE_BYTES: int = 1 << 20
## Kinds whose things can be locked behind a quest and found for the Almanach.
const KINDS: Array[StringName] = [&"character", &"weapon", &"passive", &"item", &"map", &"knodl", &"enemy"]
## Cloudflare Pages previews live on subdomains of the live site (`v1-4.knoedlinger.pages.dev`).
const PREVIEW_HOST_SUFFIX: String = ".knoedlinger.pages.dev"
## The main menu's "Spielstand sichern?" note comes back after this many more Aufträge (1.4.1, C4).
const SAVE_HINT_EVERY: int = 10

var content: GameContent
var persistent: bool = true
var data: Dictionary = {}
## Playtest builds: every quest-locked thing and every Grant level is open, without touching the save
## (quests still count and pay). On by itself on a preview URL; `unlock_all=0|1` forces it either way.
var unlock_all: bool = false
## kind:id -> the quest that unlocks it (everything else is open from the start).
var _locked_by: Dictionary[String, QuestData] = {}


func _ready() -> void:
	content = GameContent.load_default()
	for quest: QuestData in content.quests:
		if quest.unlock_kind != &"":
			_locked_by[_key(quest.unlock_kind, quest.unlock_id)] = quest
	persistent = Settings.persistent
	unlock_all = LaunchArgs.get_flag("unlock_all", is_preview_host(_page_host()))
	if unlock_all:
		print("[PROFILE] preview build: everything unlocked")
	data = _fresh()
	var had_save: bool = persistent and FileAccess.file_exists(PATH)
	if persistent:
		_load()
	# A first start has nothing new to read in the patch list (1.4.1, C5); an older save does.
	if not had_save:
		(data["notes"] as Dictionary)["patches_seen"] = _game_version()


static func is_preview_host(host: String) -> bool:
	return host.ends_with(PREVIEW_HOST_SUFFIX)


static func _page_host() -> String:
	if not OS.has_feature("web"):
		return ""
	var host: Variant = JavaScriptBridge.eval("window.location.hostname", true)
	return host if host is String else ""


# --- Reading -------------------------------------------------------------------------------------

func schilling() -> int:
	return int(data.get("schilling", 0))


func rank(upgrade: StringName) -> int:
	return int((data["ranks"] as Dictionary).get(String(upgrade), 0))


func is_quest_done(quest: StringName) -> bool:
	return (data["quests"] as Dictionary).has(String(quest))


## Open from the start unless a quest unlocks it; then open once that quest is done.
func is_unlocked(kind: StringName, id: StringName) -> bool:
	var quest: QuestData = _locked_by.get(_key(kind, id))
	return unlock_all or quest == null or is_quest_done(quest.id)


## The quest that unlocks something still locked (null when it is open).
func unlocking_quest(kind: StringName, id: StringName) -> QuestData:
	var quest: QuestData = _locked_by.get(_key(kind, id))
	return quest if quest != null and not unlock_all and not is_quest_done(quest.id) else null


func is_found(kind: StringName, id: StringName) -> bool:
	return ((data["found"] as Dictionary).get(String(kind), []) as Array).has(String(id))


## Highest Grant level that may be chosen (index into content.grants).
func grant_unlocked() -> int:
	var top: int = maxi(content.grants.size() - 1, 0)
	return top if unlock_all else clampi(int(data.get("grant_unlocked", 1)), 0, top)


## The sum of every Stammtisch rank's gain, per stat (PlayerBuild.STATS or a special).
func meta_bonus() -> Dictionary[StringName, float]:
	var bonus: Dictionary[StringName, float] = {}
	for upgrade: MetaUpgradeData in content.upgrades:
		var owned: int = rank(upgrade.id)
		if owned > 0:
			bonus[upgrade.stat] = bonus.get(upgrade.stat, 0.0) + upgrade.per_rank * owned
	return bonus


## A quest's progress toward its target (its target or more = done when checked).
func progress(quest: QuestData) -> float:
	var stats: Dictionary = data["stats"]
	var best: Dictionary = data["best"]
	var filter: String = String(quest.filter)
	match quest.kind:
		&"kills":
			return float((stats["kills"] as Dictionary).get(filter if filter != "" else "_all", 0))
		&"cash_ins":
			var tiers: Array = stats["cash_ins"]
			if filter == "":
				var total: int = 0
				for count: Variant in tiers:
					total += int(count)
				return total
			return float(tiers[clampi(filter.to_int(), 0, 3)])
		&"level":
			return float((best["level"] as Dictionary).get(filter if filter != "" else "_all", 0))
		&"wins":
			return float((stats["wins"] as Dictionary).get(filter if filter != "" else "_all", 0))
		&"runs":
			return float(stats.get("runs", 0))
		&"bosses":
			return float((stats["bosses"] as Dictionary).get(filter, 0))
		&"boss_no_throw":
			return float((best["boss_no_throw"] as Dictionary).get(filter, 0))
		&"stempel":
			return float(stats.get("stempel", 0))
		&"knodl":
			return float(best.get("knodl", 0.0))
		&"survive":
			return float(best.get("survive", 0.0)) / 60.0
		&"overtime":
			return float((best["overtime"] as Dictionary).get(filter if filter != "" else "_all", 0.0)) / 60.0
		&"schilling":
			return float(data.get("schilling_total", 0))
		&"items":
			return float(((data["found"] as Dictionary).get("item", []) as Array).size())
		&"grant_win":
			return float(best.get("grant_win", -1))
		&"coop":
			return float((stats.get("coop", {}) as Dictionary).get(filter, 0))
		&"daily_streak":
			return float((data["daily"] as Dictionary).get("best_streak", 0))
		&"daily_days":
			return float((data["daily"] as Dictionary).get("days", 0))
		&"chests", &"gold", &"standler", &"marterl":
			return float(stats.get(String(quest.kind), 0))
		&"chests_run":
			return float(best.get("chests_run", 0))
	return 0.0


## Die Tageskarte: the day was already played (its first try is used up).
func daily_played(day: String) -> bool:
	return str((data["daily"] as Dictionary).get("last", "")) == day


## Days in a row with a Tageskarte run, as it stands on `day` (0 once a day was missed).
func daily_streak(day: String) -> int:
	var daily: Dictionary = data["daily"]
	var last: String = str(daily.get("last", ""))
	return int(daily.get("streak", 0)) if last == day or last == Daily.day_before(day) else 0


func daily_best_streak() -> int:
	return int((data["daily"] as Dictionary).get("best_streak", 0))


## A Tageskarte run of `day` starts. The first one of the day counts (for the board and the streak)
## and is noted at once, so leaving or reloading never gives a second first try. True if it counts.
func start_daily(day: String) -> bool:
	if daily_played(day):
		return false
	var daily: Dictionary = data["daily"]
	var streak: int = int(daily.get("streak", 0)) + 1 if str(daily.get("last", "")) == Daily.day_before(day) else 1
	daily["streak"] = streak
	daily["best_streak"] = maxi(int(daily.get("best_streak", 0)), streak)
	daily["days"] = int(daily.get("days", 0)) + 1
	daily["last"] = day
	_save()
	return true


func record(character: StringName, map: StringName) -> Dictionary:
	return (data["records"] as Dictionary).get("%s|%s" % [character, map], {})


# --- Changing ------------------------------------------------------------------------------------

## Buys the next rank of a Stammtisch upgrade. False when maxed or too dear.
func buy(upgrade: MetaUpgradeData) -> bool:
	var owned: int = rank(upgrade.id)
	if owned >= upgrade.max_rank or schilling() < upgrade.cost(owned):
		return false
	data["schilling"] = schilling() - upgrade.cost(owned)
	(data["ranks"] as Dictionary)[String(upgrade.id)] = owned + 1
	_save()
	return true


func discover(kind: StringName, id: StringName) -> void:
	if id == &"" or is_found(kind, id):
		return
	var found: Dictionary = data["found"]
	if not found.has(String(kind)):
		found[String(kind)] = []
	(found[String(kind)] as Array).append(String(id))


func remember_choice(character: StringName, map: StringName, grant: int) -> void:
	data["last"] = {"character": String(character), "map": String(map), "grant": grant}
	_save()


func last_choice() -> Dictionary:
	return data.get("last", {})


## A run is over: counts it, pays its Schilling, stamps the quests it completed, keeps the records.
## `run` holds: character, map, grant, result ("WON", "CLOSED", "LOST", "QUIT"), time, level, kills,
## kills_by_type {enemy id: n}, cash_ins [S, M, L, XL], bosses [ids], throws, stempel, best_knodl_mass,
## schilling, found {weapons, passives, items: [ids]}. Returns {schilling, quests: [QuestData],
## records: [names], grant_unlocked: bool}.
func record_run(run: Dictionary) -> Dictionary:
	var stats: Dictionary = data["stats"]
	var best: Dictionary = data["best"]
	var character: String = str(run.get("character", ""))
	var map: String = str(run.get("map", ""))
	var won: bool = str(run.get("result", "")) == "WON"
	var earned: int = maxi(int(run.get("schilling", 0)), 0)
	data["schilling"] = schilling() + earned
	data["schilling_total"] = int(data.get("schilling_total", 0)) + earned
	stats["runs"] = int(stats.get("runs", 0)) + 1
	var kills: Dictionary = stats["kills"]
	kills["_all"] = int(kills.get("_all", 0)) + int(run.get("kills", 0))
	var by_type: Dictionary = run.get("kills_by_type", {})
	for enemy: Variant in by_type:
		kills[str(enemy)] = int(kills.get(str(enemy), 0)) + int(by_type[enemy])
		if int(by_type[enemy]) > 0:
			discover(&"enemy", StringName(str(enemy)))
	var tiers: Array = stats["cash_ins"]
	var run_tiers: Array = run.get("cash_ins", [])
	for k: int in mini(run_tiers.size(), 4):
		tiers[k] = int(tiers[k]) + int(run_tiers[k])
	stats["stempel"] = int(stats.get("stempel", 0)) + int(run.get("stempel", 0))
	# 1.4: map chests, gold earned, Der Standler and the Marterl, over all runs.
	for pair: Array in [["chests", "chests_opened"], ["gold", "gold_earned"], ["standler", "standler_buys"],
			["marterl", "marterl_used"]]:
		stats[pair[0]] = int(stats.get(pair[0], 0)) + int(run.get(pair[1], 0))
	best["chests_run"] = maxi(int(best.get("chests_run", 0)), int(run.get("chests_opened", 0)))
	# Co-op deeds (CoopRules, counted per player): {runs, revives, passes, ...: n}.
	var coop: Dictionary = run.get("coop", {})
	if not coop.is_empty():
		if not stats.has("coop"):
			stats["coop"] = {}
		var counts: Dictionary = stats["coop"]
		for key: Variant in coop:
			counts[str(key)] = int(counts.get(str(key), 0)) + int(coop[key])
	var bosses: Dictionary = stats["bosses"]
	for boss: Variant in run.get("bosses", []):
		bosses[str(boss)] = int(bosses.get(str(boss), 0)) + 1
		if int(run.get("throws", 0)) == 0:
			(best["boss_no_throw"] as Dictionary)[str(boss)] = 1
	if won:
		var wins: Dictionary = stats["wins"]
		for key: String in ["_all", character, map]:
			wins[key] = int(wins.get(key, 0)) + 1
	var levels: Dictionary = best["level"]
	var level: int = int(run.get("level", 0))
	for key: String in ["_all", character]:
		levels[key] = maxi(int(levels.get(key, 0)), level)
	best["knodl"] = maxf(float(best.get("knodl", 0.0)), float(run.get("best_knodl_mass", 0.0)))
	best["survive"] = maxf(float(best.get("survive", 0.0)), float(run.get("time", 0.0)))
	# Nachspielzeit: the longest run past Sperrstund', overall and per Knödlinger (seconds).
	var overtime: Dictionary = best["overtime"]
	for key: String in ["_all", character]:
		overtime[key] = maxf(float(overtime.get(key, 0.0)), float(run.get("overtime", 0.0)))
	var grant: int = int(run.get("grant", 1))
	var grant_up: bool = false
	if won:
		best["grant_win"] = maxi(int(best.get("grant_win", -1)), grant)
		if grant + 1 > int(data.get("grant_unlocked", 1)) and grant + 1 < content.grants.size():
			data["grant_unlocked"] = grant + 1
			grant_up = true
	for kind: StringName in [&"weapon", &"passive", &"item"]:
		for id: Variant in (run.get("found", {}) as Dictionary).get(String(kind) + "s", []):
			discover(kind, StringName(str(id)))
	var new_records: Array[String] = _keep_records(run, character, map, won, earned)
	var done: Array[QuestData] = []
	for quest: QuestData in content.quests:
		if not is_quest_done(quest.id) and progress(quest) >= quest.target:
			(data["quests"] as Dictionary)[String(quest.id)] = int(Time.get_unix_time_from_system())
			data["schilling"] = schilling() + quest.reward_schilling
			done.append(quest)
	_save()
	return {"schilling": earned, "quests": done, "records": new_records, "grant_unlocked": grant_up}


func _keep_records(run: Dictionary, character: String, map: String, won: bool, earned: int) -> Array[String]:
	var key: String = "%s|%s" % [character, map]
	var records: Dictionary = data["records"]
	var old: Dictionary = records.get(key, {})
	var new: Dictionary = old.duplicate()
	var better: Array[String] = []
	var values: Dictionary = {
		"time": float(run.get("time", 0.0)), "level": int(run.get("level", 0)), "kills": int(run.get("kills", 0)),
		"knodl": float(run.get("best_knodl_mass", 0.0)), "schilling": earned,
	}
	for name: String in values:
		if float(values[name]) > float(old.get(name, 0)):
			new[name] = values[name]
			if old.has(name):
				better.append(name)
	if won:
		new["wins"] = int(old.get("wins", 0)) + 1
		new["grant"] = maxi(int(old.get("grant", -1)), int(run.get("grant", 1)))
	new["runs"] = int(old.get("runs", 0)) + 1
	records[key] = new
	return better


## Back to a fresh profile (the settings stay).
func reset() -> void:
	data = _fresh()
	(data["notes"] as Dictionary)["patches_seen"] = _game_version()
	_save()


## For tests: a fresh profile in memory with this much Schilling.
func reset_memory(p_schilling: int = 0) -> void:
	data = _fresh()
	(data["notes"] as Dictionary)["patches_seen"] = _game_version()
	data["schilling"] = p_schilling


# --- Notes in the main menu (1.4.1) ---------------------------------------------------------------

## The game is newer than the last patch list the player opened: "Neu!" on its menu entry (C5).
func patches_new() -> bool:
	return str((data["notes"] as Dictionary).get("patches_seen", "")) != _game_version()


func mark_patches_seen() -> void:
	if not patches_new():
		return
	(data["notes"] as Dictionary)["patches_seen"] = _game_version()
	_save()


## Time to remind the player to copy their save code (C4): once the first Knödlinger is unlocked, then
## every SAVE_HINT_EVERY Aufträge, until they say "Nimma erinnern".
func save_hint_due() -> bool:
	var notes: Dictionary = data["notes"]
	if bool(notes.get("save_hint_off", false)):
		return false
	var unlocked: bool = false
	for quest: QuestData in content.quests:
		if quest.unlock_kind == &"character" and is_quest_done(quest.id):
			unlocked = true
			break
	return unlocked and (data["quests"] as Dictionary).size() >= int(notes.get("save_hint_quests", 0))


## The note was answered: `forever` = "Nimma erinnern", otherwise it waits for SAVE_HINT_EVERY more Aufträge.
func answer_save_hint(forever: bool) -> void:
	var notes: Dictionary = data["notes"]
	if forever:
		notes["save_hint_off"] = true
	else:
		notes["save_hint_quests"] = (data["quests"] as Dictionary).size() + SAVE_HINT_EVERY
	_save()


static func _game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


# --- Export code ---------------------------------------------------------------------------------

func export_code() -> String:
	var raw: PackedByteArray = JSON.stringify(data).to_utf8_buffer()
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_GZIP)
	var body: String = Marshalls.raw_to_base64(packed).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")
	return "%s%s.%s" % [CODE_PREFIX, body, _check(body)]


## Loads a code from export_code(). Returns "" on success or why not ("format", "check", "data").
func import_code(code: String) -> String:
	var text: String = code.strip_edges()
	if not text.begins_with(CODE_PREFIX):
		return "format"
	var parts: PackedStringArray = text.substr(CODE_PREFIX.length()).split(".")
	if parts.size() != 2:
		return "format"
	if _check(parts[0]) != parts[1]:
		return "check"
	var b64: String = parts[0].replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	var packed: PackedByteArray = Marshalls.base64_to_raw(b64)
	var raw: PackedByteArray = packed.decompress_dynamic(MAX_CODE_BYTES, FileAccess.COMPRESSION_GZIP)
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not parsed is Dictionary or int((parsed as Dictionary).get("v", 0)) != VERSION:
		return "data"
	data = _merged(parsed as Dictionary)
	_save()
	return ""


static func _check(body: String) -> String:
	return "%08x" % (body.hash() & 0xFFFFFFFF)


# --- Storage -------------------------------------------------------------------------------------

func _fresh() -> Dictionary:
	return {
		"v": VERSION, "schilling": 0, "schilling_total": 0, "ranks": {}, "quests": {}, "grant_unlocked": 1,
		"stats": {"kills": {}, "cash_ins": [0, 0, 0, 0], "runs": 0, "wins": {}, "bosses": {}, "stempel": 0},
		"best": {"level": {}, "knodl": 0.0, "survive": 0.0, "boss_no_throw": {}, "grant_win": -1, "overtime": {}},
		"found": {}, "records": {}, "last": {},
		"daily": {"last": "", "streak": 0, "best_streak": 0, "days": 0},
		"notes": {"patches_seen": "", "save_hint_quests": 0, "save_hint_off": false},
	}


## A loaded profile on top of a fresh one, so a save from an older build gets the newer keys.
func _merged(loaded: Dictionary) -> Dictionary:
	var fresh: Dictionary = _fresh()
	for key: Variant in loaded:
		if fresh.has(key) and fresh[key] is Dictionary and loaded[key] is Dictionary:
			var inner: Dictionary = fresh[key]
			inner.merge(loaded[key], true)
		elif fresh.has(key) and typeof(fresh[key]) == typeof(loaded[key]):
			fresh[key] = loaded[key]
		elif fresh.has(key) and fresh[key] is int and loaded[key] is float:
			fresh[key] = int(loaded[key])
	var tiers: Array = (fresh["stats"] as Dictionary)["cash_ins"]
	while tiers.size() < 4:
		tiers.append(0)
	return fresh


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		data = _merged(parsed as Dictionary)


func _save() -> void:
	changed.emit()
	if not persistent:
		return
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save the profile.")
		return
	file.store_string(JSON.stringify(data))
	file.close()


static func _key(kind: StringName, id: StringName) -> String:
	return "%s:%s" % [kind, id]
