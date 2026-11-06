class_name EditLevel
extends RefCounted
## The level editor's working copy of one level's map: a box of cells, width
## by height by floors, with the editing operations on it. Converts to and
## from the rows-of-text floors that levels.json holds.
##
## Clipboard buffers are {w, h, f, base, cells}: a box of cells cut out of a
## level, `base` the floor it came from.

const EMPTY := Rules.EMPTY

var width := 1
var height := 1
var floors := 1
var grid := PackedByteArray([EMPTY])


static func from_floors(floor_rows: Array) -> EditLevel:
	var e := EditLevel.new()
	e.floors = maxi(1, floor_rows.size())
	e.width = 1
	e.height = 1
	for rows: Array in floor_rows:
		e.height = maxi(e.height, rows.size())
		for row: String in rows:
			e.width = maxi(e.width, row.length())
	e.grid = PackedByteArray()
	e.grid.resize(e.floors * e.width * e.height)
	e.grid.fill(EMPTY)
	for f in floor_rows.size():
		var rows: Array = floor_rows[f]
		for y in rows.size():
			var bytes: PackedByteArray = (rows[y] as String).to_ascii_buffer()
			for x in bytes.size():
				e.set_cell(f, x, y, bytes[x])
	return e


## Rows of text per floor, bottom first, trailing blanks trimmed. An empty
## floor is written as one empty row.
func to_floors() -> Array:
	var out: Array = []
	for f in floors:
		var rows: Array = []
		for y in height:
			var bytes := PackedByteArray()
			for x in width:
				bytes.append(cell(f, x, y))
			rows.append(bytes.get_string_from_ascii().rstrip(" "))
		while rows.size() > 1 and rows[-1] == "":
			rows.pop_back()
		out.append(rows)
	return out


func snapshot() -> Dictionary:
	return {"w": width, "h": height, "f": floors, "grid": grid.duplicate()}


func restore(s: Dictionary) -> void:
	width = s.w
	height = s.h
	floors = s.f
	grid = s.grid.duplicate()


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func cell(f: int, x: int, y: int) -> int:
	if f < 0 or f >= floors or not inside(x, y):
		return EMPTY
	return grid[(f * height + y) * width + x]


## Sets a cell; returns whether it changed.
func set_cell(f: int, x: int, y: int, c: int) -> bool:
	if f < 0 or f >= floors or not inside(x, y):
		return false
	var i := (f * height + y) * width + x
	if grid[i] == c:
		return false
	grid[i] = c
	return true


func count(c: int) -> int:
	return grid.count(c)


## Quaggle cells in the order Rules numbers them (floor, then column, then
## row), so ids and colours match the game's.
func quaggle_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for f in floors:
		for x in width:
			for y in height:
				var c := cell(f, x, y)
				if c == Rules.START or c == Rules.SPAWN:
					out.append(Vector3i(x, y, f))
	return out


func find_all(c: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for f in floors:
		for y in height:
			for x in width:
				if cell(f, x, y) == c:
					out.append(Vector3i(x, y, f))
	return out


func floor_empty(f: int) -> bool:
	for y in height:
		for x in width:
			if cell(f, x, y) != EMPTY:
				return false
	return true


# --- size --------------------------------------------------------------------

## Grows (positive) or shrinks (negative) each side. Never below 1 x 1.
func resize(left: int, right: int, top: int, bottom: int) -> void:
	var w := maxi(1, width + left + right)
	var h := maxi(1, height + top + bottom)
	var g := PackedByteArray()
	g.resize(floors * w * h)
	g.fill(EMPTY)
	for f in floors:
		for y in h:
			for x in w:
				g[(f * h + y) * w + x] = cell(f, x - left, y - top)
	width = w
	height = h
	grid = g


## Grows the box to take in (x, y); returns how far the old cells moved.
func grow_to(x: int, y: int) -> Vector2i:
	var left := maxi(0, -x)
	var top := maxi(0, -y)
	var right := maxi(0, x - width + 1)
	var bottom := maxi(0, y - height + 1)
	if left or top or right or bottom:
		resize(left, right, top, bottom)
	return Vector2i(left, top)


## The smallest box around every non-empty cell on any floor.
func content_rect() -> Rect2i:
	var lo := Vector2i(width, height)
	var hi := Vector2i(-1, -1)
	for f in floors:
		for y in height:
			for x in width:
				if cell(f, x, y) != EMPTY:
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return Rect2i(0, 0, 1, 1)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Trims empty rows and columns from every side; returns how far cells moved.
func crop() -> Vector2i:
	var r := content_rect()
	resize(-r.position.x, -(width - r.end.x), -r.position.y, -(height - r.end.y))
	return -r.position


## Moves every cell by (dx, dy), growing the box rather than losing any.
func shift(dx: int, dy: int) -> void:
	var r := content_rect()
	var grow_l := maxi(0, -(r.position.x + dx))
	var grow_t := maxi(0, -(r.position.y + dy))
	var grow_r := maxi(0, r.end.x + dx - width)
	var grow_b := maxi(0, r.end.y + dy - height)
	resize(grow_l, grow_r, grow_t, grow_b)
	var buf := whole()
	grid.fill(EMPTY)
	stamp(buf, dx, dy, 0, false)


# --- floors ------------------------------------------------------------------

## Adds an empty floor that becomes floor `at`.
func insert_floor(at: int) -> void:
	var layer := PackedByteArray()
	layer.resize(width * height)
	layer.fill(EMPTY)
	var n := width * height
	at = clampi(at, 0, floors)
	grid = grid.slice(0, at * n) + layer + grid.slice(at * n)
	floors += 1


func remove_floor(at: int) -> void:
	if floors <= 1:
		grid.fill(EMPTY)
		return
	var n := width * height
	grid = grid.slice(0, at * n) + grid.slice((at + 1) * n)
	floors -= 1


func duplicate_floor(at: int) -> void:
	var n := width * height
	grid = grid.slice(0, (at + 1) * n) + grid.slice(at * n, (at + 1) * n) + grid.slice((at + 1) * n)
	floors += 1


func swap_floors(a: int, b: int) -> void:
	var n := width * height
	var la := grid.slice(a * n, (a + 1) * n)
	var lb := grid.slice(b * n, (b + 1) * n)
	for i in n:
		grid[a * n + i] = lb[i]
		grid[b * n + i] = la[i]


func clear_floor(f: int) -> void:
	for y in height:
		for x in width:
			set_cell(f, x, y, EMPTY)


# --- painting helpers ----------------------------------------------------------

## The cells of the same tile joined to (x, y) on floor `f`.
func flood(f: int, x: int, y: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not inside(x, y):
		return out
	var target := cell(f, x, y)
	var seen := {Vector2i(x, y): true}
	var todo: Array[Vector2i] = [Vector2i(x, y)]
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		out.append(p)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := p + d
			if inside(n.x, n.y) and not seen.has(n) and cell(f, n.x, n.y) == target:
				seen[n] = true
				todo.append(n)
	return out


## Puts walls round everything on floor `f`: every empty cell next to (or
## diagonally next to) a cell that is not a wall. Grows the box to fit.
func wrap_walls(f: int) -> Vector2i:
	var moved := Vector2i.ZERO
	var r := content_rect()
	if r.position.x == 0 or r.position.y == 0 or r.end.x == width or r.end.y == height:
		var l := 1 if r.position.x == 0 else 0
		var t := 1 if r.position.y == 0 else 0
		resize(l, 1 if r.end.x == width else 0, t, 1 if r.end.y == height else 0)
		moved = Vector2i(l, t)
	var put: Array[Vector2i] = []
	for y in height:
		for x in width:
			if cell(f, x, y) != EMPTY:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var c := cell(f, x + dx, y + dy)
					if c != EMPTY and c != Rules.WALL:
						put.append(Vector2i(x, y))
	for p in put:
		set_cell(f, p.x, p.y, Rules.WALL)
	return moved


# --- buffers -------------------------------------------------------------------

## Copies the cells in `r` on floors f0..f1 into a buffer.
func extract(r: Rect2i, f0: int, f1: int) -> Dictionary:
	var buf := {"w": r.size.x, "h": r.size.y, "f": f1 - f0 + 1, "base": f0, "cells": PackedByteArray()}
	for f in range(f0, f1 + 1):
		for y in r.size.y:
			for x in r.size.x:
				buf.cells.append(cell(f, r.position.x + x, r.position.y + y))
	return buf


func fill_rect(r: Rect2i, f0: int, f1: int, c: int) -> void:
	for f in range(f0, f1 + 1):
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				set_cell(f, x, y, c)


## Writes a buffer with its corner at (x, y) and its bottom floor at `f`,
## adding floors if it reaches above the top. `skip_empty` leaves the cells
## under the buffer's empty cells alone.
func stamp(buf: Dictionary, x: int, y: int, f: int, skip_empty: bool) -> void:
	while f + buf.f > floors:
		insert_floor(floors)
	var i := 0
	for bf in buf.f:
		for by in buf.h:
			for bx in buf.w:
				var c: int = buf.cells[i]
				i += 1
				if c == EMPTY and skip_empty:
					continue
				set_cell(f + bf, x + bx, y + by, c)


static func buffer_cell(buf: Dictionary, f: int, x: int, y: int) -> int:
	return buf.cells[(f * buf.h + y) * buf.w + x]


## A buffer mirrored left to right (`horizontal`) or top to bottom.
static func flip_buffer(buf: Dictionary, horizontal: bool) -> Dictionary:
	var out := buf.duplicate()
	out.cells = PackedByteArray()
	for f in buf.f:
		for y in buf.h:
			for x in buf.w:
				var sx: int = buf.w - 1 - x if horizontal else x
				var sy: int = y if horizontal else buf.h - 1 - y
				out.cells.append(buffer_cell(buf, f, sx, sy))
	return out


## A buffer turned a quarter turn, clockwise as the map text reads.
static func rotate_buffer(buf: Dictionary, clockwise: bool) -> Dictionary:
	var out := buf.duplicate()
	out.w = buf.h
	out.h = buf.w
	out.cells = PackedByteArray()
	for f in buf.f:
		for y in out.h:
			for x in out.w:
				if clockwise:
					out.cells.append(buffer_cell(buf, f, y, buf.h - 1 - x))
				else:
					out.cells.append(buffer_cell(buf, f, buf.w - 1 - y, x))
	return out


## The whole level as one buffer, and back: for whole-level flips and turns.
func whole() -> Dictionary:
	return extract(Rect2i(0, 0, width, height), 0, floors - 1)


func set_whole(buf: Dictionary) -> void:
	width = buf.w
	height = buf.h
	floors = buf.f
	grid = buf.cells.duplicate()


## Buffer to text, one floor after another, separated by "---" lines, top floor first
## as in a stack of map files. For the system clipboard.
static func buffer_text(buf: Dictionary) -> String:
	var parts := PackedStringArray()
	for f in range(buf.f - 1, -1, -1):
		var rows := PackedStringArray()
		for y in buf.h:
			var bytes := PackedByteArray()
			for x in buf.w:
				bytes.append(buffer_cell(buf, f, x, y))
			rows.append(bytes.get_string_from_ascii())
		parts.append("\n".join(rows))
	return "\n---\n".join(parts)


## Text in the form buffer_text() writes, back to a buffer; {} if empty.
static func text_buffer(text: String) -> Dictionary:
	var floors_text := text.replace("\r", "").split("\n---\n")
	floors_text.reverse()
	var w := 0
	var h := 0
	var layers: Array = []
	for part in floors_text:
		var rows := part.split("\n")
		layers.append(rows)
		h = maxi(h, rows.size())
		for row in rows:
			w = maxi(w, row.length())
	if w == 0:
		return {}
	var buf := {"w": w, "h": h, "f": layers.size(), "base": 0, "cells": PackedByteArray()}
	for rows: PackedStringArray in layers:
		for y in h:
			var bytes := (rows[y] if y < rows.size() else "").to_ascii_buffer()
			for x in w:
				buf.cells.append(bytes[x] if x < bytes.size() else EMPTY)
	return buf
