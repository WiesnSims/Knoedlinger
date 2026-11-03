class_name LevelUpFlow
extends RefCounted
## Host: runs every player's Speisekarte (GAME-DESIGN.md, "XP and levelling"). A player with
## level-ups waiting gets an offer; their choice (pick, reroll, banish, skip) comes back as a
## message, is checked and applied, and the next offer follows until none are left. Queued
## level-ups open one after another. In co-op the game runs on, so an offer has a time limit after
## which a random card is taken for the player. Chests from a Wirtshaus go out the same way.

var balance: BalanceData
var rng := RandomNumberGenerator.new()
## Picks, rerolls, banishes and skips taken, for the balance log.
var picks: int = 0

var _seq: int = 0
## peer -> the cards on their open offer.
var _cards: Dictionary[int, Array] = {}
var _seqs: Dictionary[int, int] = {}
var _timers: Dictionary[int, float] = {}


func _init(p_balance: BalanceData, seed_value: int = 1) -> void:
	balance = p_balance
	rng.seed = seed_value


## Opens offers for players with level-ups waiting; in co-op it also picks for players who ran out
## of time. `states` are all players' states.
func update(states: Dictionary[int, PlayerState], delta: float, coop: bool) -> void:
	for peer: int in states:
		var state: PlayerState = states[peer]
		if _cards.has(peer):
			if coop:
				_timers[peer] -= delta
				if _timers[peer] <= 0.0:
					_take(peer, state, rng.randi_range(0, _cards[peer].size() - 1), coop)
			continue
		if state.pending_levels > 0 and not state.downed:
			_deal(peer, state, coop)


## The player's answer to their offer (OfferCodec.Choice bytes).
func on_choice(peer: int, data: PackedByteArray, state: PlayerState, coop: bool) -> void:
	var choice: OfferCodec.Choice = OfferCodec.decode_choice(data)
	if choice == null or state == null or not _cards.has(peer) or choice.seq != _seqs[peer]:
		return
	var build: PlayerBuild = state.build
	var cards: Array = _cards[peer]
	match choice.action:
		OfferCodec.Action.PICK:
			if choice.card < cards.size():
				_take(peer, state, choice.card, coop)
		OfferCodec.Action.REROLL:
			if build.rerolls > 0:
				build.rerolls -= 1
				_deal(peer, state, coop)
		OfferCodec.Action.BANISH:
			if build.banishes > 0 and choice.card < cards.size():
				var card: Card = cards[choice.card]
				if card.kind == Card.Kind.WEAPON or card.kind == Card.Kind.PASSIVE:
					build.banishes -= 1
					build.banished[card.item_key()] = true
					_deal(peer, state, coop)
		OfferCodec.Action.SKIP:
			build.add_gold(balance.skip_gold)
			_finish_one(peer, state, coop)


## Host: a Wirtshaus chest for this player: its cards are taken right away and shown to them.
func give_chest(peer: int, state: PlayerState, tier: int, items: int, evolution_first: bool, gold: int) -> void:
	var offer := OfferCodec.Offer.new()
	offer.type = OfferCodec.Type.CHEST
	offer.tier = tier
	offer.value = gold
	state.build.add_gold(gold)
	if items > 0:
		offer.cards = CardDealer.open_chest(state.build, balance, rng, items, evolution_first)
		state.refresh_max_hp(balance.player_max_hp)
	NetworkManager.send_offer(peer, OfferCodec.encode_offer(offer))


func notify(peer: int, notice: OfferCodec.Notice) -> void:
	var offer := OfferCodec.Offer.new()
	offer.type = OfferCodec.Type.NOTICE
	offer.value = notice
	NetworkManager.send_offer(peer, OfferCodec.encode_offer(offer))


## A player left: forget their offer.
func forget(peer: int) -> void:
	_cards.erase(peer)
	_seqs.erase(peer)
	_timers.erase(peer)


func is_open(peer: int) -> bool:
	return _cards.has(peer)


func _deal(peer: int, state: PlayerState, coop: bool) -> void:
	var count: int = balance.card_count
	var cards: Array[Card] = CardDealer.deal(state.build, balance, rng, count)
	_seq = (_seq + 1) & 0xFFFF
	_cards[peer] = cards
	_seqs[peer] = _seq
	_timers[peer] = balance.card_seconds_coop
	state.choosing = true
	var offer := OfferCodec.Offer.new()
	offer.type = OfferCodec.Type.OFFER
	offer.seq = _seq
	offer.rerolls = state.build.rerolls
	offer.banishes = state.build.banishes
	offer.pending = state.pending_levels
	offer.seconds = ceili(balance.card_seconds_coop) if coop else 0
	offer.cards = cards
	NetworkManager.send_offer(peer, OfferCodec.encode_offer(offer))


func _take(peer: int, state: PlayerState, pick: int, coop: bool) -> void:
	var card: Card = _cards[peer][pick]
	if not CardDealer.is_valid(card, state.build, balance):
		# Stale (a chest got there first): deal again, the level-up is not used up.
		_deal(peer, state, coop)
		return
	state.heal(state.build.apply(card, balance))
	state.refresh_max_hp(balance.player_max_hp)
	picks += 1
	_finish_one(peer, state, coop)


func _finish_one(peer: int, state: PlayerState, coop: bool) -> void:
	state.pending_levels = maxi(state.pending_levels - 1, 0)
	forget(peer)
	state.choosing = false
	if state.pending_levels > 0 and not state.downed:
		_deal(peer, state, coop)
