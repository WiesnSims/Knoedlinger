class_name Speisekarte
extends CanvasLayer
## The level-up menu (GAME-DESIGN.md: the Ober presents the Speisekarte, "Was darf's sein?"):
## the cards of the host's offer, plus Nochmal bitte (reroll), Des mog i ned (banish: click it,
## then the card) and Danke, passt eh (skip). Keys: 1-4 pick, R reroll, B banish, N skip. The
## answer goes back to the host as a Choice; the host applies it and sends the next offer.
## Also shows what a Wirtshaus chest gave (no choice, it fades by itself). Runs while the game is
## paused (solo). With the bot playing it picks by itself.

## The answer for the host (OfferCodec.Choice bytes).
signal answered(data: PackedByteArray)

const RARITY_COLORS: Array[Color] = [
	Color(0.93, 0.9, 0.82), Color(0.62, 0.8, 0.95), Color(0.78, 0.68, 0.95), Color(1.0, 0.82, 0.35),
]
const PAPER := Color(0.98, 0.95, 0.86)
const INK := Color(0.22, 0.14, 0.08)
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
var _build: PlayerBuild
var _banish_mode: bool = false
var _panel: PanelContainer
var _title: Label
var _cards_box: HBoxContainer
var _card_buttons: Array[Button] = []
var _reroll: Button
var _banish: Button
var _skip: Button
var _timer_label: Label
var _chest_panel: PanelContainer
var _chest_label: Label
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
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", panel_box(Color(0.3, 0.2, 0.12, 0.94), 14, 18))
	centred(root).add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)
	_title = _label(30, PAPER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 14)
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_cards_box)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_reroll = _button(buttons)
	_reroll.pressed.connect(_answer.bind(OfferCodec.Action.REROLL, 0))
	_banish = _button(buttons)
	_banish.toggle_mode = true
	_banish.toggled.connect(_on_banish_toggled)
	_skip = _button(buttons)
	_skip.pressed.connect(_answer.bind(OfferCodec.Action.SKIP, 0))
	_timer_label = _label(18, PAPER)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_timer_label)
	_panel.visible = false
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 70.0
	top.offset_bottom = 70.0
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_chest_panel = PanelContainer.new()
	_chest_panel.add_theme_stylebox_override("panel", panel_box(Color(0.3, 0.2, 0.12, 0.9), 12, 14))
	_chest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_chest_panel)
	_chest_label = _label(20, PAPER)
	_chest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chest_panel.add_child(_chest_label)
	_chest_panel.visible = false


func is_open() -> bool:
	return _panel.visible


## Seconds since the open offer was shown.
func open_seconds() -> float:
	return (Time.get_ticks_msec() - _opened_ms) / 1000.0


## A new offer from the host for the local player.
func show_offer(offer: OfferCodec.Offer, build: PlayerBuild) -> void:
	_offer = offer
	_build = build
	_banish_mode = false
	_banish.set_pressed_no_signal(false)
	_title.text = tr("MENU_TITLE") if offer.pending <= 1 else tr("MENU_TITLE_MORE") % offer.pending
	for button: Button in _card_buttons:
		button.queue_free()
	_card_buttons.clear()
	for k: int in offer.cards.size():
		var card: Card = offer.cards[k]
		var button := Button.new()
		button.custom_minimum_size = Vector2(250.0, 250.0)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_font_size_override("font_size", 18)
		button.text = "%d · %s" % [k + 1, card_text(card, catalog, balance)]
		var color: Color = RARITY_COLORS[clampi(card.rarity, 0, RARITY_COLORS.size() - 1)]
		button.add_theme_stylebox_override("normal", panel_box(color, 10, 12))
		button.add_theme_stylebox_override("hover", panel_box(color.lightened(0.25), 10, 12))
		button.add_theme_stylebox_override("pressed", panel_box(color.darkened(0.15), 10, 12))
		button.add_theme_stylebox_override("focus", panel_box(color.lightened(0.15), 10, 12))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, INK)
		button.pressed.connect(_on_card.bind(k))
		_cards_box.add_child(button)
		_card_buttons.append(button)
	_reroll.text = tr("MENU_REROLL") % offer.rerolls
	_reroll.disabled = offer.rerolls <= 0
	_banish.text = tr("MENU_BANISH") % offer.banishes
	_banish.disabled = offer.banishes <= 0
	_skip.text = tr("MENU_SKIP") % balance.skip_gold
	_seconds_left = offer.seconds
	_timer_label.visible = offer.seconds > 0
	_bot_timer = LaunchArgs.get_float("pick_delay", BOT_DELAY)
	_opened_ms = Time.get_ticks_msec()
	_panel.visible = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## What a Wirtshaus cash-in gave (tier, gold, cards).
func show_chest(offer: OfferCodec.Offer) -> void:
	var lines: PackedStringArray = [tr("CHEST_TITLE") % tr("TIER_%d" % offer.tier)]
	if offer.value > 0:
		lines.append(tr("CHEST_GOLD") % offer.value)
	for card: Card in offer.cards:
		lines.append(card_name(card, catalog) + "  " + level_text(card))
	_chest_label.text = "\n".join(lines)
	_chest_panel.visible = true
	_chest_timer = CHEST_SECONDS


## The host took the offer away (co-op time ran out and it picked).
func close() -> void:
	_panel.visible = false
	_offer = null


## The text on a card: rarity, name, new or level, the item's one-liner and what it adds.
static func card_text(card: Card, p_catalog: UpgradeCatalog, p_balance: BalanceData) -> String:
	var lines: PackedStringArray = []
	lines.append(TranslationServer.translate("RARITY_%d" % card.rarity))
	lines.append(card_name(card, p_catalog).to_upper())
	lines.append(level_text(card))
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
	return "\n".join(lines)


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
		_timer_label.text = tr("MENU_SECONDS") % ceili(_seconds_left)
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


func _answer(action: OfferCodec.Action, card: int) -> void:
	if _offer == null:
		return
	var choice := OfferCodec.Choice.new()
	choice.seq = _offer.seq
	choice.action = action
	choice.card = card
	_panel.visible = false
	_offer = null
	answered.emit(OfferCodec.encode_choice(choice))


func _button(parent: Control) -> Button:
	var button := Button.new()
	button.add_theme_font_size_override("font_size", 17)
	button.custom_minimum_size = Vector2(200.0, 40.0)
	parent.add_child(button)
	return button


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A full-screen container under `root` that keeps what is put in it centred, whatever its size.
static func centred(root: Control) -> CenterContainer:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)
	return centre


static func panel_box(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	box.border_color = Color(0.2, 0.12, 0.06, 0.8)
	box.set_border_width_all(2)
	return box
