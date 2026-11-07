extends SceneTree
## Headless checks: godot --headless -s tests/test_rules.gd [-- solve ...]
## Rule unit checks, a load check and random play of every level, and (with
## "solve") a breadth-first search proving levels can be won, and that the
## ones marked as needing a tall stack cannot be won without it.

const DIRS := Solver.DIRS

var failures := 0

## Two levels from the original, kept here so the checks below do not depend
## on levels.json. Stepping Stone (level1): a gap at x 11 on floor 1, a
## helper quaggle and cracked tiles on floor 0.
const STEPPING_STONE := [
	["         *************", "         *...........*", "         *...........*", "         *...........*",
		"         *...........*", "         *...........*", "         *......14444*", "         *************"],
	["**********************", "*.......... .........*", "*s......... .....g...*", "*.......... .........*",
		"**********************"],
]
## Burnt Bridge (level3): a wall of fire before the gap on floor 1.
const BURNT_BRIDGE := [
	["         *************", "         *...........*", "         *...........*", "         *...........*",
		"         *...........*", "         *...........*", "         *......1....*", "         *************"],
	["**********************", "*.........X .........*", "*s........X .....g...*", "*s........X .........*",
		"**********************"],
]


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## Moves quaggle `id` once per letter of `steps`: l, r, u, d in map columns
## and rows.
func walk(r: Rules, id: int, steps: String) -> void:
	const STEP := {"l": Vector2i(-1, 0), "r": Vector2i(1, 0), "u": Vector2i(0, -1), "d": Vector2i(0, 1)}
	for ch in steps:
		r.active = id
		r.try_move(STEP[ch].x, STEP[ch].y)


func _init() -> void:
	var ids: Array[String] = []
	for level: Dictionary in Levels.all():
		ids.append(level.id)
		var loaded := Rules.load_level(level.id)
		check(loaded != null and not loaded.quaggles.is_empty(), "%s loads with a quaggle" % level.id)
		check(loaded.grid.has(Rules.GOAL), "%s has a goal" % level.id)

	# level1: s at (1,2) floor 1, helper at (16,6) floor 0, gap column x=11, goal (17,2).
	var r := Rules.from_floors("level1", STEPPING_STONE)
	check(r.quaggles.size() == 2, "level1 has two quaggles")
	var top: int = 0 if r.quaggles[0].pos.z == 1 else 1
	r.active = top
	check(not r.try_move(-1, 0), "wall blocks")
	for i in 9:
		r.try_move(1, 0)
	check(r.quaggles[top].pos == Vector3i(10, 2, 1), "walked to the edge")
	var snap := r.snapshot()
	r.try_move(1, 0)
	check(r.quaggles[top].pos == Vector3i(11, 2, 0), "fell through the gap to floor 0")
	r.restore(snap)
	check(r.quaggles[top].pos == Vector3i(10, 2, 1), "undo restores position")
	# Bring the helper under the gap, then walk across its head.
	r.active = 1 - top
	for i in 4:
		r.try_move(0, -1)
	for i in 5:
		r.try_move(-1, 0)
	check(r.quaggles[1 - top].pos == Vector3i(11, 2, 0), "helper is under the gap")
	r.active = top
	r.try_move(1, 0)
	check(r.quaggles[top].pos == Vector3i(11, 2, 1), "stands on the helper's head")
	# Carrying: the helper moves and the rider goes with it.
	r.active = 1 - top
	r.try_move(0, 1)
	check(r.quaggles[top].pos == Vector3i(11, 3, 1), "rider is carried")
	r.active = top
	for i in 6:
		r.try_move(1, 0)
	r.try_move(0, -1)
	check(r.won, "level1 can be won by hand")

	# Cracked tiles crumble behind you; fire kills and goes out.
	r = Rules.from_floors("level1", STEPPING_STONE)
	r.active = 0 if r.quaggles[0].pos.z == 0 else 1
	r.try_move(1, 0)
	r.try_move(1, 0)
	check(r.cell(0, 17, 6) == Rules.EMPTY, "cracked tile crumbled")
	r = Rules.from_floors("level3", BURNT_BRIDGE)
	var walker := -1
	for q in r.quaggles:
		if q.pos == Vector3i(1, 2, 1):
			walker = q.id
	check(walker >= 0 and r.active == walker, "level3 starts on the first 's' quaggle")
	for i in 8:
		r.try_move(1, 0)
	check(r.quaggles[walker].pos == Vector3i(9, 2, 1), "walked up to the fire")
	r.try_move(1, 0)
	check(r.quaggles[walker].gone, "fire kills")
	check(r.cell(1, 10, 2) == Rules.GROUND, "fire is put out")
	check(r.active != walker and not r.lost, "control passes to a survivor")

	# The original recursed forever when a quaggle standing on a wall top
	# bumped into something.
	r = Rules.from_floors("bump", [[" * "], ["s *"]])
	r.try_move(1, 0)
	check(r.quaggles[0].pos == Vector3i(1, 0, 1), "stands on a wall top")
	check(not r.try_move(1, 0), "bumping a wall from a wall top is just blocked")

	# You cannot walk off into nothing, but ice will slide you off.
	r = Rules.from_floors("edge", [["s.xx"]])
	check(not r.try_move(-1, 0) and not r.try_move(0, 1), "cannot walk off the edge")
	walk(r, 0, "rr")
	check(r.quaggles[0].gone and r.lost, "ice slides you off the edge")
	r = Rules.from_floors("ledge", [["  ."], ["s. "]])
	walk(r, 0, "rr")
	check(r.quaggles[0].pos == Vector3i(2, 0, 0), "walking off a ledge onto a floor below is fine")

	# A key switches off the first force field its carrier walks into, for
	# everyone, and is spent. A quaggle carries one key at a time.
	r = Rules.from_floors("field", [["s.3.3", "122.."]])
	walk(r, 0, "rr")
	check(r.quaggles[0].pos == Vector3i(1, 0, 0), "a field blocks without a key")
	walk(r, 1, "r")
	check(r.quaggles[1].key and r.cell(0, 1, 1) == Rules.GROUND, "picks up a key")
	walk(r, 1, "r")
	check(r.cell(0, 2, 1) == Rules.KEY, "a second key stays put while one is carried")
	walk(r, 1, "u")
	check(r.quaggles[1].pos == Vector3i(2, 0, 0), "walks into a field with a key")
	check(not r.quaggles[1].key and r.cell(0, 2, 0) == Rules.GROUND, "the field is gone and the key spent")
	walk(r, 1, "r")
	check(not r.try_move(1, 0), "the spent key opens no more fields")
	r = Rules.from_floors("field floor", [["3."], [" s"]])
	walk(r, 0, "l")
	check(r.quaggles[0].pos == Vector3i(0, 0, 1), "a field holds up whoever stands on it")

	# Stacks of any height. A lift raises a whole stack, and from the lift top
	# the stack can step onto another head: that builds a tower.
	r = Rules.from_floors("tower", [["s.u", "11."]])
	walk(r, 0, "rr")
	check(r.quaggles[0].pos == Vector3i(2, 0, 1), "lift raises a quaggle")
	walk(r, 2, "r")
	walk(r, 0, "d")
	check(r.quaggles[0].pos == Vector3i(2, 1, 1) and r.riders(r.quaggles[2]) == 1, "steps from the lift top onto a head")
	walk(r, 2, "u")
	check(r.quaggles[2].pos == Vector3i(2, 0, 1) and r.quaggles[0].pos == Vector3i(2, 0, 2), "lift raises a stack of two")
	walk(r, 1, "rr")
	walk(r, 2, "d")
	check(r.riders(r.quaggles[1]) == 2, "stack of three")
	walk(r, 1, "u")
	check(r.quaggles[0].pos == Vector3i(2, 0, 3), "lift raises a stack of three")
	walk(r, 1, "l")
	check(r.quaggles[1].pos == Vector3i(1, 0, 0) and r.quaggles[0].pos == Vector3i(1, 0, 2),
		"a stack of three steps off the lift and lands still stacked")
	walk(r, 1, "l")
	check(r.quaggles[0].pos == Vector3i(0, 0, 2), "a stack of three is carried")

	# A stack slides across ice together.
	r = Rules.from_floors("ice stack", [["s11xxx."]])
	r.quaggles[1].pos = Vector3i(0, 0, 1)
	r.quaggles[2].pos = Vector3i(0, 0, 2)
	walk(r, 0, "rrr")
	check(r.quaggles[0].pos == Vector3i(6, 0, 0) and r.quaggles[2].pos == Vector3i(6, 0, 2), "a stack slides together")
	var glides := [0, 0, 0]
	for e in r.events:
		if e.type == "move" and e.glide:
			glides[e.id] += 1
	check(glides == [3, 3, 3], "riders slide in step with their carrier")

	# A wall at the rider's height scrapes it off; a floor there takes it.
	r = Rules.from_floors("scrape", [["s1...."], ["   *"]])
	r.quaggles[1].pos = Vector3i(0, 0, 1)
	walk(r, 0, "rrr")
	check(r.quaggles[0].pos == Vector3i(3, 0, 0) and r.quaggles[1].pos == Vector3i(2, 0, 0), "a wall scrapes the rider off")
	r = Rules.from_floors("deliver", [["s1..."], ["   .."]])
	r.quaggles[1].pos = Vector3i(0, 0, 1)
	walk(r, 0, "rrrr")
	check(r.quaggles[0].pos == Vector3i(4, 0, 0) and r.quaggles[1].pos == Vector3i(3, 0, 1), "a rider is set down on the floor above")

	# The level file survives a round trip through the editor's writer.
	var text := FileAccess.get_file_as_string(Levels.PATH)
	check(Levels.to_json(Levels.parse(text)) == text, "levels.json is in the layout Levels.to_json() writes")

	# Random play must never hang or error.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2007
	for l in ids:
		for attempt in 10:
			var fuzz := Rules.load_level(l)
			for i in 300:
				if fuzz.won or fuzz.lost:
					break
				if rng.randf() < 0.2:
					fuzz.cycle_active()
				var dir: Vector2i = DIRS[rng.randi() % 4]
				fuzz.try_move(dir.x, dir.y)

	# `-- solve [set or level id ...] [path] [greedy] [cap=N]` checks that the
	# chosen levels (all of them by default) can be won, and that the ones
	# marked "stack": N cannot be won without a stack N quaggles tall.
	var args := OS.get_cmdline_user_args()
	if args.has("solve"):
		var chosen := Array(args.slice(args.find("solve") + 1))
		var show_path := chosen.has("path")
		var greedy := chosen.has("greedy")
		var cap := 400000
		for a: String in chosen.duplicate():
			if a.begins_with("cap="):
				cap = int(a.trim_prefix("cap="))
				chosen.erase(a)
		chosen.erase("path")
		chosen.erase("greedy")
		for level_set: Dictionary in Levels.sets():
			for level: Dictionary in level_set.levels:
				if not (chosen.is_empty() or chosen.has(level.id) or chosen.has(level_set.id)):
					continue
				solve(level.id, cap, show_path, greedy)
				var need: int = level.get("stack", 1)
				if need > 1:
					var found := solve(level.id, cap, false, false, need - 1)
					check(found == NO_SOLUTION, "%s needs a stack of %d (%s)" % [
						level.id, need, "search cap reached" if found == CAPPED else "solved without"])

	print("FAILURES: %d" % failures)
	quit(1 if failures else 0)


const NO_SOLUTION := -1
const CAPPED := -2


## Searches for the shortest solution (see Solver); returns its length, or
## NO_SOLUTION / CAPPED.
func solve(level: String, cap: int, show_path: bool, greedy := false, max_stack := 0) -> int:
	const NAMES := {Vector2i(0, -1): "up", Vector2i(1, 0): "left", Vector2i(0, 1): "down", Vector2i(-1, 0): "right"}  # as seen on screen
	var label := level if max_stack == 0 else "%s (stacks <= %d)" % [level, max_stack]
	var solver := Solver.new(Rules.load_level(level), cap, greedy, max_stack)
	match solver.run():
		Solver.SOLVED:
			print("%-26s %3d moves, %2d switches, stack %d%s (%d states, %d ms)" % [label, solver.moves,
				solver.switches, solver.stack, " (not shortest)" if greedy else "",
				solver.states, solver.elapsed_ms])
			if show_path:
				var steps := PackedStringArray()
				for m: Array in solver.path:
					steps.append("%d%s" % [m[0], NAMES[Vector2i(m[1], m[2])]])
				print("    ", " ".join(steps))
			return solver.moves
		Solver.CAPPED:
			if not greedy and max_stack == 0:
				print("%-26s too big for breadth-first (%d states); trying greedy" % [label, solver.states])
				return solve(level, cap, show_path, true)
			print("%-26s search cap reached (%d states)" % [label, solver.states])
			return CAPPED
	if max_stack == 0:
		print("%-26s NO SOLUTION (%d states)" % [label, solver.states])
		failures += 1
	else:
		print("%-26s no solution, as intended (%d states)" % [label, solver.states])
	return NO_SOLUTION
