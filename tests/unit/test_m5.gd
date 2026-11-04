extends GutTest
## M5: gamepad, the input device glyphs and the new settings.

const PAD_ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right", &"jump",
		&"schupfn", &"pause", &"inventory", &"card_reroll", &"card_banish", &"card_skip", &"look_left",
		&"look_right", &"look_up", &"look_down"]


func before_each() -> void:
	InputSetup.ensure_actions()


func after_each() -> void:
	InputDevice.kind = InputDevice.Kind.KEYS


func test_every_gameplay_action_has_a_pad_binding() -> void:
	for action: StringName in PAD_ACTIONS:
		var found: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			found = found or event is InputEventJoypadButton or event is InputEventJoypadMotion
		assert_true(found, String(action))


func test_keyboard_bindings_stay_as_they_were() -> void:
	var keys: Array[Key] = []
	for event: InputEvent in InputMap.action_get_events(&"jump"):
		if event is InputEventKey:
			keys.append((event as InputEventKey).physical_keycode)
	assert_eq(keys, [KEY_SPACE] as Array[Key])
	assert_true(InputMap.action_has_event(&"inventory", _key(KEY_TAB)))


func test_the_last_device_picks_the_glyph() -> void:
	InputDevice._input(_pad_button(JOY_BUTTON_A))
	assert_true(InputDevice.is_pad())
	assert_eq(InputDevice.glyph(&"jump", "Leertaste"), "A")
	assert_eq(InputDevice.glyph(&"", "1"), "", "number keys have no pad glyph")
	InputDevice._input(_key(KEY_W))
	assert_eq(InputDevice.glyph(&"jump", "Leertaste"), "Leertaste")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	InputDevice._input(touch)
	assert_true(InputDevice.is_touch())
	assert_eq(InputDevice.glyph(&"jump", "Leertaste"), "", "touch shows its own buttons")


func test_a_resting_stick_does_not_switch_to_the_pad() -> void:
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.1
	InputDevice._input(drift)
	assert_false(InputDevice.is_pad())


func test_keycap_follows_the_device() -> void:
	var cap := KeycapLabel.new(&"schupfn", "Shift")
	add_child_autofree(cap)
	assert_eq(cap.text, "Shift")
	InputDevice._input(_pad_button(JOY_BUTTON_B))
	assert_eq(cap.text, "RB")
	var pip := KeycapLabel.new(&"", "2")
	add_child_autofree(pip)
	assert_false(pip.visible, "pad hides the number keycaps")


func test_choice_settings_only_take_known_values() -> void:
	var before: String = str(Settings.get_value(&"quality"))
	Settings.set_value(&"quality", "ultra")
	assert_eq(Settings.get_value(&"quality"), Settings.DEFAULTS[&"quality"])
	Settings.set_value(&"quality", "low")
	assert_eq(Settings.get_value(&"quality"), "low")
	Settings.set_value(&"quality", before)


func test_ui_choice_steps_and_wraps() -> void:
	var choice := UiChoice.new()
	add_child_autofree(choice)
	choice.names = PackedStringArray(["a", "b", "c"])
	watch_signals(choice)
	choice.step(-1)
	assert_eq(choice.index, 2)
	assert_signal_emitted_with_parameters(choice, "chosen", [2])
	choice.step(1)
	assert_eq(choice.index, 0)


func test_every_setting_has_a_row() -> void:
	var listed: Array[StringName] = []
	for tab: Array in SettingsPanel.TABS:
		for column: Array in [tab[1], tab[2]]:
			for group: Array in column:
				for row: Array in group[1]:
					listed.append(row[0])
	for key: StringName in Settings.DEFAULTS:
		assert_has(listed, key, String(key))
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	assert_eq(panel._pages.size(), SettingsPanel.TABS.size())


func test_auto_quality_steps_down_after_three_slow_seconds() -> void:
	var balance: BalanceData = load("res://data/balance.tres")
	var scaler := QualityScaler.new()
	add_child_autofree(scaler)
	scaler.setup(balance, null)
	scaler.auto = true
	assert_eq(scaler.level, QualityScaler.Level.HIGH, "automated runs start on Hoch")
	_frames(scaler, balance.quality_warmup_seconds + 0.5, 10.0)
	assert_eq(scaler.level, QualityScaler.Level.HIGH, "the warm-up is not measured")
	_frames(scaler, balance.quality_drop_seconds - 1.0, 10.0)
	assert_eq(scaler.level, QualityScaler.Level.HIGH)
	_frames(scaler, 1.2, 10.0)
	assert_eq(scaler.level, QualityScaler.Level.MEDIUM, "one step after 3 s below the target")
	_frames(scaler, balance.quality_raise_seconds + 2.0, 200.0)
	assert_eq(scaler.level, QualityScaler.Level.MEDIUM, "no step up during the cooldown")
	_frames(scaler, balance.quality_raise_cooldown, 200.0)
	assert_eq(scaler.level, QualityScaler.Level.HIGH)
	assert_eq(get_viewport().scaling_3d_scale, balance.quality_render_scale[0])


func test_low_quality_thins_only_a_solo_crowd() -> void:
	var balance: BalanceData = load("res://data/balance.tres")
	var scaler := QualityScaler.new()
	add_child_autofree(scaler)
	scaler.setup(balance, null)
	assert_eq(scaler.enemy_factor(true), 1.0)
	scaler.set_level(QualityScaler.Level.LOW)
	assert_lt(scaler.enemy_factor(true), 1.0)
	assert_eq(scaler.enemy_factor(false), 1.0, "co-op keeps the host's crowd for everyone")
	scaler.set_level(QualityScaler.Level.HIGH)


func test_touch_stick_and_buttons_feed_the_actions() -> void:
	Settings.set_value(&"touch_controls", "on")
	var touch := TouchControls.new()
	add_child_autofree(touch)
	assert_true(touch.is_active())
	var view: Vector2 = touch._view.get_viewport_rect().size
	# Left thumb lands, then drags right: the player walks right.
	touch._input(_touch(0, Vector2(200.0, view.y - 150.0), true))
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(200.0 + TouchControls.STICK_RADIUS, view.y - 150.0)
	touch._input(drag)
	assert_almost_eq(Input.get_action_strength(&"move_right"), 1.0, 0.01)
	# Right thumb on Hupfn.
	var jump: Vector2 = touch._view.buttons()[TouchControls.Kind.JUMP][0]
	touch._input(_touch(1, jump, true))
	assert_true(Input.is_action_pressed(&"jump"))
	touch._input(_touch(1, jump, false))
	assert_false(Input.is_action_pressed(&"jump"))
	touch._input(_touch(0, Vector2.ZERO, false))
	assert_eq(Input.get_action_strength(&"move_right"), 0.0, "lifting the thumb stops the player")
	# A full-screen panel hides the controls and lets go of everything.
	touch._input(_touch(0, Vector2(200.0, view.y - 150.0), true))
	touch._input(drag)
	touch.covered = func() -> bool: return true
	touch._process(0.016)
	assert_false(touch.is_active())
	assert_eq(Input.get_action_strength(&"move_right"), 0.0)
	Settings.set_value(&"touch_controls", "auto")


func test_touch_controls_follow_the_setting() -> void:
	var touch := TouchControls.new()
	add_child_autofree(touch)
	assert_false(touch.is_active(), "Automatisch waits for a touch")
	InputDevice.kind = InputDevice.Kind.TOUCH
	InputDevice.changed.emit(InputDevice.kind)
	assert_true(touch.is_active())
	Settings.set_value(&"touch_controls", "off")
	assert_false(touch.is_active())
	Settings.set_value(&"touch_controls", "auto")


func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	return event


## Feeds `seconds` of frames at `fps` to the scaler.
func _frames(scaler: QualityScaler, seconds: float, fps: float) -> void:
	for k: int in ceili(seconds * fps):
		scaler._process(1.0 / fps)


func _pad_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event
