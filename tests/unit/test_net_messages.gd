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


func test_offer_round_trip() -> void:
	var offer := OfferCodec.Offer.new()
	offer.type = OfferCodec.Type.CHEST
	offer.seq = 4097
	offer.rerolls = 2
	offer.banishes = 3
	offer.pending = 4
	offer.seconds = 8
	offer.tier = 3
	offer.value = 512
	offer.cards = [Card.new(Card.Kind.WEAPON, 3, Card.Rarity.NOBLE, 5, 2, 0.15), Card.new(Card.Kind.HEAL, 0, 0, 1),
			Card.new(Card.Kind.ITEM, 7, Card.Rarity.HOFRAT, 2)]
	offer.rarity = 2
	var back: OfferCodec.Offer = OfferCodec.decode_offer(OfferCodec.encode_offer(offer))
	assert_not_null(back)
	assert_eq(back.type, OfferCodec.Type.CHEST)
	assert_eq(back.seq, 4097)
	assert_eq(back.rerolls, 2)
	assert_eq(back.banishes, 3)
	assert_eq(back.pending, 4)
	assert_eq(back.seconds, 8)
	assert_eq(back.tier, 3)
	assert_eq(back.value, 512)
	assert_eq(back.cards.size(), 3)
	assert_eq(back.rarity, 2)
	assert_eq(back.cards[0].mod, 2)
	assert_almost_eq(back.cards[0].value, 0.15, 0.001)
	assert_eq(back.cards[2].kind, Card.Kind.ITEM)
	assert_eq(back.cards[2].level, 2)
	assert_eq(back.cards[0].kind, Card.Kind.WEAPON)
	assert_eq(back.cards[0].index, 3)
	assert_eq(back.cards[0].rarity, Card.Rarity.NOBLE)
	assert_eq(back.cards[0].level, 5)
	assert_eq(back.cards[1].kind, Card.Kind.HEAL)


func test_choice_round_trip_and_garbage() -> void:
	var choice := OfferCodec.Choice.new()
	choice.seq = 65535
	choice.action = OfferCodec.Action.BANISH
	choice.card = 2
	var back: OfferCodec.Choice = OfferCodec.decode_choice(OfferCodec.encode_choice(choice))
	assert_eq(back.seq, 65535)
	assert_eq(back.action, OfferCodec.Action.BANISH)
	assert_eq(back.card, 2)
	assert_null(OfferCodec.decode_choice(PackedByteArray([1, 0, 0, 9, 0])), "unknown action")
	assert_null(OfferCodec.decode_offer(PackedByteArray([1, 0, 0])))
	var bad := OfferCodec.encode_offer(OfferCodec.Offer.new())
	bad[1] = 7
	assert_null(OfferCodec.decode_offer(bad), "unknown type")
