class_name RunEndScreen
extends CanvasLayer
## The end of a run: Sperrstund' reached (a win, GAME-DESIGN.md: "run ends as victory"), with the
## local player's numbers. In solo "Nochmal!" starts a new run; online the host decides (M6).
## The death screen and the 25 % Schilling payout come with M3/M4.

signal again_pressed

var _panel: PanelContainer
var _text: Label
var _again: Button


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Speisekarte.panel_box(Color(0.3, 0.2, 0.12, 0.95), 14, 24))
	Speisekarte.centred(root).add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_panel.add_child(column)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 22)
	_text.add_theme_color_override("font_color", Speisekarte.PAPER)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_text)
	_again = Button.new()
	_again.add_theme_font_size_override("font_size", 22)
	_again.text = tr("END_AGAIN")
	_again.pressed.connect(func() -> void: again_pressed.emit())
	column.add_child(_again)
	visible = false


## `summary` is RunWorld's run summary of the local player.
func show_result(summary: Dictionary, can_restart: bool) -> void:
	var lines: PackedStringArray = [tr("END_TITLE"), ""]
	lines.append(tr("END_LEVEL") % int(summary.get("level", 1)))
	lines.append(tr("END_KILLS") % int(summary.get("kills", 0)))
	lines.append(tr("END_GOLD") % int(summary.get("gold", 0)))
	lines.append(tr("END_KNODL") % roundi(float(summary.get("best_knodl_mass", 0.0))))
	lines.append(tr("END_CASH_INS") % int(summary.get("cash_in_total", 0)))
	lines.append(tr("END_DOWNED") % int(summary.get("deaths", 0)))
	_text.text = "\n".join(lines)
	_again.visible = can_restart
	visible = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
