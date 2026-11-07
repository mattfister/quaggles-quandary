extends SceneTree
## Headless water checks:
## godot --headless --path . -s tests/test_water.gd

var failures := 0


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
	flow()
	pools()
	print("FAILURES: %d" % failures)
	quit(1 if failures else 0)


func flow() -> void:
	var r := Rules.from_floors("flow", [["~....."]])
	var w := Water.compute(r)
	check(w.kind_at(Vector3i(0, 0, 0)) == Water.SOURCE, "a spring is a source")
	check(w.level_at(Vector3i(1, 0, 0)) == 3 and w.level_at(Vector3i(3, 0, 0)) == 1, "flow weakens a step per cell")
	check(w.kind_at(Vector3i(4, 0, 0)) == Water.NONE, "flow reaches three cells")

	r = Rules.from_floors("walls", [["~*.", ".w."]])
	w = Water.compute(r)
	check(w.kind_at(Vector3i(2, 0, 0)) == Water.NONE and w.kind_at(Vector3i(2, 1, 0)) == Water.NONE,
		"walls and glass keep water out")

	r = Rules.from_floors("ledge", [["...."], ["~.  "]])
	w = Water.compute(r)
	check(w.kind_at(Vector3i(2, 0, 1)) == Water.FALL, "water falls off a ledge")
	check(w.level_at(Vector3i(2, 0, 0)) == 4 and w.level_at(Vector3i(3, 0, 0)) == 3, "it lands at full strength")
	check(w.is_base(Vector3i(2, 0, 0)), "where it lands is the waterfall's base")

	r = Rules.from_floors("void", [["~.  "]])
	w = Water.compute(r)
	check(w.kind_at(Vector3i(2, 0, 0)) == Water.FALL and w.kind_at(Vector3i(3, 0, 0)) == Water.NONE,
		"water falls into the void")


func pools() -> void:
	# A pit two deep, walled in up to floor 1; the spring sits on floor 2.
	var r := Rules.from_floors("pit", [
		["****", "*..*", "****"],
		["****", "*  *", "****"],
		["~   ", "    ", "    "],
	])
	var w := Water.compute(r)
	check(w.kind_at(Vector3i(2, 1, 0)) == Water.POOL and w.kind_at(Vector3i(2, 1, 1)) == Water.POOL,
		"falling water fills an enclosed pit")
	check(w.kind_at(Vector3i(2, 1, 2)) == Water.FLOW, "the pool stops at its rim")
	check(w.level_at(Vector3i(3, 1, 2)) == 3, "and flows on over it")

	# Walls rise above the spring: the pool fills only to the level the
	# water fell from.
	r = Rules.from_floors("deep pit", [
		["****", "*.**", "****"],
		["****", "* ~*", "****"],
		["****", "*  *", "****"],
	])
	w = Water.compute(r)
	check(w.kind_at(Vector3i(1, 1, 1)) == Water.POOL, "the pool rises to the level the water fell from")
	check(w.kind_at(Vector3i(1, 1, 2)) == Water.NONE, "but no higher")
	check(w.kind_at(Vector3i(2, 1, 1)) == Water.SOURCE, "a spring in a pool stays a spring")
