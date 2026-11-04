class_name LaunchArgs
extends RefCounted
## Options for a run, from the command line (`godot ... -- --enemies=500 --host`) on desktop or from
## the page URL (`index.html?enemies=500&bot=1`) in the browser. A flag without a value reads as "1".

static var _values: Dictionary[String, String] = {}
static var _parsed: bool = false


static func get_string(key: String, default: String = "") -> String:
	_parse()
	return _values.get(key, default)


static func get_int(key: String, default: int = 0) -> int:
	var value: String = get_string(key)
	return value.to_int() if value.is_valid_int() else default


static func get_float(key: String, default: float = 0.0) -> float:
	var value: String = get_string(key)
	return value.to_float() if value.is_valid_float() else default


static func get_flag(key: String, default: bool = false) -> bool:
	var value: String = get_string(key)
	if value.is_empty():
		return default
	return value != "0" and value != "false"


static func has(key: String) -> bool:
	_parse()
	return _values.has(key)


## Every option given (command line or URL).
static func keys() -> Array[String]:
	_parse()
	var out: Array[String] = []
	out.assign(_values.keys())
	return out


## For tests: replaces the parsed values.
static func override(values: Dictionary[String, String]) -> void:
	_values = values
	_parsed = true


static func _parse() -> void:
	if _parsed:
		return
	_parsed = true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			_add(arg.substr(2))
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String:
			for pair: String in (search as String).trim_prefix("?").split("&", false):
				_add(pair.uri_decode())


static func _add(pair: String) -> void:
	var at: int = pair.find("=")
	if at < 0:
		_values[pair] = "1"
	else:
		_values[pair.substr(0, at)] = pair.substr(at + 1)
