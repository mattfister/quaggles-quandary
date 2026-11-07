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

## Water already worked out, by grid and quaggle positions: the solver comes
## back to the same states over and over. A Water is never changed once made.
static var _cache := {}
const CACHE_SIZE := 50000

var width := 0
var height := 0
var floors := 0
var kind := PackedByteArray()
var level := PackedByteArray()
## Steps from the water's spring, so the view can ripple it outwards.
var dist := PackedInt32Array()


static func compute(r: Rules) -> Water:
	# Quaggles in deep water swim, and so does anyone on a swimmer's head;
	# the rest dam the water. Who swims depends on the water, so start with
	# no dams and add those it shows until no new ones turn up. Dams are only
	# ever added, so this ends.
	var spots: Array[Vector3i] = []
	for q in r.quaggles:
		if not q.dead and not q.gone:
			spots.append(q.pos)
	spots.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.z < b.z or (a.z == b.z and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	var key := [r.grid, spots]
	var known: Water = _cache.get(key)
	if known:
		return known
	var dams := {}
	while true:
		var w := Water.new()
		w._fill(r, dams)
		var grew := false
		for p: Vector3i in w._dams(spots):
			if not dams.has(p):
				dams[p] = true
				grew = true
		if not grew:
			if _cache.size() >= CACHE_SIZE:
				_cache.clear()
			_cache[key] = w
			return w
	return null


## Which of `spots` (quaggles, lowest first) dam this water: all but those
## in deep water and those standing on them.
func _dams(spots: Array[Vector3i]) -> Dictionary:
	var afloat := {}
	var dams := {}
	for p in spots:
		if is_deep(p) or afloat.has(p - UP):
			afloat[p] = true
		else:
			dams[p] = true
	return dams


func kind_at(p: Vector3i) -> int:
	return kind[_i(p)] if _inside(p) else NONE


func level_at(p: Vector3i) -> int:
	return level[_i(p)] if _inside(p) else 0


## Whether `p` is on the map. Water that would flow off it is lost; only the
## view shows it falling.
func contains(p: Vector3i) -> bool:
	return _inside(p)


## Pools: deep enough to swim in. A spring is not: it is a tile, and a
## quaggle standing on it stops it up (unless a pool covers it).
func is_deep(p: Vector3i) -> bool:
	return kind_at(p) == POOL


## The cell a waterfall lands in, which cannot be walked into.
func is_base(p: Vector3i) -> bool:
	return kind_at(p) != NONE and kind_at(p + UP) == FALL


## The cells whose water pours into the waterfall landing in `base`: those
## beside the top of its column with water strong enough to flow on.
func feeds(base: Vector3i) -> Array[Vector3i]:
	var top := base + UP
	while kind_at(top + UP) == FALL:
		top += UP
	var from: Array[Vector3i] = []
	for side in SIDES:
		var n := top + side
		var k := kind_at(n)
		if k == SOURCE or k == POOL or (k == FLOW and level_at(n) > 1):
			from.append(n)
	return from


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
			if r.grid[i] == Rules.SOURCE and not blockers.has(pos(i)):
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
	var next := 0
	while next < queue.size():
		var p: Vector3i = queue[next]
		next += 1
		var i := _i(p)
		if not _rests(r, p, blockers):
			kind[i] = FALL
			level[i] = STRENGTH
			_offer(r, blockers, queue, p - UP, STRENGTH, dist[i] + 1)
			continue
		# A curb's rim keeps flowing water from crossing it either way; water
		# falling onto one stays there.
		if r.cell_at(p) == Rules.CURB:
			continue
		for side in SIDES:
			if r.cell_at(p + side) != Rules.CURB:
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


## Fills each basin that falling water lands in, from the bottom up, to the
## last level walled in all round or the level the water fell from, whichever
## is lower. A basin that fills up to a level that is not walled in overflows:
## the cells over it go into `spill`, to flow on from. Returns whether any
## pool grew.
func _pools(r: Rules, spill: Dictionary) -> bool:
	var grew := false
	for i in kind.size():
		var p := pos(i)
		if kind[i] != FLOW or kind_at(p + UP) != FALL:
			continue
		var top := p + UP
		while kind_at(top + UP) == FALL:
			top += UP
		var d := dist[i]
		var depth := 0
		var layer: Array[Vector3i] = [p]
		while layer[0].z <= top.z:
			var basin := _basin(r, layer)
			if basin.is_empty():
				if depth > 0:
					for q in layer:
						if not _walls(r.cell_at(q)):
							spill[q] = d + depth
				break
			var next: Array[Vector3i] = []
			for q in basin:
				if kind_at(q) != POOL:
					grew = true
				_put(q, POOL, STRENGTH, d + depth)
				if q.z + 1 < floors:
					next.append(q + UP)
			depth += 1
			layer = next
			if layer.is_empty():
				break
	return grew


## The cells on one level joined to `starts` that water can get into, if
## every one of them holds water up (whatever quaggles are there) and none is
## at the map's edge. Otherwise none: the water would run out.
func _basin(r: Rules, starts: Array[Vector3i]) -> Array[Vector3i]:
	var seen := {}
	var todo: Array[Vector3i] = []
	for p in starts:
		if not _walls(r.cell_at(p)):
			seen[p] = true
			todo.append(p)
	var cells: Array[Vector3i] = []
	while not todo.is_empty():
		var p: Vector3i = todo.pop_back()
		if not _rests(r, p, {}):
			return []
		cells.append(p)
		for side in SIDES:
			var n := p + side
			if not _inside(n):
				return []
			if seen.has(n) or _walls(r.cell_at(n)):
				continue
			seen[n] = true
			todo.append(n)
	return cells
