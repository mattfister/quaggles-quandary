class_name Quaggle
extends Node3D
## A quaggle: the sphere-built creature from VMan::draw, with idle and walk
## animation. Faces local -Z.

const TOON := preload("res://shaders/toon.gdshader")
const BODY_R := 0.5
const HEAD_R := 0.25
const LIMB_R := 0.2
const PALETTE: Array[Color] = [
	Color("ff6b6b"), Color("4dabf7"), Color("ffd43b"), Color("9775fa"),
	Color("ff922b"), Color("38d9a9"), Color("f783ac"), Color("a9e34b"),
]

static var _sphere: SphereMesh

var id := 0
var burn := 0.0: set = _set_burn

var _mats: Array[ShaderMaterial] = []
var _model := Node3D.new()
var _head := Node3D.new()
var _arms: Array[MeshInstance3D] = []
var _legs: Array[MeshInstance3D] = []
var _t := 0.0
var _walk := 0.0
var _target_yaw := 0.0
var _phase := Vector3.ZERO
var _cheer := false


func setup(quaggle_id: int, color_index: int, rng: RandomNumberGenerator) -> void:
	id = quaggle_id
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 24
		_sphere.rings = 12
	var primary: Color = PALETTE[color_index % PALETTE.size()]
	var secondary := primary.lerp(Color.WHITE, 0.3)
	var tertiary := primary.darkened(0.25)
	_phase = Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
	_t = rng.randf() * 10.0

	add_child(_model)
	_part(_model, Vector3(0, BODY_R, 0), BODY_R, primary)
	_head.position = Vector3(0, BODY_R * 2.0 + HEAD_R * 0.5, 0)
	_model.add_child(_head)
	_part(_head, Vector3.ZERO, HEAD_R, secondary)
	for side: float in [-1.0, 1.0]:
		_part(_head, Vector3(side * 0.11, 0.05, -0.2), 0.075, Color.WHITE)
		_part(_head, Vector3(side * 0.115, 0.055, -0.255), 0.035, Color(0.05, 0.05, 0.08))
		_arms.append(_part(_model, Vector3(side * 0.36, BODY_R * 1.5, 0), LIMB_R, tertiary))
		_legs.append(_part(_model, Vector3(side * 0.27, LIMB_R, 0), LIMB_R, tertiary))


func _part(parent: Node3D, at: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.set_shader_parameter("albedo", color)
	_mats.append(mat)
	var m := MeshInstance3D.new()
	m.mesh = _sphere
	m.material_override = mat
	m.position = at
	m.scale = Vector3.ONE * radius
	parent.add_child(m)
	return m


func _set_burn(v: float) -> void:
	burn = v
	for mat in _mats:
		mat.set_shader_parameter("burn", v)


func _process(delta: float) -> void:
	_t += delta
	rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, delta * 18.0))
	var swing := 0.0
	if _walk > 0.0:
		_walk -= delta
		swing = sin(_t * 22.0) * 0.2
		_head.rotation.y = lerp_angle(_head.rotation.y, 0.0, minf(1.0, delta * 10.0))
	else:
		_head.rotation.y = deg_to_rad(18.0 * sin(_t * 0.7 + _phase.x) + 10.0 * sin(_t * 1.9 + _phase.y))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var bob := 0.04 * sin(_t * 1.6 + _phase.z + i)
		_arms[i].position = Vector3(side * (0.36 + 0.03 * sin(_t * 1.1 + _phase.y)), BODY_R * 1.5 + bob, side * swing)
		_legs[i].position = Vector3(side * 0.27, LIMB_R, -side * swing)
	if _cheer:
		_model.position.y = absf(sin(_t * 7.0)) * 0.35
		_arms[0].position.y += 0.3
		_arms[1].position.y += 0.3


func face(dir: Vector3) -> void:
	if absf(dir.x) + absf(dir.z) > 0.01:
		_target_yaw = atan2(-dir.x, -dir.z)


func cheer() -> void:
	_cheer = true


## Appends one grid step to `tw`. Kinds: hop, slide, fall, rise.
func queue_step(tw: Tween, from: Vector3, to: Vector3, kind: String, duration: float) -> void:
	tw.tween_callback(face.bind(to - from))
	tw.tween_method(_step.bind(from, to, kind), 0.0, 1.0, duration)
	if kind == "fall":
		tw.tween_callback(_squash)


func _step(t: float, from: Vector3, to: Vector3, kind: String) -> void:
	_walk = 0.12
	var p := from.lerp(to, t)
	match kind:
		"hop":
			p.y += sin(t * PI) * 0.22
		"fall":
			# Step off the edge first, then drop.
			var flat := minf(1.0, t * 2.5)
			p = from.lerp(Vector3(to.x, from.y, to.z), flat)
			p.y = lerpf(from.y, to.y, t * t)
		"rise":
			p.y = lerpf(from.y, to.y, smoothstep(0.0, 1.0, t))
	position = p


func _squash() -> void:
	var tw := create_tween()
	tw.tween_property(_model, "scale", Vector3(1.25, 0.7, 1.25), 0.06)
	tw.tween_property(_model, "scale", Vector3.ONE, 0.12)


func queue_burn(tw: Tween) -> void:
	tw.tween_property(self, "burn", 1.0, 0.25)
	tw.tween_property(_model, "scale", Vector3(0.0, 0.0, 0.0), 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(hide)


func queue_fall_out(tw: Tween) -> void:
	tw.tween_property(self, "position:y", -14.0, 0.7).as_relative() \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(hide)
