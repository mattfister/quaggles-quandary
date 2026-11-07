extends SceneTree
## Headless water checks:
## godot --headless --path . -s tests/test_water.gd

var failures := 0

## A two-wide pit (x 2-3, row 1) walled up to floor 1. The spring on floor 2
## (0, 1) is held back by a quaggle (id 2) at (1, 1, 2); glass walls the
## channel, with a nook at (1, 0, 2) to step aside into. Quaggles 0 and 1
## start on the pit floor.
## A pit three wide (x 2-4, row 1) that the spring on floor 1 pours into
## at x 2. Quaggles 0 and 1 start on floor 1's row 2.
const POOL := [
	["******", "**...*", "******"],
	["~     ", "      ", "s1    "],
]
const FLOOD := [
	["*****", "**s1*", "*****"],
	["*****", "**  *", "*****"],
	["w.www", "~1   ", "wwwww"],
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
	flow()
	pools()
	dams()
	rules_water()
	swimming()
	floating()
	existing_levels()
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

	r = Rules.from_floors("curb", [["~.^.."]])
	w = Water.compute(r)
	check(w.kind_at(Vector3i(1, 0, 0)) == Water.FLOW and w.kind_at(Vector3i(2, 0, 0)) == Water.NONE
		and w.kind_at(Vector3i(3, 0, 0)) == Water.NONE, "a curb keeps flowing water out")

	r = Rules.from_floors("puddle", [[".^."], ["~  "]])
	w = Water.compute(r)
	check(w.kind_at(Vector3i(1, 0, 0)) == Water.FLOW and w.kind_at(Vector3i(2, 0, 0)) == Water.NONE,
		"water falling onto a curb stays there")

	# A pit (x 1-3) with a curb in the middle, which a spring on floor 2
	# pours into at x 3.
	r = Rules.from_floors("sunk curb", [
		["*****", "*.^.*", "*****"],
		["*****", "*   *", "*****"],
		["   ~ ", "     ", "     "]])
	w = Water.compute(r)
	check(w.is_deep(Vector3i(1, 1, 0)) and w.is_deep(Vector3i(2, 1, 0)), "a pool rises over a curb")


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
	check(w.kind_at(Vector3i(2, 1, 1)) == Water.POOL, "a spring under a pool is pool too")


func dams() -> void:
	var r := Rules.from_floors("dam", [["~.1..", "  ."]])
	check(Water.compute(r).kind_at(Vector3i(3, 0, 0)) == Water.NONE, "a quaggle dams the flow")
	r.quaggles[0].pos = Vector3i(2, 1, 0)
	check(Water.compute(r).kind_at(Vector3i(3, 0, 0)) == Water.FLOW, "moved aside, it lets the water through")

	r = Rules.from_floors("flood", FLOOD)
	r.quaggles[1].pos = Vector3i(2, 1, 1)
	check(Water.compute(r).kind_at(Vector3i(3, 1, 0)) == Water.NONE, "the dam keeps the pit dry")
	r.quaggles[2].pos = Vector3i(1, 0, 2)
	var w := Water.compute(r)
	check(w.kind_at(Vector3i(2, 1, 0)) == Water.POOL and w.kind_at(Vector3i(2, 1, 1)) == Water.POOL,
		"released, the water fills the pit around the stack")
	# The stack afloat: its rider stands in the stream that fills the pit.
	r.quaggles[0].pos = Vector3i(2, 1, 1)
	r.quaggles[1].pos = Vector3i(2, 1, 2)
	w = Water.compute(r)
	check(w.kind_at(Vector3i(3, 1, 1)) == Water.POOL and w.kind_at(Vector3i(4, 1, 2)) == Water.FLOW,
		"a stack afloat does not dam the water that floats it")


func rules_water() -> void:
	check(Rules.from_floors("dry", [["s."]]).water == null, "no water work without a spring")

	var r := Rules.from_floors("dam", [["~.1..", "  ."]])
	check(r.water.kind_at(Vector3i(3, 0, 0)) == Water.NONE, "loads with the water dammed")
	var snap := r.snapshot()
	walk(r, 0, "d")
	check(r.water.kind_at(Vector3i(3, 0, 0)) == Water.FLOW, "moving the dam lets the water through")
	check(r.events.any(func(e: Dictionary) -> bool: return e.type == "water"), "the move has a water event")
	r.restore(snap)
	check(r.water.kind_at(Vector3i(3, 0, 0)) == Water.NONE, "undo puts the water back")

	r = Rules.from_floors("douse", [["~.1X", "  . "]])
	check(r.cell(0, 3, 0) == Rules.FIRE, "the dam keeps the fire dry")
	walk(r, 0, "d")
	check(r.cell(0, 3, 0) == Rules.GROUND, "water puts the fire out")
	check(r.events.any(func(e: Dictionary) -> bool: return e.type == "cell" and e.id == -1 and e.was == Rules.FIRE),
		"with a cell event that belongs to no quaggle")

	r = Rules.from_floors("field", [["~3.", "12 "]])
	walk(r, 0, "rud")
	check(r.water.kind_at(Vector3i(2, 0, 0)) == Water.FLOW, "a keyed force field lets the water through")


func swimming() -> void:
	var r := Rules.from_floors("plug", [["s~..."]])
	check(r.water.kind_at(Vector3i(3, 0, 0)) == Water.FLOW, "a spring flows")
	walk(r, 0, "r")
	check(r.quaggles[0].pos == Vector3i(1, 0, 0), "a spring can be stood on")
	check(r.water.kind_at(Vector3i(1, 0, 0)) == Water.NONE and r.water.kind_at(Vector3i(2, 0, 0)) == Water.NONE,
		"standing on a spring stops it up")
	r = Rules.from_floors("swim on a spring", [
		["****", "*.**", "****"],
		["****", "* ~*", "****"],
		["****", "*  *", "****"],
	])
	r.quaggles.append({"id": 0, "pos": Vector3i(2, 1, 1), "dead": false, "gone": false, "key": false})
	r.restore(r.snapshot())
	check(r.water.kind_at(Vector3i(1, 1, 0)) == Water.POOL, "swimming over a spring under a pool does not stop it")

	r = Rules.from_floors("slide in", [["******", "**...*", "******"], ["~     ", "sx    ", "      "]])
	walk(r, 0, "r")
	check(r.quaggles[0].pos == Vector3i(2, 1, 0) and not r.quaggles[0].gone, "a slide off a ledge ends swimming in the pool")

	# Quaggle 0 on the rim at (1, 1, 1) with quaggle 1 on its head.
	r = Rules.from_floors("pool", POOL)
	r.quaggles[0].pos = Vector3i(1, 1, 1)
	r.quaggles[1].pos = Vector3i(1, 1, 2)
	r.restore(r.snapshot())
	walk(r, 0, "r")
	check(r.quaggles[0].pos == Vector3i(1, 1, 1), "a stack cannot drop into deep water")
	walk(r, 1, "r")
	check(r.quaggles[1].pos == Vector3i(2, 1, 0), "a lone quaggle drops in and swims")
	walk(r, 0, "r")
	check(r.quaggles[0].pos == Vector3i(2, 1, 1), "a swimmer's head is a stepping stone")
	walk(r, 1, "r")
	check(r.quaggles[1].pos == Vector3i(2, 1, 0), "a swimmer with someone on its head is stuck")
	walk(r, 0, "rr")
	walk(r, 1, "r")
	check(r.quaggles[0].pos == Vector3i(4, 1, 0) and r.quaggles[1].pos == Vector3i(3, 1, 0),
		"and free once they go")

	r = Rules.from_floors("base", [["...s"], ["~.  "]])
	walk(r, 0, "l")
	check(r.quaggles[0].pos == Vector3i(3, 0, 0), "a waterfall's base cannot be walked into")
	# A spring on floor 1 pours onto quaggle 0's head; the water spreads and
	# spills down all round it.
	r = Rules.from_floors("drenched", [[".....", "..s..", "....."], ["     ", "~.   ", "     "]])
	check(r.water.is_base(Vector3i(3, 1, 0)), "water spilling off a head makes waterfalls round it")
	walk(r, 0, "r")
	check(r.quaggles[0].pos == Vector3i(3, 1, 0), "a quaggle under a waterfall can walk out through it")
	walk(r, 0, "l")
	check(r.quaggles[0].pos == Vector3i(3, 1, 0), "but cannot walk back into it")
	# Springs at (3, 0, 1) and (4, 0, 1): the first pours onto quaggle 0's
	# head, and the fall to its right is fed by both.
	r = Rules.from_floors("shared fall", [["   **  ", "...s..."], ["   ~~  ", "       "]])
	check(r.water.is_base(Vector3i(4, 1, 0)) and r.water.is_base(Vector3i(2, 1, 0)), "falls both sides")
	walk(r, 0, "r")
	check(r.quaggles[0].pos == Vector3i(3, 1, 0), "no stepping out into a fall other water feeds too")
	walk(r, 0, "l")
	check(r.quaggles[0].pos == Vector3i(2, 1, 0), "but into one fed only off its head")
	# A pit (x 1-3) two floors deep with a floor-2 tile over its left end:
	# quaggle 0 starts under it.
	r = Rules.from_floors("ceiling", [
		["*****", "*s1.*", "*****"],
		["*****", "*   *", "*****"],
		["   ~ ", " .   ", "     "]])
	check(r.quaggles[0].pos == Vector3i(1, 1, 0) and r.quaggles[1].pos == Vector3i(2, 1, 1),
		"rising water lifts no one up against a floor")
	walk(r, 1, "l")
	check(r.quaggles[1].pos == Vector3i(2, 1, 1), "no swimming in under a floor")
	walk(r, 1, "r")
	walk(r, 0, "r")
	check(r.quaggles[0].pos == Vector3i(2, 1, 1), "the one held under swims out and comes up")
	r = Rules.from_floors("curb walk", [["sx^."]])
	walk(r, 0, "r")
	check(r.quaggles[0].pos == Vector3i(2, 0, 0), "a slide stops on a curb, as on floor")
	walk(r, 0, "r")
	check(r.quaggles[0].pos == Vector3i(3, 0, 0), "and quaggles step off it")
	r = Rules.from_floors("curtain", [["~. s"]])
	walk(r, 0, "l")
	check(r.quaggles[0].pos == Vector3i(3, 0, 0), "a waterfall over nothing holds no one up")

func floating() -> void:
	var r := Rules.from_floors("flood", FLOOD)
	r.quaggles[1].pos = Vector3i(2, 1, 1)
	r.restore(r.snapshot())
	walk(r, 2, "u")
	check(r.quaggles[0].pos == Vector3i(2, 1, 1) and r.quaggles[1].pos == Vector3i(2, 1, 2),
		"a flooded pit floats the stack up")
	check(r.events.any(func(e: Dictionary) -> bool: return e.get("float", false)), "floating moves are marked")
	walk(r, 0, "r")
	check(r.quaggles[0].pos == Vector3i(2, 1, 1), "the swimmer under the rider is stuck")
	walk(r, 1, "r")
	check(r.quaggles[1].pos == Vector3i(3, 1, 1), "the rider steps off into the pool and swims")


## Every level loads, with water just where it has a spring, and random play
## neither errors nor hangs.
func existing_levels() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2007
	const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for level: Dictionary in Levels.all():
		var r := Rules.load_level(level.id)
		check(r != null and (r.water != null) == r.grid.has(Rules.SOURCE), "%s loads" % level.id)
		for i in 300:
			if r.won or r.lost:
				break
			if rng.randf() < 0.2:
				r.cycle_active()
			var dir: Vector2i = DIRS[rng.randi() % 4]
			r.try_move(dir.x, dir.y)
