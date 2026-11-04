class_name OfferCodec
extends RefCounted
## Speisekarte messages (reliable). The host sends a player an OFFER (the cards to choose from), a
## CHEST (cards a Wirtshaus cash-in just gave them) or a NOTICE (e.g. "this Knödl is too small for
## the Wirt"); the player answers an offer with a Choice. Solo goes through the same messages.
##
## Offer: u8 version | u8 type | u16 seq | u8 rerolls | u8 banishes | u8 pending levels |
##        u8 seconds to choose (0 = no limit) | u8 tier | u16 value | u8 cards | u8 chest rarity,
##        per card u8 kind | u8 index | u8 rarity | u8 level | u8 weapon mod | u16 mod value * 1000
## Choice: u8 version | u16 seq | u8 action | u8 card

const VERSION: int = 2
const OFFER_HEADER: int = 13
const CARD_SIZE: int = 7
const CHOICE_SIZE: int = 5

enum Type { OFFER, CHEST, NOTICE }
enum Action { PICK, REROLL, BANISH, SKIP }
enum Notice { TOO_SMALL, WIRT_SERVED, NO_GOLD, KONTROLLE }


class Offer:
	extends RefCounted
	var type: Type = Type.OFFER
	var seq: int = 0
	var rerolls: int = 0
	var banishes: int = 0
	var pending: int = 0
	var seconds: int = 0
	## CHEST: the Wirtshaus tier (0 = S .. 3 = XL).
	var tier: int = 0
	## CHEST: gold given; NOTICE: which Notice.
	var value: int = 0
	## CHEST: the rarity it rolled.
	var rarity: int = 0
	var cards: Array[Card] = []


class Choice:
	extends RefCounted
	var seq: int = 0
	var action: Action = Action.PICK
	var card: int = 0


static func encode_offer(offer: Offer) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(OFFER_HEADER + offer.cards.size() * CARD_SIZE)
	data.encode_u8(0, VERSION)
	data.encode_u8(1, offer.type)
	data.encode_u16(2, offer.seq & 0xFFFF)
	data.encode_u8(4, clampi(offer.rerolls, 0, 255))
	data.encode_u8(5, clampi(offer.banishes, 0, 255))
	data.encode_u8(6, clampi(offer.pending, 0, 255))
	data.encode_u8(7, clampi(offer.seconds, 0, 255))
	data.encode_u8(8, clampi(offer.tier, 0, 255))
	data.encode_u16(9, clampi(offer.value, 0, 0xFFFF))
	data.encode_u8(11, offer.cards.size())
	data.encode_u8(12, clampi(offer.rarity, 0, 255))
	var o: int = OFFER_HEADER
	for card: Card in offer.cards:
		data.encode_u8(o, card.kind)
		data.encode_u8(o + 1, card.index)
		data.encode_u8(o + 2, card.rarity)
		data.encode_u8(o + 3, clampi(card.level, 0, 255))
		data.encode_u8(o + 4, clampi(card.mod, 0, 255))
		data.encode_u16(o + 5, clampi(roundi(card.value * 1000.0), 0, 0xFFFF))
		o += CARD_SIZE
	return data


## Returns null for anything that is not a valid offer.
static func decode_offer(data: PackedByteArray) -> Offer:
	if data.size() < OFFER_HEADER or data.decode_u8(0) != VERSION:
		return null
	var count: int = data.decode_u8(11)
	var type: int = data.decode_u8(1)
	if data.size() != OFFER_HEADER + count * CARD_SIZE or type > Type.NOTICE:
		return null
	var offer := Offer.new()
	offer.type = type as Type
	offer.seq = data.decode_u16(2)
	offer.rerolls = data.decode_u8(4)
	offer.banishes = data.decode_u8(5)
	offer.pending = data.decode_u8(6)
	offer.seconds = data.decode_u8(7)
	offer.tier = data.decode_u8(8)
	offer.value = data.decode_u16(9)
	offer.rarity = data.decode_u8(12)
	var o: int = OFFER_HEADER
	for k: int in count:
		var kind: int = data.decode_u8(o)
		if kind > Card.Kind.ITEM:
			return null
		offer.cards.append(Card.new(kind as Card.Kind, data.decode_u8(o + 1), data.decode_u8(o + 2), data.decode_u8(o + 3),
				data.decode_u8(o + 4), data.decode_u16(o + 5) / 1000.0))
		o += CARD_SIZE
	return offer


static func encode_choice(choice: Choice) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(CHOICE_SIZE)
	data.encode_u8(0, VERSION)
	data.encode_u16(1, choice.seq & 0xFFFF)
	data.encode_u8(3, choice.action)
	data.encode_u8(4, clampi(choice.card, 0, 255))
	return data


## Returns null for anything that is not a valid choice.
static func decode_choice(data: PackedByteArray) -> Choice:
	if data.size() != CHOICE_SIZE or data.decode_u8(0) != VERSION or data.decode_u8(3) > Action.SKIP:
		return null
	var choice := Choice.new()
	choice.seq = data.decode_u16(1)
	choice.action = data.decode_u8(3) as Action
	choice.card = data.decode_u8(4)
	return choice
