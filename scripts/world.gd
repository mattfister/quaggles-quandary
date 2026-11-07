class_name World
extends Node3D
## Builds the 3D view of a Rules state and plays back move events.
## Grid (x, y, floor) maps to world (-x, floor * H, y), which keeps the
## original's on-screen orientation (its camera mirrored the map files).

const H := 1.4  # height between floors (lheight)
const TILE_T := 0.3
const LOW := H - TILE_T  # a wall under a floor tile stops at the tile's underside
const HOP_TIME := 0.15
const SLIDE_TIME := 0.075
const FALL_TIME := 0.24
const RISE_TIME := 0.45
const SWITCH_DELAY := 0.4  # pause on a lost quaggle before moving to the next
const DEFAULT_PITCH := 1.0  # about 57 degrees above the horizon
const DEFAULT_DIST := 14.0
const BLOCK := preload("res://shaders/block.gdshader")
const BLOCK_FADE := preload("res://shaders/block_fade.gdshader")
const FLOOR_COLORS: Array[Color] = [Color("5fc9b0"), Color("f6d58a"), Color("f3a08c"), Color("b9a6ee")]
const WALL_TOP := Color("8a90b8")
const WALL_SIDE := Color("5d638c")
const SKY_HORIZON := Color("c4e4ff")
const BASE_STEPS: Array[float] = [0.5, 1.0, 1.6]  # rock depth under the ground floor, by steps in from its edge
const BASE_TOP := Color("c79a74")
const BASE_SIDE := Color("a8775a")
const CRACK_TOP := Color("c9a47a")
const CRACK_SIDE := Color("8c6a4c")

var rules: Rules
var demo := false  # slow orbit, no marker (menu backdrop)
## The level editor's preview: the camera looks at `edit_focus` and is steered
## by the editor rather than by input here; no marker.
var edit_mode := false
var edit_focus := Vector3.ZERO
var yaw := 0.0
var pitch := DEFAULT_PITCH
var dist := DEFAULT_DIST
var floor_limit := 0

var _camera := Camera3D.new()
var _sky_mat := ShaderMaterial.new()
var _marker := MeshInstance3D.new()
var _cursor := MeshInstance3D.new()
var _selection := MeshInstance3D.new()
var _vignette := CanvasLayer.new()
var _blob_mesh: PlaneMesh
var _lava_mesh: PlaneMesh
var _root: Node3D
var _floors: Array[Node3D] = []
var _quags := {}      # id -> Quaggle
var _dynamic := {}    # Vector3i -> Array[Node3D]
var _spinners: Array[Node3D] = []
var _water: WaterView
var _focus := Vector3.ZERO
var _shown := 0       # id the camera and marker follow; trails rules.active
var _hold := 0.0      # time left before _shown catches up
var _gen := 0
var _time := 0.0
var _dragging := false
var _turn: Tween
var _yaw_goal := 0.0

var _chunk_meshes: Array[BoxMesh] = []  # a quarter of a cracked tile, a pebble
var _ring_tex: ImageTexture
var _dot_tex: ImageTexture
var _particle_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _key_mat: StandardMaterial3D
var _field_mat: ShaderMaterial


func _ready() -> void:
	_make_textures()
	_camera.fov = 45.0
	_camera.near = 0.1
	_camera.far = 1500.0
	add_child(_camera)
	_camera.make_current()

	var sky := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 700.0
	dome.height = 1400.0
	dome.radial_segments = 32
	dome.rings = 16
	sky.mesh = dome
	_sky_mat.shader = preload("res://shaders/sky.gdshader")
	sky.material_override = _sky_mat
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_camera.add_child(sky)

	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.5, -1.0, -0.8))
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.5

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY_HORIZON
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.87, 1.0)
	env.ambient_light_energy = 0.33
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.48
	ring.outer_radius = 0.6
	_marker.mesh = ring
	_marker.scale = Vector3(1, 0.25, 1)
	_marker.material_override = _flat(Color(1.0, 0.72, 0.2), 0.9)
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)

	for box: MeshInstance3D in [_cursor, _selection]:
		box.mesh = BoxMesh.new()
		var mat := _flat(Color(1.0, 0.72, 0.2, 0.35) if box == _cursor else Color(0.3, 0.55, 1.0, 0.3), 0.6)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = box == _cursor
		box.material_override = mat
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		box.visible = false
		add_child(box)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.material = ShaderMaterial.new()
	(vignette.material as ShaderMaterial).shader = preload("res://shaders/vignette.gdshader")
	_vignette.layer = -1
	_vignette.add_child(vignette)
	add_child(_vignette)


static func cell_pos(p: Vector3i) -> Vector3:
	return Vector3(-(p.x + 0.5), p.z * H, p.y + 0.5)


## Rebuilds everything from `r`. Camera angle is kept unless `reset_camera`.
func build(r: Rules, reset_camera := true) -> void:
	rules = r
	_gen += 1
	_shown = r.active
	_hold = 0.0
	if _root:
		_root.queue_free()
	_root = Node3D.new()
	add_child(_root)
	_floors.clear()
	_quags.clear()
	_dynamic.clear()
	_spinners.clear()

	var level_seed := hash(r.name)
	_sky_mat.set_shader_parameter("seed", float(level_seed % 97))

	for f in r.floors:
		var node := Node3D.new()
		_root.add_child(node)
		_floors.append(node)
		var groups := {}
		for y in r.height:
			for x in r.width:
				var c := r.cell(f, x, y)
				if c == Rules.EMPTY:
					continue
				var p := Vector3i(x, y, f)
				var at := cell_pos(p)
				var shade := 1.0 if (x + y) % 2 == 0 else 0.93
				var slab := Transform3D(Basis.IDENTITY, at - Vector3(0, TILE_T * 0.5, 0))
				var column := Transform3D(Basis.IDENTITY, at + Vector3(0, H * 0.5, 0))
				# A full-height wall's top would sit level with the top of a
				# tile on it and flicker, so that wall is cut short.
				var capped := _has_tile(r.cell(f + 1, x, y))
				var low := Transform3D(Basis.IDENTITY, at + Vector3(0, LOW * 0.5, 0))
				var joined := _joined(r, p)
				match c:
					Rules.WALL:
						_group(groups, "wall_low" if capped else "wall", low if capped else column, shade * 0.5 + 0.5, joined)
					Rules.WINDOW: _group(groups, "window_low" if capped else "window", low if capped else column, 1.0, joined)
					Rules.ICE: _group(groups, "ice", slab, shade * 0.5 + 0.5, joined)
					Rules.DOWN: _group(groups, "hole", slab)
					Rules.CRACK: _add_crack(node, p)
					_:
						_group(groups, "tile", slab, shade, joined)
						match c:
							Rules.GROUND, Rules.START, Rules.SPAWN, Rules.SOURCE: pass
							Rules.FIRE: _add_fire(node, p)
							Rules.KEY: _add_key(node, p)
							Rules.UP: _add_lift(node, at)
							Rules.FIELD: _add_field(node, p)
							Rules.GOAL:
								_group(groups, "goal", column)
								_group(groups, "pad", Transform3D(Basis.IDENTITY, at + Vector3(0, 0.02, 0)))
								_add_sparkles(node, at)
							_: _group(groups, "block", Transform3D(Basis.IDENTITY, at + Vector3(0, 0.35, 0)))
		if f == 0:
			_add_base(groups)
		for kind: String in groups:
			_add_multimesh(node, kind, groups[kind], f)

	_water = WaterView.new()
	_root.add_child(_water)
	_water.build(r.water, _floors)

	for q in r.quaggles:
		if q.gone:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = level_seed + q.id * 7919
		var quag := Quaggle.new()
		_root.add_child(quag)
		quag.setup(q.id, absi(level_seed) + q.id * 3, rng)
		quag.position = cell_pos(q.pos)
		quag.face(Vector3(0, 0, 1))
		_add_blob(quag)
		_quags[q.id] = quag
		if q.key:
			_give_key(quag)

	if reset_camera:
		yaw = 0.0
		pitch = DEFAULT_PITCH
		dist = DEFAULT_DIST
		_focus = _focus_target()
	set_floor_limit(r.floors if reset_camera else floor_limit)


## Whether cell `c` has a floor tile (or ice or cracked tile) at its bottom.
static func _has_tile(c: int) -> bool:
	return c != Rules.EMPTY and c != Rules.WALL and c != Rules.WINDOW and c != Rules.DOWN


## Which cells draw as one continuous shape with their like neighbours: 0 for
## none, else a class shared by everything that merges together.
static func _merge_class(c: int) -> int:
	match c:
		Rules.EMPTY, Rules.DOWN, Rules.CRACK: return 0
		Rules.WALL: return 1
		Rules.WINDOW: return 2
		Rules.ICE: return 3
	return 4


## For the block shader: which of the cell's sides (+x, -x, +z, -z in world
## axes) join a neighbour of the same merge class.
static func _joined(r: Rules, p: Vector3i) -> Color:
	var k := _merge_class(r.cell_at(p))
	var j := Color(0, 0, 0, 0)
	if k == 0:
		return j
	var sides: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in 4:
		j[i] = 1.0 if _merge_class(r.cell(p.z, p.x + sides[i].x, p.y + sides[i].y)) == k else 0.0
	return j


func set_floor_limit(n: int) -> void:
	floor_limit = clampi(n, 1, rules.floors)
	for f in _floors.size():
		_floors[f].visible = f < floor_limit


func active_floor() -> int:
	return rules.quaggles[rules.active].pos.z


## Turns WASD-style input (x: right, y: forward) into a grid step, relative to
## the camera's nearest quarter turn.
func grid_dir(input: Vector2i) -> Vector2i:
	var quarter := roundf(yaw / (PI * 0.5)) * PI * 0.5
	var w := (Vector3(0, 0, -1) * input.y + Vector3(1, 0, 0) * input.x).rotated(Vector3.UP, quarter)
	return Vector2i(-roundi(w.x), roundi(w.z))


## Animates the events of one move. Returns how long the animation takes.
## Water plays once every quaggle before it has finished moving, and anyone
## it floats rises once it has spread.
func play(events: Array[Dictionary]) -> float:
	var clock := {}
	var tweens := {}
	var slid := {}
	var leaving: Array[int] = []
	var water_end := 0.0
	for e in events:
		if e.type == "water" or e.id < 0:
			var start := water_end
			for t: float in clock.values():
				start = maxf(start, t)
			if e.type == "water":
				water_end = start + _water.play(e, start, rules.water)
			else:
				var cell_tw := create_tween()
				cell_tw.tween_interval(start)
				cell_tw.tween_callback(_apply_cell.bind(e, _gen))
			continue
		var id: int = e.id
		var quag: Quaggle = _quags.get(id)
		if quag == null:
			continue
		if not tweens.has(id):
			tweens[id] = quag.create_tween()
			clock[id] = 0.0
		var tw: Tween = tweens[id]
		match e.type:
			"move":
				var from: Vector3i = e.from
				var to: Vector3i = e.to
				var kind := "hop"
				var time := HOP_TIME
				if e.get("float", false):
					kind = "rise"
					time = RISE_TIME
					if clock[id] < water_end:
						tw.tween_interval(water_end - clock[id])
						clock[id] = water_end
				elif to.z < from.z:
					kind = "fall"
					time = FALL_TIME * (from.z - to.z)
				elif to.z > from.z:
					kind = "rise"
					time = RISE_TIME
					tw.tween_callback(Sfx.play.bind("lift"))
				elif e.glide:
					kind = "slide"
					time = SLIDE_TIME if slid.has(id) else HOP_TIME
					if not slid.has(id):
						slid[id] = true
						if e.cell == Rules.ICE:
							tw.tween_callback(Sfx.play.bind("slide", 0.1))
				else:
					tw.tween_callback(Sfx.play.bind("step", 0.2))
				if e.cell == Rules.FIELD:
					tw.tween_callback(Sfx.play.bind("field"))
				quag.queue_step(tw, cell_pos(from), cell_pos(to), kind, time)
				if kind == "fall":
					tw.tween_callback(Sfx.play.bind("land", 0.1))
				clock[id] += time
			"cell":
				tw.tween_callback(_apply_cell.bind(e, _gen))
			"burn":
				tw.tween_callback(Sfx.play.bind("burn"))
				quag.queue_burn(tw)
				clock[id] += 0.55
				leaving.append(id)
			"fall_out":
				var from: Vector3i = e.from
				var to: Vector3i = e.to
				if to != from:
					tw.tween_callback(Sfx.play.bind("step", 0.2))
					quag.queue_step(tw, cell_pos(from), cell_pos(to), "hop", HOP_TIME)
					clock[id] += HOP_TIME
				tw.tween_callback(Sfx.play.bind("fall"))
				quag.queue_fall_out(tw)
				clock[id] += 0.7
				leaving.append(id)
			"win":
				tw.tween_callback(Sfx.play.bind("win"))
				tw.tween_callback(quag.cheer)
				clock[id] += 0.3
	for id in leaving:
		_quags.erase(id)
	var total := water_end
	for id: int in clock:
		total = maxf(total, clock[id])
	if leaving.has(_shown):
		total += SWITCH_DELAY
		_hold = total
	return total


func _apply_cell(e: Dictionary, gen: int) -> void:
	if gen != _gen:
		return
	var p: Vector3i = e.pos
	var at := cell_pos(p)
	var nodes: Array = _dynamic.get(p, [])
	_dynamic.erase(p)
	match e.was:
		Rules.CRACK:
			Sfx.play("crumble", 0.15)
			var below := rules.cell(p.z - 1, p.x, p.y)
			if below == Rules.WALL or below == Rules.WINDOW:
				_add_cap(p, below)
			for n: Node3D in nodes:
				n.queue_free()
			_crumble(p)
			_puff(at, Color(0.5, 0.42, 0.35))
		Rules.KEY:
			Sfx.play("key")
			for n: Node3D in nodes:
				_spinners.erase(n)
				n.queue_free()
			_puff(at + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.3))
			if _quags.has(e.id):
				_give_key(_quags[e.id])
		Rules.FIRE:
			for n: Node3D in nodes:
				n.queue_free()
			_puff(at + Vector3(0, 0.3, 0), Color(0.25, 0.25, 0.25))
		Rules.FIELD:
			for n: Node3D in nodes:
				var tw := n.create_tween()
				tw.tween_property(n, "scale", Vector3(1.15, 0.0, 1.15), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				tw.tween_callback(n.queue_free)
			_puff(at + Vector3(0, 0.6, 0), Color(0.85, 0.3, 0.8))
			if _quags.has(e.id):
				_take_key(_quags[e.id])


func _process(delta: float) -> void:
	_time += delta
	for s in _spinners:
		s.rotation.y += delta * 2.0
		s.position.y = s.get_meta("base_y") + 0.08 * sin(_time * 2.5)
	if rules == null:
		return
	if demo:
		yaw += delta * 0.12
	_hold -= delta
	if _hold <= 0.0:
		_shown = rules.active
	_focus = _focus.lerp(_focus_target(), 1.0 - exp(-delta * 7.0))
	var offset := Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw) * dist
	_camera.position = _focus + offset
	_camera.look_at(_focus)

	_vignette.visible = not edit_mode
	for child in _root.get_children():
		if child is Quaggle:
			_place_blob(child)

	var quag: Quaggle = _quags.get(_shown)
	_marker.visible = quag != null and not demo and not edit_mode and not rules.won
	if quag:
		_marker.position = quag.position + Vector3(0, 0.03, 0)
		_marker.scale = Vector3(1, 0.25, 1) * (1.0 + 0.08 * sin(_time * 6.0))


func _focus_target() -> Vector3:
	if edit_mode:
		return edit_focus
	var quag: Quaggle = _quags.get(_shown)
	if quag:
		return quag.position + Vector3(0, 0.6, 0)
	return _focus


func _unhandled_input(event: InputEvent) -> void:
	if demo or edit_mode:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(5.0, dist * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(45.0, dist * 1.1)
	elif event is InputEventMouseMotion and _dragging:
		_stop_turn()
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.006, 0.35, 1.5)


## Swings the camera round by `steps` quarter turns (positive: to the left),
## ending square to the grid. Presses during a turn add to where it is going.
func turn(steps: int) -> void:
	var quarter := PI * 0.5
	var from := _yaw_goal if _turn and _turn.is_running() else roundf(yaw / quarter) * quarter
	_yaw_goal = from + steps * quarter
	_stop_turn()
	_turn = create_tween()
	_turn.tween_property(self, "yaw", _yaw_goal, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_turn() -> void:
	if _turn:
		_turn.kill()
		_turn = null


func recenter() -> void:
	_stop_turn()
	yaw = 0.0
	pitch = DEFAULT_PITCH
	dist = DEFAULT_DIST
	set_floor_limit(active_floor() + 1)


# --- level editor -----------------------------------------------------------

## The grid cell (x, y) on floor `f` under a point of the screen, or null if
## that floor's plane is not under it.
func pick(screen: Vector2, f: int) -> Variant:
	var origin := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var t := (f * H - origin.y) / dir.y
	if t <= 0.0:
		return null
	var hit := origin + dir * t
	return Vector2i(floori(-hit.x), floori(hit.z))


## Middle of a level of the given size, for the editor camera to look at.
static func middle(w: int, h: int, f: int) -> Vector3:
	return Vector3(-w * 0.5, f * H * 0.5, h * 0.5)


## Outlines the cells from `a` to `b` (grid corners, inclusive) with the
## hover cursor (`selection` false) or the selection box.
func show_box(a: Vector3i, b: Vector3i, selection := false) -> void:
	var box := _selection if selection else _cursor
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	# From the bottom of the floor tiles to just over the tops of walls.
	var size := Vector3(hi.x - lo.x + 1, (hi.z - lo.z + 1) * H + TILE_T, hi.y - lo.y + 1) + Vector3(0.04, 0.06, 0.04)
	(box.mesh as BoxMesh).size = size
	box.position = Vector3(-(lo.x + size.x * 0.5) + 0.02, lo.z * H - TILE_T - 0.02 + size.y * 0.5, lo.y + size.z * 0.5 - 0.02)
	box.visible = true


func hide_box(selection := false) -> void:
	(_selection if selection else _cursor).visible = false


# --- construction helpers ---------------------------------------------------

func _group(groups: Dictionary, kind: String, t: Transform3D, shade := 1.0, joined := Color(0, 0, 0, 0)) -> void:
	if not groups.has(kind):
		groups[kind] = []
	groups[kind].append([t, Color(shade, shade, shade), joined])


## The rock under the ground floor, stepping deeper toward the middle so the
## level reads as a solid floating island. Groups "base:<height in cm>".
func _add_base(groups: Dictionary) -> void:
	var sides: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in rules.height:
		for x in rules.width:
			if not _on_base(x, y):
				continue
			# Steps in from the edge, counting diagonals.
			var steps := 1
			while steps < BASE_STEPS.size() and _base_square(x, y, steps):
				steps += 1
			var c := rules.cell(0, x, y)
			# Walls stand on y = 0 with no tile under them; fill that in.
			var top := 0.0 if c == Rules.WALL or c == Rules.WINDOW else -TILE_T
			var height := BASE_STEPS[steps - 1] + top + TILE_T
			var joined := Color(0, 0, 0, 0)
			for i in 4:
				joined[i] = 1.0 if _on_base(x + sides[i].x, y + sides[i].y) else 0.0
			var at := cell_pos(Vector3i(x, y, 0)) + Vector3(0, top - height * 0.5, 0)
			var shade := 1.0 if (x + y) % 2 == 0 else 0.96
			_group(groups, "base:%d" % roundi(height * 100.0), Transform3D(Basis.IDENTITY, at), shade, joined)


func _on_base(x: int, y: int) -> bool:
	var c := rules.cell(0, x, y)
	return c != Rules.EMPTY and c != Rules.DOWN and c != Rules.CRACK


## Whether every cell within `r` of (x, y) is on the base.
func _base_square(x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if not _on_base(x + dx, y + dy):
				return false
	return true


func _add_multimesh(parent: Node3D, kind: String, items: Array, f: int) -> void:
	var box := BoxMesh.new()
	var mat: Material
	var floor_color := FLOOR_COLORS[f % FLOOR_COLORS.size()]
	var shadows := true
	if kind.begins_with("base:"):
		box.size = Vector3(1, kind.substr(5).to_float() / 100.0, 1)
		mat = _block(box.size, BASE_TOP, BASE_SIDE)
		(mat as ShaderMaterial).set_shader_parameter("shade_span", Vector2(0.15, 0.85))
		shadows = false
	match kind:
		"tile":
			box.size = Vector3(1, TILE_T, 1)
			mat = _block(box.size, floor_color, floor_color.darkened(0.35))
		"ice":
			box.size = Vector3(1, TILE_T, 1)
			var ice := _block(box.size, Color("a9e4ff"), Color("6fa9d0"))
			ice.set_shader_parameter("streaks", 1.0)
			ice.set_shader_parameter("edge", 0.03)
			mat = ice
		"wall", "wall_low":
			box.size = Vector3(1, H if kind == "wall" else LOW, 1)
			mat = _wall_mat(box.size, 0.0, box.size.y / H)
		"window", "window_low":
			box.size = Vector3(1, H if kind == "window" else LOW, 1)
			mat = _glass_mat(box.size)
			shadows = false
		"hole":
			box.size = Vector3(0.9, 0.03, 0.9)
			mat = _flat(Color(0.05, 0.05, 0.1, 0.55), 0.0)
			shadows = false
		"block":
			box.size = Vector3(0.7, 0.7, 0.7)
			mat = _block(box.size, Color("6b5f58"), Color("4d443f"))
		"pad":
			box.size = Vector3(0.84, 0.04, 0.84)
			mat = _flat(Color(0.35, 1.0, 0.5), 1.6)
			shadows = false
		"goal":
			box.size = Vector3(0.8, H * 1.5, 0.8)
			var beam := ShaderMaterial.new()
			beam.shader = preload("res://shaders/beam.gdshader")
			beam.set_shader_parameter("height", box.size.y)
			mat = beam
			shadows = false
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = box
	mm.instance_count = items.size()
	for i in items.size():
		var t: Transform3D = items[i][0]
		if kind == "goal":
			t.origin.y += (box.size.y - H) * 0.5
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, items[i][1])
		mm.set_instance_custom_data(i, items[i][2])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	if not shadows:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


func _wall_mat(size: Vector3, from: float, to: float) -> ShaderMaterial:
	var m := _block(size, WALL_TOP, WALL_SIDE)
	m.set_shader_parameter("shade_span", Vector2(from, to))
	return m


func _glass_mat(size: Vector3) -> ShaderMaterial:
	var glass := ShaderMaterial.new()
	glass.shader = preload("res://shaders/glass.gdshader")
	glass.set_shader_parameter("size", size)
	return glass


## Tops a cut-short wall (or glass) back up to full height once the cracked
## tile on it has crumbled, so whoever stands there is not left hovering.
func _add_cap(p: Vector3i, below: int) -> void:
	var cap := MeshInstance3D.new()
	var box := BoxMesh.new()
	if below == Rules.WALL:
		box.size = Vector3(1, TILE_T, 1)
		cap.material_override = _wall_mat(box.size, LOW / H, 1.0)
	else:
		box.size = Vector3(1, TILE_T, 1)
		cap.material_override = _glass_mat(box.size)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.mesh = box
	cap.position = cell_pos(p) - Vector3(0, TILE_T * 0.5, 0)
	_floors[p.z - 1].add_child(cap)


func _block(size: Vector3, top: Color, side: Color, shader: Shader = BLOCK) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("side_color", side)
	return m


## Plain colour; translucent if alpha < 1, glowing by `emission`.
func _flat(color: Color, emission: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = Color(color, 1.0)
		m.emission_energy_multiplier = emission
	return m


func _track(p: Vector3i, node: Node3D) -> void:
	if not _dynamic.has(p):
		_dynamic[p] = []
	_dynamic[p].append(node)


func _add_crack(parent: Node3D, p: Vector3i) -> void:
	var tile := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.94, TILE_T, 0.94)
	tile.mesh = box
	var mat := _block(box.size, CRACK_TOP, CRACK_SIDE)
	mat.set_shader_parameter("cracks", 1.0)
	mat.set_shader_parameter("crack_seed", float(hash(p) % 1000))
	tile.material_override = mat
	tile.position = cell_pos(p) - Vector3(0, TILE_T * 0.5, 0)
	parent.add_child(tile)
	_track(p, tile)


## Breaks a cracked tile into its four quarters and some loose pebbles, which
## shiver, then tumble away one by one, fading out as they go.
func _crumble(p: Vector3i) -> void:
	if _chunk_meshes.is_empty():
		for size: float in [0.45, 0.13]:
			var box := BoxMesh.new()
			box.size = Vector3(size, TILE_T if size > 0.2 else size, size)
			_chunk_meshes.append(box)
	var middle := cell_pos(p) - Vector3(0, TILE_T * 0.5, 0)
	for i in 10:
		var quarter := i < 4
		var chunk := MeshInstance3D.new()
		var box := _chunk_meshes[0 if quarter else 1]
		chunk.mesh = box
		# Each its own material, to fade on its own.
		var mat := _block(box.size, CRACK_TOP, CRACK_SIDE, BLOCK_FADE)
		if quarter:
			mat.set_shader_parameter("cracks", 1.0)
			mat.set_shader_parameter("crack_seed", float(hash(p) % 1000 + i))
		chunk.material_override = mat
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var spot := Vector3(randf_range(-0.35, 0.35), randf_range(-0.05, 0.1), randf_range(-0.35, 0.35))
		if quarter:
			spot = Vector3(0.235 if i % 2 else -0.235, 0, 0.235 if i < 2 else -0.235)
		chunk.position = middle + spot
		chunk.rotation.y = randf_range(-0.12, 0.12) if quarter else randf_range(0, TAU)
		chunk.scale = Vector3.ONE * randf_range(0.9, 1.0)
		_root.add_child(chunk)
		var tw := chunk.create_tween()
		for k in 3:
			var shiver := Vector3(randf_range(-0.025, 0.025), 0, randf_range(-0.025, 0.025))
			tw.tween_property(chunk, "position", middle + spot + shiver, 0.03)
		tw.tween_interval(randf_range(0.0, 0.2) if quarter else randf_range(0.0, 0.06))
		var drift := spot * randf_range(0.5, 1.2) + Vector3(randf_range(-0.15, 0.15), 0, randf_range(-0.15, 0.15))
		tw.tween_property(chunk, "position", middle + spot + drift + Vector3(0, -6.0, 0), 0.75) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(chunk, "rotation", Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3)), 0.75)
		var fade := func(v: float) -> void: mat.set_shader_parameter("fade", v)
		tw.parallel().tween_method(fade, 0.0, 1.0, 0.45).set_delay(0.3)
		tw.tween_callback(chunk.queue_free)


func _add_fire(parent: Node3D, p: Vector3i) -> void:
	if _lava_mesh == null:
		_lava_mesh = PlaneMesh.new()
		_lava_mesh.size = Vector2(1, 1)
	var fire := MeshInstance3D.new()
	fire.mesh = _lava_mesh
	# Edged with a crust where it does not meet more fire, so a run of fire
	# is one pool (the lava's pattern is in world space, so it carries on).
	var joined := Color(0, 0, 0, 0)
	var sides: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in 4:
		joined[i] = 1.0 if rules.cell(p.z, p.x + sides[i].x, p.y + sides[i].y) == Rules.FIRE else 0.0
	var lava := ShaderMaterial.new()
	lava.shader = preload("res://shaders/lava.gdshader")
	lava.set_shader_parameter("size", Vector3(1, 0, 1))
	lava.set_shader_parameter("joined", joined)
	fire.material_override = lava
	fire.position = cell_pos(p) + Vector3(0, 0.003, 0)  # flush on the tile, no sides
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fire)
	_track(p, fire)

	var flames := _particles(10, 0.9)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(0.4, 0.02, 0.4)
	flames.initial_velocity_min = 0.7
	flames.initial_velocity_max = 1.5
	flames.scale_amount_min = 0.7
	flames.scale_amount_max = 1.5
	flames.color_ramp = _ramp([Color(1, 0.95, 0.4, 0.9), Color(1, 0.45, 0.05, 0.8), Color(0.8, 0.05, 0.0, 0.0)])
	flames.preprocess = 1.0
	fire.add_child(flames)


func _add_key(parent: Node3D, p: Vector3i) -> void:
	if _key_mat == null:
		_key_mat = _flat(Color(1.0, 0.8, 0.15), 0.6)
		_key_mat.metallic = 0.8
		_key_mat.roughness = 0.3
	var key := _make_key()
	key.position = cell_pos(p) + Vector3(0, 0.7, 0)
	key.set_meta("base_y", key.position.y)
	parent.add_child(key)
	_spinners.append(key)
	_track(p, key)


func _make_key() -> Node3D:
	var key := Node3D.new()
	var bow := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.09
	torus.outer_radius = 0.17
	bow.mesh = torus
	bow.rotation.x = PI * 0.5
	bow.position.y = 0.3
	var shaft := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.07, 0.42, 0.07)
	shaft.mesh = bar
	shaft.position.y = -0.05
	var bit := MeshInstance3D.new()
	var tooth := BoxMesh.new()
	tooth.size = Vector3(0.16, 0.12, 0.07)
	bit.mesh = tooth
	bit.position = Vector3(0.09, -0.19, 0)
	for part: MeshInstance3D in [bow, shaft, bit]:
		part.material_override = _key_mat
		key.add_child(part)
	return key


## Floats a small key over a quaggle that is carrying one.
func _give_key(quag: Quaggle) -> void:
	var key := _make_key()
	key.name = "Key"
	key.scale = Vector3.ONE * 0.75
	key.position = Vector3(0, 1.85, 0)
	key.set_meta("base_y", key.position.y)
	quag.add_child(key)
	_spinners.append(key)


## A soft round shadow under a quaggle, kept by _place_blob on whatever
## surface is below it so heights and drops read clearly.
func _add_blob(quag: Quaggle) -> void:
	if _blob_mesh == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.05, 0.08, 0.2, 0.5)
		mat.albedo_texture = _dot_tex
		mat.render_priority = -1
		_blob_mesh = PlaneMesh.new()
		_blob_mesh.size = Vector2(0.95, 0.95)
		_blob_mesh.material = mat
	var blob := MeshInstance3D.new()
	blob.name = "Blob"
	blob.mesh = _blob_mesh
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.top_level = true
	quag.add_child(blob)


func _place_blob(quag: Quaggle) -> void:
	var blob: MeshInstance3D = quag.get_node_or_null("Blob")
	if blob == null:
		return
	var at := quag.position
	var x := floori(-at.x)
	var y := floori(at.z)
	var ground := -1
	for f in range(mini(floori(at.y / H + 0.05), floor_limit - 1), -1, -1):
		var below := rules.cell(f - 1, x, y)
		if _has_tile(rules.cell(f, x, y)) or below == Rules.WALL or below == Rules.WINDOW:
			ground = f
			break
	var fade := clampf(1.0 - (at.y - ground * H) / 6.0, 0.0, 1.0)
	blob.visible = quag.visible and ground >= 0 and fade > 0.0
	if not blob.visible:
		return
	blob.global_position = Vector3(at.x, ground * H + 0.045, at.z)
	blob.scale = Vector3.ONE * lerpf(0.55, 1.0, fade)
	blob.transparency = 1.0 - fade


## Spends the key a quaggle is carrying.
func _take_key(quag: Quaggle) -> void:
	var key := quag.get_node_or_null("Key")
	if key:
		_spinners.erase(key)
		key.queue_free()


## A force field is its own mesh, not part of a multimesh, so a key can
## switch it off.
func _add_field(parent: Node3D, p: Vector3i) -> void:
	if _field_mat == null:
		_field_mat = ShaderMaterial.new()
		_field_mat.shader = preload("res://shaders/field.gdshader")
	var field := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.96, H * 0.98, 0.96)
	field.mesh = box
	field.material_override = _field_mat
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.position = cell_pos(p) + Vector3(0, H * 0.5, 0)
	parent.add_child(field)
	_track(p, field)


func _add_lift(parent: Node3D, at: Vector3) -> void:
	if _ring_mat == null:
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ring_mat.vertex_color_use_as_albedo = true
		_ring_mat.albedo_texture = _ring_tex
	var rings := CPUParticles3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.92, 0.92)
	plane.material = _ring_mat
	rings.mesh = plane
	rings.amount = 4
	rings.lifetime = 1.4
	rings.preprocess = 1.4
	rings.direction = Vector3.UP
	rings.spread = 0.0
	rings.gravity = Vector3.ZERO
	rings.initial_velocity_min = H / 1.4
	rings.initial_velocity_max = H / 1.4
	rings.color_ramp = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	rings.color_initial_ramp = _ramp([Color(1, 0.3, 0.3), Color(1, 1, 0.3), Color(0.3, 1, 0.5), Color(0.3, 0.6, 1), Color(1, 0.3, 1)])
	rings.position = at + Vector3(0, 0.03, 0)
	parent.add_child(rings)


func _add_sparkles(parent: Node3D, at: Vector3) -> void:
	var sparks := _particles(8, 1.3)
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.35, 0.05, 0.35)
	sparks.initial_velocity_min = 0.6
	sparks.initial_velocity_max = 1.0
	sparks.scale_amount_min = 0.3
	sparks.scale_amount_max = 0.6
	sparks.color_ramp = _ramp([Color(0.6, 1, 0.5, 0.0), Color(0.8, 1, 0.5, 1.0), Color(1, 1, 0.6, 0.0)])
	sparks.position = at
	parent.add_child(sparks)


func _puff(at: Vector3, color: Color) -> void:
	var puff := _particles(14, 0.6)
	puff.one_shot = true
	puff.explosiveness = 0.95
	puff.spread = 180.0
	puff.initial_velocity_min = 0.8
	puff.initial_velocity_max = 2.0
	puff.color_ramp = _ramp([Color(color, 0.9), Color(color, 0.0)])
	puff.position = at
	_root.add_child(puff)
	puff.emitting = true
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(puff):
			puff.queue_free())


## Additive billboard particles drifting upward.
func _particles(amount: int, lifetime: float) -> CPUParticles3D:
	if _particle_mat == null:
		_particle_mat = StandardMaterial3D.new()
		_particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_particle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_particle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_particle_mat.vertex_color_use_as_albedo = true
		_particle_mat.albedo_texture = _dot_tex
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	quad.material = _particle_mat
	p.mesh = quad
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = 10.0
	p.gravity = Vector3.ZERO
	return p


func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	return g


func _make_textures() -> void:
	const N := 32
	var ring := Image.create(N, N, true, Image.FORMAT_RGBA8)
	var dot := Image.create(N, N, true, Image.FORMAT_RGBA8)
	for i in N:
		for j in N:
			var rim := i < 3 or j < 3 or i >= N - 3 or j >= N - 3
			ring.set_pixel(i, j, Color(1, 1, 1, 1.0 if rim else 0.0))
			var d := Vector2(i - N * 0.5 + 0.5, j - N * 0.5 + 0.5).length() / (N * 0.5)
			dot.set_pixel(i, j, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	for img: Image in [ring, dot]:
		img.generate_mipmaps()
	_ring_tex = ImageTexture.create_from_image(ring)
	_dot_tex = ImageTexture.create_from_image(dot)
