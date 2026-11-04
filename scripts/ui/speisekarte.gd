class_name Speisekarte
extends CanvasLayer
## The level-up menu (GAME-DESIGN.md: the Ober presents the Speisekarte, "Was darf's sein?"), laid
## out like docs/UI-STYLE.md asks: the build (InventoryPanel) left, the menu card in the middle, the
## stats (StatsPanel) right. The menu card lists the host's offer as rows (UpgradeCard: icon, name,
## one change line, pips, rarity border); the hovered row's one-liner and numbers show in the footer
## and its stat changes in the stats panel. Below: Nochmal bitte (reroll), Des mog i ned (banish:
## press it, then the row) and Danke, passt eh (skip). Keys: 1-4 pick, arrows + Enter, R, B, N.
## The answer goes back to the host as a Choice; the host applies it and sends the next offer.
## Also shows what a Wirtshaus chest gave (icon tiles, no choice, it fades by itself). Runs while
## the game is paused (solo). With the bot playing it picks by itself.

## The answer for the host (OfferCodec.Choice bytes).
signal answered(data: PackedByteArray)

const CHEST_SECONDS: float = 3.5
const MENU_WIDTH: float = 560.0
const FOOTER_HEIGHT: float = 64.0
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
var _menu: Control
var _stage: HBoxContainer
var _inventory: InventoryPanel
var _stats: StatsPanel
var _title: Label
var _pending: Label
var _cards_box: VBoxContainer
var _cards: Array[UpgradeCard] = []
var _details: Label
var _details_meta: Label
var _reroll: ActionPill
var _banish: ActionPill
var _skip: ActionPill
var _timer_bar: ProgressBar
var _chest_panel: PanelContainer
var _chest_title: Label
var _chest_items: HBoxContainer
var _chest_timer: float = 0.0
var _seconds_left: float = 0.0
var _bot_timer: float = 0.0
var _opened_ms: int = 0
var _menu_tween: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 99
	var root: Control = UiStyle.root(self)
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_menu)
	var shade := ColorRect.new()
	shade.color = Color(UiStyle.color("panel"), 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(shade)
	_stage = UiStyle.hbox(&"Row32")
	UiStyle.centred(_menu).add_child(_stage)
	_inventory = InventoryPanel.new()
	_stage.add_child(_inventory)
	var card_panel: PanelContainer = UiStyle.panel()
	card_panel.custom_minimum_size = Vector2(MENU_WIDTH, 0.0)
	card_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_stage.add_child(card_panel)
	_stats = StatsPanel.new()
	_stage.add_child(_stats)
	var column := UiStyle.vbox(&"Gap16")
	card_panel.add_child(column)
	var header := UiStyle.hbox()
	column.add_child(header)
	var titles := UiStyle.vbox(&"Tight")
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	_title = UiStyle.label(&"LabelTitle")
	titles.add_child(_title)
	titles.add_child(UiStyle.label(&"LabelMuted", tr("MENU_SUBTITLE")))
	_pending = UiStyle.label(&"LabelAccent")
	_pending.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_pending)
	_cards_box = UiStyle.vbox()
	column.add_child(_cards_box)
	var footer: PanelContainer = UiStyle.panel(&"PanelRaised")
	footer.custom_minimum_size = Vector2(0.0, FOOTER_HEIGHT)
	column.add_child(footer)
	var footer_text := UiStyle.vbox(&"Tight")
	footer_text.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_child(footer_text)
	_details = UiStyle.label(&"LabelSmall")
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_text.add_child(_details)
	_details_meta = UiStyle.label(&"LabelMuted")
	_details_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_text.add_child(_details_meta)
	var buttons := UiStyle.hbox()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	_reroll = ActionPill.new("R")
	buttons.add_child(_reroll)
	_reroll.pressed.connect(_answer.bind(OfferCodec.Action.REROLL, 0))
	_banish = ActionPill.new("B")
	_banish.toggle_mode = true
	buttons.add_child(_banish)
	_banish.toggled.connect(_on_banish_toggled)
	_skip = ActionPill.new("N")
	buttons.add_child(_skip)
	_skip.pressed.connect(_answer.bind(OfferCodec.Action.SKIP, 0))
	_timer_bar = UiStyle.bar(&"BarTimer")
	_timer_bar.custom_minimum_size = Vector2(0.0, 4.0)
	column.add_child(_timer_bar)
	_menu.visible = false
	# The chest reveal, top centre.
	var top := UiStyle.hbox()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 96.0
	top.offset_bottom = 96.0
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(top)
	_chest_panel = UiStyle.panel()
	_chest_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_chest_panel)
	var chest_column := UiStyle.vbox(&"Gap16")
	_chest_panel.add_child(chest_column)
	_chest_title = UiStyle.label(&"LabelTitle")
	_chest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chest_column.add_child(_chest_title)
	_chest_items = UiStyle.hbox(&"Row16")
	_chest_items.alignment = BoxContainer.ALIGNMENT_CENTER
	chest_column.add_child(_chest_items)
	_chest_panel.visible = false


func is_open() -> bool:
	return _menu.visible and _offer != null


## Open, or still fading out after the answer (the HUD stays hidden until the menu is gone, so the
## two are never drawn on top of each other: that frame cost about 190 draw calls).
func is_shown() -> bool:
	return _menu.visible


## Seconds since the open offer was shown.
func open_seconds() -> float:
	return (Time.get_ticks_msec() - _opened_ms) / 1000.0


## The build and stats panels beside the menu (RunWorld calls it every frame while it is open).
func show_player(state: PlayerState, knodl: Knodl) -> void:
	if state == null or state.build == null:
		return
	_inventory.show_build(state.build, balance)
	_stats.show_stats(state, knodl, balance)


## A new offer from the host for the local player.
func show_offer(offer: OfferCodec.Offer, build: PlayerBuild) -> void:
	var was_open: bool = is_open()
	_offer = offer
	_build = build
	GameAudio.play(&"menu_open")
	_banish_mode = false
	_banish.set_pressed_no_signal(false)
	_title.text = tr("MENU_TITLE")
	_pending.text = tr("MENU_PENDING") % (offer.pending - 1) if offer.pending > 1 else ""
	for card_view: UpgradeCard in _cards:
		card_view.queue_free()
	_cards.clear()
	for k: int in offer.cards.size():
		var card: Card = offer.cards[k]
		var view := UpgradeCard.new()
		_cards_box.add_child(view)
		var owned: int = card.level - 1 if card.kind == Card.Kind.WEAPON or card.kind == Card.Kind.PASSIVE else 0
		view.setup(card, k + 1, change_text(card, catalog, balance, build), owned, catalog)
		view.pressed.connect(_on_card.bind(k))
		view.hovered.connect(_on_card_hovered.bind(k))
		view.reveal(UiStyle.T_STAGGER * (k + 1))
		_cards.append(view)
	_show_details(-1)
	_reroll.set_label(tr("MENU_REROLL"), str(offer.rerolls))
	_reroll.disabled = offer.rerolls <= 0
	_banish.set_label(tr("MENU_BANISH"), str(offer.banishes))
	_banish.disabled = offer.banishes <= 0
	_skip.set_label(tr("MENU_SKIP"), "+%d" % balance.skip_gold)
	_seconds_left = offer.seconds
	_timer_bar.visible = offer.seconds > 0
	_timer_bar.max_value = maxf(offer.seconds, 1.0)
	_timer_bar.value = offer.seconds
	_bot_timer = LaunchArgs.get_float("pick_delay", BOT_DELAY)
	_opened_ms = Time.get_ticks_msec()
	if _menu_tween != null:
		_menu_tween.kill()
	_menu.visible = true
	if not was_open:
		_menu.modulate.a = 0.0
		_menu_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_menu_tween.tween_property(_menu, "modulate:a", 1.0, UiStyle.T_PANEL_IN)
	else:
		_menu.modulate.a = 1.0
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
		_chest_items.add_child(_chest_tile(load(UiStyle.ICON_GOLD), tr("CHEST_GOLD") % offer.value, "", &"TileEvolution"))
	for card: Card in offer.cards:
		_chest_items.add_child(_chest_tile(UiStyle.card_icon(card, catalog), card_name(card, catalog),
				level_text(card), UiStyle.rarity_variation("Tile", card)))
	_chest_panel.visible = true
	_chest_panel.modulate.a = 1.0
	_chest_timer = CHEST_SECONDS


## The host took the offer away (co-op time ran out and it picked).
func close() -> void:
	_menu.visible = false
	_offer = null


## The one line under a card's name: what it changes ("+18 % Schaden", "Neu!", "+25 Gold").
static func change_text(card: Card, p_catalog: UpgradeCatalog, p_balance: BalanceData, build: PlayerBuild) -> String:
	var bonus: float = p_balance.rarity_bonus[clampi(card.rarity, 0, p_balance.rarity_bonus.size() - 1)]
	match card.kind:
		Card.Kind.EVOLUTION:
			return TranslationServer.translate("CARD_EVOLUTION")
		Card.Kind.WEAPON:
			if card.level <= 1:
				return TranslationServer.translate("CARD_NEW")
			var weapon: WeaponData = p_catalog.weapons[card.index]
			var owned: PlayerBuild.OwnedWeapon = build.owned_weapon(card.index) if build != null else null
			var old_bonus: float = owned.bonus if owned != null else float(card.level - 1)
			var before: float = Formulas.weapon_damage(weapon, card.level - 1, old_bonus, 0.0, p_balance)
			var after: float = Formulas.weapon_damage(weapon, card.level, old_bonus + bonus, 0.0, p_balance)
			var parts: PackedStringArray = [stat_text(&"damage", after / maxf(before, 0.001) - 1.0)]
			if Formulas.weapon_amount(weapon, card.level) > Formulas.weapon_amount(weapon, card.level - 1):
				parts.append(TranslationServer.translate("CARD_MORE_PIECES"))
			return " · ".join(parts)
		Card.Kind.PASSIVE:
			if card.level <= 1:
				return TranslationServer.translate("CARD_NEW")
			var passive: PassiveData = p_catalog.passives[card.index]
			for key: StringName in passive.stats:
				var times: float = 1.0 if PlayerBuild.COUNT_STATS.has(key) else bonus
				return stat_text(key, passive.stats[key] * times)
		Card.Kind.GOLD:
			return TranslationServer.translate("CHEST_GOLD") % p_balance.fallback_gold
		Card.Kind.HEAL:
			return "+%d HP" % roundi(p_balance.fallback_heal)
	return ""


## The hovered card's footer: the item's one-liner, then rarity, level and every number it adds.
static func card_details(card: Card, p_catalog: UpgradeCatalog, p_balance: BalanceData) -> PackedStringArray:
	var line: String = ""
	var meta: PackedStringArray = []
	if card.kind != Card.Kind.GOLD and card.kind != Card.Kind.HEAL:
		meta.append(TranslationServer.translate("RARITY_%d" % card.rarity))
		var max_level: int = UiStyle.card_max_level(card, p_catalog)
		if max_level > 0:
			meta.append(TranslationServer.translate("CARD_LEVEL_OF") % [card.level, max_level])
	match card.kind:
		Card.Kind.WEAPON, Card.Kind.EVOLUTION:
			var weapon: WeaponData = p_catalog.weapons[card.index]
			line = TranslationServer.translate(weapon.desc_key)
			if card.kind == Card.Kind.WEAPON and card.level > 1:
				meta.append(TranslationServer.translate("CARD_WEAPON_LEVEL"))
		Card.Kind.PASSIVE:
			var passive: PassiveData = p_catalog.passives[card.index]
			line = TranslationServer.translate(passive.desc_key)
			for key: StringName in card_stats(card, p_catalog, p_balance):
				meta.append(stat_text(key, card_stats(card, p_catalog, p_balance)[key]))
		Card.Kind.GOLD:
			line = TranslationServer.translate("CARD_GOLD_DESC") % p_balance.fallback_gold
		Card.Kind.HEAL:
			line = TranslationServer.translate("CARD_HEAL_DESC") % roundi(p_balance.fallback_heal)
	return PackedStringArray([line, " · ".join(meta)])


## What a passive card adds per stat (for the footer and the stats preview).
static func card_stats(card: Card, p_catalog: UpgradeCatalog, p_balance: BalanceData) -> Dictionary:
	var changes: Dictionary = {}
	if card.kind != Card.Kind.PASSIVE:
		return changes
	var passive: PassiveData = p_catalog.passives[card.index]
	var bonus: float = p_balance.rarity_bonus[clampi(card.rarity, 0, p_balance.rarity_bonus.size() - 1)]
	for key: StringName in passive.stats:
		var times: float = 1.0 if PlayerBuild.COUNT_STATS.has(key) else bonus
		changes[key] = passive.stats[key] * times
	return changes


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
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			# Arrow keys walk the rows; the focused one shows its details, Enter takes it.
			if not _cards.is_empty() and get_viewport().gui_get_focus_owner() == null:
				var forward: bool = key.physical_keycode == KEY_DOWN or key.physical_keycode == KEY_RIGHT
				_cards[0 if forward else _cards.size() - 1].grab_focus()
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


func _on_card_hovered(on: bool, k: int) -> void:
	_show_details(k if on else -1)


## The footer and the stats preview for row k (-1: the plain hint).
func _show_details(k: int) -> void:
	if _offer == null or k < 0 or k >= _offer.cards.size():
		_details.text = tr("MENU_HINT")
		_details_meta.text = ""
		_stats.preview({}, balance)
		return
	var card: Card = _offer.cards[k]
	var lines: PackedStringArray = card_details(card, catalog, balance)
	_details.text = lines[0]
	_details_meta.text = lines[1]
	_stats.preview(card_stats(card, catalog, balance), balance)


func _on_banish_toggled(on: bool) -> void:
	_banish_mode = on
	_title.text = tr("MENU_BANISH_HINT") if on else tr("MENU_TITLE")
	# Rows that can be banished stay bright; gold and heal fade out.
	for k: int in _cards.size():
		var card: Card = _offer.cards[k]
		var banishable: bool = card.kind == Card.Kind.WEAPON or card.kind == Card.Kind.PASSIVE
		_cards[k].modulate = Color.WHITE if not on or banishable else Color(1.0, 1.0, 1.0, 0.35)


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
	_offer = null
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	# The picked row flashes, then the menu fades; a next offer (more level-ups) cuts the fade short.
	if action == OfferCodec.Action.PICK and card < _cards.size():
		_cards[card].modulate = Color(1.6, 1.5, 1.2)
	if _menu_tween != null:
		_menu_tween.kill()
	_menu_tween = create_tween()
	_menu_tween.tween_property(_menu, "modulate:a", 0.0, UiStyle.T_PANEL_OUT)
	_menu_tween.tween_callback(func() -> void:
		if _offer == null:
			_menu.visible = false)
	answered.emit(OfferCodec.encode_choice(choice))


func _chest_tile(icon: Texture2D, title: String, subtitle: String, variation: StringName) -> VBoxContainer:
	var tile := UiStyle.vbox()
	var frame: PanelContainer = UiStyle.panel(variation)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_child(UiStyle.icon_rect(icon, 56.0))
	tile.add_child(frame)
	var name_label: Label = UiStyle.label(&"LabelSmall", title)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.add_child(name_label)
	if subtitle != "":
		var sub: Label = UiStyle.label(&"LabelChange", subtitle)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(sub)
	return tile
