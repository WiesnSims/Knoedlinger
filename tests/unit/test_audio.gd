extends GutTest
## The audio buses come from default_bus_layout.tres: on the web, buses added at runtime never reach
## the browser's audio graph, so everything played on them was silent (docs/DECISIONS.md, audio fix).


func test_buses_come_from_the_layout_file() -> void:
	var layout: AudioBusLayout = load("res://default_bus_layout.tres")
	assert_not_null(layout)
	for bus: StringName in Settings.BUSES.values():
		var index: int = AudioServer.get_bus_index(bus)
		assert_gt(index, -1, "bus %s exists" % bus)
		if index > 0:
			assert_eq(AudioServer.get_bus_send(index), &"Master", "bus %s sends to Master" % bus)


func test_players_use_the_layout_buses() -> void:
	for player: Node in GameAudio.get_children():
		assert_gt(AudioServer.get_bus_index((player as AudioStreamPlayer).bus), 0, player.name)
