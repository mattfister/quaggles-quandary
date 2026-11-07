class_name WaterView
extends Node3D
## Draws a level's water (see Water) on the world's floor nodes, so it hides
## with them, and plays "water" events: new water ripples out from its spring,
## old water drains away.

const SHADER := preload("res://shaders/water.gdshader")
const RIPPLE := 0.05    # seconds per cell from the spring
const GROW := 0.2
const SHEET := 0.04     # flowing water's depth per step of strength
const VOID_DROP := 6.0  # how far a curtain falls into the void as it fades

var _floors: Array[Node3D] = []
var _cells := {}  # Vector3i -> Array[MeshInstance3D]
var _still := ShaderMaterial.new()
var _falling := ShaderMaterial.new()
var _vanishing := ShaderMaterial.new()


func _init() -> void:
	_still.shader = SHADER
	_falling.shader = SHADER
	_falling.set_shader_parameter("falling", 1.0)
	_vanishing.shader = SHADER
	_vanishing.set_shader_parameter("falling", 1.0)
	_vanishing.set_shader_parameter("fade_length", VOID_DROP)


func build(water: Water, floors: Array[Node3D]) -> void:
	_floors = floors
	if water == null:
		return
	for i in water.kind.size():
		if water.kind[i] != Water.NONE:
			var p := water.pos(i)
			_place(p, _make(p, water.kind[i], water.level[i], water))


## Plays a "water" event from `start` seconds on; returns how long after
## `start` it runs. `water` is the water the move ends with.
func play(e: Dictionary, start: float, water: Water) -> float:
	var longest := 0.0
	for c: Dictionary in e.removed:
		_drain(c.pos, start + c.delay * RIPPLE)
		longest = maxf(longest, c.delay * RIPPLE)
	for c: Dictionary in e.added:
		var t: float = start + c.delay * RIPPLE
		_drain(c.pos, t)
		var parts := _make(c.pos, c.kind, c.level, water)
		_place(c.pos, parts)
		for part in parts:
			part.scale = Vector3(1, 0.01, 1)
			var tw := part.create_tween()
			tw.tween_interval(t)
			tw.tween_property(part, "scale", Vector3.ONE, GROW).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		longest = maxf(longest, c.delay * RIPPLE)
	return longest + GROW


func _place(p: Vector3i, parts: Array[MeshInstance3D]) -> void:
	for part in parts:
		_floors[p.z].add_child(part)
	_cells[p] = parts


## Shrinks away whatever water is drawn at `p`, `t` seconds from now.
func _drain(p: Vector3i, t: float) -> void:
	var parts: Array = _cells.get(p, [])
	_cells.erase(p)
	for part: MeshInstance3D in parts:
		var tw := part.create_tween()
		tw.tween_interval(t)
		tw.tween_property(part, "scale", Vector3(1, 0.01, 1), GROW).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(part.queue_free)


func _make(p: Vector3i, k: int, l: int, water: Water) -> Array[MeshInstance3D]:
	var at := World.cell_pos(p)
	var parts: Array[MeshInstance3D] = []
	match k:
		Water.FLOW:
			var t := SHEET * l
			parts.append(_box(Vector3(1, t, 1), at + Vector3(0, t * 0.5 + 0.01, 0), _still))
		Water.POOL:
			# Full to the brim under more pool; the top cell shows a surface.
			var h := World.H if water.kind_at(p + Water.UP) == Water.POOL else World.H * 0.7
			parts.append(_box(Vector3(1, h, 1), at + Vector3(0, h * 0.5, 0), _still))
		Water.SOURCE:
			parts.append(_box(Vector3(0.9, 0.35, 0.9), at + Vector3(0, 0.175, 0), _still))
			parts.append(_box(Vector3(0.3, 0.5, 0.3), at + Vector3(0, 0.25, 0), _falling))
		Water.FALL:
			parts.append(_box(Vector3(0.8, World.H, 0.8), at + Vector3(0, World.H * 0.5, 0), _falling))
			if p.z == 0:
				parts.append(_box(Vector3(0.8, VOID_DROP, 0.8), at - Vector3(0, VOID_DROP * 0.5, 0), _vanishing))
	return parts


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m
