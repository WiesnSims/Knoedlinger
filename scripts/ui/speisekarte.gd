class_name Speisekarte
extends CanvasLayer
## The level-up menu (GAME-DESIGN.md: the Ober presents the Speisekarte, "Was darf's sein?"):
## the cards of the host's offer (UpgradeCard: icon, name, rarity, level pips; the details show on
## hover), plus Nochmal bitte (reroll), Des mog i ned (banish: press it, then the card) and Danke,
## passt eh (skip). Keys: 1-4 pick, arrows + Enter, R reroll, B banish, N skip. The answer goes back
## to the host as a Choice; the host applies it and sends the next offer.
## Also shows what a Wirtshaus chest gave (icons, no choice, it fades by itself). Runs while the
## game is paused (solo). With the bot playing it picks by itself.

## The answer for the host (OfferCodec.Choice bytes).
signal answered(data: PackedByteArray)

const CHEST_SECONDS: float = 3.5
## The bot reads the menu this long before it picks (`?pick_delay=3` for screenshots).
const BOT_DELAY: float = 0.35
## Stats shown as flat numbers; the rest are percentages.
const FLAT_STATS: Array[StringName] = [&"max_hp", &"regen", &"armor", &"extra_jumps", &"knodl_guard"]

var catalog: UpgradeCatalog
var balance: BalanceData
## Picks by itself (the bot plays).
var auto_pick: bool = false

var _offer: OfferCodec.Offer
var _banish_mode: bool = false
var _menu: Control
var _title: Label
var _subtitle: Label
var _cards_box: HBoxContainer
var _cards: Array[UpgradeCard] = []
var _reroll: Button
var _banish: Button
var _skip: Button
var _timer_bar: ProgressBar
var _chest_panel: PanelContainer
var _chest_title: Label
var _chest_items: HBoxContainer
var _chest_timer: float = 0.0
var _seconds_left: float = 0.0
var _bot_timer: float = 0.0
var _opened_ms: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 99
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_menu)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.03, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(shade)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	centred(_menu).add_child(column)
	_title = UiStyle.label(36, UiStyle.TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	_title.add_theme_constant_override("outline_size", 6)
	column.add_child(_title)
	_subtitle = UiStyle.label(15, UiStyle.GOLD)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.text = tr("MENU_SUBTITLE")
	column.add_child(_subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 10.0)
	column.add_child(gap)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 18)
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_cards_box)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0.0, 12.0)
	column.add_child(gap2)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_reroll = UiStyle.pill(buttons)
	_reroll.pressed.connect(_answer.bind(OfferCodec.Action.REROLL, 0))
	_banish = UiStyle.pill(buttons)
	_banish.toggle_mode = true
	_banish.toggled.connect(_on_banish_toggled)
	_skip = UiStyle.pill(buttons)
	_skip.pressed.connect(_answer.bind(OfferCodec.Action.SKIP, 0))
	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0.0, 6.0)
	_timer_bar.add_theme_stylebox_override("background", UiStyle.box(Color(1.0, 1.0, 1.0, 0.1), 3, 0))
	_timer_bar.add_theme_stylebox_override("fill", UiStyle.box(UiStyle.GOLD, 3, 0))
	column.add_child(_timer_bar)
	_menu.visible = false
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 64.0
	top.offset_bottom = 64.0
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_chest_panel = PanelContainer.new()
	_chest_panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 16, 16, UiStyle.GOLD.darkened(0.3), 2, 10))
	_chest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_chest_panel)
	var chest_column := VBoxContainer.new()
	chest_column.add_theme_constant_override("separation", 10)
	_chest_panel.add_child(chest_column)
	_chest_title = UiStyle.label(20, UiStyle.GOLD)
	_chest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chest_column.add_child(_chest_title)
	_chest_items = HBoxContainer.new()
	_chest_items.alignment = BoxContainer.ALIGNMENT_CENTER
	_chest_items.add_theme_constant_override("separation", 14)
	chest_column.add_child(_chest_items)
	_chest_panel.visible = false


func is_open() -> bool:
	return _menu.visible


## Seconds since the open offer was shown.
func open_seconds() -> float:
	return (Time.get_ticks_msec() - _opened_ms) / 1000.0


## A new offer from the host for the local player.
func show_offer(offer: OfferCodec.Offer, _build: PlayerBuild) -> void:
	_offer = offer
	GameAudio.play(&"menu_open")
	_banish_mode = false
	_banish.set_pressed_no_signal(false)
	_title.text = tr("MENU_TITLE") if offer.pending <= 1 else tr("MENU_TITLE_MORE") % offer.pending
	for card_view: UpgradeCard in _cards:
		card_view.queue_free()
	_cards.clear()
	for k: int in offer.cards.size():
		var card: Card = offer.cards[k]
		var view := UpgradeCard.new()
		_cards_box.add_child(view)
		var owned: int = card.level - 1 if card.kind == Card.Kind.WEAPON or card.kind == Card.Kind.PASSIVE else 0
		view.setup(card, k + 1, card_details(card, catalog, balance), owned, catalog)
		view.pressed.connect(_on_card.bind(k))
		_cards.append(view)
	_reroll.text = tr("MENU_REROLL") % offer.rerolls
	_reroll.disabled = offer.rerolls <= 0
	_banish.text = tr("MENU_BANISH") % offer.banishes
	_banish.disabled = offer.banishes <= 0
	_skip.text = tr("MENU_SKIP") % balance.skip_gold
	_seconds_left = offer.seconds
	_timer_bar.visible = offer.seconds > 0
	_timer_bar.max_value = maxf(offer.seconds, 1.0)
	_timer_bar.value = offer.seconds
	_bot_timer = LaunchArgs.get_float("pick_delay", BOT_DELAY)
	_opened_ms = Time.get_ticks_msec()
	_menu.visible = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## What a Wirtshaus cash-in gave (tier, gold, cards), as icon tiles.
func show_chest(offer: OfferCodec.Offer) -> void:
	_chest_title.text = tr("CHEST_TITLE") % tr("TIER_%d" % offer.tier) if offer.tier < 4 else tr("CHEST_TITLE_%d" % offer.tier)
	GameAudio.play(&"cash_in" if offer.tier < 4 else &"chest")
	if offer.tier < 4:
		GameAudio.play(&"mahlzeit")
	for child: Node in _chest_items.get_children():
		child.queue_free()
	if offer.value > 0:
		_chest_items.add_child(_chest_tile(load(UiStyle.ICON_GOLD), tr("CHEST_GOLD") % offer.value, "", UiStyle.GOLD))
	for card: Card in offer.cards:
		_chest_items.add_child(_chest_tile(UiStyle.card_icon(card, catalog), card_name(card, catalog),
				level_text(card), UiStyle.rarity_color(card.rarity)))
	_chest_panel.visible = true
	_chest_panel.modulate.a = 1.0
	_chest_timer = CHEST_SECONDS


## The host took the offer away (co-op time ran out and it picked).
func close() -> void:
	_menu.visible = false
	_offer = null


## What a card does, shown while it is hovered: the item's one-liner and what this level adds.
static func card_details(card: Card, p_catalog: UpgradeCatalog, p_balance: BalanceData) -> String:
	var lines: PackedStringArray = []
	match card.kind:
		Card.Kind.WEAPON, Card.Kind.EVOLUTION:
			var weapon: WeaponData = p_catalog.weapons[card.index]
			lines.append(TranslationServer.translate(weapon.desc_key))
			if card.kind == Card.Kind.WEAPON and card.level > 1:
				lines.append(TranslationServer.translate("CARD_WEAPON_LEVEL"))
		Card.Kind.PASSIVE:
			var passive: PassiveData = p_catalog.passives[card.index]
			lines.append(TranslationServer.translate(passive.desc_key))
			var bonus: float = p_balance.rarity_bonus[clampi(card.rarity, 0, p_balance.rarity_bonus.size() - 1)]
			for key: StringName in passive.stats:
				var times: float = 1.0 if PlayerBuild.COUNT_STATS.has(key) else bonus
				lines.append(stat_text(key, passive.stats[key] * times))
		Card.Kind.GOLD:
			lines.append(TranslationServer.translate("CARD_GOLD_DESC") % p_balance.fallback_gold)
		Card.Kind.HEAL:
			lines.append(TranslationServer.translate("CARD_HEAL_DESC") % roundi(p_balance.fallback_heal))
	return "\n\n".join(lines)


static func card_name(card: Card, p_catalog: UpgradeCatalog) -> String:
	match card.kind:
		Card.Kind.WEAPON, Card.Kind.EVOLUTION:
			return TranslationServer.translate(p_catalog.weapons[card.index].name_key)
		Card.Kind.PASSIVE:
			return TranslationServer.translate(p_catalog.passives[card.index].name_key)
		Card.Kind.GOLD:
			return TranslationServer.translate("CARD_GOLD")
	return TranslationServer.translate("CARD_HEAL")


static func level_text(card: Card) -> String:
	match card.kind:
		Card.Kind.EVOLUTION:
			return TranslationServer.translate("CARD_EVOLUTION")
		Card.Kind.WEAPON, Card.Kind.PASSIVE:
			return TranslationServer.translate("CARD_NEW") if card.level <= 1 \
					else TranslationServer.translate("CARD_LEVEL") % card.level
	return ""


## "+10 % Fläche", "+1 Rüstung".
static func stat_text(key: StringName, value: float) -> String:
	var label: String = TranslationServer.translate("STAT_" + String(key).to_upper())
	if FLAT_STATS.has(key):
		var number: String = "%d" % roundi(value) if is_equal_approx(value, roundf(value)) else "%.1f" % value
		return "+%s %s" % [number, label]
	return "+%d %% %s" % [roundi(value * 100.0), label]


## A full-screen container under `root` that keeps what is put in it centred, whatever its size.
static func centred(root: Control) -> CenterContainer:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)
	return centre


func _process(delta: float) -> void:
	if _chest_timer > 0.0:
		_chest_timer -= delta
		_chest_panel.modulate.a = clampf(_chest_timer / 0.5, 0.0, 1.0)
		if _chest_timer <= 0.0:
			_chest_panel.visible = false
	if not is_open():
		return
	if _offer.seconds > 0:
		_seconds_left = maxf(_seconds_left - delta, 0.0)
		_timer_bar.value = _seconds_left
	if auto_pick:
		_bot_timer -= delta
		if _bot_timer <= 0.0:
			_answer(OfferCodec.Action.PICK, _bot_choice())


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			var k: int = key.physical_keycode - KEY_1
			if k < _offer.cards.size():
				_on_card(k)
		KEY_R:
			if _offer.rerolls > 0:
				_answer(OfferCodec.Action.REROLL, 0)
		KEY_B:
			if _offer.banishes > 0:
				_banish.button_pressed = not _banish.button_pressed
		KEY_N:
			_answer(OfferCodec.Action.SKIP, 0)
		KEY_LEFT, KEY_RIGHT:
			# Arrow keys walk the cards; the focused one shows its details, Enter takes it.
			if not _cards.is_empty() and get_viewport().gui_get_focus_owner() == null:
				_cards[0 if key.physical_keycode == KEY_RIGHT else _cards.size() - 1].grab_focus()
			else:
				return
		_:
			return
	get_viewport().set_input_as_handled()


## The bot's taste: an evolution first, then its own weapons, then anything new, at random within
## the same appetite.
func _bot_choice() -> int:
	var best: int = 0
	var best_score: float = -1.0
	for k: int in _offer.cards.size():
		var card: Card = _offer.cards[k]
		var score: float = _rng.randf()
		match card.kind:
			Card.Kind.EVOLUTION:
				score += 10.0
			Card.Kind.WEAPON:
				score += 3.0 if card.level > 1 else 2.0
			Card.Kind.PASSIVE:
				score += 1.5
		if score > best_score:
			best_score = score
			best = k
	return best


func _on_card(k: int) -> void:
	if _banish_mode:
		var card: Card = _offer.cards[k]
		if card.kind == Card.Kind.WEAPON or card.kind == Card.Kind.PASSIVE:
			_answer(OfferCodec.Action.BANISH, k)
		return
	_answer(OfferCodec.Action.PICK, k)


func _on_banish_toggled(on: bool) -> void:
	_banish_mode = on
	_title.text = tr("MENU_BANISH_HINT") if on else tr("MENU_TITLE")
	# Cards that can be banished stay bright; gold and heal fade out.
	for k: int in _cards.size():
		var card: Card = _offer.cards[k]
		var banishable: bool = card.kind == Card.Kind.WEAPON or card.kind == Card.Kind.PASSIVE
		_cards[k].modulate = Color(1.0, 0.92, 0.85) if on and banishable else (Color(1.0, 1.0, 1.0, 0.35) if on else Color.WHITE)


func _answer(action: OfferCodec.Action, card: int) -> void:
	if _offer == null:
		return
	GameAudio.play(&"card")
	if action == OfferCodec.Action.SKIP:
		GameAudio.bark(&"wurscht")
	var choice := OfferCodec.Choice.new()
	choice.seq = _offer.seq
	choice.action = action
	choice.card = card
	_menu.visible = false
	_offer = null
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	answered.emit(OfferCodec.encode_choice(choice))


func _chest_tile(icon: Texture2D, title: String, subtitle: String, accent: Color) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_theme_constant_override("separation", 2)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UiStyle.box(Color(1.0, 1.0, 1.0, 0.05), 12, 6, accent, 2))
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_child(UiStyle.icon_rect(icon, 56.0))
	tile.add_child(frame)
	var name_label: Label = UiStyle.label(14, UiStyle.TEXT)
	name_label.text = title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.add_child(name_label)
	if subtitle != "":
		var sub: Label = UiStyle.label(12, accent)
		sub.text = subtitle
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(sub)
	return tile
