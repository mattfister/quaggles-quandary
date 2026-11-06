class_name EditorPreview
extends SubViewportContainer
## The level editor's live 3D view: the game's own World in a viewport of
## its own. Right or middle drag orbits, wheel zooms, Shift + right drag pans,
## and the left button uses the current tool on the floor being edited.

var editor: LevelEditor
var world := World.new()

var _viewport := SubViewport.new()
var _orbiting := false
var _panning := false
var _pressed := false
var _pan := Vector3.ZERO


func _init() -> void:
	stretch = true
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	world.edit_mode = true
	_viewport.add_child(world)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK


func _propagate_input_event(_event: InputEvent) -> bool:
	return false  # the World is steered from here


## Rebuilds the scene from `r`; `reset` also points the camera afresh.
func show_level(r: Rules, reset: bool) -> void:
	world.build(r, reset)
	if reset:
		_pan = Vector3.ZERO
		world.pitch = 0.95
		frame()
	refocus()


## Backs the camera off far enough to take in the whole level, allowing for
## a narrow view.
func frame() -> void:
	var lv := editor.level
	var aspect := size.x / maxf(1.0, size.y)
	var reach := maxf(lv.width, lv.height) * 0.55 + 1.5
	world.dist = clampf(reach / tan(deg_to_rad(22.5)) / minf(1.0, aspect), 8.0, 90.0)


func refocus() -> void:
	if world.rules == null:
		return
	var lv := editor.level
	world.edit_focus = World.middle(lv.width, lv.height, 0) + Vector3(0, editor.cur_floor * World.H, 0) + _pan
	world.set_floor_limit(editor.cur_floor + 1 if editor.cutaway else lv.floors)


func _cell(pos: Vector2) -> Variant:
	return world.pick(pos * Vector2(_viewport.size) / size, editor.cur_floor)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				world.dist = maxf(4.0, world.dist * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				world.dist = minf(90.0, world.dist * 1.1)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_orbiting = mb.pressed and not mb.shift_pressed
				_panning = mb.pressed and mb.shift_pressed
			MOUSE_BUTTON_LEFT:
				var c: Variant = _cell(mb.position)
				if mb.pressed and c != null:
					grab_focus()
					_pressed = true
					# Ctrl + click erases here, since the right button orbits.
					editor.tool_press(c, MOUSE_BUTTON_RIGHT if mb.ctrl_pressed else MOUSE_BUTTON_LEFT,
						mb.shift_pressed, false, mb.alt_pressed)
				elif not mb.pressed and _pressed:
					_pressed = false
					editor.tool_release(c if c != null else editor.hover)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			world.yaw -= mm.relative.x * 0.008
			world.pitch = clampf(world.pitch + mm.relative.y * 0.006, 0.2, 1.52)
		elif _panning:
			var right := Vector3(cos(world.yaw), 0, -sin(world.yaw))
			var forward := Vector3(sin(world.yaw), 0, cos(world.yaw))
			_pan += (-right * mm.relative.x + -forward * mm.relative.y) * world.dist * 0.0015
			refocus()
		var c: Variant = _cell(mm.position)
		editor.set_hover(c)
		if _pressed and c != null:
			editor.tool_drag(c, mm.shift_pressed)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and editor:
		editor.set_hover(null)


## Moves the hover cursor and selection box to match the editor.
func show_marks(hover: Variant, sel: Rect2i, sel_floors: Vector2i) -> void:
	if hover is Vector2i:
		var cells := editor.brush_cells(hover)
		var lo: Vector2i = cells[0]
		var hi: Vector2i = cells[-1]
		world.show_box(Vector3i(lo.x, lo.y, editor.cur_floor), Vector3i(hi.x, hi.y, editor.cur_floor))
	else:
		world.hide_box()
	if sel.size != Vector2i.ZERO:
		world.show_box(Vector3i(sel.position.x, sel.position.y, sel_floors.x),
			Vector3i(sel.end.x - 1, sel.end.y - 1, sel_floors.y), true)
	else:
		world.hide_box(true)
