extends Node
## Game flow: main menu, level lists, options, play, win/lose, undo, and the
## level editor's playtests. Owns the UI and input.

const SAVE_PATH := "user://progress.cfg"

const NAVY := Color("1b2240")
const CREAM := Color("fff6e0")
const AMBER := Color("ffb84d")
const GREEN := Color("6fdc8c")
const TITLE_FONT := preload("res://fonts/CarterOne-Regular.ttf")
const BODY_FONT := preload("res://fonts/Comfortaa-Bold.ttf")
const CREDITS := preload("res://ui/menu_credits.tscn")

## Help panel legend: swatch color, then what the tile does.
const LEGEND := [
	[Color("5dff8f"), "Goal. Get any one quaggle here to win."],
	[Color("a9e4ff"), "Ice. You slide until something stops you."],
	[Color("ff6a2a"), "Fire. Burns the quaggle that steps in, but that puts it out."],
	[Color("ffcc33"), "Key. Pick it up to walk through force fields."],
	[Color("d94fd0"), "Force field. Solid unless you carry the key."],
	[Color("d9b48c"), "Cracked tile. Crumbles after you step off it."],
	[Color("ffffff"), "Lift (rising rings). Carries you up one floor."],
	[Color("8a90b8"), "Walls and glass block you, but you can stand on top of them."],
]
const TIPS := "Walk off an edge and you drop to the floor below. A quaggle will not step out over nothing, but ice can slide it off the edge, and then it is gone.\n" \
	+ "Quaggles can stand on each other's heads, as many as you like: park one in a gap to make a bridge. The one underneath carries the whole stack when it moves, and a lift raises all of them."
const CONTROLS := [
	["WASD / Arrows", "Move"], ["N / Tab", "Switch quaggle"], ["Z", "Undo"], ["R", "Restart level"],
	["Q / E", "Turn camera"], ["C", "Recenter camera"], ["+ / -", "Show or hide upper floors"], ["Mouse drag", "Orbit camera"],
	["Mouse wheel", "Zoom"], ["Esc", "Back to level list"], ["H", "This help"],
]

var world := World.new()
var rules: Rules
var level := ""        # id of the level being played
var level_set := "intro"
var playing := false
var testing := false   # playing the level editor's level rather than a real one
var undo_stack: Array[Dictionary] = []
var done := {}
var volume := 0.8
var fullscreen := false

var _busy := 0.0
var _result_pending := false
var _bumped := false
var _test_level := {}
var _autoplay: Array = []  # solution moves still to show, [quaggle id, dx, dy]

var _screens: Array[Control] = []
var _menu: Control
var _menu_sets: VBoxContainer
var _editor: LevelEditor
var _credits: Control
var _list: Control
var _list_title: Label
var _list_grid: GridContainer
var _options: Control
var _reset_button: Button
var _hud: Control
var _status: Label
var _hint: PanelContainer
var _hint_label: Label
var _result: Control
var _result_title: Label
var _next_button: Button
var _undo_button: Button
var _back_button: Button
var _result_back: Button
var _help: Control


func _ready() -> void:
	add_child(world)
	_load_progress()
	_apply_options()
	_build_ui()
	show_menu()
	for arg in OS.get_cmdline_user_args():
		if arg == "--editor":
			show_editor()
		if arg.begins_with("--shot="):
			_screenshot(arg.trim_prefix("--shot="))


## Shows one full-screen UI state and hides the rest. The menus sit over a
## slowly orbiting level.
func _show(screen: Control) -> void:
	for other in _screens:
		other.visible = other == screen
	_credits.visible = screen == _menu
	world.visible = screen != _editor
	if screen != _hud and (playing or world.rules == null):
		playing = false
		world.demo = true
		world.build(Rules.load_level("level1"))
		world.pitch = 0.7
		world.dist = 17.0


func show_menu() -> void:
	_fill_menu_sets()
	_show(_menu)


func show_editor() -> void:
	_show(_editor)
	_editor.open(level)


func show_list(set_name: String) -> void:
	if Levels.get_set(set_name).is_empty():
		set_name = Levels.sets()[0].id
	level_set = set_name
	var levels: Array = Levels.get_set(set_name).levels
	_list_title.text = Levels.get_set(set_name).title
	for child in _list_grid.get_children():
		child.queue_free()
	for i in levels.size():
		var entry: Dictionary = levels[i]
		var b := _button("%d.  %s" % [i + 1, entry.title], start.bind(entry.id))
		b.custom_minimum_size = Vector2(270, 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if done.has(entry.id):
			b.theme_type_variation = "DoneButton"
		_list_grid.add_child(b)
	_show(_list)


func show_options() -> void:
	_reset_button.text = "Reset progress"
	_show(_options)


func start(level_id: String) -> void:
	var loaded := Rules.load_level(level_id)
	if loaded == null:
		return
	level_set = Levels.set_of(level_id)
	level = level_id
	testing = false
	_autoplay = []
	_begin(loaded, Levels.find(level_id))


## Plays a level straight from the editor. `moves`, if given, are played out
## for the player to watch (a solver's solution).
func playtest(entry: Dictionary, moves: Array = []) -> void:
	var loaded := Rules.from_floors(entry.id, entry.floors)
	if loaded.quaggles.is_empty():
		return
	testing = true
	_test_level = entry
	_autoplay = moves.duplicate()
	_begin(loaded, entry)


func _begin(loaded: Rules, entry: Dictionary) -> void:
	rules = loaded
	undo_stack.clear()
	_busy = 0.0
	_result_pending = false
	_show(_hud)
	playing = true
	world.demo = false
	world.build(rules)
	_result.hide()
	_back_button.text = "Editor" if testing else "Levels"
	_result_back.text = _back_button.text
	var hint: String = entry.get("hint", "")
	_hint_label.text = hint
	_hint.visible = hint != ""
	_update_status()


func undo() -> void:
	if not playing or undo_stack.is_empty():
		return
	rules.restore(undo_stack.pop_back())
	_busy = 0.0
	_result_pending = false
	_result.hide()
	world.build(rules, false)
	_update_status()


func _retry() -> void:
	if testing:
		playtest(_test_level)
	else:
		start(level)


func _back() -> void:
	if testing:
		show_editor()
	else:
		show_list(level_set)


func _index_in(set_name: String, level_id: String) -> int:
	var levels: Array = Levels.get_set(set_name).get("levels", [])
	for i in levels.size():
		if levels[i].id == level_id:
			return i
	return -1


## The level after the current one: the next in its set, then the first of
## the following set. Empty after the very last level.
func _next_id() -> String:
	var levels: Array = Levels.get_set(level_set).levels
	var i := _index_in(level_set, level)
	if i + 1 < levels.size():
		return levels[i + 1].id
	var sets := Levels.sets()
	for following in range(_set_index(level_set) + 1, sets.size()):
		if not sets[following].levels.is_empty():
			return sets[following].levels[0].id
	return ""


func _set_index(set_name: String) -> int:
	var sets := Levels.sets()
	for i in sets.size():
		if sets[i].id == set_name:
			return i
	return -1


func next_level() -> void:
	var next := _next_id()
	if next == "":
		show_list(level_set)
	else:
		start(next)


func _process(delta: float) -> void:
	if not playing or _help.visible:
		return
	_busy -= delta
	if _busy > 0.0:
		return
	if _result_pending:
		_result_pending = false
		_show_result()
	if rules.won or rules.lost:
		return
	if not _autoplay.is_empty():
		_play_next_move()
		return
	var input := Vector2i.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input = Vector2i(0, 1)
	elif Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input = Vector2i(-1, 0)
	elif Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input = Vector2i(0, -1)
	elif Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input = Vector2i(1, 0)
	if input == Vector2i.ZERO:
		_bumped = false
		return
	var dir := world.grid_dir(input)
	var before := rules.snapshot()
	if rules.try_move(dir.x, dir.y):
		undo_stack.append(before)
		_bumped = false
		_busy = world.play(rules.events) + 0.02
		_result_pending = rules.won or rules.lost
		_update_status()
	elif not _bumped:
		_bumped = true
		Sfx.play("bump", 0.1)


## Plays out the next move of a solution being shown.
func _play_next_move() -> void:
	var m: Array = _autoplay.pop_front()
	if rules.quaggles[m[0]].gone:
		_autoplay.clear()
		return
	var before := rules.snapshot()
	rules.active = m[0]
	if not rules.try_move(m[1], m[2]):
		_autoplay.clear()
		return
	undo_stack.append(before)
	_busy = world.play(rules.events) + 0.12
	_result_pending = rules.won or rules.lost
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _editor.visible:
		return
	if _help.visible:
		_help.hide()
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_H or event.physical_keycode == KEY_F1:
		_help.show()
		return
	if not playing:
		if event.physical_keycode == KEY_ESCAPE and not _menu.visible:
			Sfx.play("click")
			show_menu()
		return
	if not _autoplay.is_empty() and event.physical_keycode != KEY_ESCAPE:
		_autoplay.clear()  # any key takes over from a solution being shown
		_update_status()
	match event.physical_keycode:
		KEY_ESCAPE:
			Sfx.play("click")
			_back()
		KEY_R:
			Sfx.play("click")
			_retry()
		KEY_Z, KEY_U, KEY_BACKSPACE:
			Sfx.play("click")
			undo()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _result.visible:
				if rules.won and not testing:
					next_level()
				elif rules.won:
					show_editor()
				else:
					_retry()
		KEY_N, KEY_TAB:
			if _busy <= 0.0 and rules.cycle_active():
				Sfx.play("switch")
				_update_status()
		KEY_C:
			world.recenter()
		KEY_Q:
			world.turn(1)
		KEY_E:
			world.turn(-1)
		KEY_EQUAL, KEY_KP_ADD:
			world.set_floor_limit(world.floor_limit + 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			world.set_floor_limit(world.floor_limit - 1)


func _show_result() -> void:
	_hint.hide()
	if rules.won and testing:
		_result_title.text = "Playtest won in %d moves" % undo_stack.size()
		_next_button.hide()
		_undo_button.show()
	elif rules.won:
		done[level] = true
		_save_progress()
		_result_title.text = "Level complete!"
		var next := _next_id()
		if next == "":
			_next_button.text = "Levels"
		elif _index_in(level_set, next) < 0:
			_next_button.text = "On to %s" % Levels.get_set(Levels.set_of(next)).title
		else:
			_next_button.text = "Next level"
		_next_button.show()
		_undo_button.hide()
	else:
		Sfx.play("lose")
		_result_title.text = "No quaggles left"
		_next_button.hide()
		_undo_button.show()
	_result.show()


func _update_status() -> void:
	var text := ""
	if testing:
		text = "Playtest:  %s" % _test_level.title
		if not _autoplay.is_empty():
			text += "      Solution, move %d (any key takes over)" % (undo_stack.size() + 1)
	else:
		text = "%s %d:  %s" % [Levels.get_set(level_set).label, _index_in(level_set, level) + 1, Levels.find(level).title]
	text += "      Quaggles: %d" % rules.alive().size()
	if not rules.quaggles[rules.active].gone and rules.quaggles[rules.active].key:
		text += "      Has key"
	_status.text = text


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		for key: String in cfg.get_value("progress", "done", []):
			done[key] = true
		volume = cfg.get_value("options", "volume", volume)
		fullscreen = cfg.get_value("options", "fullscreen", fullscreen)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "done", done.keys())
	cfg.set_value("options", "volume", volume)
	cfg.set_value("options", "fullscreen", fullscreen)
	cfg.save(SAVE_PATH)


func _apply_options() -> void:
	AudioServer.set_bus_mute(0, volume <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


# --- UI ---------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	layer.add_child(root)

	# Main menu.
	_menu = _centered_panel(root)
	var menu_box: VBoxContainer = _menu.get_meta("box")
	menu_box.add_child(_heading("Quaggles' Quandary", 64))
	menu_box.add_child(_label("Get any quaggle to the green goal.", 20))
	_menu_sets = VBoxContainer.new()
	_menu_sets.add_theme_constant_override("separation", 16)
	menu_box.add_child(_menu_sets)
	_fill_menu_sets()
	var entries: Array = [["How to Play", func() -> void: _help.show()], ["Options", show_options]]
	# The editor writes into res://, so it is only offered when running from Godot.
	if OS.has_feature("editor") or OS.get_cmdline_user_args().has("--editor"):
		entries.append(["Level Editor", show_editor])
	for entry: Array in entries:
		menu_box.add_child(_menu_button(entry[0], entry[1]))
	_credits = CREDITS.instantiate()
	# Same placement as on Extranaut's title screen.
	_credits.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_credits.offset_left = -280
	_credits.offset_top = -112
	_credits.offset_right = -8
	_credits.offset_bottom = -8
	_credits.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_credits.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_credits)

	# Level list, filled in by show_list().
	_list = _centered_panel(root)
	var list_box: VBoxContainer = _list.get_meta("box")
	_list_title = _heading("", 44)
	list_box.add_child(_list_title)
	_list_grid = GridContainer.new()
	_list_grid.columns = 3
	list_box.add_child(_list_grid)
	list_box.add_child(_centered(_button("Back", show_menu)))

	# Options.
	_options = _centered_panel(root)
	var options_box: VBoxContainer = _options.get_meta("box")
	options_box.add_child(_heading("Options", 44))
	var rows := GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override("h_separation", 24)
	rows.add_theme_constant_override("v_separation", 18)
	options_box.add_child(rows)
	rows.add_child(_text("Sound volume", 20))
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = volume
	slider.custom_minimum_size = Vector2(260, 28)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void:
		volume = v
		_apply_options())
	slider.drag_ended.connect(func(_changed: bool) -> void:
		_save_progress()
		Sfx.play("key"))
	rows.add_child(slider)
	rows.add_child(_text("Fullscreen", 20))
	var toggle := CheckButton.new()
	toggle.button_pressed = fullscreen
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.toggled.connect(func(on: bool) -> void:
		fullscreen = on
		_apply_options()
		_save_progress())
	rows.add_child(toggle)
	_reset_button = _button("Reset progress", _reset_progress)
	options_box.add_child(_centered(_reset_button))
	options_box.add_child(_centered(_button("Back", show_menu)))

	# In-game HUD.
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud)
	_status = _label("", 24)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status.position = Vector2(18, 16)
	_hud.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.position += Vector2(-16, 12)
	buttons.add_child(_button("Help", func() -> void: _help.show()))
	buttons.add_child(_button("Undo", undo))
	buttons.add_child(_button("Restart", _retry))
	_back_button = _button("Levels", _back)
	buttons.add_child(_back_button)
	_hud.add_child(buttons)
	var hint_anchor := CenterContainer.new()
	hint_anchor.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_anchor.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_anchor.offset_bottom = -20
	hint_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(hint_anchor)
	_hint = PanelContainer.new()
	_hint.theme_type_variation = "HintPanel"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_anchor.add_child(_hint)
	_hint_label = _text("", 20)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(720, 0)
	_hint.add_child(_hint_label)

	# Win / lose panel, shown over the HUD.
	_result = _centered_panel(_hud)
	var result_box: VBoxContainer = _result.get_meta("box")
	_result_title = _heading("", 44)
	_result_title.add_theme_color_override("font_color", CREAM)
	result_box.add_child(_result_title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_next_button = _button("Next level", next_level)
	_undo_button = _button("Undo", undo)
	row.add_child(_next_button)
	row.add_child(_undo_button)
	row.add_child(_button("Restart", _retry))
	_result_back = _button("Levels", _back)
	row.add_child(_result_back)
	result_box.add_child(row)

	_editor = LevelEditor.new()
	_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_editor.play_requested.connect(playtest)
	_editor.close_requested.connect(show_menu)
	root.add_child(_editor)

	_screens = [_menu, _list, _options, _hud, _editor]
	_build_help(root)


## One menu button per level set; the editor can add, remove and rename sets.
func _fill_menu_sets() -> void:
	if _menu_sets == null:
		return
	for child in _menu_sets.get_children():
		child.queue_free()
	for s: Dictionary in Levels.sets():
		_menu_sets.add_child(_menu_button(s.title, show_list.bind(s.id)))


func _menu_button(text: String, action: Callable) -> Button:
	var b := _button(text, action)
	b.custom_minimum_size = Vector2(280, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


## Asks for a second click before wiping the list of completed levels.
func _reset_progress() -> void:
	if _reset_button.text == "Reset progress":
		_reset_button.text = "Click again to reset"
		return
	done.clear()
	_save_progress()
	_reset_button.text = "Progress reset"


func _build_help(root: Control) -> void:
	var dim := ColorRect.new()
	dim.color = Color(NAVY, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.hide()
	root.add_child(dim)
	_help = _centered_panel(root)
	_help.visibility_changed.connect(func() -> void: dim.visible = _help.visible)
	_help.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks behind the panel
	var box: VBoxContainer = _help.get_meta("box")
	box.add_theme_constant_override("separation", 12)
	box.add_child(_heading("How to play", 40))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	box.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	for entry: Array in LEGEND:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var swatch := Panel.new()
		var chip := StyleBoxFlat.new()
		chip.bg_color = entry[0]
		chip.set_corner_radius_all(6)
		swatch.add_theme_stylebox_override("panel", chip)
		swatch.custom_minimum_size = Vector2(24, 24)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(swatch)
		line.add_child(_text(entry[1], 16))
		left.add_child(line)
	var tips := _text(TIPS, 16)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips.custom_minimum_size = Vector2(520, 0)
	left.add_child(tips)

	var keys := GridContainer.new()
	keys.columns = 2
	keys.add_theme_constant_override("h_separation", 16)
	keys.add_theme_constant_override("v_separation", 8)
	columns.add_child(keys)
	for pair: Array in CONTROLS:
		var key := _text(pair[0], 16)
		key.add_theme_color_override("font_color", AMBER)
		keys.add_child(key)
		keys.add_child(_text(pair[1], 16))

	var close := _button("Got it", func() -> void: _help.hide())
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(close)
	_help.hide()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(NAVY, 0.96)
	panel.border_color = Color(CREAM, 0.25)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(22)
	panel.set_content_margin_all(30)
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	var hint := panel.duplicate()
	hint.bg_color = Color(NAVY, 0.8)
	hint.set_corner_radius_all(14)
	hint.set_content_margin_all(14)
	hint.shadow_size = 0
	t.set_stylebox("panel", "HintPanel", hint)
	t.set_type_variation("HintPanel", "PanelContainer")
	for variation: String in ["Button", "DoneButton"]:
		var base := AMBER if variation == "Button" else GREEN
		t.set_stylebox("normal", variation, _button_box(base, 4))
		t.set_stylebox("hover", variation, _button_box(base.lightened(0.25), 4))
		t.set_stylebox("pressed", variation, _button_box(base.darkened(0.12), 1))
		t.set_stylebox("focus", variation, StyleBoxEmpty.new())
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(state, variation, NAVY)
		t.set_font("font", variation, TITLE_FONT)
		t.set_font_size("font_size", variation, 20)
	t.set_type_variation("DoneButton", "Button")
	t.set_color("font_color", "Label", CREAM)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 10)
	t.set_constant("v_separation", "GridContainer", 10)
	return t


## Chunky rounded button: `lip` is the darker bottom edge, squashed when pressed.
func _button_box(color: Color, lip: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = color.darkened(0.35)
	box.border_width_bottom = lip
	box.set_corner_radius_all(12)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8 + (4 - lip)
	box.content_margin_bottom = 8 + lip
	return box


## A full-screen centering container holding a panel; its VBox is in meta "box".
func _centered_panel(parent: Node) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	center.add_child(panel)
	center.set_meta("box", box)
	parent.add_child(center)
	return center


## Centered heading with a dark outline, readable over the 3D scene.
func _label(text: String, size: int) -> Label:
	var l := _text(text, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(NAVY, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	return l


func _text(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(104, 46)
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		action.call())
	return b


func _heading(text: String, size: int) -> Label:
	var l := _label(text, size)
	l.add_theme_font_override("font", TITLE_FONT)
	l.add_theme_color_override("font_color", AMBER)
	return l


func _centered(control: Control) -> Control:
	control.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return control


# --- debug: `-- --shot=<level id|menu|help|options|<set id>|editor[:<level id>[:<command>]]>,<png path>[,<moves e.g. ddds>]`

func _screenshot(spec: String) -> void:
	var parts := spec.split(",")
	match parts[0]:
		"menu": pass
		"help": _help.show()
		"options": show_options()
		_:
			if parts[0].begins_with("editor"):
				var bits := parts[0].split(":")
				_show(_editor)
				_editor.open(bits[1] if bits.size() > 1 else "")
				for command in bits.slice(2):
					_editor.debug_command(command)
				parts.resize(2)
			elif not Levels.get_set(parts[0]).is_empty():
				show_list(parts[0])
			else:
				start(parts[0])
	if parts.size() > 2:
		var keys := {"w": Vector2i(0, 1), "a": Vector2i(-1, 0), "s": Vector2i(0, -1), "d": Vector2i(1, 0)}
		for ch in parts[2]:
			if ch == "n":
				rules.cycle_active()
				continue
			var dir := world.grid_dir(keys[ch])
			rules.try_move(dir.x, dir.y)
			await get_tree().create_timer(world.play(rules.events) + 0.05).timeout
		_update_status()
		if rules.won or rules.lost:
			_show_result()
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(parts[1])
	get_tree().quit()
