class_name BuildView
extends HBoxContainer
## The build with what every piece does (1.4, DECISIONS 6.8): the inventory tiles, a detail panel in
## a fixed spot (not a floating tooltip, so the pad's focus and a tap work as well as the mouse) and
## the stats. Used by the Esc pause menu (beside its entries) and the Tab screen.
## Weapons show their numbers on paper (Formulas.weapon_dps, "Theorie") and measured this run
## (DamageLedger, "dieser Lauf"); items their exact effect (ItemText) and procs; stat upgrades what
## every stat they touch is made of.

const DETAIL_WIDTH: float = 280.0

var inventory: InventoryPanel
var stats: StatsPanel
var _detail: PanelContainer
var _name: Label
var _meta: Label
var _lines: VBoxContainer
var _desc: Label

var _state: PlayerState
var _balance: BalanceData
var _ledger: DamageLedger
var _peer: int = 0
var _run_time: float = 0.0
var _section: int = -1
var _index: int = -1
## The detail rows are rebuilt on a new pick, else twice a second (the measured numbers move).
var _next_refresh: int = 0


func _init() -> void:
	theme_type_variation = &"Row16"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory = InventoryPanel.new(true)
	inventory.picked.connect(_on_picked)
	add_child(inventory)
	_detail = UiStyle.panel()
	_detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0.0)
	_detail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)
	var column := UiStyle.vbox(&"Gap16")
	_detail.add_child(column)
	var head := UiStyle.vbox(&"Tight")
	column.add_child(head)
	_name = UiStyle.label(&"LabelAccent", "")
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_name)
	_meta = UiStyle.label(&"LabelMuted", "")
	head.add_child(_meta)
	_lines = UiStyle.vbox(&"Tight")
	column.add_child(_lines)
	_desc = UiStyle.label(&"LabelMuted", "")
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_desc)
	stats = StatsPanel.new()
	add_child(stats)
	_show_hint()


## Every frame while open (co-op runs on): the tiles, the stats and the picked tile's numbers.
func show_player(state: PlayerState, knodl: Knodl, balance: BalanceData, ledger: DamageLedger, peer: int,
		run_time: float) -> void:
	if state == null or state.build == null:
		return
	_state = state
	_balance = balance
	_ledger = ledger
	_peer = peer
	_run_time = run_time
	inventory.show_build(state.build, balance)
	stats.show_stats(state, knodl, balance)
	if Time.get_ticks_msec() >= _next_refresh:
		_refresh()


func focus_first() -> void:
	inventory.focus_first()


func _on_picked(section: InventoryPanel.Section, index: int) -> void:
	_section = section
	_index = index
	_refresh()


func _refresh() -> void:
	if _state == null:
		return
	_next_refresh = Time.get_ticks_msec() + 500
	var build: PlayerBuild = _state.build
	for child: Node in _lines.get_children():
		child.queue_free()
	match _section:
		InventoryPanel.Section.WEAPON:
			if _index < build.weapons.size():
				_show_weapon(build.weapons[_index], build)
				return
		InventoryPanel.Section.PASSIVE:
			if _index < build.passives.size():
				_show_passive(build.passives[_index], build)
				return
		InventoryPanel.Section.ITEM:
			if _index < build.items.size():
				_show_item(build.items[_index], build)
				return
	_show_hint()


func _show_hint() -> void:
	_name.text = tr("BV_TITLE")
	_meta.text = ""
	_desc.text = tr("BV_HINT")


func _show_weapon(owned: PlayerBuild.OwnedWeapon, build: PlayerBuild) -> void:
	var weapon: WeaponData = owned.data
	_name.text = tr(weapon.name_key)
	_meta.text = (tr("CARD_EVOLUTION") + " · " if weapon.is_evolution else "") + tr("CARD_LEVEL") % owned.level
	var paper: Dictionary = Formulas.weapon_dps(owned, build, _balance)
	_row("BV_DAMAGE_HIT", ItemText.num(snappedf(paper["damage"], 0.1)))
	_row("BV_ORBIT_RATE" if paper["per_enemy"] else "BV_RATE", ItemText.num(snappedf(paper["rate"], 0.01)))
	_row("BV_AMOUNT", str(paper["amount"]))
	_row("BV_CRIT", tr("BV_CRIT_VALUE") % [ItemText.num(roundf(paper["crit"] * 100.0)), ItemText.num(paper["crit_mult"])])
	if paper["burn"] > 0.0:
		_row("BV_BURN", ItemText.num(roundf(paper["burn"])))
	_row("BV_THEORY_ENEMY" if paper["per_enemy"] else "BV_THEORY", ItemText.num(roundf(paper["dps"])), true)
	var index: int = build.catalog.weapons.find(weapon)
	_row("BV_RUN", ItemText.num(roundf(_ledger.total(_peer, DamageLedger.Kind.WEAPON, index))), true)
	_row("BV_RECENT", ItemText.num(roundf(_ledger.recent_dps(_peer, DamageLedger.Kind.WEAPON, index, _run_time))), true)
	_desc.text = tr(weapon.desc_key)


func _show_passive(owned: PlayerBuild.OwnedPassive, build: PlayerBuild) -> void:
	_name.text = tr(owned.data.name_key)
	_meta.text = tr("CARD_LEVEL") % owned.level
	for key: StringName in owned.data.stats:
		# The stat now, then where it comes from.
		_row("STAT_" + String(key).to_upper(), StatsPanel.value_text(key, build.stat(key), _balance), true)
		var parts: Dictionary = _stat_parts(key, build)
		for part: String in parts:
			if absf(parts[part]) > 0.0001:
				_row(part, Speisekarte.stat_text(key, parts[part]).split(" ")[0] + (" %" if not Speisekarte.FLAT_STATS.has(key) else ""))
	_desc.text = tr(owned.data.desc_key)


func _show_item(owned: PlayerBuild.OwnedItem, build: PlayerBuild) -> void:
	var item: ItemData = owned.data
	_name.text = tr(item.name_key)
	_meta.text = tr("RARITY_%d" % item.rarity) + (" · ×%d" % owned.count if owned.count > 1 else "")
	for line: String in ItemText.describe(item, owned.count, _balance):
		var label: Label = UiStyle.label(&"LabelSmall", line)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = DETAIL_WIDTH - 32.0
		_lines.add_child(label)
	var lantern: float = ItemProcs.total(build, ItemEffect.Action.PROC_CHANCE)
	for effect: ItemEffect in item.effects:
		if effect.chance < 0.999 and lantern > 0.0:
			_row("BV_CHANCE_LANTERN", ItemText.num(roundf(ItemProcs.stacked_chance(effect.chance, owned.count, lantern) * 1000.0) / 10.0) + " %")
	var index: int = build.catalog.items.find(item)
	var procs: int = _ledger.procs(_peer, DamageLedger.Kind.ITEM, index)
	var dealt: float = _ledger.total(_peer, DamageLedger.Kind.ITEM, index)
	if procs > 0:
		_row("BV_PROCS", str(procs), true)
	if dealt > 0.0:
		_row("BV_RUN", ItemText.num(roundf(dealt)), true)
	_desc.text = tr(item.desc_key)


## A stat's parts: from stat upgrades, items and the Stammtisch.
func _stat_parts(key: StringName, build: PlayerBuild) -> Dictionary:
	var from_passives: float = 0.0
	for owned: PlayerBuild.OwnedPassive in build.passives:
		var times: float = float(owned.level) if PlayerBuild.COUNT_STATS.has(key) else owned.bonus
		from_passives += owned.data.stats.get(key, 0.0) * times
	var from_items: float = 0.0
	for owned: PlayerBuild.OwnedItem in build.items:
		from_items += owned.data.stats.get(key, 0.0) * owned.count
	return {"BV_FROM_PASSIVES": from_passives, "BV_FROM_ITEMS": from_items, "BV_FROM_META": build.meta.get(key, 0.0)}


## Name left, value right (accent for the headline numbers).
func _row(key: String, value: String, accent: bool = false) -> void:
	var row := UiStyle.hbox()
	_lines.add_child(row)
	var name: Label = UiStyle.label(&"LabelMuted", tr(key))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name)
	var number: Label = UiStyle.label(&"LabelChange" if accent else &"LabelSmall", value)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(number)
