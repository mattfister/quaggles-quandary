extends Node
## Headless checks of the level editor: godot --headless tests/test_editor.tscn
## (a scene rather than -s, so that the Sfx autoload the World uses exists).
## Drives the editor the way the mouse and keys do, on levels of its own held
## in memory: it never saves, and never touches the real autosave.

var failures := 0

## The levels the editor checks below are written against, whatever has
## become of the real ones since.
const FIXTURE := [
	{"id": "a", "title": "A", "label": "A", "levels": [
		{"id": "intro_walk", "title": "First Steps", "hint": "", "floors": [
			["*******", "*s....*", "*****.*", "    *.*", "    *g*", "    ***"]]},
		{"id": "intro_key", "title": "Lock and Key", "hint": "", "floors": [["*********", "*2..s.3g*", "*********"]]},
	]},
	{"id": "b", "title": "B", "label": "B", "levels": [
		{"id": "step_stool", "title": "Step Stool", "hint": "", "stack": 2, "floors": [
			["s1.u", "....", "...."], ["", "", "g"]]},
	]},
]


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func click(e: LevelEditor, c: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	e.tool_press(c, button, false, false, false)
	e.tool_release(c)


func drag(e: LevelEditor, a: Vector2i, b: Vector2i, shift := false) -> void:
	e.tool_press(a, MOUSE_BUTTON_LEFT, shift, false, false)
	e.tool_drag(b, shift)
	e.tool_release(b)


func _ready() -> void:
	# Every level survives the editor's map conversion unchanged.
	for lv: Dictionary in Levels.all():
		var a := EditLevel.from_floors(lv.floors)
		var b := EditLevel.from_floors(a.to_floors())
		var same := a.width == b.width and a.height == b.height and a.floors == b.floors and a.grid == b.grid
		var r1 := Rules.from_floors(lv.id, lv.floors)
		var r2 := Rules.from_floors(lv.id, a.to_floors())
		for f in r1.floors:
			for y in r1.height:
				for x in r1.width:
					same = same and r1.cell(f, x, y) == r2.cell(f, x, y)
		check(same, "%s survives EditLevel" % lv.id)

	Levels.replace(FIXTURE)  # in memory only
	var e := LevelEditor.new()
	e.autosave_path = "user://test_editor_autosave.json"
	add_child(e)
	e.show()
	e.open("intro_walk")
	check(e._entry.id == "intro_walk", "opens the asked-for level")
	check(e.level.width == 7 and e.level.height == 6, "intro_walk is 7 x 6")
	check(Levels.to_json(e._data) == e._saved_json, "nothing is unsaved on opening")

	# Paint, undo, redo.
	e._set_tile(Rules.ICE)
	e._set_tool(LevelEditor.PAINT)
	click(e, Vector2i(2, 1))
	check(e.level.cell(0, 2, 1) == Rules.ICE, "paints a cell")
	check(e._entry.floors[0][1] == "*sx...*", "writes the map back to the level")
	click(e, Vector2i(2, 1), MOUSE_BUTTON_RIGHT)
	check(e.level.cell(0, 2, 1) == Rules.EMPTY, "right button erases")
	e.undo()
	check(e.level.cell(0, 2, 1) == Rules.ICE, "undo")
	e.undo()
	check(e.level.cell(0, 2, 1) == Rules.GROUND, "undo again")
	e.redo()
	check(e.level.cell(0, 2, 1) == Rules.ICE, "redo")
	e.undo()

	# A painted stroke is one undo step and fills the gaps between samples.
	e._set_tile(Rules.WALL)
	e.tool_press(Vector2i(0, 5), MOUSE_BUTTON_LEFT, false, false, false)
	e.tool_drag(Vector2i(3, 5), false)
	e.tool_release(Vector2i(3, 5))
	check(e.level.cell(0, 1, 5) == Rules.WALL and e.level.cell(0, 2, 5) == Rules.WALL, "a stroke leaves no gaps")
	e.undo()
	check(e.level.cell(0, 1, 5) == Rules.EMPTY, "a stroke undoes in one step")

	# Painting outside the map grows it, keeping the cells where they were.
	var start_at := e.level.find_all(Rules.START)[0]
	click(e, Vector2i(-2, -1))
	check(e.level.width == 9 and e.level.height == 7, "painting outside grows the map")
	check(e.level.find_all(Rules.START)[0] == start_at + Vector3i(2, 1, 0), "old cells moved with the growth")
	check(e.level.cell(0, 0, 0) == Rules.WALL, "the new cell is painted")
	e.undo()
	check(e.level.width == 7, "undo shrinks it back")

	# Shapes.
	e._set_tool(LevelEditor.RECT)
	e._set_tile(Rules.GROUND)
	drag(e, Vector2i(0, 0), Vector2i(3, 2))
	check(e.level.cell(0, 1, 1) == Rules.START and e.level.cell(0, 3, 0) == Rules.GROUND, "rect draws an outline only")
	e.undo()
	e._set_tool(LevelEditor.BOX)
	drag(e, Vector2i(0, 0), Vector2i(2, 1))
	check(e.level.cell(0, 1, 1) == Rules.GROUND, "box fills")
	e.undo()
	e._set_tool(LevelEditor.LINE)
	drag(e, Vector2i(0, 3), Vector2i(3, 4), true)
	check(e.level.cell(0, 3, 3) == Rules.GROUND and e.level.cell(0, 3, 4) == Rules.EMPTY, "shift keeps a line straight")
	e.undo()
	e._set_tool(LevelEditor.FILL)
	e._set_tile(Rules.ICE)
	click(e, Vector2i(5, 3))
	check(e.level.cell(0, 5, 1) == Rules.ICE and e.level.cell(0, 2, 1) == Rules.ICE and e.level.cell(0, 1, 1) == Rules.START,
		"fill takes the joined floor only")
	e.undo()

	# Pick.
	e._set_tool(LevelEditor.PICK)
	click(e, Vector2i(5, 4))
	check(e.tile == Rules.GOAL and e.cur_tool == LevelEditor.FILL, "pick takes the tile and goes back to the last tool")

	# Select, move, copy, paste, transforms.
	e._set_tool(LevelEditor.SELECT)
	drag(e, Vector2i(4, 3), Vector2i(6, 5))
	check(e.selection_rect() == Rect2i(4, 3, 3, 3), "select")
	drag(e, Vector2i(5, 4), Vector2i(5, 3))
	check(e.level.cell(0, 5, 3) == Rules.GOAL and e.level.cell(0, 5, 5) == Rules.EMPTY, "drag moves the selection")
	check(e.selection_rect() == Rect2i(4, 2, 3, 3), "the selection moves with it")
	e.undo()
	check(e.level.cell(0, 5, 4) == Rules.GOAL, "undo puts it back")
	check(e.selection_rect().size == Vector2i.ZERO, "undo drops the selection")
	drag(e, Vector2i(4, 3), Vector2i(6, 5))
	check(e.copy_selection(), "copy")
	e.hover = Vector2i(1, 1)
	e.paste()
	check(not e.floating.is_empty(), "paste floats the copy")
	e.float_pos = Vector2i(0, 0)
	click(e, Vector2i(1, 1))
	check(e.level.cell(0, 1, 1) == Rules.GOAL, "click stamps it")
	e._key(_key_event(KEY_ESCAPE))
	check(e.floating.is_empty(), "Esc stops pasting")
	e.undo()
	var before := e.level.snapshot()
	e._sel = Rect2i()
	for i in 4:
		e.transform("o")
	check(e.level.grid == before.grid and e.level.width == 7, "four quarter turns change nothing")
	e.transform("o")
	check(e.level.width == 6 and e.level.height == 7, "a quarter turn swaps width and height")
	e.undo()
	e.transform("h")
	e.transform("h")
	check(e.level.grid == before.grid, "two flips change nothing")
	e._sel = Rect2i(1, 1, 2, 1)
	e._sel_floors = Vector2i(0, 0)
	e.transform("h")
	check(e.level.cell(0, 2, 1) == Rules.START, "flips just the selection")
	e.nudge(Vector2i(0, 1))
	check(e.level.cell(0, 2, 2) == Rules.START, "arrow keys nudge the selection (down)")
	e._sel = Rect2i()
	e.undo()
	e.undo()

	# Floors and size.
	e._floor_op("above")
	check(e.level.floors == 2 and e.cur_floor == 1, "add a floor above")
	e._set_tool(LevelEditor.PAINT)
	e._set_tile(Rules.GROUND)
	click(e, Vector2i(3, 3))
	check(e._entry.floors[1][3] == "   .", "paints on the upper floor")
	e._floor_op("down")
	check(e.cur_floor == 0 and e.level.cell(0, 3, 3) == Rules.GROUND, "floors swap")
	e._floor_op("delete")
	check(e.level.floors == 1, "delete a floor")
	for i in 4:
		e.undo()
	check(e._entry.floors == Levels.find("intro_walk").floors, "floor edits undo")
	e._resize_side("top", 1)
	check(e.level.height == 7 and e.level.cell(0, 1, 2) == Rules.START, "grow the top")
	e._size_op("crop")
	check(e.level.height == 6, "crop trims the empty row")
	e._shift(Vector2i(0, 1))
	check(e.level.height == 7 and e.level.cell(0, 1, 2) == Rules.START, "shift down grows to keep everything")
	e.undo()
	e.undo()
	e.undo()
	check(e._entry.floors == Levels.find("intro_walk").floors, "everything undone")

	# Symmetry.
	e.sym_x = true
	e._set_tile(Rules.FIRE)
	click(e, Vector2i(1, 1))
	check(e.level.cell(0, 5, 1) == Rules.FIRE, "mirror painting")
	e.sym_x = false
	e.undo()

	# Level management.
	var count := Levels.all().size()
	e.new_level()
	check(e._entry.id == "new_level" and e._data[0].levels[1] == e._entry, "new level after the current one")
	e.duplicate_level()
	check(e._entry.id == "new_level_copy", "duplicate gets its own id")
	e.delete_level()
	e.delete_level()
	check(e._entry.id != "new_level_copy", "delete (on the second click)")
	e._select_id("new_level")
	e.move_item(-1)
	check(e._data[0].levels[0].id == "new_level", "move up")
	e._move_to_set(1)
	check(e._data[1].levels[-1].id == "new_level" and e._set_i == 1, "move to another set")
	e._commit_id()
	e._id_edit.text = "intro_walk"
	e._commit_id()
	check(e._entry.id == "new_level", "refuses a duplicate id")
	e.revert_all()
	e.revert_all()
	var total := 0
	for s: Dictionary in e._data:
		total += s.levels.size()
	check(total == count and Levels.to_json(e._data) == e._saved_json, "revert all")

	# Solver: the solution it finds wins the level.
	e._select_id("step_stool")
	e.find_min_stack()
	while e._solver:
		e._solver.run()
		e._search_done()
	check(e._entry.get("stack", 1) == 2, "finds the smallest stack (2)")
	e.solve()
	while e._solver:
		e._solver.run()
		e._search_done()
	check(not e._solution.is_empty(), "solves step_stool")
	var r := Rules.from_floors(e._entry.id, e._entry.floors)
	for m: Array in e._solution:
		r.active = m[0]
		r.try_move(m[1], m[2])
	check(r.won, "the solution wins")
	check(e._solve_lines[-1].contains("Needs a stack of 2"), "checks the stack too")

	# Review marks: toggled in the panel, shown in the tree, kept in the file.
	e._select_id("intro_key")
	e._review_buttons["wip"].button_pressed = true
	check(e._entry.get("review") == "wip", "marks a level in progress")
	e._review_buttons["ok"].button_pressed = true
	check(e._entry.get("review") == "ok" and not e._review_buttons["wip"].button_pressed, "one review mark at a time")
	e._rebuild_tree()
	var marked := e._tree.get_root().get_child(0).get_child(1)
	check(marked.get_text(0).begins_with("✓"), "the tree shows the mark")
	check(not e._tree.get_root().get_child(0).get_child(0).get_text(0).begins_with("✓"), "unreviewed levels have no mark")
	check(Levels.parse(Levels.to_json(e._data))[0].levels[1].get("review") == "ok", "the mark survives the file")
	e._review_buttons["ok"].button_pressed = false
	check(not e._entry.has("review"), "clicking again clears the mark")
	e.revert_all()
	e.revert_all()

	# Checks.
	e._select_id("intro_key")
	e._set_tool(LevelEditor.PAINT)
	e._set_tile(Rules.GROUND)
	click(e, Vector2i(1, 1))
	e._check()
	var warned := false
	for issue: Dictionary in e.issues:
		warned = warned or issue.text.contains("no key")
	check(warned, "warns of a force field without a key")
	e.revert_all()
	e.revert_all()

	# The level file text has no editor bookkeeping in it.
	check(not Levels.to_json(e._data).contains("_uid"), "uids stay out of the file")
	check(EditLevel.text_buffer(EditLevel.buffer_text(e.level.whole())).cells == e.level.whole().cells, "map text round trip")

	# A wall under a floor tile is cut short so their tops do not flicker, and
	# topped up again when a cracked tile on it crumbles.
	var w := World.new()
	add_child(w)
	var rw := Rules.from_floors("cap", [[".*."], ["s4."]])
	w.build(rw)
	var short := 0
	for mmi in w._floors[0].get_children():
		if mmi is MultiMeshInstance3D and is_equal_approx(mmi.multimesh.mesh.size.y, World.LOW):
			short += 1
	check(short == 1, "the wall under the cracked tile is cut short")
	rw.try_move(1, 0)
	rw.try_move(1, 0)
	var capped := false
	for ev: Dictionary in rw.events:
		if ev.type == "cell":
			w._apply_cell(ev, w._gen)
	for n in w._floors[0].get_children():
		capped = capped or (n is MeshInstance3D and is_equal_approx(n.mesh.size.y, World.TILE_T))
	check(capped, "a cap tops the wall up once the cracked tile crumbles")

	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures else 0)


func _key_event(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k
