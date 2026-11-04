extends Node
## The co-op room, "Stammtisch aufmachen" (GAME-DESIGN.md, Co-op): the host opens a room and gets a
## 4-letter code, friends join with it, everyone picks a different Knödlinger ("Es gibt nur eine
## Oma!"), the host picks the map and Grant level and starts; after the run the host takes everyone
## back to the room. Drop-in only here, never mid-run (the relay refuses joiners once started).
##
## The rules live here, the messages in NetworkManager (LobbyProfile per player). The host settles
## clashes: whoever chose a character second gets the first free one they have unlocked.
## Headless tests: `--net=ws --host --lobby=N` starts the run once N clients are in the room;
## `--net=ws --join=<ip> --lobby` waits in the room until the host starts.

signal changed
## Joining failed or the room closed under us (relay or handshake reason).
signal failed(reason: String)

enum State { OFFLINE, CONNECTING, LOBBY, RUN }

const RUN_SCENE: String = "res://scenes/run/run_world.tscn"
const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const MIN_PLAYERS: int = 2

var state: State = State.OFFLINE
## Why the last session failed or ended ("" when it did not).
var error: String = ""
## The setup the host started the last run with (map, grant, seed, roster).
var setup: Dictionary = {}
var content: GameContent
# Headless: the host starts once this many clients are in the room (-1 = a person starts).
var _auto_clients: int = -1
var _automated: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	content = GameContent.load_default()
	NetworkManager.room_opened.connect(_on_room_opened)
	NetworkManager.joined_host.connect(_on_joined_host)
	NetworkManager.roster_changed.connect(_on_roster_changed)
	NetworkManager.run_start_received.connect(_on_run_start)
	NetworkManager.lobby_return_received.connect(_on_lobby_return)
	NetworkManager.join_failed.connect(_on_failed)
	NetworkManager.session_ended.connect(_on_failed)
	if LaunchArgs.has("lobby"):
		_automated = true
		_auto_clients = LaunchArgs.get_int("lobby", 1) if NetworkManager.is_host() else -1
		if NetworkManager.is_online():
			state = State.LOBBY if NetworkManager.is_host() else State.CONNECTING
			NetworkManager.send_profile(my_profile(RunSetup.character_id()))


func is_active() -> bool:
	return state != State.OFFLINE


## Opens a room on the relay ("Stammtisch aufmachen").
func open_room() -> void:
	error = ""
	NetworkManager.local_profile = my_profile(_wanted_character())
	if NetworkManager.host_relay() != OK:
		_on_failed("lost")
		return
	_set_state(State.CONNECTING)


## Joins a friend's room by its code.
func join_room(code: String) -> void:
	error = ""
	NetworkManager.local_profile = my_profile(_wanted_character())
	var result: Error = NetworkManager.join_relay(code)
	if result == ERR_INVALID_PARAMETER:
		_on_failed("no_room")
		return
	if result != OK:
		_on_failed("lost")
		return
	_set_state(State.CONNECTING)


func leave() -> void:
	RunSetup.from_room = false
	NetworkManager.leave()
	setup = {}
	_set_state(State.OFFLINE)


## Our Knödlinger in the room.
func choose_character(id: StringName) -> void:
	if taken_by_other(id) or not Profile.is_unlocked(&"character", id):
		return
	NetworkManager.send_profile(my_profile(String(id)))


## Host: the room's map and Grant level.
func choose_map(map: StringName, grant: int) -> void:
	if not NetworkManager.is_host():
		return
	var profile: Dictionary = NetworkManager.local_profile.duplicate(true)
	profile["map"] = String(map)
	profile["grant"] = grant
	NetworkManager.send_profile(profile)


## Our profile as the room should know it (name, character, Stammtisch bonus, unlocked characters).
func my_profile(character: String) -> Dictionary:
	var unlocked: Array = []
	for data: CharacterData in content.characters:
		if _automated or Profile.is_unlocked(&"character", data.id):
			unlocked.append(String(data.id))
	var meta: Dictionary = {} if _automated else Profile.meta_bonus()
	var player_name: String = LaunchArgs.get_string("name", Settings.player_name())
	var profile: Dictionary = LobbyProfile.make(player_name, character, meta, unlocked)
	# The host keeps its map and Grant choice.
	for key: String in ["map", "grant"]:
		if NetworkManager.local_profile.has(key):
			profile[key] = NetworkManager.local_profile[key]
	return profile


## The room's map and Grant level (the host's choice).
func room_map() -> StringName:
	return StringName(str(NetworkManager.profiles.get(NetworkManager.HOST_ID, {}).get("map", RunSetup.map_id())))


func room_grant() -> int:
	return int(NetworkManager.profiles.get(NetworkManager.HOST_ID, {}).get("grant", RunSetup.grant_index()))


func taken_by_other(id: StringName) -> bool:
	for peer: int in NetworkManager.profiles:
		if peer != NetworkManager.local_id() and str(NetworkManager.profiles[peer].get("character", "")) == String(id):
			return true
	return false


## Host: everyone has a different Knödlinger and there are at least two of us.
func can_start() -> bool:
	if state != State.LOBBY or not NetworkManager.is_host():
		return false
	var players: Dictionary[int, Dictionary] = NetworkManager.profiles
	if players.size() < (1 if _automated else MIN_PLAYERS):
		return false
	var seen: Dictionary = {}
	for peer: int in players:
		var character: String = str(players[peer].get("character", ""))
		if character == "" or seen.has(character) or content.character(StringName(character)) == null:
			return false
		seen[character] = true
	return true


## Host: off to the Kirtag, everyone.
func start() -> void:
	if not can_start():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	NetworkManager.start_run({
		"map": String(room_map()),
		"grant": room_grant(),
		"seed": rng.randi_range(1, 99999),
		"roster": NetworkManager.profiles.duplicate(true),
	})


## Host, after a run: everyone back to the room.
func back_to_room() -> void:
	if NetworkManager.is_host() and NetworkManager.is_online():
		NetworkManager.back_to_lobby()


func _wanted_character() -> String:
	var last: Dictionary = Profile.last_choice()
	return str(last.get("character", RunSetup.character))


func _set_state(new_state: State) -> void:
	state = new_state
	changed.emit()


func _on_room_opened(_code: String) -> void:
	if NetworkManager.is_host():
		# The host starts with its last map and Grant level.
		var last: Dictionary = Profile.last_choice()
		var profile: Dictionary = NetworkManager.local_profile.duplicate(true)
		profile["map"] = str(last.get("map", RunSetup.map))
		profile["grant"] = clampi(int(last.get("grant", RunSetup.grant)), 0, Profile.grant_unlocked())
		NetworkManager.send_profile(profile)
		_set_state(State.LOBBY)


func _on_joined_host() -> void:
	if state == State.CONNECTING:
		_set_state(State.LOBBY)


## Host: whoever picked a character second gets the first free one they have unlocked.
func _on_roster_changed() -> void:
	if NetworkManager.is_host() and state == State.LOBBY:
		var used: Dictionary = {}
		var order: Array[int] = [NetworkManager.HOST_ID]
		order.append_array(NetworkManager.room_ids())
		for peer: int in order:
			var profile: Dictionary = NetworkManager.profiles.get(peer, {})
			if profile.is_empty():
				continue
			var character: String = str(profile.get("character", ""))
			if character == "" or used.has(character) or content.character(StringName(character)) == null:
				var free: String = ""
				for id: Variant in profile.get("unlocked", []):
					if not used.has(str(id)) and content.character(StringName(str(id))) != null:
						free = str(id)
						break
				if free != character:
					var fixed: Dictionary = profile.duplicate(true)
					fixed["character"] = free
					NetworkManager.set_profile(peer, fixed)
					# set_profile announced the change and called us again.
					return
				character = free
			if character != "":
				used[character] = true
		if _auto_clients >= 0 and NetworkManager.room_ids().size() >= _auto_clients and can_start():
			start.call_deferred()
	changed.emit()


func _on_run_start(new_setup: Dictionary) -> void:
	setup = new_setup
	RunSetup.map = str(setup.get("map", RunSetup.map))
	RunSetup.grant = int(setup.get("grant", RunSetup.grant))
	RunSetup.seed = int(setup.get("seed", -1))
	var mine: Dictionary = NetworkManager.profiles.get(NetworkManager.local_id(), NetworkManager.local_profile)
	RunSetup.character = str(mine.get("character", RunSetup.character))
	RunSetup.from_menu = not _automated
	RunSetup.from_room = true
	print("[LOBBY] run starts: map=%s grant=%d seed=%d players=%d" % [RunSetup.map, RunSetup.grant, RunSetup.seed,
			NetworkManager.profiles.size()])
	_set_state(State.RUN)
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(RUN_SCENE)


func _on_lobby_return() -> void:
	_set_state(State.LOBBY)
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _on_failed(reason: String) -> void:
	if state == State.OFFLINE:
		return
	# Headless tests: refused in the room (the run scene would report it once loaded).
	if _automated and state != State.RUN:
		print("[RESULT] " + JSON.stringify({"role": "client", "rejected": reason}))
		get_tree().quit(0)
	error = reason
	setup = {}
	RunSetup.from_room = false
	_set_state(State.OFFLINE)
	failed.emit(reason)
