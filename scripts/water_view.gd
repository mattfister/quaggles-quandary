class_name WaterView
extends Node3D
## Draws a level's water (see Water) on the world's floor nodes, so it hides
## with them, and plays "water" events: new water ripples out from its spring,
## old water drains away, and waterfalls pour down and dry up from the top.
##
## Still water (streams, pools, springs) is drawn per cell with only the faces
## that show: the top, and whatever of a side rises above the water next to
## it. A waterfall is one sheet per edge it pours over, owned by the cell it
## starts in: it curls over the lip and drops to where it lands.

const SHADER := preload("res://shaders/water.gdshader")
const FOAM := preload("res://shaders/foam.gdshader")
const RIPPLE := 0.05    # seconds per cell from the spring
const GROW := 0.2
const SHEET := 0.04     # flowing water's depth per step of strength
const CURL := 0.28      # radius of the bend where water pours over an edge
const THICK := 0.16     # how thick a waterfall is
const POUR := 8.0       # how fast a waterfall's front or tail travels, per second
const VOID_DROP := 6.0  # how far a fall into the void goes as it fades
const H := World.H
const SIDES: Array[Vector3i] = Water.SIDES
const UP := Water.UP

static var _dot: ImageTexture

var _floors: Array[Node3D] = []
var _still := {}  # Vector3i -> Node3D: a stream, pool or spring cell
var _falls := {}  # Vector3i -> Node3D: a waterfall, by the cell it starts in
var _kinds := {}  # Vector3i -> Water kind, as drawn
var _dams := {}   # [water cell, side] -> spray where a quaggle holds that water back
var _still_mat := ShaderMaterial.new()
var _jet_mat := ShaderMaterial.new()
var _drop_mat := StandardMaterial3D.new()
var _mist_mat := StandardMaterial3D.new()
var _foam_mat := ShaderMaterial.new()


func _init() -> void:
	_still_mat.shader = SHADER
	_jet_mat.shader = SHADER
	_jet_mat.set_shader_parameter("still", 0.0)
	_jet_mat.set_shader_parameter("scroll", -2.0)
	if _dot == null:
		const N := 16
		var img := Image.create(N, N, true, Image.FORMAT_RGBA8)
		for i in N:
			for j in N:
				var d := Vector2(i - N * 0.5 + 0.5, j - N * 0.5 + 0.5).length() / (N * 0.5)
				img.set_pixel(i, j, Color(1, 1, 1, clampf((1.0 - d) * 2.0, 0.0, 1.0)))
		img.generate_mipmaps()
		_dot = ImageTexture.create_from_image(img)
	_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Added, not blended: particles not yet emitted draw as black dots at the
	# emitter otherwise, and black adds nothing.
	_drop_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_drop_mat.vertex_color_use_as_albedo = true
	_drop_mat.albedo_texture = _dot
	_mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mist_mat.vertex_color_use_as_albedo = true
	_mist_mat.albedo_texture = _dot
	_foam_mat.shader = FOAM


func build(water: Water, floors: Array[Node3D]) -> void:
	_floors = floors
	if water == null:
		return
	for i in water.kind.size():
		var k := water.kind[i]
		if k == Water.NONE:
			continue
		var p := water.pos(i)
		_kinds[p] = k
		if k != Water.FALL:
			_still[p] = _place(p, _make_still(p, k, water))
			for side in SIDES:
				if _off_edge(p + side, water) and not _falls.has(p + side):
					_falls[p + side] = _place(p + side, _make_fall(p + side, water))
		elif water.kind_at(p + UP) != Water.FALL:
			_falls[p] = _place(p, _make_fall(p, water))


## Plays a "water" event from `start` seconds on; returns how long after
## `start` it runs. `water` is the water the move ends with.
func play(e: Dictionary, start: float, water: Water) -> float:
	var when := {}  # Vector3i -> seconds from now that the cell changes
	var longest := 0.0
	for c: Dictionary in e.removed + e.added:
		var t: float = start + c.delay * RIPPLE
		when[c.pos] = minf(when.get(c.pos, INF), t)
		longest = maxf(longest, t - start + GROW)

	# Waterfalls touched: old ones through the cells they ran down as drawn,
	# new ones through the water as it ends up.
	var tops := {}  # Vector3i -> seconds from now
	for p: Vector3i in when:
		if _kinds.get(p, Water.NONE) == Water.FALL:
			var top := p
			while _kinds.get(top + UP, Water.NONE) == Water.FALL:
				top += UP
			tops[top] = minf(tops.get(top, INF), when[p])
	for c: Dictionary in e.removed:
		_kinds.erase(c.pos)
	for c: Dictionary in e.added:
		_kinds[c.pos] = c.kind
	var redraw := {}  # Vector3i -> seconds from now: still water whose faces change
	for p: Vector3i in when:
		for n in _around(p):
			var k := water.kind_at(n)
			if not water.contains(n) and n.z >= 0 and n.z < water.floors:
				tops[n] = minf(tops.get(n, INF), when[p])
			elif k == Water.FALL:
				var top := n
				while water.kind_at(top + UP) == Water.FALL:
					top += UP
				tops[top] = minf(tops.get(top, INF), when[p])
			elif k != Water.NONE and _still.has(n) and not when.has(n):
				redraw[n] = minf(redraw.get(n, INF), when[p])

	for c: Dictionary in e.removed:
		_drain(c.pos, when[c.pos])
	# Still water that turns into a fall (off the head of a quaggle who walked
	# away) drains too.
	for c: Dictionary in e.added:
		_drain(c.pos, when[c.pos])
		if c.kind != Water.FALL:
			_grow(c.pos, _make_still(c.pos, c.kind, water), when[c.pos])
	for n: Vector3i in redraw:
		_swap(_still, n, _make_still(n, water.kind_at(n), water), redraw[n])

	for top: Vector3i in tops:
		var t: float = tops[top]
		var starts := water.kind_at(top) == Water.FALL and water.kind_at(top + UP) != Water.FALL 			or _off_edge(top, water)
		if _falls.has(top) and starts:
			_swap(_falls, top, _make_fall(top, water), t)
		elif _falls.has(top):
			longest = maxf(longest, _dry(top, t) - start)
		elif starts:
			longest = maxf(longest, _pour(top, water, t) - start)
	return longest


## Whether water pours into `p` from beside it off the edge of the map, where
## the rules let it go; the view still shows it falling into the void.
static func _off_edge(p: Vector3i, water: Water) -> bool:
	if water.contains(p) or p.z < 0 or p.z >= water.floors:
		return false
	for side in SIDES:
		var k := water.kind_at(p + side)
		if k == Water.SOURCE or (k == Water.FLOW and water.level_at(p + side) > 1):
			return true
	return false


## Spray off every edge where water presses against a quaggle damming it.
## `spots` are where the quaggles stand.
func set_dams(spots: Array[Vector3i], water: Water) -> void:
	var want := {}
	if water:
		for q in spots:
			if water.kind_at(q) != Water.NONE:
				continue  # afloat, or standing in water that flows past
			for side in SIDES:
				var p := q - side
				var k := water.kind_at(p)
				if k == Water.SOURCE or (k == Water.FLOW and water.level_at(p) > 1):
					want[[p, side]] = depth(p, water)
	for key: Array in _dams.keys():
		if not want.has(key):
			var node: Node3D = _dams[key]
			_dams.erase(key)
			node.queue_free()
	for key: Array in want:
		if not _dams.has(key):
			_dams[key] = _place(key[0], _dam_spray(key[1], want[key]))


## Water piling up against a quaggle on the `side` of its cell: a strip of
## foam along the edge and spray splashing up and back off it.
func _dam_spray(side: Vector3i, top: float) -> Node3D:
	var toward := Vector3(-side.x, 0, side.y)
	var along := Vector3(absf(toward.z), 0, absf(toward.x))
	var node := Node3D.new()
	node.set_meta("offset", toward * 0.38 + Vector3(0, top + 0.02, 0))
	var foam := MeshInstance3D.new()
	var strip := PlaneMesh.new()
	strip.size = Vector2(0.95, 0.26) if along.x > 0.5 else Vector2(0.26, 0.95)
	foam.mesh = strip
	foam.material_override = _foam_mat
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(foam)
	var spray := _drops(22, 0.5)
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	spray.emission_box_extents = along * 0.4
	spray.direction = (Vector3.UP - toward * 0.6).normalized()
	spray.spread = 28.0
	spray.initial_velocity_min = 1.4
	spray.initial_velocity_max = 2.4
	spray.scale_amount_min = 1.0
	spray.scale_amount_max = 2.0
	spray.gravity = Vector3(0, -8.0, 0)
	node.add_child(spray)
	return node


static func _around(p: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = [p + UP, p - UP]
	for side in SIDES:
		cells.append(p + side)
	return cells


func _place(p: Vector3i, node: Node3D) -> Node3D:
	node.position = World.cell_pos(p) + node.get_meta("offset", Vector3.ZERO)
	_floors[p.z].add_child(node)
	return node


## Shows `node` as the still water at `p`, growing up from the floor `t`
## seconds from now.
func _grow(p: Vector3i, node: Node3D, t: float) -> void:
	_still[p] = _place(p, node)
	node.scale = Vector3(1, 0.01, 1)
	var tw := node.create_tween()
	tw.tween_interval(t)
	tw.tween_property(node, "scale", Vector3.ONE, GROW).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Shrinks away the still water drawn at `p`, `t` seconds from now.
func _drain(p: Vector3i, t: float) -> void:
	var node: Node3D = _still.get(p)
	_still.erase(p)
	if node == null:
		return
	var tw := node.create_tween()
	tw.tween_interval(t)
	tw.tween_property(node, "scale", Vector3(1, 0.01, 1), GROW).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(node.queue_free)


## Replaces what `drawn` has at `p` with `node`, `t` seconds from now.
func _swap(drawn: Dictionary, p: Vector3i, node: Node3D, t: float) -> void:
	var old: Node3D = drawn.get(p)
	drawn[p] = _place(p, node)
	node.visible = false
	var tw := create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func() -> void:
		# A later change may already have replaced either.
		if is_instance_valid(old):
			old.queue_free()
		if is_instance_valid(node):
			node.visible = true)


# --- still water ------------------------------------------------------------

## How high still water at `p` stands above the cell's floor; 0 for none.
static func depth(p: Vector3i, water: Water) -> float:
	match water.kind_at(p):
		Water.FLOW:
			return SHEET * water.level_at(p)
		Water.SOURCE:
			return SHEET * Water.STRENGTH
		Water.POOL:
			# Under more water a pool fills its cell; on top, it stands as
			# high as the water that filled it.
			return H if water.kind_at(p + UP) != Water.NONE else SHEET * Water.STRENGTH
	return 0.0


func _make_still(p: Vector3i, k: int, water: Water) -> Node3D:
	var node := Node3D.new()
	var top := depth(p, water)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := Vector3(-0.5, 0.0, -0.5)
	var hi := Vector3(0.5, top, 0.5)
	if not (top >= H and water.kind_at(p + UP) != Water.NONE):
		_quad(st, Vector3(lo.x, top, lo.z), Vector3(hi.x, top, lo.z), Vector3(hi.x, top, hi.z), Vector3(lo.x, top, hi.z), Vector3.UP)
	for side in SIDES:
		var cover := depth(p + side, water) if water.kind_at(p + side) != Water.FALL else 0.0
		if cover >= top:
			continue
		# Grid +x is world -x; grid +y is world +z.
		var n := Vector3(-side.x, 0, side.y)
		var u := Vector3(absf(n.z), 0, absf(n.x)) * 0.5
		var c := n * 0.5
		_quad(st, c - u + Vector3(0, cover, 0), c + u + Vector3(0, cover, 0), c + u + Vector3(0, top, 0), c - u + Vector3(0, top, 0), n)
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = _still_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(m)
	if k == Water.SOURCE:
		_add_fountain(node, top)
	return node


## A quad facing `normal`, whichever way round the corners come.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var swap := b
		b = d
		d = swap
	st.set_normal(normal)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


## A jet of water from the middle of a spring, falling back as droplets.
func _add_fountain(node: Node3D, top: float) -> void:
	var jet := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.04
	tube.bottom_radius = 0.09
	tube.height = 0.55
	tube.radial_segments = 10
	jet.mesh = tube
	jet.material_override = _jet_mat
	jet.position = Vector3(0, top + 0.275, 0)
	jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(jet)
	var drops := _drops(22, 0.75)
	drops.position = Vector3(0, top + 0.5, 0)
	drops.spread = 40.0
	drops.initial_velocity_min = 0.9
	drops.initial_velocity_max = 1.5
	drops.gravity = Vector3(0, -6.0, 0)
	node.add_child(drops)


func _drops(amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.11, 0.11)
	quad.material = _drop_mat
	p.mesh = quad
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.85, 0.95, 1.0, 0.95), Color(0.6, 0.85, 1.0, 0.0)])
	p.color_ramp = g
	return p


# --- waterfalls ---------------------------------------------------------------

## The waterfall starting at `top`: a sheet over each edge water pours in
## across, down to where it lands (or on into the void, fading out).
func _make_fall(top: Vector3i, water: Water) -> Node3D:
	var node := Node3D.new()
	var low := top
	while water.kind_at(low - UP) == Water.FALL:
		low -= UP
	if not water.contains(top):
		low.z = 0  # off the map, nothing below
	var lost := low.z == 0
	var bottom := -float(top.z - low.z + 1) * H  # from the top cell's floor
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("still", 0.0)
	mat.set_shader_parameter("scroll", 2.5)
	var floor_y := World.cell_pos(top).y
	node.set_meta("land", floor_y + bottom)
	if lost:
		mat.set_shader_parameter("fade_from", floor_y + bottom)
		mat.set_shader_parameter("fade_length", VOID_DROP)
		bottom -= VOID_DROP
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fed := false
	for side in SIDES:
		var k := water.kind_at(top + side)
		if k == Water.FLOW or k == Water.SOURCE or k == Water.POOL:
			if not water.contains(top) and k == Water.FLOW and water.level_at(top + side) < 2:
				continue  # too weak to reach over the map's edge
			fed = true
			_ribbon(st, side, depth(top + side, water), bottom, 0.5, CURL)
			if not lost:
				node.add_child(_splash(side, bottom))
	if not fed:
		_ribbon(st, Vector3i(1, 0, 0), 0.0, bottom, 0.0, 0.0)
	if not lost:
		node.add_child(_foam(bottom))
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(m)
	node.set_meta("mat", mat)
	node.set_meta("span", Vector2(floor_y + bottom, floor_y + SHEET * Water.STRENGTH))
	return node


## A slab of water pouring over the edge `edge` from the middle of the cell
## toward `side` (where the water comes from): out level from height `from`,
## curling down with radius `curl`, then straight down to `bottom`.
static func _ribbon(st: SurfaceTool, side: Vector3i, from: float, bottom: float, edge: float, curl: float) -> void:
	var toward := Vector3(-side.x, 0, side.y)  # world direction of the feeding side
	var along := Vector3(absf(toward.z), 0, absf(toward.x)) * 0.5
	var lip := toward * edge
	var profile: Array[Vector2] = [Vector2(-0.06, from)]  # (out from the edge, height)
	const STEPS := 6
	for i in STEPS + 1:
		var a := PI * 0.5 * i / STEPS
		profile.append(Vector2(curl * sin(a), from - curl + curl * cos(a)))
	profile.append(Vector2(curl, bottom))
	# The underside: the profile moved in by the thickness, square to it.
	var thick := minf(THICK, curl) if curl > 0.0 else THICK * 0.5
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for i in profile.size():
		var dir := profile[mini(i + 1, profile.size() - 1)] - profile[maxi(i - 1, 0)]
		dir = dir.normalized()
		var under := profile[i] + Vector2(dir.y, -dir.x) * thick
		outer.append(lip - toward * profile[i].x + Vector3(0, profile[i].y, 0))
		inner.append(lip - toward * under.x + Vector3(0, under.y, 0))
	for i in profile.size() - 1:
		var down := outer[i + 1] - outer[i]
		_quad(st, outer[i] - along, outer[i] + along, outer[i + 1] + along, outer[i + 1] - along, down.cross(along).normalized())
		_quad(st, inner[i] - along, inner[i] + along, inner[i + 1] + along, inner[i + 1] - along, along.cross(down).normalized())
		for end: float in [-1.0, 1.0]:
			_quad(st, outer[i] + along * end, outer[i + 1] + along * end, inner[i + 1] + along * end, inner[i] + along * end, along * end)


## Spray and mist where a waterfall over the edge toward `side` lands.
func _splash(side: Vector3i, bottom: float) -> Node3D:
	var toward := Vector3(-side.x, 0, side.y)
	var line := Vector3(absf(toward.z), 0, absf(toward.x)) * 0.45
	var node := Node3D.new()
	node.position = toward * (0.5 - CURL) + Vector3(0, bottom + 0.1, 0)
	var spray := _drops(28, 0.55)
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	spray.emission_box_extents = line
	spray.spread = 60.0
	spray.initial_velocity_min = 1.2
	spray.initial_velocity_max = 2.4
	spray.scale_amount_min = 0.8
	spray.scale_amount_max = 1.6
	spray.gravity = Vector3(0, -7.0, 0)
	node.add_child(spray)
	var mist := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	quad.material = _mist_mat
	mist.mesh = quad
	mist.amount = 10
	mist.lifetime = 1.3
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = line
	mist.direction = Vector3.UP
	mist.spread = 70.0
	mist.initial_velocity_min = 0.2
	mist.initial_velocity_max = 0.5
	mist.gravity = Vector3.ZERO
	mist.scale_amount_min = 0.7
	mist.scale_amount_max = 1.4
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	mist.color_ramp = g
	node.add_child(mist)
	return node


## White water churning over the cell a waterfall lands in, bubbles boiling
## up all over it.
func _foam(bottom: float) -> MeshInstance3D:
	var patch := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	patch.mesh = plane
	patch.material_override = _foam_mat
	patch.position = Vector3(0, bottom + SHEET * Water.STRENGTH + 0.015, 0)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var boil := _drops(24, 0.35)
	boil.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	boil.emission_box_extents = Vector3(0.42, 0.0, 0.42)
	boil.spread = 25.0
	boil.initial_velocity_min = 0.4
	boil.initial_velocity_max = 0.9
	boil.gravity = Vector3(0, -3.0, 0)
	boil.scale_amount_min = 1.0
	boil.scale_amount_max = 1.8
	patch.add_child(boil)
	return patch


## Starts the waterfall at `top` `t` seconds from now, pouring down from its
## lip. Returns when it has reached the bottom, in seconds from now.
func _pour(top: Vector3i, water: Water, t: float) -> float:
	var node := _make_fall(top, water)
	_falls[top] = _place(top, node)
	var mat: ShaderMaterial = node.get_meta("mat")
	var span: Vector2 = node.get_meta("span")
	mat.set_shader_parameter("front", span.y)
	var time := (span.y - span.x) / POUR
	_spray(node, false)
	var tw := node.create_tween()
	tw.tween_interval(t)
	tw.tween_method(func(y: float) -> void: mat.set_shader_parameter("front", y), span.y, span.x, time)
	tw.tween_callback(_spray.bind(node, true))
	# The move waits only until it lands, not while it runs off into the void.
	return t + (span.y - float(node.get_meta("land"))) / POUR


## Dries up the waterfall at `top` `t` seconds from now, from the top down.
## Returns when it is gone, in seconds from now.
func _dry(top: Vector3i, t: float) -> float:
	var node: Node3D = _falls[top]
	_falls.erase(top)
	var mat: ShaderMaterial = node.get_meta("mat")
	var span: Vector2 = node.get_meta("span")
	var time := (span.y - span.x) / POUR
	var tw := node.create_tween()
	tw.tween_interval(t)
	tw.tween_method(func(y: float) -> void: mat.set_shader_parameter("cut_top", y), span.y, span.x, time)
	tw.tween_callback(node.queue_free)
	return t + (span.y - float(node.get_meta("land"))) / POUR


## Turns a waterfall's landing on or off: spray, mist and foam.
static func _spray(node: Node3D, on: bool) -> void:
	for child in node.get_children():
		if child.get_child_count() > 0 and child.get_child(0) is CPUParticles3D:
			for p: CPUParticles3D in child.get_children():
				p.emitting = on
		elif child is MeshInstance3D and child.material_override is ShaderMaterial and child.material_override.shader == FOAM:
			child.visible = on
			for p: CPUParticles3D in child.get_children():
				p.emitting = on
