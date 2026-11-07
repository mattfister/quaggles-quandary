class_name Water
extends RefCounted
## Water from springs ('~'), worked out from scratch for one state of a level.
## It flows a few cells over floors, falls off edges (below floor 0 it is lost
## to the void) and fills the basins it falls into. Nothing here goes into
## snapshots: Rules works it out again after every move.

enum { NONE, FLOW, FALL, POOL, SOURCE }
const STRENGTH := 4  # a spring's; flowing water loses one per cell
const UP := Vector3i(0, 0, 1)
const SIDES: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]

var width := 0
var height := 0
var floors := 0
var kind := PackedByteArray()
var level := PackedByteArray()
## Steps from the water's spring, so the view can ripple it outwards.
var dist := PackedInt32Array()


static func compute(r: Rules) -> Water:
	var w := Water.new()
	w._fill(r, {})
	return w


func kind_at(p: Vector3i) -> int:
	return kind[_i(p)] if _inside(p) else NONE


func level_at(p: Vector3i) -> int:
	return level[_i(p)] if _inside(p) else 0


## Springs and pools: deep enough to swim in.
func is_deep(p: Vector3i) -> bool:
	var k := kind_at(p)
	return k == POOL or k == SOURCE


## The cell a waterfall lands in, which cannot be walked into.
func is_base(p: Vector3i) -> bool:
	return kind_at(p) != NONE and kind_at(p + UP) == FALL


@warning_ignore("integer_division")
func pos(i: int) -> Vector3i:
	return Vector3i(i % width, (i / width) % height, i / (width * height))


func _i(p: Vector3i) -> int:
	return (p.z * height + p.y) * width + p.x


func _inside(p: Vector3i) -> bool:
	return p.x >= 0 and p.x < width and p.y >= 0 and p.y < height and p.z >= 0 and p.z < floors


func _put(p: Vector3i, k: int, l: int, d: int) -> void:
	var i := _i(p)
	kind[i] = k
	level[i] = l
	dist[i] = d


## Walls, glass, force fields and lifts keep water out.
static func _walls(c: int) -> bool:
	return c == Rules.WALL or c == Rules.WINDOW or c == Rules.FIELD or c == Rules.UP


## Whether water at `p` stays there rather than falling: on a tile in its
## cell, or on a wall, a pool or one of `blockers` (quaggles) below.
func _rests(r: Rules, p: Vector3i, blockers: Dictionary) -> bool:
	var c := r.cell_at(p)
	if not Rules.is_air(c) and not _walls(c):
		return true
	var below := p - UP
	return _walls(r.cell_at(below)) or kind_at(below) == POOL or blockers.has(below)


func _fill(r: Rules, blockers: Dictionary) -> void:
	width = r.width
	height = r.height
	floors = r.floors
	var n := width * height * floors
	kind.resize(n)
	kind.fill(NONE)
	level.resize(n)
	dist.resize(n)
	var spill := {}  # Vector3i -> dist: cells over an overflowing pool
	while true:
		# Start over each round, keeping the pools found so far: water that
		# fell where a pool now is flows on over it instead.
		var queue: Array[Vector3i] = []
		for i in n:
			if kind[i] == POOL:
				continue
			kind[i] = NONE
			level[i] = 0
			dist[i] = 0
			if r.grid[i] == Rules.SOURCE:
				_put(pos(i), SOURCE, STRENGTH, 0)
				queue.append(pos(i))
		for p: Vector3i in spill:
			if kind_at(p) == NONE and not blockers.has(p):
				_put(p, FLOW, STRENGTH, spill[p])
				queue.append(p)
		_flow(r, blockers, queue)
		if not _pools(r, spill):
			return


## Spreads water from `queue`: sideways, a step weaker per cell, where it
## rests; straight down at full strength where it does not.
func _flow(r: Rules, blockers: Dictionary, queue: Array[Vector3i]) -> void:
	while not queue.is_empty():
		var p: Vector3i = queue.pop_front()
		var i := _i(p)
		if not _rests(r, p, blockers):
			kind[i] = FALL
			level[i] = STRENGTH
			_offer(r, blockers, queue, p - UP, STRENGTH, dist[i] + 1)
			continue
		for side in SIDES:
			_offer(r, blockers, queue, p + side, level[i] - 1, dist[i] + 1)


## Water of strength `l` reaching `p`, unless it is kept out or `p` already
## has as much.
func _offer(r: Rules, blockers: Dictionary, queue: Array[Vector3i], p: Vector3i, l: int, d: int) -> void:
	if l <= 0 or not _inside(p) or _walls(r.cell_at(p)) or blockers.has(p):
		return
	var i := _i(p)
	if kind[i] == POOL or kind[i] == SOURCE or level[i] >= l:
		return
	if kind[i] == NONE:
		dist[i] = d
	kind[i] = FLOW
	level[i] = l
	queue.append(p)


## Fills the basins falling water lands in (see Task 2). Returns whether any
## pool grew.
func _pools(_r: Rules, _spill: Dictionary) -> bool:
	return false
