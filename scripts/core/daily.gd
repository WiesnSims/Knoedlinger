class_name Daily
extends RefCounted
## Die Tageskarte (Daily Kirtag, 1.4 task 5.1): one run a day that is the same for everyone – the
## Knödlinger, the map, the Grant level and the seed all follow from the UTC date, so every player
## gets the same card from midnight UTC on. The first try of a day goes onto its own Ehrentafel board
## (mode "daily", map "daily_<day>"); more tries that day are only for practice. Any Knödlinger and any
## map can come up, locked or not: the Tageskarte is a taste, it unlocks nothing (the Speisekarte still
## offers only what the player has unlocked).

const SECONDS_PER_DAY: int = 86400
## The board's map key for a day (board/board.js checks the same pattern).
const BOARD_PREFIX: String = "daily_"


## The UTC day of a unix time as "YYYYMMDD".
static func day_id(unix: int) -> String:
	var date: Dictionary = Time.get_date_dict_from_unix_time(unix)
	return "%04d%02d%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]


static func now() -> int:
	return int(Time.get_unix_time_from_system())


## Today's day id; `daily_day=YYYYMMDD` on the command line or in the URL pins it (tests).
static func today() -> String:
	var pinned: String = LaunchArgs.get_string("daily_day", "")
	return pinned if pinned.length() == 8 and pinned.is_valid_int() else day_id(now())


## The day before a day id.
static func day_before(day: String) -> String:
	return day_id(unix_of(day) - SECONDS_PER_DAY)


## Midnight UTC of a day id.
static func unix_of(day: String) -> int:
	return Time.get_unix_time_from_datetime_dict({
		"year": day.substr(0, 4).to_int(), "month": day.substr(4, 2).to_int(), "day": day.substr(6, 2).to_int(),
		"hour": 0, "minute": 0, "second": 0,
	})


static func board_map(day: String) -> String:
	return BOARD_PREFIX + day


## "6.11.2026" for the screens.
static func date_text(day: String) -> String:
	return "%d.%d.%s" % [day.substr(6, 2).to_int(), day.substr(4, 2).to_int(), day.substr(0, 4)]


## The day's card: {character, map, grant, seed}. Only the date and the content lists decide it.
static func pick(content: GameContent, balance: BalanceData, day: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("knoedlinger-tageskarte-" + day).hash()
	var character: CharacterData = content.characters[rng.randi_range(0, content.characters.size() - 1)]
	var map: MapInfo = content.maps[rng.randi_range(0, content.maps.size() - 1)]
	var top: int = mini(balance.daily_grant_max, content.grants.size() - 1)
	var grant: int = rng.randi_range(mini(balance.daily_grant_min, top), top)
	return {"character": character.id, "map": map.id, "grant": grant, "seed": rng.randi_range(1, 99999)}
