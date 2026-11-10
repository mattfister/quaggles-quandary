class_name LevelEditor
extends Control
## The level editor: every level of every set, editable in a 2D map and a
## live 3D view, with playtesting, a solver that can show its solution, and
## checks for common mistakes. Saves to levels/levels.json (Levels.save),
## keeping a backup of the previous file in user://level_backups, and
## autosaves unsaved work to user://editor_autosave.json.

signal play_requested(level: Dictionary, moves: Array)
signal close_requested

enum { PAINT, LINE, RECT, BOX, FILL, PICK, SELECT }
enum { VIEW_2D, VIEW_SPLIT, VIEW_3D }

## [tool, name, key, what it does]
const TOOLS := [
	[PAINT, "Paint", "B", "Paint tiles. Right button erases. Shift + drag in Line or Rect keeps it straight or square."],
	[LINE, "Line", "L", "Drag a straight line of tiles."],
	[RECT, "Rect", "R", "Drag the outline of a rectangle."],
	[BOX, "Box", "T", "Drag a filled rectangle."],
	[FILL, "Fill", "F", "Flood-fill the joined area of one tile."],
	[PICK, "Pick", "I", "Pick up the tile under the cursor (or Alt + click with any tool)."],
	[SELECT, "Select", "M", "Drag to select; drag the selection to move it (Ctrl + drag copies). Ctrl+C / X / V, Delete, H / V / O to flip and turn."],
]
## [cell, name, key, what it does]
const TILES := [
	[Rules.EMPTY, "Empty", "E", "Nothing. Quaggles fall through."],
	[Rules.GROUND, "Floor", ".", "Plain floor."],
	[Rules.WALL, "Wall", "*", "Blocks the way; can be stood on from the floor above."],
	[Rules.WINDOW, "Glass", "w", "Like a wall, but see-through."],
	[Rules.ICE, "Ice", "x", "Slide until something stops you."],
	[Rules.FIRE, "Fire", "X", "Burns the quaggle that steps in, then goes out."],
	[Rules.KEY, "Key", "2", "Switches off one force field; used up."],
	[Rules.FIELD, "Force field", "3", "Solid until a key carrier walks in."],
	[Rules.CRACK, "Cracked", "4", "Crumbles once you step off it."],
	[Rules.CURB, "Curb", "^", "Floor with a low rim. Quaggles step over it; flowing water can't cross it, but a filling pool rises over it."],
	[Rules.SPIKE, "Spikes", "!", "Quaggles won't walk onto them, but sliding or falling onto them kills. Water flows right over them."],
	[Rules.SOURCE, "Spring", "~", "Water flows 3 cells, falls off edges and fills pits it pours into. Quaggles dam it, stop it up by standing on it, and swim in pools. It puts out fire."],
	[Rules.UP, "Lift", "u", "Raises whoever steps in (and their stack) one floor."],
	[Rules.GOAL, "Goal", "g", "Get any quaggle here to win."],
	[Rules.START, "Start", "s", "A quaggle; play begins with the first of these."],
	[Rules.SPAWN, "Quaggle", "1", "Another quaggle."],
	[Rules.DOWN, "Hole", "d", "Old hole marker: as empty as Empty."],
]
const SHORTCUTS := [
	["Tiles", "the map character: . * w x X 2 3 4 ^ ! ~ u g s 1 d, E for empty"],
	["Tools", "B paint, L line, R rect, T box, F fill, I pick, M select"],
	["Mouse", "left uses the tool, right erases, Alt + click picks, wheel zooms, middle drag or Space + drag pans"],
	["3D view", "left uses the tool, Ctrl + click erases, right drag orbits, Shift + right drag pans"],
	["Floors", "PageUp / PageDown or ] / [, Ctrl + wheel"],
	["Selection", "Ctrl+A all, Ctrl+D none, Ctrl+C / X / V, Delete, arrows nudge"],
	["Transform", "H flip across, V flip up-down, O turn (selection, paste, or whole level)"],
	["Edit", "Ctrl+Z undo, Ctrl+Y or Ctrl+Shift+Z redo, Ctrl+S save, Ctrl+N new level"],
	["Test", "F5 or P playtest, F6 solve, F7 watch the solution"],
	["View", "Tab 2D / split / 3D, Home fits the map, + / - zoom, F1 or ? this help"],
]

const BACKUPS := "user://level_backups"
const NAVY := Color("1b2240")
const DEEP := Color("10152a")
const CREAM := Color("fff6e0")
const AMBER := Color("ffb84d")
const GREEN := Color("6fdc8c")
const RED := Color("ff6b6b")
const TITLE_FONT := preload("res://fonts/CarterOne-Regular.ttf")
const BODY_FONT := preload("res://fonts/Comfortaa-Bold.ttf")

# --- state read by the map and the 3D view ------------------------------------------

var level := EditLevel.new()
var cur_floor := 0
var tile := Rules.WALL
var cur_tool := PAINT
var mirror := true        # draw the map as the game camera first sees it
var show_grid := true
var ghost_below := true
var ghost_above := true
var cutaway := true       # hide floors above the one being edited, in 3D
var sym_x := false
var sym_y := false
var brush := 1
var transparent_paste := false
var sel_all_floors := false

var hover: Variant = null           # Vector2i under the mouse, or null
var preview := {}                   # Vector2i -> cell, for Line / Rect / Box
var floating := {}                  # buffer being moved or pasted
var float_pos := Vector2i.ZERO
var float_floor := 0
var issues: Array = []              # {level: error|warn|info, text, pos?}
var quag_colors := {}               # Vector3i -> Color, as in the game
var quag_ids := {}                  # Vector3i -> quaggle id
var flash_cell := Vector3i.ZERO
var flash_time := 0.0

# --- the levels ------------------------------------------------------------------------

var _data: Array = []               # working copy of every set
var _set_i := 0
var _level_i := 0
var _entry := {}                    # the level being edited, inside _data
var _saved_json := ""
var _saved_levels := {}             # uid -> level_json() as last saved
var _history := {}                  # uid -> {undo: [], redo: []}
var _next_uid := 1
var _opened := false
var autosave_path := "user://editor_autosave.json"
var _last_request := ""
var _tree_set := -1                 # set picked in the tree (not a level), or -1

# --- tools -----------------------------------------------------------------------------

var _sel := Rect2i()
var _sel_floors := Vector2i.ZERO
var _sel_anchor := Vector2i.ZERO
var _selecting := false
var _moving := false
var _move_grab := Vector2i.ZERO
var _clip := {}
var _stroke := false
var _stroke_tool := PAINT
var _stroke_tile := Rules.WALL
var _drag_start := Vector2i.ZERO
var _last_cell := Vector2i.ZERO
var _prev_tool := PAINT
var _before := {}
var _in_edit := false

# --- solver ----------------------------------------------------------------------------

var _solver: Solver
var _solve_phase := ""
var _solve_floors: Array = []
var _solve_lines := PackedStringArray()
var _solution: Array = []
var _min_stack := 1

# --- refresh ---------------------------------------------------------------------------

var _refresh_pending := false
var _preview_pending := false
var _preview_reset := false
var _preview_wait := 0.0
var _autosave_wait := -1.0
var _message_wait := 0.0
var _confirm := ""                  # action waiting on a second click
var _confirm_wait := 0.0
var _view := VIEW_SPLIT
var _fit_pending := true

# --- UI --------------------------------------------------------------------------------

var _grid: EditorGrid
var _preview: EditorPreview
var _split: HSplitContainer
var _tree: Tree
var _filter: LineEdit
var _title_edit: LineEdit
var _id_edit: LineEdit
var _hint_edit: TextEdit
var _stack_spin: SpinBox
var _review_buttons := {}           # review value -> its toggle in the Level panel
var _set_option: OptionButton
var _set_title: LineEdit
var _set_label: LineEdit
var _floor_list: VBoxContainer
var _floor_buttons: Array[Button] = []
var _size_label: Label
var _solve_label: RichTextLabel
var _watch_buttons: Array[Button] = []
var _solve_buttons: Array[Button] = []
var _cap_spin: SpinBox
var _issue_list: VBoxContainer
var _stats_label: Label
var _tool_buttons := {}
var _tile_buttons := {}
var _brush_buttons: Array[Button] = []
var _view_buttons: Array[Button] = []
var _message: Label
var _dirty_label: Label
var _hover_label: Label
var _hint_label: Label
var _zoom_label: Label
var _banner: PanelContainer
var _help: Control
var _undo_button: Button
var _redo_button: Button
var _save_button: Button
var _confirm_buttons := {}          # action -> [button, text]


func _ready() -> void:
	theme = _make_theme()
	_build_ui()
	hide()


## Shows the editor, on `level_id` if one is given and was not asked for last time.
func open(level_id := "") -> void:
	if not _opened:
		_opened = true
		_load_sets(Levels.sets())
		_check_autosave()
	if level_id != "" and level_id != _last_request:
		_last_request = level_id
		_select_id(level_id)
	if _entry.is_empty():
		_select(0, 0)
	_rebuild_tree()
	_queue_preview(true)
	_refresh_now()


func _load_sets(sets: Array) -> void:
	_data = Levels.parse(Levels.to_json(sets))
	_saved_json = Levels.to_json(Levels.sets())
	_saved_levels.clear()
	_history.clear()
	for s: Dictionary in Levels.sets():
		for lv: Dictionary in s.levels:
			_saved_levels[lv.id] = Levels.level_json(lv)
	# Levels get a uid for the editor's bookkeeping; to_json() leaves it out.
	# Saved levels are matched up by id once, here.
	var by_id := {}
	for id: String in _saved_levels:
		by_id[id] = _saved_levels[id]
	_saved_levels.clear()
	for s: Dictionary in _data:
		for lv: Dictionary in s.levels:
			lv._uid = _next_uid
			_next_uid += 1
			if by_id.has(lv.id):
				_saved_levels[lv._uid] = by_id[lv.id]


# --- selection of levels -----------------------------------------------------------------

func _select(set_i: int, level_i: int) -> void:
	_finish_stroke()
	set_i = clampi(set_i, 0, _data.size() - 1)
	# Skip empty sets.
	var tries := 0
	while _data[set_i].levels.is_empty() and tries < _data.size():
		set_i = (set_i + 1) % _data.size()
		tries += 1
	_set_i = set_i
	_level_i = clampi(level_i, 0, _data[set_i].levels.size() - 1)
	_entry = _data[_set_i].levels[_level_i]
	_tree_set = -1
	level = EditLevel.from_floors(_entry.floors)
	var qs := level.quaggle_cells()
	cur_floor = qs[0].z if not qs.is_empty() else 0
	_sel = Rect2i()
	floating = {}
	preview.clear()
	_solver = null
	_solve_phase = ""
	_solution = []
	_solve_lines = PackedStringArray()
	_fit_pending = true
	_fill_fields()
	_rebuild_floor_list()
	_queue_preview(true)
	_refresh_now()
	_show_solve()


func _select_id(id: String) -> void:
	for s in _data.size():
		for l in _data[s].levels.size():
			if _data[s].levels[l].id == id:
				_select(s, l)
				return


func _uid() -> int:
	return _entry.get("_uid", 0)


func _hist() -> Dictionary:
	if not _history.has(_uid()):
		_history[_uid()] = {"undo": [], "redo": []}
	return _history[_uid()]


# --- edits ---------------------------------------------------------------------------

## Starts one undoable change; end it with _end().
func _begin() -> void:
	if _in_edit:
		return
	_in_edit = true
	_before = level.snapshot()
	_before.floor = cur_floor


func _end() -> void:
	if not _in_edit:
		return
	_in_edit = false
	var after := level.snapshot()
	if after.grid == _before.grid and after.w == _before.w and after.f == _before.f:
		return
	var h := _hist()
	h.undo.append(_before)
	if h.undo.size() > 300:
		h.undo.pop_front()
	h.redo.clear()
	_changed()


## The map changed: write it back to the level and refresh what shows it.
func _changed() -> void:
	_entry.floors = level.to_floors()
	cur_floor = clampi(cur_floor, 0, level.floors - 1)
	_grid.queue_redraw()
	_queue_preview(false)
	_refresh_pending = true
	_autosave_wait = 2.0
	if _floor_buttons.size() != level.floors:
		_rebuild_floor_list()


## A level's title, hint and so on changed.
func _meta_changed() -> void:
	_refresh_pending = true
	_autosave_wait = 2.0


func undo() -> void:
	_finish_stroke()
	var h := _hist()
	if h.undo.is_empty():
		_say("Nothing to undo")
		return
	var now := level.snapshot()
	now.floor = cur_floor
	h.redo.append(now)
	_restore(h.undo.pop_back())


func redo() -> void:
	_finish_stroke()
	var h := _hist()
	if h.redo.is_empty():
		_say("Nothing to redo")
		return
	var now := level.snapshot()
	now.floor = cur_floor
	h.undo.append(now)
	_restore(h.redo.pop_back())


func _restore(s: Dictionary) -> void:
	level.restore(s)
	cur_floor = clampi(s.get("floor", cur_floor), 0, level.floors - 1)
	_sel = Rect2i()
	floating = {}
	_changed()
	_rebuild_floor_list()


## Writes one cell, mirrored if symmetry is on, growing the level if the cell
## is outside it. Returns how far the existing cells moved.
func _put(p: Vector2i, c: int) -> Vector2i:
	var moved := Vector2i.ZERO
	if not level.inside(p.x, p.y):
		if c == Rules.EMPTY:
			return moved
		moved = _grow_to(p)
		p += moved
	var changed := level.set_cell(cur_floor, p.x, p.y, c)
	var mx := level.width - 1 - p.x
	var my := level.height - 1 - p.y
	if sym_x:
		changed = level.set_cell(cur_floor, mx, p.y, c) or changed
	if sym_y:
		changed = level.set_cell(cur_floor, p.x, my, c) or changed
	if sym_x and sym_y:
		changed = level.set_cell(cur_floor, mx, my, c) or changed
	if changed:
		_changed()
	return moved


func _grow_to(p: Vector2i) -> Vector2i:
	var old_w := level.width
	var moved := level.grow_to(p.x, p.y)
	_after_resize(moved, old_w)
	return moved


## Keeps everything that points at cells pointing at the same ones after the
## level was resized and its cells moved by `moved`.
func _after_resize(moved: Vector2i, old_w: int) -> void:
	_grid.on_grown(moved, old_w)
	_drag_start += moved
	_last_cell += moved
	_sel_anchor += moved
	float_pos += moved
	if _sel.size != Vector2i.ZERO:
		_sel.position += moved
	if hover is Vector2i:
		hover += moved
	var shifted := {}
	for p: Vector2i in preview:
		shifted[p + moved] = preview[p]
	preview = shifted
	_changed()


func brush_cells(c: Vector2i) -> Array[Vector2i]:
	var n := brush if cur_tool == PAINT or cur_tool == LINE else 1
	var o := c - Vector2i((n - 1) / 2, (n - 1) / 2)
	var out: Array[Vector2i] = []
	for y in n:
		for x in n:
			out.append(o + Vector2i(x, y))
	return out


func selection_rect() -> Rect2i:
	return _sel


# --- tools ----------------------------------------------------------------------------

func tool_press(c: Vector2i, button: int, shift: bool, ctrl: bool, alt: bool) -> void:
	# Pasting: left stamps (again and again), right gives up.
	if not floating.is_empty() and not _moving:
		if button == MOUSE_BUTTON_LEFT:
			_stamp_floating()
		else:
			floating = {}
			_grid.queue_redraw()
		return
	var t := PICK if alt else cur_tool
	if t == PICK:
		if level.inside(c.x, c.y):
			_set_tile(level.cell(cur_floor, c.x, c.y), false)
		if cur_tool == PICK:
			_set_tool(_prev_tool)
		return
	_stroke_tool = t
	_stroke_tile = Rules.EMPTY if button == MOUSE_BUTTON_RIGHT else tile
	match t:
		PAINT:
			_begin()
			_stroke = true
			_last_cell = c
			_paint(c)
		LINE, RECT, BOX:
			_stroke = true
			_drag_start = c
			_update_shape(c, shift)
		FILL:
			_begin()
			_fill(c)
			_end()
		SELECT:
			if button == MOUSE_BUTTON_RIGHT:
				_sel = Rect2i()
			elif _sel.has_point(c) and cur_floor >= _sel_floors.x and cur_floor <= _sel_floors.y:
				_begin()
				_moving = true
				floating = level.extract(_sel, _sel_floors.x, _sel_floors.y)
				float_floor = _sel_floors.x
				float_pos = _sel.position
				_move_grab = c - _sel.position
				if not ctrl:
					level.fill_rect(_sel, _sel_floors.x, _sel_floors.y, Rules.EMPTY)
					_changed()
			else:
				_selecting = true
				_sel_anchor = _clamp_cell(c)
				_sel = Rect2i(_sel_anchor, Vector2i.ONE)
				_sel_floors = Vector2i(0, level.floors - 1) if sel_all_floors else Vector2i(cur_floor, cur_floor)
			_grid.queue_redraw()
	_refresh_marks()


func tool_drag(c: Vector2i, shift: bool) -> void:
	if _moving:
		float_pos = c - _move_grab
	elif _selecting:
		var a := _sel_anchor
		var b := _clamp_cell(c)
		_sel = Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), (a - b).abs() + Vector2i.ONE)
	elif _stroke:
		match _stroke_tool:
			PAINT:
				for p in _line(_last_cell, c):
					var moved := _paint(p)
					c += moved
				_last_cell = c
			LINE, RECT, BOX:
				_update_shape(c, shift)
	_grid.queue_redraw()
	_refresh_marks()


func tool_release(c: Variant) -> void:
	if _moving:
		_moving = false
		var size := Vector2i(floating.w, floating.h)
		var moved := _grow_to(float_pos)
		moved += _grow_to(float_pos + size - Vector2i.ONE)
		level.stamp(floating, float_pos.x, float_pos.y, float_floor, transparent_paste)
		_sel = Rect2i(float_pos, size)
		floating = {}
		_changed()
		_end()
	elif _selecting:
		_selecting = false
	elif _stroke:
		_stroke = false
		match _stroke_tool:
			PAINT:
				_end()
			LINE, RECT, BOX:
				_begin()
				var cells := preview.duplicate()
				preview.clear()
				var off := Vector2i.ZERO
				for p: Vector2i in cells:
					off += _put(p + off, cells[p])
				_end()
	_grid.queue_redraw()
	_refresh_marks()


func _finish_stroke() -> void:
	if _stroke or _moving or _selecting:
		tool_release(hover)
	_stroke = false
	preview.clear()


func _clamp_cell(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x, 0, level.width - 1), clampi(c.y, 0, level.height - 1))


func _paint(c: Vector2i) -> Vector2i:
	var off := Vector2i.ZERO
	for p in brush_cells(c):
		off += _put(p + off, _stroke_tile)
	return off


func _fill(c: Vector2i) -> void:
	if not level.inside(c.x, c.y) or level.cell(cur_floor, c.x, c.y) == _stroke_tile:
		return
	for p in level.flood(cur_floor, c.x, c.y):
		_put(p, _stroke_tile)


func _update_shape(c: Vector2i, shift: bool) -> void:
	preview.clear()
	var a := _drag_start
	var b := c
	if shift:
		var d := b - a
		if _stroke_tool == LINE:
			# Straight across, up and down, or at 45 degrees.
			if absi(d.x) > absi(d.y) * 2:
				b.y = a.y
			elif absi(d.y) > absi(d.x) * 2:
				b.x = a.x
			else:
				var n := maxi(absi(d.x), absi(d.y))
				b = a + Vector2i(signi(d.x) * n, signi(d.y) * n)
		else:
			var n := maxi(absi(d.x), absi(d.y))
			b = a + Vector2i(n if d.x >= 0 else -n, n if d.y >= 0 else -n)
	var cells: Array[Vector2i] = []
	match _stroke_tool:
		LINE:
			for p in _line(a, b):
				cells.append_array(brush_cells(p))
		RECT, BOX:
			var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
			var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					if _stroke_tool == BOX or x == lo.x or x == hi.x or y == lo.y or y == hi.y:
						cells.append(Vector2i(x, y))
	for p in cells:
		preview[p] = _stroke_tile


## The cells on a line from `a` to `b` (Bresenham).
func _line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := (b - a).abs()
	var s := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var err := d.x - d.y
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			p.x += s.x
		if e2 < d.x:
			err += d.x
			p.y += s.y
	return out


func _stamp_floating() -> void:
	_begin()
	var size := Vector2i(floating.w, floating.h)
	_grow_to(float_pos)
	_grow_to(float_pos + size - Vector2i.ONE)
	level.stamp(floating, float_pos.x, float_pos.y, float_floor, transparent_paste)
	_changed()
	_end()


func set_hover(c: Variant) -> void:
	if c == hover:
		return
	hover = c
	if not floating.is_empty() and not _moving and c is Vector2i:
		float_pos = c - Vector2i(floating.w / 2, floating.h / 2)
	_grid.queue_redraw()
	_refresh_marks()
	_update_hover_label()


# --- selection, clipboard, transforms --------------------------------------------------

func copy_selection() -> bool:
	if _sel.size == Vector2i.ZERO:
		_say("Select something first (M)")
		return false
	_clip = level.extract(_sel, _sel_floors.x, _sel_floors.y)
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(EditLevel.buffer_text(_clip))
	_say("Copied %d x %d%s" % [_clip.w, _clip.h, " x %d floors" % _clip.f if _clip.f > 1 else ""])
	return true


func cut_selection() -> void:
	if copy_selection():
		delete_selection()


func delete_selection() -> void:
	if _sel.size == Vector2i.ZERO:
		return
	_begin()
	level.fill_rect(_sel, _sel_floors.x, _sel_floors.y, Rules.EMPTY)
	_changed()
	_end()


func paste() -> void:
	# Map text copied from elsewhere (another level, a text editor) wins over
	# the editor's own clipboard when it differs.
	var text := DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) else ""
	var buf := _clip
	if text != "" and (_clip.is_empty() or text != EditLevel.buffer_text(_clip)) and not text.begins_with("{"):
		var from_text := EditLevel.text_buffer(text)
		if not from_text.is_empty() and from_text.w <= 64 and from_text.h <= 64 and from_text.f <= 12:
			buf = from_text
	if buf.is_empty():
		_say("Nothing to paste")
		return
	floating = buf.duplicate()
	float_floor = cur_floor if buf.f == 1 else buf.base
	var at: Vector2i = hover if hover is Vector2i else Vector2i(level.width / 2, level.height / 2)
	float_pos = at - Vector2i(buf.w / 2, buf.h / 2)
	_set_tool(SELECT)
	_say("Click to paste (again and again); right-click or Esc when done")
	_grid.queue_redraw()


func select_all() -> void:
	_sel = Rect2i(0, 0, level.width, level.height)
	_sel_floors = Vector2i(0, level.floors - 1) if sel_all_floors else Vector2i(cur_floor, cur_floor)
	_set_tool(SELECT)
	_grid.queue_redraw()
	_refresh_marks()


## Flips ("h", "v") or turns ("o") the paste, the selection, or the level.
func transform(kind: String) -> void:
	var apply := func(buf: Dictionary) -> Dictionary:
		match kind:
			"h": return EditLevel.flip_buffer(buf, true)
			"v": return EditLevel.flip_buffer(buf, false)
		# On a mirrored map a quarter turn of the text looks the other way.
		return EditLevel.rotate_buffer(buf, not mirror)
	if not floating.is_empty():
		floating = apply.call(floating)
		_grid.queue_redraw()
		return
	_begin()
	if _sel.size != Vector2i.ZERO:
		var buf: Dictionary = apply.call(level.extract(_sel, _sel_floors.x, _sel_floors.y))
		level.fill_rect(_sel, _sel_floors.x, _sel_floors.y, Rules.EMPTY)
		var at := _sel.position
		var moved := _grow_to(at + Vector2i(buf.w, buf.h) - Vector2i.ONE)
		at += moved
		level.stamp(buf, at.x, at.y, _sel_floors.x, false)
		_sel = Rect2i(at, Vector2i(buf.w, buf.h))
	else:
		var old_w := level.width
		level.set_whole(apply.call(level.whole()))
		_grid.on_grown(Vector2i.ZERO, old_w)
		_fit_pending = true
	_changed()
	_end()


## Moves the selected cells one step (arrow keys).
func nudge(d: Vector2i) -> void:
	if _sel.size == Vector2i.ZERO:
		_grid.auto_fit = false
		_grid.pan -= Vector2(d) * _grid.zoom
		_grid.queue_redraw()
		return
	if mirror:
		d.x = -d.x
	_begin()
	var buf := level.extract(_sel, _sel_floors.x, _sel_floors.y)
	level.fill_rect(_sel, _sel_floors.x, _sel_floors.y, Rules.EMPTY)
	var at := _sel.position + d
	at += _grow_to(at)
	at += _grow_to(at + _sel.size - Vector2i.ONE)
	level.stamp(buf, at.x, at.y, _sel_floors.x, false)
	_sel.position = at
	_changed()
	_end()


# --- floors and size ----------------------------------------------------------------------

func change_floor(delta: int) -> void:
	set_floor(cur_floor + delta)


func set_floor(f: int) -> void:
	_finish_stroke()
	cur_floor = clampi(f, 0, level.floors - 1)
	if _sel.size != Vector2i.ZERO and not sel_all_floors:
		_sel_floors = Vector2i(cur_floor, cur_floor)
	for i in _floor_buttons.size():
		_floor_buttons[i].set_pressed_no_signal(level.floors - 1 - i == cur_floor)
	_preview.refocus()
	_grid.queue_redraw()
	_refresh_marks()
	_update_hover_label()


func _floor_op(op: String) -> void:
	_finish_stroke()
	_begin()
	match op:
		"above":
			level.insert_floor(cur_floor + 1)
			cur_floor += 1
		"below":
			level.insert_floor(cur_floor)
		"dup":
			level.duplicate_floor(cur_floor)
			cur_floor += 1
		"delete":
			level.remove_floor(cur_floor)
		"up":
			if cur_floor + 1 < level.floors:
				level.swap_floors(cur_floor, cur_floor + 1)
				cur_floor += 1
		"down":
			if cur_floor > 0:
				level.swap_floors(cur_floor, cur_floor - 1)
				cur_floor -= 1
		"clear":
			level.clear_floor(cur_floor)
	_sel = Rect2i()
	_changed()
	_end()
	_rebuild_floor_list()
	set_floor(cur_floor)


## Grows (+1) or shrinks (-1) one side, as the side is seen on the map.
func _resize_side(side: String, amount: int) -> void:
	_finish_stroke()
	if mirror and (side == "left" or side == "right"):
		side = "right" if side == "left" else "left"
	var l := amount if side == "left" else 0
	var r := amount if side == "right" else 0
	var t := amount if side == "top" else 0
	var b := amount if side == "bottom" else 0
	_begin()
	var old_w := level.width
	level.resize(l, r, t, b)
	_after_resize(Vector2i(l, t), old_w)
	_end()


func _size_op(op: String) -> void:
	_finish_stroke()
	_begin()
	var old_w := level.width
	match op:
		"crop":
			_after_resize(level.crop(), old_w)
		"walls":
			_after_resize(level.wrap_walls(cur_floor), old_w)
	_end()


func _shift(d: Vector2i) -> void:
	_finish_stroke()
	if mirror:
		d.x = -d.x
	_begin()
	var old_w := level.width
	var before := level.content_rect().position
	level.shift(d.x, d.y)
	var moved := level.content_rect().position - before - d
	_after_resize(moved, old_w)
	_end()


# --- level management -----------------------------------------------------------------

func _unique_id(base: String) -> String:
	base = _slug(base)
	var ids := {}
	for s: Dictionary in _data:
		for lv: Dictionary in s.levels:
			if lv != _entry or base == "":
				ids[lv.id] = true
	if not ids.has(base) and base != "":
		return base
	var n := 2
	while ids.has("%s_%d" % [base, n]):
		n += 1
	return "%s_%d" % [base, n]


static func _slug(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif not out.ends_with("_") and out != "":
			out += "_"
	return out.trim_suffix("_")


func _add_level(lv: Dictionary, set_i: int, at: int) -> void:
	lv._uid = _next_uid
	_next_uid += 1
	_data[set_i].levels.insert(at, lv)
	_select(set_i, at)
	_rebuild_tree()
	_meta_changed()


func new_level() -> void:
	var lv := {
		"id": "", "title": "New Level", "hint": "",
		"floors": [["*********", "*s.....g*", "*********"]],
	}
	_entry = {}
	lv.id = _unique_id("new_level")
	_add_level(lv, _set_i, _level_i + 1)
	_say("New level added after the one you were on")


func duplicate_level() -> void:
	var lv: Dictionary = Levels.normalize(_entry)
	lv.title = _entry.title + " (copy)"
	lv.erase("review")
	var keep := _entry
	_entry = {}
	lv.id = _unique_id(keep.id + "_copy")
	_add_level(lv, _set_i, _level_i + 1)


func delete_level() -> void:
	if not _confirmed("delete"):
		return
	var total := 0
	for s: Dictionary in _data:
		total += s.levels.size()
	if total <= 1:
		_say("That is the last level; make another first")
		return
	var title: String = _entry.title
	_data[_set_i].levels.remove_at(_level_i)
	if _data[_set_i].levels.is_empty():
		_select(_set_i + 1, 0)
	else:
		_select(_set_i, mini(_level_i, _data[_set_i].levels.size() - 1))
	_rebuild_tree()
	_meta_changed()
	_say("Deleted \"%s\" (Revert all brings it back until you save)" % title)


## Moves the level (or the set picked in the tree) up or down. Levels move on
## into the next set past either end of theirs.
func move_item(delta: int) -> void:
	if _tree_set >= 0:
		var to := _tree_set + delta
		if to < 0 or to >= _data.size():
			return
		var s: Dictionary = _data[_tree_set]
		_data.remove_at(_tree_set)
		_data.insert(to, s)
		if _set_i == _tree_set:
			_set_i = to
		elif _set_i == to:
			_set_i = _tree_set
		_tree_set = to
		_rebuild_tree()
		_meta_changed()
		return
	var lv: Dictionary = _data[_set_i].levels[_level_i]
	var to := _level_i + delta
	_data[_set_i].levels.remove_at(_level_i)
	if to < 0 and _set_i > 0:
		_set_i -= 1
		to = _data[_set_i].levels.size()
	elif to > _data[_set_i].levels.size() and _set_i + 1 < _data.size():
		_set_i += 1
		to = 0
	to = clampi(to, 0, _data[_set_i].levels.size())
	_data[_set_i].levels.insert(to, lv)
	_level_i = to
	_rebuild_tree()
	_fill_fields()
	_meta_changed()


func _move_to_set(set_i: int) -> void:
	if set_i == _set_i:
		return
	var lv: Dictionary = _data[_set_i].levels[_level_i]
	_data[_set_i].levels.remove_at(_level_i)
	_set_i = set_i
	_data[_set_i].levels.append(lv)
	_level_i = _data[_set_i].levels.size() - 1
	_rebuild_tree()
	_fill_fields()
	_meta_changed()
	_say("Moved to the end of %s" % _data[set_i].title)


func new_set() -> void:
	var ids := {}
	for s: Dictionary in _data:
		ids[s.id] = true
	var id := "set"
	var n := 2
	while ids.has(id):
		id = "set_%d" % n
		n += 1
	_data.append({"id": id, "title": "New Levels", "label": "New", "levels": []})
	_entry = {}
	var lv := {"id": _unique_id("new_level"), "title": "New Level", "hint": "",
		"floors": [["*********", "*s.....g*", "*********"]]}
	_add_level(lv, _data.size() - 1, 0)
	_say("New set added at the end, with one level in it")


func delete_set() -> void:
	var s_i := _tree_set if _tree_set >= 0 else _set_i
	if not _data[s_i].levels.is_empty():
		_say("Only an empty set can be deleted: move or delete its levels first")
		return
	if _data.size() <= 1:
		return
	_data.remove_at(s_i)
	_tree_set = -1
	if _set_i > s_i:
		_set_i -= 1
	_rebuild_tree()
	_meta_changed()


func copy_level_json() -> void:
	DisplayServer.clipboard_set(Levels.level_json(_entry))
	_say("Level copied to the clipboard as JSON")


## Pastes a level copied as JSON (or as map text) as a new level.
func paste_level() -> void:
	var text := DisplayServer.clipboard_get()
	var parsed: Variant = JSON.parse_string(text)
	var lv := {}
	if parsed is Dictionary and parsed.has("floors"):
		lv = Levels.normalize(parsed)
	else:
		var buf := EditLevel.text_buffer(text)
		if buf.is_empty():
			_say("The clipboard holds no level")
			return
		var e := EditLevel.new()
		e.set_whole(buf)
		lv = {"id": "pasted", "title": "Pasted Level", "hint": "", "floors": e.to_floors()}
	_entry = {}
	lv.id = _unique_id(lv.id)
	_add_level(lv, _set_i, _level_i + 1)
	_say("Pasted as a new level")


# --- save, revert, autosave ------------------------------------------------------------

func save() -> void:
	_finish_stroke()
	var errors := _id_problems()
	if errors != "":
		_say(errors, true)
		return
	_backup()
	var err := Levels.save(_data)
	if err != OK:
		_say("Could not write %s (%s)" % [Levels.PATH, error_string(err)], true)
		return
	_saved_json = Levels.to_json(_data)
	_saved_levels.clear()
	for s: Dictionary in _data:
		for lv: Dictionary in s.levels:
			_saved_levels[lv._uid] = Levels.level_json(lv)
	if FileAccess.file_exists(autosave_path):
		DirAccess.remove_absolute(autosave_path)
	_autosave_wait = -1.0
	_refresh_now()
	_say("Saved %s" % Levels.PATH)


## Problems that would make a broken level file: missing or doubled ids.
func _id_problems() -> String:
	var seen := {}
	for s: Dictionary in _data:
		for lv: Dictionary in s.levels:
			if lv.id == "":
				return "\"%s\" has no id" % lv.title
			if seen.has(lv.id):
				return "Two levels have the id \"%s\"" % lv.id
			seen[lv.id] = true
	return ""


func _backup() -> void:
	if not FileAccess.file_exists(Levels.PATH):
		return
	DirAccess.make_dir_recursive_absolute(BACKUPS)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file := FileAccess.open("%s/levels_%s.json" % [BACKUPS, stamp], FileAccess.WRITE)
	if file:
		file.store_string(FileAccess.get_file_as_string(Levels.PATH))
		file.close()
	var names := Array(DirAccess.get_files_at(BACKUPS))
	names.sort()
	while names.size() > 30:
		DirAccess.remove_absolute("%s/%s" % [BACKUPS, names.pop_front()])


func revert_level() -> void:
	if not _saved_levels.has(_uid()):
		_say("This level has never been saved; delete it instead")
		return
	var saved: Dictionary = Levels.normalize(JSON.parse_string(_saved_levels[_uid()]))
	_begin()
	level = EditLevel.from_floors(saved.floors)
	for key in ["id", "title", "hint"]:
		_entry[key] = saved[key]
	if saved.has("stack"):
		_entry.stack = saved.stack
	else:
		_entry.erase("stack")
	cur_floor = clampi(cur_floor, 0, level.floors - 1)
	_changed()
	_end()
	_fill_fields()
	_rebuild_floor_list()
	_rebuild_tree()
	_say("Level reverted to its saved state (Ctrl+Z undoes this)")


func revert_all() -> void:
	if not _confirmed("revert_all"):
		return
	var id: String = _entry.id
	_load_sets(Levels.sets())
	_select_id(id)
	if _entry.is_empty() or _entry.id != id:
		_select(0, 0)
	_rebuild_tree()
	if FileAccess.file_exists(autosave_path):
		DirAccess.remove_absolute(autosave_path)
	_say("Every level is back as last saved")


func _autosave() -> void:
	var file := FileAccess.open(autosave_path, FileAccess.WRITE)
	if file:
		file.store_string(Levels.to_json(_data))
		file.close()


func _check_autosave() -> void:
	if not FileAccess.file_exists(autosave_path):
		return
	var text := FileAccess.get_file_as_string(autosave_path)
	if text == _saved_json or Levels.parse(text).is_empty():
		DirAccess.remove_absolute(autosave_path)
		return
	_banner.show()


func _restore_autosave() -> void:
	var id: String = _entry.get("id", "")
	var sets := Levels.parse(FileAccess.get_file_as_string(autosave_path))
	var saved := _saved_levels.duplicate()
	var by_id := {}
	for s: Dictionary in _data:
		for lv: Dictionary in s.levels:
			if saved.has(lv._uid):
				by_id[lv.id] = saved[lv._uid]
	_data = sets
	_saved_levels.clear()
	_history.clear()
	for s: Dictionary in _data:
		for lv: Dictionary in s.levels:
			lv._uid = _next_uid
			_next_uid += 1
			if by_id.has(lv.id):
				_saved_levels[lv._uid] = by_id[lv.id]
	_banner.hide()
	_select_id(id)
	if _entry.is_empty() or not _entry.has("_uid"):
		_select(0, 0)
	_rebuild_tree()
	_say("Unsaved work restored. Save to keep it.")


func _discard_autosave() -> void:
	DirAccess.remove_absolute(autosave_path)
	_banner.hide()


## Some buttons want a second click within a few seconds.
func _confirmed(action: String) -> bool:
	if _confirm == action and _confirm_wait > 0.0:
		_confirm = ""
		_reset_confirm_buttons()
		return true
	_reset_confirm_buttons()
	_confirm = action
	_confirm_wait = 3.0
	if _confirm_buttons.has(action):
		_confirm_buttons[action][0].text = "Sure?"
	_say("Click again to confirm")
	return false


func _reset_confirm_buttons() -> void:
	for action: String in _confirm_buttons:
		_confirm_buttons[action][0].text = _confirm_buttons[action][1]


# --- playtest and solver ---------------------------------------------------------------

func playtest() -> void:
	_finish_stroke()
	if level.quaggle_cells().is_empty():
		_say("Place a start (s) first", true)
		return
	play_requested.emit(Levels.normalize(_entry), [])


func watch_solution() -> void:
	if _solution.is_empty() or _solve_floors != _entry.floors:
		_say("Solve the level first (F6)")
		return
	play_requested.emit(Levels.normalize(_entry), _solution)


func solve() -> void:
	_finish_stroke()
	if level.quaggle_cells().is_empty() or level.count(Rules.GOAL) == 0:
		_say("The level needs a quaggle and a goal", true)
		return
	_solve_lines = PackedStringArray()
	_solution = []
	_start_search("bfs", false, 0)


## Finds the shortest stack the level can be won with, and sets "stack".
func find_min_stack() -> void:
	_finish_stroke()
	if level.quaggle_cells().is_empty() or level.count(Rules.GOAL) == 0:
		_say("The level needs a quaggle and a goal", true)
		return
	_solve_lines = PackedStringArray()
	_min_stack = 1
	_start_search("min", false, 1)


func _start_search(phase: String, greedy: bool, max_stack: int) -> void:
	_solve_phase = phase
	_solve_floors = _entry.floors.duplicate(true)
	_solver = Solver.new(Rules.from_floors(_entry.id, _entry.floors), int(_cap_spin.value), greedy, max_stack)
	_show_solve()


func _search_done() -> void:
	var s := _solver
	_solver = null
	var stack: int = _entry.get("stack", 1)
	match _solve_phase:
		"bfs", "greedy":
			if s.state == Solver.SOLVED:
				_solution = s.path
				_solve_lines.append("[color=#6fdc8c]Solvable:[/color] %d moves%s, %d switches, tallest stack %d  [color=#8a90b8](%s states, %d ms)[/color]" % [
					s.moves, " (not the shortest)" if s.greedy else "", s.switches, s.stack, _num(s.states), s.elapsed_ms])
				if stack > 1:
					_start_search("stack", false, stack - 1)
					return
			elif s.state == Solver.CAPPED and not s.greedy:
				_solve_lines.append("[color=#8a90b8]Too big to search exhaustively (%s states); trying nearest-first.[/color]" % _num(s.states))
				_start_search("greedy", true, 0)
				return
			elif s.state == Solver.CAPPED:
				_solve_lines.append("[color=#ffcc33]Gave up after %s states.[/color] Raise the state limit and try again." % _num(s.states))
			else:
				_solve_lines.append("[color=#ff6b6b]No solution.[/color] Every reachable position was tried (%s)." % _num(s.states))
		"stack":
			if s.state == Solver.NO_SOLUTION:
				_solve_lines.append("[color=#6fdc8c]Needs a stack of %d,[/color] as marked." % stack)
			elif s.state == Solver.SOLVED:
				_solve_lines.append("[color=#ffcc33]Winnable with stacks of %d or less:[/color] \"stack\" says %d. Try Min stack." % [stack - 1, stack])
			else:
				_solve_lines.append("[color=#8a90b8]Stack check gave up after %s states.[/color]" % _num(s.states))
		"min":
			var quaggles := level.quaggle_cells().size()
			if s.state == Solver.SOLVED:
				_solution = s.path
				_set_stack(_min_stack)
				_solve_lines.append("[color=#6fdc8c]Smallest stack that wins: %d.[/color] Stack set to %d. (%d moves)" % [_min_stack, _min_stack, s.moves])
			elif s.state == Solver.NO_SOLUTION and _min_stack < quaggles:
				_solve_lines.append("Not with stacks of %d." % _min_stack)
				_min_stack += 1
				_start_search("min", false, _min_stack)
				return
			elif s.state == Solver.NO_SOLUTION:
				_solve_lines.append("[color=#ff6b6b]No solution with any stack.[/color]")
			else:
				_solve_lines.append("[color=#ffcc33]Gave up at stacks of %d after %s states.[/color]" % [_min_stack, _num(s.states)])
	_solve_phase = ""
	_show_solve()


func _set_stack(n: int) -> void:
	if n > 1:
		_entry.stack = n
	else:
		_entry.erase("stack")
	_stack_spin.set_value_no_signal(n)
	_meta_changed()


## Marks the level reviewed: "ok" (happy), "wip" (in progress) or "" (not yet).
func _set_review(r: String) -> void:
	if r == "":
		_entry.erase("review")
	else:
		_entry.review = r
	_show_review()
	_meta_changed()


func _show_review() -> void:
	for r: String in _review_buttons:
		_review_buttons[r].set_pressed_no_signal(_entry.get("review", "") == r)


func _show_solve() -> void:
	if _solve_label == null:
		return
	var text := "\n".join(_solve_lines)
	if _solver:
		var what := {"bfs": "Searching", "greedy": "Searching nearest-first", "stack": "Checking the stack",
			"min": "Trying stacks of %d" % _min_stack}
		text += ("\n" if text != "" else "") + "%s... %s states" % [what.get(_solve_phase, "Searching"), _num(_solver.states)]
	elif _solve_lines.is_empty():
		text = "[color=#8a90b8]Press Solve (F6) to find the shortest solution.[/color]"
	var stale: bool = not _solve_floors.is_empty() and _solve_floors != _entry.floors
	if stale and not _solve_lines.is_empty() and _solver == null:
		text += "\n[color=#8a90b8](The level has changed since.)[/color]"
	_solve_label.text = text
	for b in _watch_buttons:
		b.disabled = _solution.is_empty() or stale or _solver != null
	for b in _solve_buttons:
		b.disabled = _solver != null


static func _num(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(-3)
	return s + out


# --- checks ------------------------------------------------------------------------------

func _check() -> void:
	issues = []
	var add := func(lvl: String, text: String, pos: Variant = null) -> void:
		issues.append({"level": lvl, "text": text, "pos": pos})
	var qs := level.quaggle_cells()
	if qs.is_empty():
		add.call("error", "No quaggles: place a start (s).")
	var goals := level.find_all(Rules.GOAL)
	if goals.is_empty():
		add.call("error", "No goal (g).")
	elif goals.size() > 1:
		add.call("info", "%d goals: reaching any of them wins." % goals.size(), goals[1])
	var starts := level.find_all(Rules.START)
	if starts.is_empty() and not qs.is_empty():
		add.call("info", "No start (s): play begins with quaggle 0.", qs[0])
	elif starts.size() > 1:
		add.call("info", "%d starts: play begins on the first one; the rest are plain quaggles." % starts.size(), starts[1])
	var keys := level.find_all(Rules.KEY)
	var fields := level.find_all(Rules.FIELD)
	if not keys.is_empty() and fields.is_empty():
		add.call("warn", "A key, but no force field for it.", keys[0])
	if keys.is_empty() and not fields.is_empty():
		add.call("warn", "A force field, but no key: it is just a wall.", fields[0])
	for lift in level.find_all(Rules.UP):
		if lift.z == level.floors - 1:
			add.call("warn", "A lift on the top floor: it lifts into thin air.", lift)
		elif not Rules.is_air(level.cell(lift.z + 1, lift.x, lift.y)):
			add.call("warn", "Something sits right above this lift.", lift)
	var stack: int = _entry.get("stack", 1)
	if stack > qs.size():
		add.call("warn", "\"stack\" is %d but there are only %d quaggles." % [stack, qs.size()])
	var same := 0
	for s: Dictionary in _data:
		for lv: Dictionary in s.levels:
			if lv.id == _entry.id:
				same += 1
	if same > 1:
		add.call("error", "Another level already has the id \"%s\"." % _entry.id)
	if _entry.title.strip_edges() == "":
		add.call("warn", "The level has no title.")
	for f in level.floors:
		if level.floor_empty(f) and f < level.floors - 1:
			add.call("info", "Floor %d is empty." % f)
	# Quaggles numbered and coloured as the game will.
	quag_colors.clear()
	quag_ids.clear()
	var level_seed := absi(hash(_entry.id))
	for i in qs.size():
		quag_ids[qs[i]] = i
		quag_colors[qs[i]] = Quaggle.PALETTE[(level_seed + i * 3) % Quaggle.PALETTE.size()]


# --- refresh -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible or _entry.is_empty():
		return
	if _solver:
		if _solver.step(12000):
			_search_done()
		else:
			_show_solve()
	if flash_time > 0.0:
		flash_time -= delta
	if _confirm_wait > 0.0:
		_confirm_wait -= delta
		if _confirm_wait <= 0.0:
			_confirm = ""
			_reset_confirm_buttons()
	if _message_wait > 0.0:
		_message_wait -= delta
		if _message_wait <= 0.0:
			_message.text = ""
	if _autosave_wait > 0.0:
		_autosave_wait -= delta
		if _autosave_wait <= 0.0:
			_autosave()
	if _fit_pending and _grid.size.x > 10:
		_fit_pending = false
		_grid.auto_fit = true
		_grid.fit()
		_update_zoom_label()
	if _refresh_pending:
		_refresh_now()
	_preview_wait -= delta
	if _preview_pending and _preview_wait <= 0.0 and _preview.is_visible_in_tree():
		_preview_pending = false
		_preview_wait = 0.08
		_preview.show_level(Rules.from_floors(_entry.id, _entry.floors), _preview_reset)
		_preview_reset = false
		_refresh_marks()


func _queue_preview(reset: bool) -> void:
	_preview_pending = true
	_preview_reset = _preview_reset or reset


func _refresh_now() -> void:
	_refresh_pending = false
	if _entry.is_empty():
		return
	_check()
	_show_issues()
	_update_tree_labels()
	var dirty := Levels.to_json(_data) != _saved_json
	_dirty_label.text = "Unsaved changes" if dirty else "All saved"
	_dirty_label.add_theme_color_override("font_color", AMBER if dirty else GREEN)
	_save_button.text = "Save*" if dirty else "Save"
	var h := _hist()
	_undo_button.disabled = h.undo.is_empty()
	_redo_button.disabled = h.redo.is_empty()
	_size_label.text = "%d x %d, %d floor%s" % [level.width, level.height, level.floors, "" if level.floors == 1 else "s"]
	for b in _floor_list.get_children():
		b.queue_redraw()
		for child in b.get_children():
			(child as Control).queue_redraw()
	_show_solve()
	_grid.queue_redraw()


func _refresh_marks() -> void:
	if _preview == null:
		return
	var h: Variant = hover if floating.is_empty() else null
	var sel := _sel
	var floors := _sel_floors
	if not floating.is_empty():
		sel = Rect2i(float_pos, Vector2i(floating.w, floating.h))
		floors = Vector2i(float_floor, float_floor + floating.f - 1)
	_preview.show_marks(h, sel, floors)


func _say(text: String, bad := false) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", RED if bad else CREAM)
	_message_wait = 5.0


func _update_hover_label() -> void:
	if not (hover is Vector2i) or not level.inside(hover.x, hover.y):
		_hover_label.text = "Floor %d of %d" % [cur_floor, level.floors]
		return
	var c := level.cell(cur_floor, hover.x, hover.y)
	var text := "Column %d, row %d, floor %d:  %s" % [hover.x, hover.y, cur_floor, _tile_name(c)]
	var p := Vector3i(hover.x, hover.y, cur_floor)
	if quag_ids.has(p):
		text += " %d" % quag_ids[p]
	if c == Rules.EMPTY and cur_floor > 0:
		var below := level.cell(cur_floor - 1, hover.x, hover.y)
		if EditorGrid._standable(below):
			text += "  (standing on the %s below)" % _tile_name(below).to_lower()
	_hover_label.text = text


func _update_zoom_label() -> void:
	if _zoom_label:
		_zoom_label.text = "%d%%" % roundi(_grid.zoom / 32.0 * 100.0)


static func _tile_name(c: int) -> String:
	for t: Array in TILES:
		if t[0] == c:
			return t[1]
	return "'%s'" % char(c)


# --- input -------------------------------------------------------------------------------

func _set_tool(t: int) -> void:
	if t == PICK and cur_tool != PICK:
		_prev_tool = cur_tool
	if t != SELECT and not _moving:
		floating = {}
	cur_tool = t
	for k: int in _tool_buttons:
		_tool_buttons[k].set_pressed_no_signal(k == t)
	_hint_label.text = TOOLS[t][3]
	_grid.queue_redraw()


## Picks the tile to paint with; `to_paint` also leaves Select for Paint.
func _set_tile(c: int, to_paint := true) -> void:
	tile = c
	for k: int in _tile_buttons:
		_tile_buttons[k].set_pressed_no_signal(k == c)
	if to_paint and (cur_tool == SELECT or cur_tool == PICK):
		_set_tool(PAINT)


func _set_view(v: int) -> void:
	_view = v
	_grid.visible = v != VIEW_3D
	_preview.visible = v != VIEW_2D
	for i in _view_buttons.size():
		_view_buttons[i].set_pressed_no_signal(i == v)
	if _preview.visible:
		_queue_preview(false)
	_fit_pending = true


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is TextEdit
	var ctrl := k.ctrl_pressed or k.meta_pressed
	if _help.visible and not k.echo:
		_help.hide()
		accept_event()
		return
	# These work even while typing in a field.
	if ctrl and k.keycode == KEY_S:
		save()
	elif k.keycode == KEY_F5 or (ctrl and k.keycode == KEY_ENTER):
		playtest()
	elif k.keycode == KEY_F6:
		solve()
	elif k.keycode == KEY_F7:
		watch_solution()
	elif typing:
		if k.keycode == KEY_ESCAPE:
			focus.release_focus()
			accept_event()
		return
	elif ctrl:
		match k.keycode:
			KEY_Z:
				if k.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y: redo()
			KEY_C: copy_selection()
			KEY_X: cut_selection()
			KEY_V: paste()
			KEY_A: select_all()
			KEY_D:
				_sel = Rect2i()
				_grid.queue_redraw()
				_refresh_marks()
			KEY_N: new_level()
			_: return
	elif not _key(k):
		return
	accept_event()


## The editor's plain-key shortcuts. Returns whether `k` was one.
func _key(k: InputEventKey) -> bool:
	match k.keycode:
		KEY_ESCAPE:
			if not floating.is_empty() and not _moving:
				floating = {}
			elif not preview.is_empty():
				_stroke = false
				preview.clear()
			else:
				_sel = Rect2i()
			_grid.queue_redraw()
			_refresh_marks()
			return true
		KEY_DELETE, KEY_BACKSPACE:
			delete_selection()
			return true
		KEY_PAGEUP:
			change_floor(1)
			return true
		KEY_PAGEDOWN:
			change_floor(-1)
			return true
		KEY_TAB:
			_set_view((_view + 1) % 3)
			return true
		KEY_HOME:
			_grid.auto_fit = true
			_grid.fit()
			_preview.frame()
			_update_zoom_label()
			return true
		KEY_F1:
			_help.show()
			return true
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			var d := {KEY_LEFT: Vector2i(-1, 0), KEY_RIGHT: Vector2i(1, 0), KEY_UP: Vector2i(0, -1), KEY_DOWN: Vector2i(0, 1)}
			nudge(d[k.keycode])
			return true
	if k.echo:
		return false
	var ch := char(k.unicode) if k.unicode > 0 else ""
	for t: Array in TILES:
		if ch == t[2] or (t[0] == Rules.EMPTY and ch == "e"):
			_set_tile(t[0])
			return true
	match ch.to_lower():
		"b": _set_tool(PAINT)
		"l": _set_tool(LINE)
		"r": _set_tool(RECT)
		"t": _set_tool(BOX)
		"f": _set_tool(FILL)
		"i": _set_tool(PICK)
		"m": _set_tool(SELECT)
		"h": transform("h")
		"v": transform("v")
		"o": transform("o")
		"p": playtest()
		"]": change_floor(1)
		"[": change_floor(-1)
		"?": _help.show()
		"=", "+":
			_grid.zoom_by(1.2, _grid.size * 0.5)
			_update_zoom_label()
		"-":
			_grid.zoom_by(1.0 / 1.2, _grid.size * 0.5)
			_update_zoom_label()
		_: return false
	return true


## For screenshots from the command line (see main.gd).
func debug_command(command: String) -> void:
	match command:
		"2d": _set_view(VIEW_2D)
		"3d": _set_view(VIEW_3D)
		"split": _set_view(VIEW_SPLIT)
		"help": _help.show()
		"solve": solve()
		"watch":
			solve()
			while _solver:
				_solver.run()
				_search_done()
			watch_solution()
		"play": playtest()
		"select": select_all()
		"up": change_floor(1)


# --- UI ----------------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.theme_type_variation = "EdBackground"
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	margin.add_child(root)

	root.add_child(_build_top_bar())
	_banner = _build_banner()
	root.add_child(_banner)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_left())
	var middle_and_right := HSplitContainer.new()
	middle_and_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(middle_and_right)
	middle_and_right.add_child(_build_middle())
	middle_and_right.add_child(_build_right())

	root.add_child(_build_status_bar())
	_help = _build_help()
	add_child(_help)
	_set_tool(PAINT)
	_set_tile(Rules.WALL)
	_set_view(VIEW_SPLIT)


func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.add_child(_btn("Menu", func() -> void:
		_finish_stroke()
		close_requested.emit(), "Back to the main menu. Unsaved work stays here (and is autosaved)."))
	var title := Label.new()
	title.text = "Level Editor"
	title.theme_type_variation = "EdTitle"
	bar.add_child(title)
	bar.add_child(_gap(12))
	_undo_button = _btn("Undo", undo, "Ctrl+Z")
	_redo_button = _btn("Redo", redo, "Ctrl+Y")
	bar.add_child(_undo_button)
	bar.add_child(_redo_button)
	bar.add_child(_gap(12))
	_save_button = _btn("Save", save, "Ctrl+S: write every level to %s" % Levels.PATH)
	_save_button.theme_type_variation = "EdPrimary"
	bar.add_child(_save_button)
	bar.add_child(_btn("Revert level", revert_level, "Put this level back as last saved"))
	bar.add_child(_confirm_btn("revert_all", "Revert all", revert_all, "Throw away every unsaved change"))
	bar.add_child(_gap(12))
	var play := _btn("Playtest", playtest, "F5 or P: play this level now")
	play.theme_type_variation = "EdPrimary"
	bar.add_child(play)
	var s := _btn("Solve", solve, "F6: search for the shortest solution")
	_solve_buttons.append(s)
	bar.add_child(s)
	var w := _btn("Watch", watch_solution, "F7: play the solution back")
	_watch_buttons.append(w)
	bar.add_child(w)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_message = Label.new()
	_message.clip_text = true
	_message.custom_minimum_size.x = 80
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_message)
	_dirty_label = Label.new()
	bar.add_child(_dirty_label)
	bar.add_child(_btn("?", func() -> void: _help.show(), "F1: keys and mouse"))
	return bar


func _build_banner() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "EdBanner"
	var row := HBoxContainer.new()
	panel.add_child(row)
	var text := Label.new()
	text.text = "There is unsaved work from an earlier session."
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	row.add_child(_btn("Restore it", _restore_autosave))
	row.add_child(_btn("Discard it", _discard_autosave))
	panel.hide()
	return panel


func _build_left() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 230
	box.add_child(_header("Levels"))
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter by title or id"
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t: String) -> void: _rebuild_tree())
	box.add_child(_filter)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.focus_mode = Control.FOCUS_CLICK
	_tree.item_selected.connect(_on_tree_selected)
	box.add_child(_tree)
	var row := HBoxContainer.new()
	row.add_child(_btn("New", new_level, "Ctrl+N: a new level after this one"))
	row.add_child(_btn("Copy", duplicate_level, "Duplicate this level"))
	row.add_child(_confirm_btn("delete", "Delete", delete_level, "Delete this level"))
	box.add_child(row)
	row = HBoxContainer.new()
	row.add_child(_btn("Move up", move_item.bind(-1), "Move the level (or the set picked in the list) earlier"))
	row.add_child(_btn("Move down", move_item.bind(1), "Move it later"))
	box.add_child(row)

	box.add_child(_header("Set"))
	_set_title = LineEdit.new()
	_set_title.placeholder_text = "Set title (menu button)"
	_set_title.text_changed.connect(func(t: String) -> void:
		_data[_tree_set if _tree_set >= 0 else _set_i].title = t
		_rebuild_tree.call_deferred()
		_meta_changed())
	box.add_child(_labelled("Title", _set_title))
	_set_label = LineEdit.new()
	_set_label.placeholder_text = "Short label (in-game status)"
	_set_label.text_changed.connect(func(t: String) -> void:
		_data[_tree_set if _tree_set >= 0 else _set_i].label = t
		_meta_changed())
	box.add_child(_labelled("Label", _set_label))
	row = HBoxContainer.new()
	row.add_child(_btn("New set", new_set, "A new set at the end, with one level"))
	row.add_child(_btn("Delete set", delete_set, "Delete the set (only once it is empty)"))
	box.add_child(row)
	return box


func _build_middle() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.x = 420

	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 4)
	tools.add_theme_constant_override("v_separation", 4)
	var group := ButtonGroup.new()
	for t: Array in TOOLS:
		var b := _toggle(t[1], false, func(_on: bool) -> void: _set_tool(t[0]), "%s (%s)\n%s" % [t[1], t[2], t[3]])
		b.button_group = group
		_tool_buttons[t[0]] = b
		tools.add_child(b)
	tools.add_child(_gap(8))
	var brush_group := ButtonGroup.new()
	for n in [1, 2, 3]:
		var b := _toggle("%dx" % n, n == 1, func(_on: bool) -> void: brush = n, "Brush size for Paint and Line")
		b.button_group = brush_group
		_brush_buttons.append(b)
		tools.add_child(b)
	tools.add_child(_gap(8))
	tools.add_child(_toggle("Mirror X", false, func(on: bool) -> void: sym_x = on, "Paint mirrored across the level"))
	tools.add_child(_toggle("Mirror Y", false, func(on: bool) -> void: sym_y = on, "Paint mirrored up and down the level"))
	tools.add_child(_toggle("Sel. all floors", false, func(on: bool) -> void: sel_all_floors = on,
		"New selections take in every floor, to move or copy whole stacks"))
	tools.add_child(_toggle("Paste over", false, func(on: bool) -> void: transparent_paste = on,
		"Pasting and moving leave what is under empty cells alone"))
	box.add_child(tools)

	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 4)
	var view_group := ButtonGroup.new()
	for i in 3:
		var b := _toggle(["2D", "Split", "3D"][i], i == VIEW_SPLIT, func(_on: bool) -> void: _set_view(i), "Tab cycles the views")
		b.button_group = view_group
		_view_buttons.append(b)
		views.add_child(b)
	views.add_child(_gap(8))
	views.add_child(_toggle("Grid", true, func(on: bool) -> void:
		show_grid = on
		_grid.queue_redraw()))
	views.add_child(_toggle("Below", true, func(on: bool) -> void:
		ghost_below = on
		_grid.queue_redraw(), "Show the floor below through empty cells. Outlined cells are solid there: you can stand on them."))
	views.add_child(_toggle("Above", true, func(on: bool) -> void:
		ghost_above = on
		_grid.queue_redraw(), "Outline what is on the floor above"))
	views.add_child(_toggle("Game view", true, func(on: bool) -> void:
		var old_w := level.width
		mirror = on
		_grid.on_grown(Vector2i.ZERO, old_w)
		_fit_pending = true, "Draw the map the way round the game camera first sees it (the level file reads mirrored)"))
	views.add_child(_toggle("Cutaway", true, func(on: bool) -> void:
		cutaway = on
		_preview.refocus(), "In 3D, hide the floors above the one being edited"))
	views.add_child(_btn("Fit", func() -> void:
		_grid.auto_fit = true
		_grid.fit()
		_preview.frame()
		_update_zoom_label(), "Home: fit the map in view"))
	box.add_child(views)

	_split = HSplitContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_split)
	_grid = EditorGrid.new()
	_grid.editor = self
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.size_flags_stretch_ratio = 1.2
	_grid.custom_minimum_size = Vector2(200, 200)
	_grid.resized.connect(func() -> void: _update_zoom_label())
	_split.add_child(_grid)
	_preview = EditorPreview.new()
	_preview.editor = self
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(200, 200)
	_split.add_child(_preview)
	return box


func _build_right() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	box.add_child(_header("Tiles"))
	var tiles := GridContainer.new()
	tiles.columns = 2
	tiles.add_theme_constant_override("h_separation", 4)
	tiles.add_theme_constant_override("v_separation", 4)
	var group := ButtonGroup.new()
	for t: Array in TILES:
		var b := _toggle("%s   %s" % [t[1], t[2]], false, func(_on: bool) -> void: _set_tile(t[0]), t[3])
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.theme_type_variation = "EdTile"
		var swatch := Swatch.new()
		swatch.cell = t[0]
		swatch.position = Vector2(5, 4)
		swatch.size = Vector2(22, 22)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(swatch)
		_tile_buttons[t[0]] = b
		tiles.add_child(b)
	box.add_child(tiles)

	box.add_child(_header("Level"))
	_title_edit = LineEdit.new()
	_title_edit.text_changed.connect(func(t: String) -> void:
		_entry.title = t
		_meta_changed())
	box.add_child(_labelled("Title", _title_edit))
	_id_edit = LineEdit.new()
	_id_edit.tooltip_text = "Used for saved progress; lowercase letters, digits and _"
	_id_edit.text_submitted.connect(func(_t: String) -> void: _commit_id())
	_id_edit.focus_exited.connect(_commit_id)
	var id_row := HBoxContainer.new()
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(_id_edit)
	id_row.add_child(_btn("From title", func() -> void:
		_id_edit.text = _unique_id(_entry.title)
		_commit_id(), "Make the id from the title"))
	box.add_child(_labelled("Id", id_row))
	_hint_edit = TextEdit.new()
	_hint_edit.custom_minimum_size.y = 64
	_hint_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_hint_edit.placeholder_text = "Shown at the bottom while playing (optional)"
	_hint_edit.text_changed.connect(func() -> void:
		_entry.hint = _hint_edit.text.replace("\n", " ")
		_meta_changed())
	box.add_child(_labelled("Hint", _hint_edit))
	_stack_spin = SpinBox.new()
	_stack_spin.min_value = 1
	_stack_spin.max_value = 12
	_stack_spin.tooltip_text = "The tallest stack of quaggles the level cannot be won without (1: none). The tests check it."
	_stack_spin.value_changed.connect(func(v: float) -> void: _set_stack(int(v)))
	var stack_row := HBoxContainer.new()
	stack_row.add_child(_stack_spin)
	var min_button := _btn("Find", find_min_stack, "Search for the smallest stack the level can be won with, and set it")
	_solve_buttons.append(min_button)
	stack_row.add_child(min_button)
	box.add_child(_labelled("Stack", stack_row))
	var review_row := HBoxContainer.new()
	for r: Array in [["ok", "✓  Happy", "Totally happy with this level"], ["wip", "?  In progress", "Still working on this level"]]:
		var b := _toggle(r[1], false, func(on: bool) -> void: _set_review(r[0] if on else ""), r[2] + " (click again to clear)")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_review_buttons[r[0]] = b
		review_row.add_child(b)
	box.add_child(_labelled("Review", review_row))
	_set_option = OptionButton.new()
	_set_option.focus_mode = Control.FOCUS_NONE
	_set_option.item_selected.connect(_move_to_set)
	_set_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_labelled("In set", _set_option))
	var row := HBoxContainer.new()
	row.add_child(_btn("Copy as JSON", copy_level_json, "Copy this level to the clipboard"))
	row.add_child(_btn("Paste as new", paste_level, "Make a new level from JSON or map text on the clipboard"))
	box.add_child(row)

	box.add_child(_header("Floors"))
	_floor_list = VBoxContainer.new()
	_floor_list.add_theme_constant_override("separation", 3)
	box.add_child(_floor_list)
	var ops := GridContainer.new()
	ops.columns = 4
	ops.add_theme_constant_override("h_separation", 4)
	for op: Array in [["+ Above", "above", "Add an empty floor above this one"], ["+ Below", "below", "Add an empty floor below this one"],
			["Copy", "dup", "Duplicate this floor above itself"], ["Clear", "clear", "Empty this floor"],
			["Raise", "up", "Swap with the floor above"], ["Lower", "down", "Swap with the floor below"],
			["Delete", "delete", "Remove this floor"]]:
		var b := _btn(op[0], _floor_op.bind(op[1]), op[2])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ops.add_child(b)
	box.add_child(ops)

	box.add_child(_header("Size"))
	_size_label = Label.new()
	box.add_child(_size_label)
	var sides := GridContainer.new()
	sides.columns = 6
	sides.add_theme_constant_override("h_separation", 4)
	for side: String in ["left", "right", "top", "bottom"]:
		var name := Label.new()
		name.text = side.capitalize()
		name.custom_minimum_size.x = 52
		sides.add_child(name)
		sides.add_child(_btn("-", _resize_side.bind(side, -1), "Remove a column or row on this side"))
		sides.add_child(_btn("+", _resize_side.bind(side, 1), "Add a column or row on this side"))
	box.add_child(sides)
	row = HBoxContainer.new()
	row.add_child(_btn("Crop", _size_op.bind("crop"), "Trim empty rows and columns off every side"))
	row.add_child(_btn("Wall in", _size_op.bind("walls"), "Put walls round everything on this floor"))
	box.add_child(row)
	row = HBoxContainer.new()
	var shift_label := Label.new()
	shift_label.text = "Shift"
	row.add_child(shift_label)
	for d: Array in [["Left", Vector2i(-1, 0)], ["Right", Vector2i(1, 0)], ["Up", Vector2i(0, -1)], ["Down", Vector2i(0, 1)]]:
		row.add_child(_btn(d[0], _shift.bind(d[1]), "Move everything one cell"))
	box.add_child(row)
	row = HBoxContainer.new()
	row.add_child(_btn("Flip across", transform.bind("h"), "H: flip the selection (or the level) left to right"))
	row.add_child(_btn("Flip up-down", transform.bind("v"), "V: flip top to bottom"))
	row.add_child(_btn("Turn", transform.bind("o"), "O: a quarter turn clockwise"))
	box.add_child(row)

	box.add_child(_header("Solver"))
	_solve_label = RichTextLabel.new()
	_solve_label.bbcode_enabled = true
	_solve_label.fit_content = true
	_solve_label.scroll_active = false
	_solve_label.custom_minimum_size.x = 260
	box.add_child(_solve_label)
	row = HBoxContainer.new()
	var s := _btn("Solve", solve, "F6")
	_solve_buttons.append(s)
	row.add_child(s)
	var w := _btn("Watch", watch_solution, "F7: play the solution back in the game")
	_watch_buttons.append(w)
	row.add_child(w)
	_cap_spin = SpinBox.new()
	_cap_spin.min_value = 10000
	_cap_spin.max_value = 5000000
	_cap_spin.step = 10000
	_cap_spin.value = 300000
	_cap_spin.tooltip_text = "How many positions to try before giving up"
	row.add_child(_cap_spin)
	box.add_child(row)

	box.add_child(_header("Checks"))
	_issue_list = VBoxContainer.new()
	box.add_child(_issue_list)
	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.custom_minimum_size.x = 260
	_stats_label.theme_type_variation = "EdDim"
	box.add_child(_stats_label)
	return scroll


func _build_status_bar() -> Control:
	var bar := HBoxContainer.new()
	_hover_label = Label.new()
	_hover_label.custom_minimum_size.x = 420
	bar.add_child(_hover_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = "EdDim"
	_hint_label.clip_text = true
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_hint_label)
	_zoom_label = Label.new()
	_zoom_label.theme_type_variation = "EdDim"
	bar.add_child(_zoom_label)
	return bar


func _build_help() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(DEEP, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			dim.hide())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "EdPopup"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Level editor keys"
	title.theme_type_variation = "EdTitle"
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	for pair: Array in SHORTCUTS:
		var k := Label.new()
		k.text = pair[0]
		k.add_theme_color_override("font_color", AMBER)
		grid.add_child(k)
		var v := Label.new()
		v.text = pair[1]
		grid.add_child(v)
	box.add_child(grid)
	var tips := Label.new()
	tips.text = "Painting past the edge of the map grows the level. The floor below shows through empty cells;\n" \
		+ "outlined ones are solid there, so a quaggle can stand on them. Quaggles are numbered and coloured as in the game."
	tips.theme_type_variation = "EdDim"
	box.add_child(tips)
	var close := Label.new()
	close.text = "Click or press any key to close"
	close.theme_type_variation = "EdDim"
	close.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(close)
	dim.hide()
	return dim


func _fill_fields() -> void:
	if _title_edit == null or _entry.is_empty():
		return
	_title_edit.text = _entry.title
	_id_edit.text = _entry.id
	_hint_edit.text = _entry.hint
	_stack_spin.set_value_no_signal(_entry.get("stack", 1))
	_show_review()
	_set_option.clear()
	for s: Dictionary in _data:
		_set_option.add_item(s.title)
	_set_option.select(_set_i)
	var s_i := _tree_set if _tree_set >= 0 else _set_i
	_set_title.text = _data[s_i].title
	_set_label.text = _data[s_i].get("label", "")


func _commit_id() -> void:
	var id := _id_edit.text.strip_edges()
	if id == _entry.id:
		return
	if id != _slug(id) or id == "":
		_say("Ids are lowercase letters, digits and _", true)
		_id_edit.text = _entry.id
		return
	for s: Dictionary in _data:
		for lv: Dictionary in s.levels:
			if lv != _entry and lv.id == id:
				_say("Another level already has the id \"%s\"" % id, true)
				_id_edit.text = _entry.id
				return
	_entry.id = id
	_meta_changed()
	_rebuild_tree()


func _rebuild_tree() -> void:
	if _tree == null or _data.is_empty():
		return
	_tree.clear()
	var root := _tree.create_item()
	var filter := _filter.text.strip_edges().to_lower()
	for s in _data.size():
		var set_item := _tree.create_item(root)
		set_item.set_text(0, "%s  (%d)" % [_data[s].title, _data[s].levels.size()])
		set_item.set_custom_color(0, AMBER)
		set_item.set_metadata(0, [s, -1])
		if _tree_set == s:
			set_item.select(0)
		for l in _data[s].levels.size():
			var lv: Dictionary = _data[s].levels[l]
			if filter != "" and not (lv.title.to_lower().contains(filter) or lv.id.contains(filter)):
				continue
			var item := _tree.create_item(set_item)
			item.set_metadata(0, [s, l])
			if s == _set_i and l == _level_i and _tree_set < 0:
				item.select(0)
				_scroll_tree.call_deferred()
	_update_tree_labels()
	_fill_fields()


## Brings the selected level into view. Deferred, after the tree has its
## size; it looks the item up then, since the tree may be rebuilt meanwhile.
func _scroll_tree() -> void:
	var item := _tree.get_selected()
	if item:
		_tree.scroll_to_item(item)


func _update_tree_labels() -> void:
	if _tree == null or _tree.get_root() == null:
		return
	for set_item in _tree.get_root().get_children():
		for item in set_item.get_children():
			var at: Array = item.get_metadata(0)
			if at[0] >= _data.size() or at[1] >= _data[at[0]].levels.size():
				continue  # the tree is about to be rebuilt
			var lv: Dictionary = _data[at[0]].levels[at[1]]
			var changed: bool = not _saved_levels.has(lv._uid) or _saved_levels[lv._uid] != Levels.level_json(lv)
			var mark: String = {"ok": "✓  ", "wip": "?  "}.get(lv.get("review", ""), "")
			item.set_text(0, "%s%d.  %s%s" % [mark, at[1] + 1, lv.title, "  *" if changed else ""])
			item.set_tooltip_text(0, "%s%s" % [lv.id, " (unsaved changes)" if changed else ""])
			item.set_custom_color(0, AMBER.lightened(0.3) if changed else CREAM)


func _on_tree_selected() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var at: Array = item.get_metadata(0)
	if at[1] < 0:
		_tree_set = at[0]
		_set_title.text = _data[at[0]].title
		_set_label.text = _data[at[0]].get("label", "")
		return
	if at[0] == _set_i and at[1] == _level_i and _tree_set < 0:
		return
	_select(at[0], at[1])
	_fill_fields()


func _rebuild_floor_list() -> void:
	if _floor_list == null:
		return
	for child in _floor_list.get_children():
		child.queue_free()
	_floor_buttons.clear()
	for i in level.floors:
		var f := level.floors - 1 - i
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 54)
		b.text = "Floor %d%s" % [f, "  (top)" if f == level.floors - 1 and f > 0 else ""]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = "EdFloor"
		b.button_pressed = f == cur_floor
		b.pressed.connect(set_floor.bind(f))
		var thumb := FloorThumb.new()
		thumb.editor = self
		thumb.floor_index = f
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		thumb.offset_left = -130
		thumb.offset_right = -6
		thumb.offset_top = 4
		thumb.offset_bottom = -4
		b.add_child(thumb)
		_floor_list.add_child(b)
		_floor_buttons.append(b)


func _show_issues() -> void:
	for child in _issue_list.get_children():
		child.queue_free()
	if issues.is_empty():
		var ok := Label.new()
		ok.text = "Nothing looks wrong."
		ok.add_theme_color_override("font_color", GREEN)
		_issue_list.add_child(ok)
	for issue: Dictionary in issues:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 260
		b.text = {"error": "Error: ", "warn": "Warning: ", "info": "Note: "}[issue.level] + issue.text
		var col: Color = {"error": RED, "warn": Color("ffcc33"), "info": Color("a9b4e8")}[issue.level]
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(state, col)
		var pos: Variant = issue.get("pos")
		if pos is Vector3i:
			b.tooltip_text = "Show me"
			b.pressed.connect(func() -> void:
				set_floor(pos.z)
				flash_cell = pos
				flash_time = 1.6)
		_issue_list.add_child(b)
	var counts := PackedStringArray()
	for t: Array in TILES:
		var n := level.count(t[0])
		if n > 0 and t[0] != Rules.EMPTY:
			counts.append("%d %s" % [n, t[1].to_lower()])
	_stats_label.text = "%d quaggles.  %s." % [level.quaggle_cells().size(), ", ".join(counts)]


# --- widgets -------------------------------------------------------------------------------

func _btn(text: String, action: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(func() -> void: action.call())
	return b


func _confirm_btn(action: String, text: String, callback: Callable, tip := "") -> Button:
	var b := _btn(text, callback, tip + " (click twice)")
	_confirm_buttons[action] = [b, text]
	return b


func _toggle(text: String, on: bool, action: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.toggled.connect(func(pressed: bool) -> void: action.call(pressed))
	return b


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "EdHeader"
	return l


func _labelled(text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 52
	l.theme_type_variation = "EdDim"
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _gap(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = w
	return c


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = 13
	var box := func(bg: Color, border := Color(0, 0, 0, 0), radius := 6, pad := 6) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		if border.a > 0:
			s.set_border_width_all(1)
		s.set_corner_radius_all(radius)
		s.content_margin_left = pad + 2
		s.content_margin_right = pad + 2
		s.content_margin_top = pad - 2
		s.content_margin_bottom = pad - 2
		return s
	var base := Color("2a3360")
	t.set_stylebox("normal", "Button", box.call(base))
	t.set_stylebox("hover", "Button", box.call(base.lightened(0.15)))
	t.set_stylebox("pressed", "Button", box.call(AMBER))
	t.set_stylebox("hover_pressed", "Button", box.call(AMBER.lightened(0.15)))
	t.set_stylebox("disabled", "Button", box.call(Color(base, 0.45)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", NAVY)
	t.set_color("font_hover_pressed_color", "Button", NAVY)
	t.set_color("font_focus_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", Color(CREAM, 0.35))
	for v: Array in [["EdPrimary", AMBER, NAVY], ["EdTile", base, CREAM], ["EdFloor", base, CREAM]]:
		t.set_type_variation(v[0], "Button")
	t.set_stylebox("normal", "EdPrimary", box.call(AMBER))
	t.set_stylebox("hover", "EdPrimary", box.call(AMBER.lightened(0.2)))
	t.set_stylebox("pressed", "EdPrimary", box.call(AMBER.darkened(0.15)))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "EdPrimary", NAVY)
	var tile_box: StyleBoxFlat = box.call(base)
	tile_box.content_margin_left = 34
	t.set_stylebox("normal", "EdTile", tile_box)
	var tile_hover: StyleBoxFlat = tile_box.duplicate()
	tile_hover.bg_color = base.lightened(0.15)
	t.set_stylebox("hover", "EdTile", tile_hover)
	var tile_on: StyleBoxFlat = tile_box.duplicate()
	tile_on.bg_color = AMBER
	t.set_stylebox("pressed", "EdTile", tile_on)
	t.set_stylebox("hover_pressed", "EdTile", tile_on)
	var floor_on: StyleBoxFlat = box.call(Color(AMBER, 0.9))
	t.set_stylebox("pressed", "EdFloor", floor_on)
	t.set_stylebox("hover_pressed", "EdFloor", floor_on)

	var field: StyleBoxFlat = box.call(DEEP, Color("3a4580"), 5, 6)
	var field_focus: StyleBoxFlat = box.call(DEEP, AMBER, 5, 6)
	for kind in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", kind, field)
		t.set_stylebox("focus", kind, field_focus)
		t.set_stylebox("read_only", kind, field)
		t.set_color("font_color", kind, CREAM)
		t.set_color("font_placeholder_color", kind, Color(CREAM, 0.35))
		t.set_color("caret_color", kind, AMBER)
		t.set_color("selection_color", kind, Color(AMBER, 0.35))
	t.set_stylebox("panel", "Tree", box.call(DEEP, Color("3a4580"), 6, 4))
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("selected", "Tree", box.call(Color(AMBER, 0.3), Color(0, 0, 0, 0), 4, 2))
	t.set_stylebox("selected_focus", "Tree", box.call(Color(AMBER, 0.4), Color(0, 0, 0, 0), 4, 2))
	t.set_color("font_color", "Tree", CREAM)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_color("guide_color", "Tree", Color(1, 1, 1, 0.05))
	t.set_constant("v_separation", "Tree", 3)
	t.set_stylebox("panel", "PopupMenu", box.call(NAVY, Color("3a4580")))
	t.set_stylebox("hover", "PopupMenu", box.call(Color(AMBER, 0.85)))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", NAVY)
	t.set_stylebox("panel", "TooltipPanel", box.call(NAVY, AMBER, 5, 8))
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_color("font_color", "Label", CREAM)
	t.set_color("default_color", "RichTextLabel", CREAM)
	t.set_constant("separation", "HBoxContainer", 4)
	t.set_constant("separation", "VBoxContainer", 4)

	t.set_type_variation("EdBackground", "Panel")
	t.set_stylebox("panel", "EdBackground", box.call(NAVY, Color(0, 0, 0, 0), 0))
	t.set_type_variation("EdBanner", "PanelContainer")
	t.set_stylebox("panel", "EdBanner", box.call(Color("4a3a20"), AMBER, 6, 8))
	t.set_type_variation("EdPopup", "PanelContainer")
	var popup: StyleBoxFlat = box.call(Color(NAVY, 0.98), Color(CREAM, 0.3), 16, 22)
	popup.shadow_color = Color(0, 0, 0, 0.5)
	popup.shadow_size = 20
	t.set_stylebox("panel", "EdPopup", popup)
	t.set_type_variation("EdHeader", "Label")
	t.set_font("font", "EdHeader", TITLE_FONT)
	t.set_font_size("font_size", "EdHeader", 16)
	t.set_color("font_color", "EdHeader", AMBER)
	t.set_type_variation("EdTitle", "Label")
	t.set_font("font", "EdTitle", TITLE_FONT)
	t.set_font_size("font_size", "EdTitle", 20)
	t.set_color("font_color", "EdTitle", AMBER)
	t.set_type_variation("EdDim", "Label")
	t.set_color("font_color", "EdDim", Color("a9b4e8"))
	return t


## A tile drawn as on the map, for the palette.
class Swatch extends Control:
	var cell := Rules.EMPTY

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("10152a"))
		if cell == Rules.EMPTY:
			draw_line(Vector2(4, size.y - 4), Vector2(size.x - 4, 4), Color("ff6b6b"), 2.0)
		else:
			EditorGrid.draw_tile(self, r, cell, 0)


## A small picture of one floor, for the floor list.
class FloorThumb extends Control:
	var editor: LevelEditor
	var floor_index := 0

	func _draw() -> void:
		var lv := editor.level
		var cs := minf(size.x / lv.width, size.y / lv.height)
		var origin := (size - Vector2(lv.width, lv.height) * cs) * 0.5
		draw_rect(Rect2(origin, Vector2(lv.width, lv.height) * cs), Color("10152a"))
		for y in lv.height:
			for x in lv.width:
				var c := lv.cell(floor_index, x, y)
				if c != Rules.EMPTY:
					var col := lv.width - 1 - x if editor.mirror else x
					EditorGrid.draw_tile(self, Rect2(origin + Vector2(col, y) * cs, Vector2(cs, cs)), c, floor_index)
