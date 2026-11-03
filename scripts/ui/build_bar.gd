class_name BuildBar
extends Control
## The build in the HUD: a row of weapon slots and a row of passive slots (Knödl upgrades after
## them), each the item's icon with its level; a maxed item gets a gold frame, empty slots are faint
## outlines so you see what is still free. Drawn in one pass (all frames, then all icons, then all
## numbers) so the canvas batches stay few; redrawn only when the build changes.

const SLOT: float = 44.0
const GAP: float = 6.0
const ICON_INSET: float = 5.0

class Slot:
	extends RefCounted
	var icon: Texture2D
	var level: int = 0
	var maxed: bool = false
	var accent: Color = UiStyle.LINE


var _rows: Array[Array] = [[], []]
var _signature: String = ""
var _empty_box: StyleBoxFlat
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_box = UiStyle.box(Color(0.08, 0.06, 0.05, 0.62), 10, 0, Color(UiStyle.LINE, 0.45), 1)
	_font = get_theme_default_font()


func show_build(build: PlayerBuild, balance: BalanceData) -> void:
	var signature: String = ""
	for owned: PlayerBuild.OwnedWeapon in build.weapons:
		signature += "%d.%d," % [owned.index, owned.level]
	signature += "|"
	for owned: PlayerBuild.OwnedPassive in build.passives:
		signature += "%d.%d," % [owned.index, owned.level]
	if signature == _signature:
		return
	_signature = signature
	var weapons: Array[Slot] = []
	for k: int in maxi(balance.weapon_slots, build.weapons.size()):
		var slot := Slot.new()
		if k < build.weapons.size():
			var owned: PlayerBuild.OwnedWeapon = build.weapons[k]
			slot.icon = owned.data.icon
			slot.level = owned.level
			slot.maxed = owned.level >= owned.data.max_level
			slot.accent = UiStyle.GOLD if owned.data.is_evolution else UiStyle.LINE
		weapons.append(slot)
	var passives: Array[Slot] = []
	var extras: Array[Slot] = []
	for owned: PlayerBuild.OwnedPassive in build.passives:
		var slot := Slot.new()
		slot.icon = owned.data.icon
		if owned.data.kind == PassiveData.Kind.PASSIVE:
			slot.level = owned.level
			slot.maxed = owned.level >= owned.data.max_level
			passives.append(slot)
		else:
			slot.accent = UiStyle.GOLD.darkened(0.2)
			extras.append(slot)
	while passives.size() < balance.passive_slots:
		passives.append(Slot.new())
	passives.append_array(extras)
	_rows = [weapons, passives]
	var widest: int = maxi(weapons.size(), passives.size())
	custom_minimum_size = Vector2(widest * (SLOT + GAP), 2.0 * SLOT + GAP)
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	# Frames first, then icons, then numbers: few texture switches, few draw calls.
	for row: int in _rows.size():
		for k: int in _rows[row].size():
			var slot: Slot = _rows[row][k]
			var rect := _slot_rect(row, k)
			if slot.icon == null:
				draw_style_box(_empty_box, rect)
			else:
				var border: Color = UiStyle.GOLD if slot.maxed else slot.accent
				draw_style_box(UiStyle.box(Color(0.08, 0.06, 0.05, 0.75), 10, 0, border, 2), rect)
	for row: int in _rows.size():
		for k: int in _rows[row].size():
			var slot: Slot = _rows[row][k]
			if slot.icon != null:
				draw_texture_rect(UiStyle.atlas_icon(slot.icon), _slot_rect(row, k).grow(-ICON_INSET), false)
	for row: int in _rows.size():
		for k: int in _rows[row].size():
			var slot: Slot = _rows[row][k]
			if slot.icon == null or slot.level <= 0:
				continue
			var rect := _slot_rect(row, k)
			var at := Vector2(rect.end.x - 14.0, rect.end.y - 3.0)
			var color: Color = UiStyle.GOLD if slot.maxed else UiStyle.TEXT
			draw_string_outline(_font, at, str(slot.level), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, 5, Color(0.05, 0.03, 0.02))
			draw_string(_font, at, str(slot.level), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, color)


func _slot_rect(row: int, k: int) -> Rect2:
	return Rect2(Vector2(k * (SLOT + GAP), row * (SLOT + GAP)), Vector2(SLOT, SLOT))
