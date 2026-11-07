class_name EditorGrid
extends Control
## The level editor's 2D map of one floor. Draws the cells, the floors above
## and below as ghosts, tool previews and the selection, and turns the mouse
## into tool presses on the editor. Wheel zooms, middle drag (or Space + drag)
## pans.

const FLOOR_COLORS := World.FLOOR_COLORS
const WALL_TOP := World.WALL_TOP
const WALL_SIDE := World.WALL_SIDE
const BG := Color("141a33")
const OUTSIDE := Color("10152a")
const INSIDE := Color("1e2648")
const BORDER := Color("ffb84d")
const SELECT := Color("6fd8ff")

var editor: LevelEditor
var zoom := 32.0
var pan := Vector2(40, 40)
## Refit whenever the view changes size, until the user zooms or pans.
var auto_fit := true

var _panning := false
var _pressed := -1   # mouse button held over the map for the tool, or -1
var _time := 0.0


func _ready() -> void:
	resized.connect(func() -> void:
		if auto_fit and editor.level:
			fit())
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func _process(delta: float) -> void:
	_time += delta
	if is_visible_in_tree() and (editor.selection_rect().size != Vector2i.ZERO or not editor.floating.is_empty() or editor.flash_time > 0.0):
		queue_redraw()


# --- coordinates -----------------------------------------------------------------

func _col(x: int, w: int) -> int:
	return w - 1 - x if editor.mirror else x


func cell_rect(x: int, y: int) -> Rect2:
	return Rect2(pan + Vector2(_col(x, editor.level.width), y) * zoom, Vector2(zoom, zoom))


func cell_at(pos: Vector2) -> Vector2i:
	var col := floori((pos.x - pan.x) / zoom)
	var row := floori((pos.y - pan.y) / zoom)
	return Vector2i(_col(col, editor.level.width), row)


## Keeps the map still on screen after the level grew by `moved` cells
## up/left from a width of `old_w`.
func on_grown(moved: Vector2i, old_w: int) -> void:
	var before := _col(0, old_w)
	var after := _col(moved.x, editor.level.width)
	pan += Vector2(before - after, -moved.y) * zoom
	queue_redraw()


## Zooms and centres so the whole level fits.
func fit() -> void:
	var lw := editor.level.width
	var lh := editor.level.height
	var avail := size - Vector2(48, 48)
	zoom = clampf(minf(avail.x / lw, avail.y / lh), 6.0, 64.0)
	pan = (size - Vector2(lw, lh) * zoom) * 0.5
	queue_redraw()


func zoom_by(factor: float, around: Vector2) -> void:
	auto_fit = false
	var old := zoom
	zoom = clampf(zoom * factor, 6.0, 96.0)
	pan = around - (around - pan) * (zoom / old)
	queue_redraw()


# --- input -------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					if mb.ctrl_pressed:
						editor.change_floor(1)
					else:
						zoom_by(1.15, mb.position)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					if mb.ctrl_pressed:
						editor.change_floor(-1)
					else:
						zoom_by(1.0 / 1.15, mb.position)
				accept_event()
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
				accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SPACE):
					_panning = true
				elif mb.pressed and _pressed == -1:
					grab_focus()
					_pressed = mb.button_index
					editor.tool_press(cell_at(mb.position), mb.button_index, mb.shift_pressed, mb.ctrl_pressed, mb.alt_pressed)
				elif not mb.pressed and mb.button_index == _pressed:
					_pressed = -1
					editor.tool_release(cell_at(mb.position))
				elif not mb.pressed:
					_panning = false
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			auto_fit = false
			pan += mm.relative
			queue_redraw()
		var c := cell_at(mm.position)
		editor.set_hover(c)
		if _pressed != -1:
			editor.tool_drag(c, mm.shift_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		editor.set_hover(null)


# --- drawing -----------------------------------------------------------------------

func _draw() -> void:
	var lv := editor.level
	var f := editor.cur_floor
	draw_rect(Rect2(Vector2.ZERO, size), OUTSIDE)
	var area := Rect2(pan, Vector2(lv.width, lv.height) * zoom)
	draw_rect(area, INSIDE)
	var font := get_theme_default_font()

	# The floor below shows through empty cells; what is solid there (walls,
	# glass, lifts, closed fields) can be stood on from this floor.
	if editor.ghost_below and f > 0:
		for y in lv.height:
			for x in lv.width:
				if lv.cell(f, x, y) == Rules.EMPTY:
					var below := lv.cell(f - 1, x, y)
					if below != Rules.EMPTY:
						var r := cell_rect(x, y)
						draw_tile(self, r.grow(-zoom * 0.08), below, f - 1, 0.28, 1.0, Color(), null)
						if _standable(below):
							draw_rect(r.grow(-zoom * 0.1), Color(1, 1, 1, 0.22), false, maxf(1.0, zoom * 0.04))

	for y in lv.height:
		for x in lv.width:
			var c := lv.cell(f, x, y)
			if c == Rules.EMPTY:
				continue
			var p := Vector3i(x, y, f)
			draw_tile(self, cell_rect(x, y), c, f, 1.0, 1.0 if (x + y) % 2 == 0 else 0.93,
				editor.quag_colors.get(p, Color()), font if zoom >= 16 else null, editor.quag_ids.get(p, -1))

	if editor.ghost_above and f + 1 < lv.floors:
		for y in lv.height:
			for x in lv.width:
				var above := lv.cell(f + 1, x, y)
				if above != Rules.EMPTY:
					var r := cell_rect(x, y).grow(-zoom * 0.18)
					draw_rect(r, Color(1, 1, 1, 0.35), false, maxf(1.0, zoom * 0.05))

	if editor.show_grid and zoom >= 10:
		var line := Color(1, 1, 1, 0.07)
		for x in lv.width + 1:
			draw_line(pan + Vector2(x * zoom, 0), pan + Vector2(x * zoom, lv.height * zoom), line)
		for y in lv.height + 1:
			draw_line(pan + Vector2(0, y * zoom), pan + Vector2(lv.width * zoom, y * zoom), line)
	draw_rect(area, Color(BORDER, 0.6), false, 2.0)

	# Problems found by the checks, on this floor.
	for issue: Dictionary in editor.issues:
		var at: Variant = issue.get("pos")
		if at is Vector3i and at.z == f:
			var r := cell_rect(at.x, at.y)
			var col := Color("ff5c5c") if issue.level == "error" else Color("ffcc33")
			draw_rect(r.grow(-1), col, false, maxf(2.0, zoom * 0.08))

	# Tool previews.
	for p: Vector2i in editor.preview:
		draw_tile(self, cell_rect(p.x, p.y), editor.preview[p], f, 0.7, 1.0, Color(), null)
		if editor.preview[p] == Rules.EMPTY:
			draw_rect(cell_rect(p.x, p.y).grow(-zoom * 0.3), Color(1, 0.4, 0.4, 0.6))
	var buf := editor.floating
	if not buf.is_empty():
		var bf := clampi(f - editor.float_floor, 0, buf.f - 1)
		for by in buf.h:
			for bx in buf.w:
				var c := EditLevel.buffer_cell(buf, bf, bx, by)
				var pos: Vector2i = editor.float_pos + Vector2i(bx, by)
				var r := cell_rect(pos.x, pos.y)
				if c != Rules.EMPTY:
					draw_tile(self, r, c, f, 0.8, 1.0, Color(), null)
				draw_rect(r, Color(SELECT, 0.12))
		_draw_marquee(Rect2i(editor.float_pos, Vector2i(buf.w, buf.h)))

	var sel := editor.selection_rect()
	if sel.size != Vector2i.ZERO and buf.is_empty():
		_draw_marquee(sel)

	var hover: Variant = editor.hover
	if hover is Vector2i and buf.is_empty():
		for p: Vector2i in editor.brush_cells(hover):
			var r := cell_rect(p.x, p.y)
			if editor.cur_tool == LevelEditor.PAINT and editor.preview.is_empty():
				draw_tile(self, r, editor.tile, f, 0.45, 1.0, Color(), null)
			draw_rect(r, Color(BORDER, 0.95), false, 2.0)

	if editor.flash_time > 0.0 and editor.flash_cell.z == f:
		var r := cell_rect(editor.flash_cell.x, editor.flash_cell.y)
		var grow := zoom * (0.2 + 0.6 * fmod(editor.flash_time * 2.0, 1.0))
		draw_rect(r.grow(grow), Color(1, 1, 1, clampf(editor.flash_time, 0, 1)), false, 3.0)

	# Rulers: map columns and rows as the level file numbers them.
	if zoom >= 18:
		var small := 11
		for x in lv.width:
			var r := cell_rect(x, 0)
			draw_string(font, Vector2(r.position.x, pan.y - 6), str(x), HORIZONTAL_ALIGNMENT_CENTER, zoom, small, Color(1, 1, 1, 0.35))
		for y in lv.height:
			var r := cell_rect(0, y)
			draw_string(font, Vector2(pan.x - 30, r.position.y + zoom * 0.5 + 4), str(y), HORIZONTAL_ALIGNMENT_RIGHT, 24, small, Color(1, 1, 1, 0.35))


func _draw_marquee(r: Rect2i) -> void:
	var a := cell_rect(r.position.x, r.position.y)
	var b := cell_rect(r.end.x - 1, r.end.y - 1)
	var box := a.merge(b)
	draw_rect(box, Color(SELECT, 0.1))
	var dash := 6.0
	var off := fmod(_time * 20.0, dash * 2.0)
	var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in 4:
		draw_dashed_line(corners[i] + (corners[(i + 1) % 4] - corners[i]).normalized() * off,
			corners[(i + 1) % 4], SELECT, 2.0, dash)


static func _standable(c: int) -> bool:
	return c == Rules.WALL or c == Rules.WINDOW or c == Rules.UP or c == Rules.FIELD


## Draws one cell's tile into `r`. Shared by the map, the palette and the
## floor thumbnails. `quag` is the quaggle colour for starts, `id` its number.
static func draw_tile(ci: CanvasItem, r: Rect2, c: int, f: int, alpha := 1.0, shade := 1.0,
		quag := Color(), font: Font = null, id := -1) -> void:
	var s := r.size.x
	var inset := r.grow(-maxf(0.5, s * 0.03))
	var floor_col: Color = FLOOR_COLORS[f % FLOOR_COLORS.size()] * Color(shade, shade, shade)
	var a := func(col: Color) -> Color: return Color(col, col.a * alpha)
	match c:
		Rules.EMPTY:
			return
		Rules.WALL:
			ci.draw_rect(inset, a.call(WALL_SIDE))
			ci.draw_rect(Rect2(inset.position, inset.size - Vector2(0, s * 0.14)), a.call(WALL_TOP * Color(shade, shade, shade)))
			return
		Rules.WINDOW:
			ci.draw_rect(inset, a.call(Color(0.55, 0.8, 0.98, 0.45)))
			ci.draw_rect(inset.grow(-s * 0.04), a.call(Color(0.85, 0.95, 1.0, 0.9)), false, maxf(1.0, s * 0.06))
			ci.draw_line(inset.position + Vector2(s * 0.25, s * 0.7), inset.position + Vector2(s * 0.7, s * 0.25), a.call(Color(1, 1, 1, 0.8)), maxf(1.0, s * 0.05))
			return
		Rules.ICE:
			ci.draw_rect(inset, a.call(Color("a9e4ff") * Color(shade, shade, shade)))
			for k in 2:
				var o := inset.position + Vector2(s * (0.2 + 0.35 * k), s * 0.15)
				ci.draw_line(o, o + Vector2(s * 0.3, s * 0.4), a.call(Color(1, 1, 1, 0.75)), maxf(1.0, s * 0.05))
			return
		Rules.CRACK:
			ci.draw_rect(inset, a.call(Color("d9b48c")))
			var p := inset.position
			var crack := PackedVector2Array([p + Vector2(s * 0.15, s * 0.2), p + Vector2(s * 0.45, s * 0.45),
				p + Vector2(s * 0.4, s * 0.65), p + Vector2(s * 0.8, s * 0.85)])
			ci.draw_polyline(crack, a.call(Color("5a4330")), maxf(1.0, s * 0.06))
			ci.draw_line(p + Vector2(s * 0.45, s * 0.45), p + Vector2(s * 0.8, s * 0.3), a.call(Color("5a4330")), maxf(1.0, s * 0.05))
			return
		Rules.DOWN:
			ci.draw_rect(inset, a.call(Color(0.05, 0.05, 0.1, 0.6)))
			ci.draw_circle(r.get_center(), s * 0.25, a.call(Color(0, 0, 0, 0.8)))
			return
	# The rest stand on a floor tile.
	ci.draw_rect(inset, a.call(floor_col))
	var mid := r.get_center()
	match c:
		Rules.GROUND:
			pass
		Rules.GOAL:
			ci.draw_rect(inset.grow(-s * 0.1), a.call(Color(0.36, 1.0, 0.56)))
			ci.draw_rect(inset.grow(-s * 0.26), a.call(Color(0.8, 1.0, 0.85)))
		Rules.FIRE:
			ci.draw_rect(inset.grow(-s * 0.08), a.call(Color("ff6a2a")))
			var flame := PackedVector2Array([mid + Vector2(-s * 0.22, s * 0.25), mid + Vector2(0, -s * 0.32),
				mid + Vector2(s * 0.22, s * 0.25)])
			ci.draw_colored_polygon(flame, a.call(Color("ffd84a")))
		Rules.KEY:
			var gold: Color = a.call(Color("ffcc33"))
			var w := maxf(1.5, s * 0.08)
			ci.draw_arc(mid + Vector2(-s * 0.15, 0), s * 0.14, 0, TAU, 16, gold, w)
			ci.draw_line(mid + Vector2(-s * 0.01, 0), mid + Vector2(s * 0.32, 0), gold, w)
			ci.draw_line(mid + Vector2(s * 0.22, 0), mid + Vector2(s * 0.22, s * 0.14), gold, w)
		Rules.FIELD:
			ci.draw_rect(inset.grow(-s * 0.06), a.call(Color(0.85, 0.31, 0.82, 0.75)))
			for k in 3:
				var x0 := inset.position.x + s * (0.25 + 0.25 * k)
				ci.draw_line(Vector2(x0, inset.position.y + s * 0.12), Vector2(x0, inset.end.y - s * 0.12), a.call(Color(1, 0.8, 1, 0.8)), maxf(1.0, s * 0.04))
		Rules.CURB:
			ci.draw_rect(inset.grow(-s * 0.1), a.call(Color(0.62, 0.65, 0.82)), false, maxf(1.5, s * 0.12))
		Rules.SOURCE:
			ci.draw_rect(inset.grow(-s * 0.1), a.call(Color(0.2, 0.55, 0.95)))
			ci.draw_circle(mid, s * 0.18, a.call(Color(0.88, 0.97, 1.0)))
			ci.draw_circle(mid, s * 0.09, a.call(Color(0.2, 0.55, 0.95)))
		Rules.UP:
			var cols := [Color(1, 1, 1), Color(1, 0.9, 0.45), Color(0.55, 0.9, 1)]
			for k in 3:
				ci.draw_rect(inset.grow(-s * (0.08 + 0.12 * k)), a.call(cols[k]), false, maxf(1.0, s * 0.05))
			ci.draw_colored_polygon(PackedVector2Array([mid + Vector2(-s * 0.12, s * 0.05), mid + Vector2(0, -s * 0.12),
				mid + Vector2(s * 0.12, s * 0.05)]), a.call(Color.WHITE))
		Rules.START, Rules.SPAWN:
			var body := quag if quag.a > 0.0 else (Color("ff6b6b") if c == Rules.START else Color("4dabf7"))
			if c == Rules.START:
				ci.draw_circle(mid, s * 0.42, a.call(Color("ffb84d")))
			ci.draw_circle(mid, s * 0.34, a.call(body.darkened(0.3)))
			ci.draw_circle(mid + Vector2(0, -s * 0.03), s * 0.3, a.call(body))
			ci.draw_circle(mid + Vector2(-s * 0.1, -s * 0.08), s * 0.07, a.call(Color.WHITE))
			ci.draw_circle(mid + Vector2(s * 0.1, -s * 0.08), s * 0.07, a.call(Color.WHITE))
			ci.draw_circle(mid + Vector2(-s * 0.1, -s * 0.07), s * 0.035, a.call(Color.BLACK))
			ci.draw_circle(mid + Vector2(s * 0.1, -s * 0.07), s * 0.035, a.call(Color.BLACK))
			if font and id >= 0:
				ci.draw_string(font, r.position + Vector2(s * 0.62, s * 0.95), str(id), HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(s * 0.3), a.call(Color("1b2240")))
		_:
			ci.draw_rect(inset.grow(-s * 0.15), a.call(Color("6b5f58")))
			if font:
				ci.draw_string(font, r.position + Vector2(0, s * 0.68), char(c), HORIZONTAL_ALIGNMENT_CENTER, s,
					int(s * 0.45), a.call(Color.WHITE))
