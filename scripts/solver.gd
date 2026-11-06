class_name Solver
extends RefCounted
## Breadth-first search for the shortest solution of a level, run a slice at
## a time with step() so the level editor stays responsive (or all at once
## with run(), as the tests do). Levels too big for that (`greedy`) are
## searched nearest-to-the-goal first instead, which proves they can be won
## without finding the shortest way. `max_stack` > 0 forbids taller stacks.

enum { RUNNING, SOLVED, NO_SOLUTION, CAPPED }

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var state := RUNNING
var greedy := false
var max_stack := 0
var cap := 400000
## Once SOLVED: the moves, each [quaggle id, dx, dy] in grid cells.
var path: Array = []
var moves := 0
var switches := 0
var stack := 0
var states := 0
var elapsed_ms := 0

var _r: Rules
var _goal := Vector3i.ZERO
var _seen := {}
# One queue per goal distance; breadth-first uses only the first.
# Nodes: [snapshot, moves, parent node, quaggle, dir, switches, tallest stack]
var _nodes: Array = []
var _buckets: Array = []
var _heads := PackedInt32Array()
var _start := 0


func _init(r: Rules, search_cap := 400000, is_greedy := false, stack_limit := 0) -> void:
	_r = r
	cap = search_cap
	greedy = is_greedy
	max_stack = stack_limit
	for f in r.floors:
		for y in r.height:
			for x in r.width:
				if r.cell(f, x, y) == Rules.GOAL:
					_goal = Vector3i(x, y, f)
	for i in 400:
		_buckets.append(PackedInt32Array())
	_heads.resize(_buckets.size())
	_seen[key_of(r)] = true
	_push([r.snapshot(), 0, -1, -1, -1, 0, tallest_stack(r)])
	_start = Time.get_ticks_msec()


## Searches for about `budget_usec` microseconds. Returns true once finished.
func step(budget_usec := 8000) -> bool:
	var until := Time.get_ticks_usec() + budget_usec
	while state == RUNNING and Time.get_ticks_usec() < until:
		_expand()
	elapsed_ms = Time.get_ticks_msec() - _start
	return state != RUNNING


func run() -> int:
	while state == RUNNING:
		_expand()
	elapsed_ms = Time.get_ticks_msec() - _start
	return state


func _push(node: Array) -> void:
	_nodes.append(node)
	var b: int = mini(goal_distance(_r, _goal), _buckets.size() - 1) if greedy else 0
	_buckets[b].append(_nodes.size() - 1)


func _expand() -> void:
	states = _seen.size()
	if states >= cap:
		state = CAPPED
		return
	var b := 0
	while b < _buckets.size() and _heads[b] >= _buckets[b].size():
		b += 1
	if b == _buckets.size():
		state = NO_SOLUTION
		return
	var index: int = _buckets[b][_heads[b]]
	_heads[b] += 1
	var node: Array = _nodes[index]
	var snap: Dictionary = node[0]
	node[0] = null  # expanded: only the path back is needed from now on
	for q: Dictionary in snap.quaggles:
		if q.gone:
			continue
		for d in DIRS.size():
			_r.restore(snap)
			_r.active = q.id
			if not _r.try_move(DIRS[d].x, DIRS[d].y):
				continue
			var tall := tallest_stack(_r)
			if max_stack > 0 and tall > max_stack:
				continue
			var last: int = node[3]
			var child := [null, node[1] + 1, index, q.id, d,
				node[5] + int(last != -1 and last != q.id), maxi(tall, node[6])]
			if _r.won:
				_finish(child)
				return
			if _r.lost:
				continue
			var k := key_of(_r)
			if not _seen.has(k):
				_seen[k] = true
				child[0] = _r.snapshot()
				_push(child)


func _finish(node: Array) -> void:
	state = SOLVED
	moves = node[1]
	switches = node[5]
	stack = node[6]
	states = _seen.size()
	path = []
	while node[3] != -1:
		var dir: Vector2i = DIRS[node[4]]
		path.push_front([node[3], dir.x, dir.y])
		node = _nodes[node[2]]
	_nodes.clear()
	_buckets.clear()


## One state per arrangement: which quaggle is which does not matter.
static func key_of(r: Rules) -> String:
	var parts := PackedStringArray()
	for q in r.quaggles:
		if not q.gone:
			parts.append("%d,%d,%d,%d" % [q.pos.x, q.pos.y, q.pos.z, int(q.key)])
	parts.sort()
	return "%d|%s" % [hash(r.grid), "|".join(parts)]


static func tallest_stack(r: Rules) -> int:
	var best := 0
	for q in r.quaggles:
		if not q.gone:
			best = maxi(best, 1 + r.riders(q))
	return best


## Distance from the nearest living quaggle to the goal, for the greedy search.
static func goal_distance(r: Rules, goal: Vector3i) -> int:
	var best := 9999
	for q in r.quaggles:
		if not q.gone:
			var d: Vector3i = (q.pos - goal).abs()
			best = mini(best, d.x + d.y + 3 * d.z)
	return best
