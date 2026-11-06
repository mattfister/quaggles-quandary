class_name Rules
extends RefCounted
## Pure puzzle rules, after level.cxx, cell.cxx and VMan::moveTo from the 2007
## original. No nodes; every move produces a list of events for the view.
##
## A move is one horizontal step by the active quaggle, taking along whoever
## stands on its head (and on theirs, however tall the stack), followed by
## gravity for everyone left without footing.

const EMPTY := 32   # ' '
const GROUND := 46  # '.'
const WALL := 42    # '*'
const WINDOW := 119 # 'w'
const ICE := 120    # 'x'  (GROUND_BAD)
const FIRE := 88    # 'X'  (GROUND_WORSE)
const UP := 117     # 'u'
const DOWN := 100   # 'd'
const START := 115  # 's'
const GOAL := 103   # 'g'
const SPAWN := 49   # '1'  (SPECIAL_1)
const KEY := 50     # '2'  (SPECIAL_2)
const FIELD := 51   # '3'  (SPECIAL_3)
const CRACK := 52   # '4'  (SPECIAL_4)

const UP_ONE := Vector3i(0, 0, 1)
enum { WALK, SLIDE, CARRIED }

var name := ""
var width := 0
var height := 0
var floors := 0
var grid := PackedByteArray()

## Each quaggle: {id, pos: Vector3i(x, y, floor), dead, gone, key}.
## `dead` is set mid-move; `gone` once the move that killed it is over.
var quaggles: Array[Dictionary] = []
var active := 0
var won := false
var lost := false
var events: Array[Dictionary] = []

var _no_start_yet := true
var _momentum := {}  # id -> direction of this move's last step, for ice
var _gliding := false  # the stack now stepping is sliding on ice


static func load_level(level_id: String) -> Rules:
	var level := Levels.find(level_id)
	if level.is_empty():
		push_error("Level '%s' does not exist" % level_id)
		return null
	return from_floors(level_id, level.floors)


## Builds a level from rows of cell characters, one array of rows per floor,
## bottom floor first.
static func from_floors(level_name: String, floor_rows: Array) -> Rules:
	var r := Rules.new()
	r.name = level_name
	r.floors = floor_rows.size()
	for rows: Array in floor_rows:
		r.height = maxi(r.height, rows.size())
		for row: String in rows:
			r.width = maxi(r.width, row.length())
	r.grid.resize(r.floors * r.width * r.height)
	r.grid.fill(EMPTY)
	for f in r.floors:
		var rows: Array = floor_rows[f]
		for y in rows.size():
			var bytes: PackedByteArray = rows[y].to_ascii_buffer()
			for x in bytes.size():
				r.set_cell(f, x, y, bytes[x])
	for f in r.floors:
		for x in r.width:
			for y in r.height:
				var c := r.cell(f, x, y)
				if c == START or c == SPAWN:
					# The original always started on quaggle 0; prefer an 's' one.
					if c == START and r._no_start_yet:
						r._no_start_yet = false
						r.active = r.quaggles.size()
					r.quaggles.append({
						"id": r.quaggles.size(), "pos": Vector3i(x, y, f),
						"dead": false, "gone": false, "key": false,
					})
					r.set_cell(f, x, y, GROUND)
	return r


func cell(f: int, x: int, y: int) -> int:
	if f < 0 or f >= floors or x < 0 or x >= width or y < 0 or y >= height:
		return EMPTY
	return grid[f * width * height + y * width + x]


func cell_at(p: Vector3i) -> int:
	return cell(p.z, p.x, p.y)


func set_cell(f: int, x: int, y: int, c: int) -> void:
	if f >= 0 and f < floors and x >= 0 and x < width and y >= 0 and y < height:
		grid[f * width * height + y * width + x] = c


static func is_walkable(c: int) -> bool:
	return c == START or c == GROUND or c == FIRE or c == KEY or c == CRACK


static func is_air(c: int) -> bool:
	return c == EMPTY or c == DOWN


func alive() -> Array[Dictionary]:
	return quaggles.filter(func(q: Dictionary) -> bool: return not q.gone)


func snapshot() -> Dictionary:
	return {
		"grid": grid.duplicate(), "quaggles": quaggles.duplicate(true),
		"active": active, "won": won, "lost": lost,
	}


func restore(s: Dictionary) -> void:
	grid = s.grid.duplicate()
	quaggles = s.quaggles.duplicate(true)
	active = s.active
	won = s.won
	lost = s.lost
	events = []


func cycle_active() -> bool:
	for i in range(1, quaggles.size()):
		var n := (active + i) % quaggles.size()
		if not quaggles[n].gone:
			active = n
			return true
	return false


## Moves the active quaggle one cell. Returns false if nothing happened.
func try_move(dx: int, dy: int) -> bool:
	events = []
	if won or lost or quaggles[active].gone:
		return false
	_momentum.clear()
	if not _step(quaggles[active], Vector3i(dx, dy, 0), WALK):
		return false
	_settle()
	for other in quaggles:
		if other.dead:
			other.gone = true
	if quaggles[active].gone:
		var rest := alive()
		if rest.is_empty():
			lost = not won
		else:
			active = rest[0].id
	return true


func _occupied(p: Vector3i) -> bool:
	for q in quaggles:
		if q.pos == p and not q.dead:
			return true
	return false


## The quaggle standing on `q`'s head, or {} if there is none.
func _rider(q: Dictionary) -> Dictionary:
	var above: Vector3i = q.pos + UP_ONE
	for other in quaggles:
		if other.pos == above and not other.dead and is_air(cell_at(above)):
			return other
	return {}


## How many quaggles are stacked on `q`'s head.
func riders(q: Dictionary) -> int:
	var n := 0
	var top := _rider(q)
	while not top.is_empty():
		n += 1
		top = _rider(top)
	return n


func _can_enter(q: Dictionary, c: int) -> bool:
	return is_walkable(c) or is_air(c) or c == ICE or c == GOAL or (c == FIELD and q.key)


## Whether `q` would stay at `p` rather than fall: it is standing in a tile,
## on a head, or on top of something solid.
func _holds(q: Dictionary, p: Vector3i) -> bool:
	if not is_air(cell_at(p)):
		return true
	var below := p - UP_ONE
	if _occupied(below):
		return true
	var c := cell_at(below)
	return c == WALL or c == WINDOW or c == UP or (c == FIELD and not q.key)


## Whether there is anything at or under `p` for `q` to land on.
func _has_landing(q: Dictionary, p: Vector3i) -> bool:
	while p.z >= 0:
		if _holds(q, p):
			return true
		p -= UP_ONE
	return false


## `glide` marks a step taken sliding on ice, by the quaggle on the ice and by
## everyone riding on it, so the view moves the whole stack alike.
func _set_pos(q: Dictionary, p: Vector3i, glide := false) -> void:
	if p == q.pos:
		return
	# A drop continues the quaggle's previous step or drop: one event, so the
	# view shows a single fall.
	if p == q.pos - UP_ONE:
		for i in range(events.size() - 1, -1, -1):
			var e := events[i]
			if e.id != q.id:
				continue
			if e.type == "move" and e.to == q.pos and e.to.z <= e.from.z:
				e.to = p
				e.cell = cell_at(p)
				q.pos = p
				return
			break
	events.append({"type": "move", "id": q.id, "from": q.pos, "to": p, "cell": cell_at(p), "glide": glide})
	q.pos = p


func _change_cell(q: Dictionary, p: Vector3i, c: int) -> void:
	events.append({"type": "cell", "id": q.id, "pos": p, "was": cell_at(p), "now": c})
	set_cell(p.z, p.x, p.y, c)


## Moves `q` by `delta`, with its riders. WALK refuses to step out over
## nothing; a SLIDE or a CARRIED rider goes wherever it is taken.
func _step(q: Dictionary, delta: Vector3i, mode: int) -> bool:
	var old: Vector3i = q.pos
	var new := old + delta
	var c := cell_at(new)
	if c == UP:
		# A lift raises whoever steps in, and everyone on their head.
		delta += UP_ONE
		new += UP_ONE
		c = cell_at(new)
	if _occupied(new) or not _can_enter(q, c):
		return false
	if mode == WALK and not _has_landing(q, new):
		return false
	var rider := _rider(q)
	if mode != CARRIED:
		_gliding = c == ICE
	_set_pos(q, new, _gliding)
	_momentum[q.id] = Vector3i(delta.x, delta.y, 0)
	if cell_at(old) == CRACK:
		_change_cell(q, old, EMPTY)
	# A rider that cannot follow is left behind and drops in _settle().
	if not rider.is_empty() and not _step(rider, delta, CARRIED):
		_momentum.erase(rider.id)
	_arrive(q, c)
	return true


## What the cell `q` has just entered does to it.
func _arrive(q: Dictionary, c: int) -> void:
	match c:
		GOAL:
			won = true
			events.append({"type": "win", "id": q.id})
		FIRE:
			q.dead = true
			_change_cell(q, q.pos, GROUND)
			events.append({"type": "burn", "id": q.id})
		KEY:
			q.key = true
			_change_cell(q, q.pos, GROUND)
		ICE:
			var dir: Vector3i = _momentum.get(q.id, Vector3i.ZERO)
			if dir != Vector3i.ZERO:
				_step(q, dir, SLIDE)


## Gravity: drops every quaggle without footing, lowest first, until all rest.
func _settle() -> void:
	var order := quaggles.duplicate()
	var moving := true
	while moving:
		moving = false
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.z < b.pos.z)
		var on_ice: Array[Dictionary] = []
		for q: Dictionary in order:
			if q.dead or q.gone or _holds(q, q.pos):
				continue
			moving = true
			_fall(q)
			if not q.dead and cell_at(q.pos) == ICE:
				on_ice.append(q)
		# Slide on only once the whole stack has come down.
		for q in on_ice:
			if not q.dead and cell_at(q.pos) == ICE:
				_arrive(q, ICE)


func _fall(q: Dictionary) -> void:
	while true:
		var below: Vector3i = q.pos - UP_ONE
		if below.z < 0:
			q.dead = true
			events.append({"type": "fall_out", "id": q.id, "from": q.pos, "to": q.pos})
			return
		_set_pos(q, below)
		var c := cell_at(below)
		if not is_air(c):
			if c != ICE:
				_arrive(q, c)
			return
		if _holds(q, below):
			return
