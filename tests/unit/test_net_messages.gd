extends GutTest


func test_input_message_round_trip() -> void:
	var message := InputMessage.new()
	message.tick = 77
	message.move = Vector2(0.5, -1.0)
	message.buttons = InputMessage.BUTTON_JUMP
	message.position = Vector3(12.5, 0.1, -40.25)
	message.yaw = 1.2
	var back: InputMessage = InputMessage.from_bytes(message.to_bytes())
	assert_not_null(back)
	assert_eq(back.tick, 77)
	assert_almost_eq(back.move.x, 0.5, 0.01)
	assert_almost_eq(back.move.y, -1.0, 0.01)
	assert_eq(back.buttons, InputMessage.BUTTON_JUMP)
	assert_almost_eq(back.position.x, 12.5, 0.001)
	assert_almost_eq(back.position.z, -40.25, 0.001)
	assert_almost_eq(back.yaw, 1.2, 0.001)


func test_input_message_rejects_wrong_size() -> void:
	assert_null(InputMessage.from_bytes(PackedByteArray([1, 2, 3])))


func test_room_codes_are_four_unambiguous_letters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bad: int = 0
	for i: int in 200:
		var code: String = RoomCode.generate(rng)
		if not RoomCode.is_valid(code) or code.contains("I") or code.contains("O"):
			bad += 1
	assert_eq(bad, 0)
	assert_true(RoomCode.is_valid(RoomCode.normalize(" kndl ")))
	assert_false(RoomCode.is_valid("KND"))
	assert_false(RoomCode.is_valid("KN0L"))


func test_handshake_carries_game_and_version() -> void:
	var values: Dictionary[String, String] = Handshake.parse_query(Handshake.query("0.0.1", "abc-1"))
	assert_eq(values["game"], "knoedlinger")
	assert_eq(values["ver"], "0.0.1")
	assert_eq(values["build"], "abc-1")


func test_handshake_rejects_mismatches() -> void:
	assert_eq(Handshake.check("knoedlinger", "0.0.1", "b", "0.0.1", "b"), Handshake.OK_REASON)
	assert_eq(Handshake.check("berghittn", "0.0.1", "b", "0.0.1", "b"), Handshake.REASON_GAME)
	assert_eq(Handshake.check("knoedlinger", "0.0.2", "b", "0.0.1", "b"), Handshake.REASON_VERSION)
	assert_eq(Handshake.check("knoedlinger", "0.0.1", "c", "0.0.1", "b"), Handshake.REASON_BUILD)
