extends Node
## Die Ehrentafel (autoload Board; docs/DECISIONS.md, M4): the global highscore board on
## <page origin>/api/board (board/board.js), reused from Berghittn's Gipfelbuch. A run asks for a
## ticket when it starts (start_run), its end sends the result with it (submit), and the Rekorde
## screen lists the boards (fetch). Only real runs count: started from the main menu, with the
## setting on, in the browser (previews have their own board); automated and debug runs never send.
## Without a connection nothing happens: the signals just say so, the game goes on.

## Our result was saved: its place, all time and this week, and its id.
signal ranked(rank: int, week_rank: int, id: int)
signal not_ranked
## The board asked for by fetch(): `entries` as the server sends them (empty if it failed).
signal listed(mode: String, map: String, period: String, entries: Array, ok: bool)

const TIMEOUT: float = 8.0
## Own entries remembered (highlighted on the board).
const REMEMBERED: int = 50

var _ticket: String = ""
var _asking: bool = false


## This run may go onto the Ehrentafel at all.
func run_counts() -> bool:
	return base_url() != "" and Settings.persistent and Settings.get_bool(&"board") and RunSetup.from_menu \
			and Boot.start_scene(LaunchArgs.keys()) == "menu"


## A run started: a fresh ticket for it.
func start_run(mode: String, map: String) -> void:
	_ticket = ""
	if not run_counts():
		return
	_asking = true
	var reply: Dictionary = await _request("ticket", HTTPClient.METHOD_POST, {"mode": mode, "map": map})
	_asking = false
	if reply.has("ticket"):
		_ticket = str(reply["ticket"])


## Sends the run (keys as board/board.js takes them; the ticket is added here). Emits ranked or
## not_ranked. The ticket counts once.
func submit(entry: Dictionary) -> void:
	while _asking:
		await get_tree().process_frame
	if _ticket == "" or not run_counts():
		not_ranked.emit()
		return
	var body: Dictionary = entry.duplicate()
	body["ticket"] = _ticket
	body["version"] = NetworkManager.version
	_ticket = ""
	var reply: Dictionary = await _request("entry", HTTPClient.METHOD_POST, body)
	if not reply.has("rank"):
		not_ranked.emit()
		return
	remember(int(reply["id"]))
	ranked.emit(int(reply["rank"]), int(reply["week_rank"]), int(reply["id"]))


func remember(id: int) -> void:
	var ids: Array = Profile.data.get("board_ids", [])
	if id > 0 and not ids.has(id):
		ids.append(id)
		while ids.size() > REMEMBERED:
			ids.remove_at(0)
		Profile.data["board_ids"] = ids
		Profile._save()


func is_mine(id: int) -> bool:
	return (Profile.data.get("board_ids", []) as Array).has(float(id)) or (Profile.data.get("board_ids", []) as Array).has(id)


## One board: `mode` solo or coop, a map id, `period` all or week; answered by `listed`.
func fetch(mode: String, map: String, period: String) -> void:
	if base_url() == "":
		listed.emit.call_deferred(mode, map, period, [], false)
		return
	var reply: Dictionary = await _request("list?mode=%s&map=%s&range=%s" % [mode, map, period], HTTPClient.METHOD_GET, {})
	var entries: Array = reply.get("entries", []) if reply.get("entries") is Array else []
	listed.emit(mode, map, period, entries, reply.has("entries"))


## Where the board is: the page's own origin in the browser (previews have their own database),
## else --board=<url>; "" on the desktop without it, so test runs never write to the real one.
func base_url() -> String:
	if has_meta(&"test_url"):
		return get_meta(&"test_url")
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("location.origin", true)
		return str(origin) if origin is String and str(origin).begins_with("http") else ""
	return LaunchArgs.get_string("board", "")


func _request(path: String, method: HTTPClient.Method, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	# The end screen and menus may pause the game; the request must still finish.
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var data: String = JSON.stringify(body) if method == HTTPClient.METHOD_POST else ""
	if http.request("%s/api/board/%s" % [base_url(), path], headers, method, data) != OK:
		http.queue_free()
		return {}
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return {}
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}
