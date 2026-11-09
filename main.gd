extends Node3D
## Primeval: original forest survival game for Meta Quest 3.
## Everything is built in code so the project stays a few small text files.
## On Quest it runs in VR via OpenXR; on a PC without a headset it falls back
## to WASD + mouse so you can test quickly in the Godot editor.

const WORLD := 180.0
const TREE_COUNT := 650
const DAY_LENGTH := 300.0          # seconds for a full day
const MOVE_SPEED := 2.6
const SNAP_ANGLE := PI / 6.0
const WOOD_PER_FIRE := 5
const MAX_FIRES := 4               # keep dynamic lights low for Quest
const SWING_SPEED := 2.2           # m/s the axe blade needs to count as a hit

# arm locomotion: plant your hands on the ground or a trunk and push yourself along
const GRAVITY := 9.8
const JUMP_MULT := 1.25            # boost when you let go mid-push
const MAX_LAUNCH := 6.5            # m/s cap so you can't fling across the map
const GROUND_FRICTION := 6.0
const HAND_RADIUS := 0.05
const GRASS_COUNT := 9000
const ROCK_COUNT := 180

var xr_active := false
var rng := RandomNumberGenerator.new()

var origin: XROrigin3D
var camera: XRCamera3D
var left: XRController3D
var right: XRController3D
var axe_tip: Node3D
var desk_axe: Node3D
var sun: DirectionalLight3D
var env: Environment
var hud_3d: Label3D
var hud_2d: Label
var thunk_player: AudioStreamPlayer

var sky_mat: ProceduralSkyMaterial
var tree_kinds: Array[Dictionary] = []   # each: parts (MultiMesh list), stump, ...
var trees: Array[Dictionary] = []
var logs: Array[Node3D] = []
var fires: Array[Dictionary] = []

var bark_mat: StandardMaterial3D
var log_mesh: CylinderMesh

var wood := 0
var time_of_day := 0.3             # 0 = 06:00, 0.25 = noon, 0.75 = midnight
var msg := ""
var msg_t := 0.0
var chop_cooldown := 0.0
var prev_tip := Vector3.ZERO
var snapped := false
var prev_a := false
var yaw := 0.0
var pitch := 0.0
var swing := 0.0
var velocity := Vector3.ZERO
var on_ground := true
# per hand: touching, anchor (world point the hand is stuck to), prev hand pos in origin space
var hand_state := {}


func _ready() -> void:
	rng.seed = 1337
	_setup_xr()
	_build_world()
	_build_player()
	_build_trees()
	_build_audio()
	_update_hud()


# ---------------------------------------------------------------- setup

func _setup_xr() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		xr_active = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func height_at(x: float, z: float) -> float:
	return sin(x * 0.045) * cos(z * 0.05) * 2.2 \
		+ sin(x * 0.11 + z * 0.07) * 0.8 \
		+ cos(z * 0.13 - x * 0.03) * 0.5


func _build_world() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 8.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 8.0
	env.fog_depth_end = 70.0
	env.fog_sky_affect = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("fff1d0")
	sun.shadow_enabled = true
	sun.shadow_bias = 0.08
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 28.0
	add_child(sun)

	add_child(Scenery.terrain(WORLD, 120, height_at))
	_build_grass()
	_build_rocks()

	bark_mat = Scenery.mat("4a3423")
	log_mesh = CylinderMesh.new()
	log_mesh.top_radius = 0.12
	log_mesh.bottom_radius = 0.12
	log_mesh.height = 0.9
	log_mesh.radial_segments = 6
	log_mesh.material = bark_mat


func _build_grass() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Scenery.grass_clump()
	mm.instance_count = GRASS_COUNT
	var placed := 0
	while placed < GRASS_COUNT:
		var x := rng.randf_range(-0.5, 0.5) * (WORLD - 6.0)
		var z := rng.randf_range(-0.5, 0.5) * (WORLD - 6.0)
		# grass grows in patches: skip spots where a slow noise is low
		if sin(x * 0.09) * cos(z * 0.07) + sin(x * 0.23 + z * 0.17) * 0.5 < -0.2:
			continue
		var s := rng.randf_range(0.6, 1.3)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.4), s))
		mm.set_instance_transform(placed, Transform3D(b, Vector3(x, height_at(x, z) - 0.03, z)))
		mm.set_instance_color(placed, Color(1, 1, 1).lerp(Color("b8a660"), rng.randf() * 0.3))
		placed += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_rocks() -> void:
	for variant in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Scenery.rock(variant + 11)
		mm.instance_count = ROCK_COUNT / 3
		for i in mm.instance_count:
			var x := rng.randf_range(-0.5, 0.5) * (WORLD - 8.0)
			var z := rng.randf_range(-0.5, 0.5) * (WORLD - 8.0)
			var s := rng.randf_range(0.4, 1.6) * (3.0 if rng.randf() < 0.08 else 1.0)
			var b := Basis.from_euler(Vector3(rng.randf() * 0.4, rng.randf() * TAU, rng.randf() * 0.4)).scaled(Vector3(s, s * 0.7, s))
			mm.set_instance_transform(i, Transform3D(b, Vector3(x, height_at(x, z) - 0.2 * s, z)))
			var g := rng.randf_range(0.24, 0.36)
			mm.set_instance_color(i, Color(g, g * 0.98, g * 0.92).lerp(Color("4b5a32"), rng.randf() * 0.3))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		add_child(mi)


func _build_player() -> void:
	origin = XROrigin3D.new()
	add_child(origin)
	camera = XRCamera3D.new()
	camera.near = 0.05
	camera.far = 200.0
	origin.add_child(camera)

	left = XRController3D.new()
	left.tracker = "left_hand"
	origin.add_child(left)
	right = XRController3D.new()
	right.tracker = "right_hand"
	origin.add_child(right)

	var axe := _make_axe()
	right.add_child(axe)
	axe_tip = axe.get_node("Tip")

	hud_3d = Label3D.new()
	hud_3d.pixel_size = 0.0004
	hud_3d.font_size = 64
	hud_3d.outline_size = 12
	hud_3d.position = Vector3(0, 0.04, 0.06)
	hud_3d.rotation = Vector3(-PI / 3, 0, 0)
	left.add_child(hud_3d)

	if not xr_active:
		camera.position.y = 1.6
		desk_axe = _make_axe()
		desk_axe.position = Vector3(0.28, -0.3, -0.35)
		desk_axe.rotation.x = 0.2
		camera.add_child(desk_axe)
		var layer := CanvasLayer.new()
		hud_2d = Label.new()
		hud_2d.position = Vector2(16, 16)
		hud_2d.add_theme_font_size_override("font_size", 20)
		hud_2d.add_theme_constant_override("outline_size", 6)
		hud_2d.add_theme_color_override("font_outline_color", Color.BLACK)
		layer.add_child(hud_2d)
		add_child(layer)


func _make_axe() -> Node3D:
	var axe := Node3D.new()
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.018
	hm.bottom_radius = 0.022
	hm.height = 0.62
	hm.radial_segments = 6
	hm.material = Scenery.mat("8a6440")
	handle.mesh = hm
	handle.rotation.x = PI / 2
	handle.position.z = -0.2
	axe.add_child(handle)
	var head := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.16, 0.1)
	var steel := Scenery.mat("9aa3a8")
	steel.metallic = 0.6
	steel.roughness = 0.4
	bm.material = steel
	head.mesh = bm
	head.position = Vector3(0, 0.06, -0.46)
	axe.add_child(head)
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = Vector3(0, 0.1, -0.46)
	axe.add_child(tip)
	return axe


func _multimesh(mesh: Mesh, count: int, colors := false, shadows := true) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm


func _build_trees() -> void:
	tree_kinds = Scenery.tree_kinds()
	# decide each tree's kind and spot first, so each kind's MultiMesh gets an exact count
	var counts := []
	counts.resize(tree_kinds.size())
	counts.fill(0)
	for i in TREE_COUNT:
		var x := 0.0
		var z := 0.0
		while x * x + z * z < 49.0:
			x = rng.randf_range(-0.5, 0.5) * (WORLD - 10.0)
			z = rng.randf_range(-0.5, 0.5) * (WORLD - 10.0)
		# pines on high ground, broadleaf in the hollows
		var h := height_at(x, z)
		var kind := 0 if rng.randf() < clampf(0.45 + h * 0.12, 0.15, 0.9) else 1
		var s := rng.randf_range(0.75, 1.35)
		trees.append({
			"kind": kind, "k": counts[kind],
			"pos": Vector3(x, h - 0.1, z), "s": s, "rot": rng.randf() * TAU,
			"tilt": Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04)),
			"tint": rng.randf_range(0.8, 1.15),
			"hp": 4, "felled": false, "shake": 0.0,
			"r": tree_kinds[kind].radius * s, "trunk_h": tree_kinds[kind].trunk_h * s,
		})
		counts[kind] += 1
	for ki in tree_kinds.size():
		var kd: Dictionary = tree_kinds[ki]
		var mms: Array[MultiMesh] = []
		for p in kd.parts:
			mms.append(_multimesh(p, counts[ki], true))
		kd.mms = mms
		kd.stump_mm = _multimesh(kd.stump, counts[ki], false, false)
	for i in trees.size():
		var t: Dictionary = trees[i]
		var kd: Dictionary = tree_kinds[t.kind]
		for pi in kd.mms.size():
			var c := Color(kd.part_colors[pi])
			kd.mms[pi].set_instance_color(t.k, Color(c.r * t.tint, c.g * t.tint, c.b * t.tint))
		_set_tree(i)


func _set_tree(i: int, sway := 0.0) -> void:
	var t: Dictionary = trees[i]
	var kd: Dictionary = tree_kinds[t.kind]
	var b := Basis.from_euler(Vector3(t.tilt.x + sway, t.rot, t.tilt.y + sway * 0.5)).scaled(Vector3.ONE * t.s)
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), t.pos)
	var standing := hidden if t.felled else Transform3D(b, t.pos)
	for mm in kd.mms:
		mm.set_instance_transform(t.k, standing)
	kd.stump_mm.set_instance_transform(t.k, Transform3D(Basis(Vector3.UP, t.rot).scaled(Vector3.ONE * t.s), t.pos) if t.felled else hidden)


func _build_audio() -> void:
	# synthesized "thunk": decaying noise, no audio asset files needed
	var rate := 22050
	var n := int(rate * 0.12)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.25)
		var v := lp * pow(1.0 - float(i) / n, 4.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	thunk_player = AudioStreamPlayer.new()
	thunk_player.stream = wav
	thunk_player.max_polyphony = 4
	add_child(thunk_player)


func _thunk(strength := 1.0) -> void:
	thunk_player.volume_db = linear_to_db(clampf(0.6 * strength, 0.05, 1.0))
	thunk_player.play()


# ---------------------------------------------------------------- gameplay

func _say(text: String) -> void:
	msg = text
	msg_t = 2.5


func _try_hit(point: Vector3, speed: float, ctrl: XRController3D = null) -> bool:
	if chop_cooldown > 0.0:
		return false
	for i in trees.size():
		var t: Dictionary = trees[i]
		if t.felled:
			continue
		var d := Vector2(point.x - t.pos.x, point.z - t.pos.z)
		if d.length_squared() > pow(t.r + 0.15, 2):
			continue
		var y_rel: float = point.y - t.pos.y
		if y_rel < 0.0 or y_rel > t.trunk_h:
			continue
		chop_cooldown = 0.35
		t.hp -= 1
		t.shake = 0.4
		_thunk(minf(1.0, speed / 4.0))
		if ctrl:
			ctrl.trigger_haptic_pulse("haptic", 0.0, 0.7, 0.06, 0.0)
		if t.hp <= 0:
			t.felled = true
			_drop_logs(t.pos)
			_say("Timber!")
			if ctrl:
				ctrl.trigger_haptic_pulse("haptic", 0.0, 1.0, 0.2, 0.0)
		_set_tree(i)
		return true
	return false


func _drop_logs(at: Vector3) -> void:
	for k in 3:
		var l := MeshInstance3D.new()
		l.mesh = log_mesh
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.8, 1.6)
		var p := Vector3(at.x + cos(a) * d, 0.0, at.z + sin(a) * d)
		p.y = height_at(p.x, p.z) + 0.12
		l.position = p
		l.rotation = Vector3(0, rng.randf() * TAU, PI / 2)
		add_child(l)
		logs.append(l)


func _place_fire() -> void:
	if wood < WOOD_PER_FIRE:
		_say("Need %d wood" % WOOD_PER_FIRE)
		return
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var p := camera.global_position + fwd * 1.5
	p.y = height_at(p.x, p.z)
	var g := Node3D.new()
	g.position = p
	for k in 4:
		var l := MeshInstance3D.new()
		l.mesh = log_mesh
		l.position.y = 0.1
		l.rotation = Vector3(0, k * PI / 4, PI / 2)
		g.add_child(l)
	var flame := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.0
	fm.bottom_radius = 0.25
	fm.height = 0.7
	fm.radial_segments = 6
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color("ffa040")
	fm.material = fmat
	flame.mesh = fm
	flame.position.y = 0.45
	g.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color("ff8a30")
	light.omni_range = 14.0
	light.position.y = 0.9
	g.add_child(light)
	add_child(g)
	fires.append({"node": g, "flame": flame, "light": light, "fuel": 180.0})
	if fires.size() > MAX_FIRES:
		fires.pop_front().node.queue_free()
	wood -= WOOD_PER_FIRE
	_say("Campfire lit")


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if xr_active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0025
		pitch = clampf(pitch - event.relative.y * 0.0025, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif swing <= 0.0:
			swing = 0.3
			var from := camera.global_position
			var dir := -camera.global_transform.basis.z
			var d := 0.5
			while d <= 2.0 and not _try_hit(from + dir * d, 4.0):
				d += 0.1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_place_fire()
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# Returns the surface point the hand is pressing into, or null if it is touching nothing.
func _hand_contact(p: Vector3):
	var g := height_at(p.x, p.z)
	if p.y < g + HAND_RADIUS:
		return Vector3(p.x, g + HAND_RADIUS, p.z)
	for t in trees:
		if t.felled:
			continue
		var d := Vector2(p.x - t.pos.x, p.z - t.pos.z)
		var r: float = t.r + HAND_RADIUS
		var y_rel: float = p.y - t.pos.y
		if d.length_squared() < r * r and y_rel > 0.0 and y_rel < t.trunk_h:
			var n := d.normalized() if d.length_squared() > 0.000001 else Vector2(1, 0)
			return Vector3(t.pos.x + n.x * r, p.y, t.pos.z + n.y * r)
	return null


func _arm_locomotion(dt: float) -> bool:
	var body_before := origin.global_position
	var any_touch := false
	var was_touching := false
	for c in [left, right]:
		var hs: Dictionary = hand_state.get(c, {"touch": false, "anchor": Vector3.ZERO, "prev": c.position})
		was_touching = was_touching or hs.touch
		var local_delta: Vector3 = c.position - hs.prev
		hs.prev = c.position
		if hs.touch:
			# where the hand would be if the body stayed put
			var wanted: Vector3 = hs.anchor + origin.global_transform.basis * local_delta
			if _hand_contact(wanted) == null:
				hs.touch = false            # hand lifted off the surface
			else:
				origin.global_position -= origin.global_transform.basis * local_delta
				any_touch = true
		else:
			var hit = _hand_contact(c.global_position)
			if hit != null:
				hs.touch = true
				hs.anchor = hit
				origin.global_position += hit - c.global_position
				any_touch = true
				c.trigger_haptic_pulse("haptic", 0.0, 0.25, 0.03, 0.0)
		hand_state[c] = hs

	if any_touch:
		var v := (origin.global_position - body_before) / maxf(dt, 0.001)
		velocity = velocity.lerp(v, 0.6)
	elif was_touching:
		velocity *= JUMP_MULT           # just let go: launch
		if velocity.length() > MAX_LAUNCH:
			velocity = velocity.normalized() * MAX_LAUNCH
	return any_touch


func _apply_body_physics(dt: float, holding: bool) -> void:
	var g := height_at(origin.position.x, origin.position.z)
	if not holding:
		velocity.y -= GRAVITY * dt
		origin.position += velocity * dt
	if origin.position.y <= g:
		origin.position.y = g
		velocity.y = maxf(velocity.y, 0.0)
		on_ground = true
		velocity.x = lerpf(velocity.x, 0.0, minf(1.0, GROUND_FRICTION * dt))
		velocity.z = lerpf(velocity.z, 0.0, minf(1.0, GROUND_FRICTION * dt))
	else:
		on_ground = false


func _update_vr(dt: float) -> void:
	var holding := _arm_locomotion(dt)

	# left stick also walks, but only on the ground
	var mv := left.get_vector2("primary")
	if on_ground and not holding and mv.length() > 0.15:
		var fwd := -camera.global_transform.basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		var rt := fwd.cross(Vector3.UP)
		origin.position += (fwd * mv.y + rt * mv.x) * MOVE_SPEED * dt

	# right stick: snap turn around the head
	var turn := right.get_vector2("primary").x
	if absf(turn) > 0.7 and not snapped:
		snapped = true
		var ang := -signf(turn) * SNAP_ANGLE
		var head := camera.global_position
		var xf := origin.global_transform
		xf.origin -= head
		xf = xf.rotated(Vector3.UP, ang)
		xf.origin += head
		origin.global_transform = xf
	elif absf(turn) < 0.3:
		snapped = false

	# A button: campfire
	var a := right.is_button_pressed("ax_button")
	if a and not prev_a:
		_place_fire()
	prev_a = a

	# axe swing: hit when the blade moves fast enough
	var tip := axe_tip.global_position
	var speed := tip.distance_to(prev_tip) / maxf(dt, 0.001)
	prev_tip = tip
	if speed > SWING_SPEED:
		_try_hit(tip, speed, right)

	_apply_body_physics(dt, holding)


func _update_desktop(dt: float) -> void:
	camera.rotation = Vector3(pitch, yaw, 0)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var rt := Vector3(cos(yaw), 0, -sin(yaw))
	var sp := MOVE_SPEED * (1.8 if Input.is_key_pressed(KEY_SHIFT) else 1.0) * dt
	if Input.is_key_pressed(KEY_W): origin.position += fwd * sp
	if Input.is_key_pressed(KEY_S): origin.position -= fwd * sp
	if Input.is_key_pressed(KEY_D): origin.position += rt * sp
	if Input.is_key_pressed(KEY_A): origin.position -= rt * sp
	origin.position.y = height_at(origin.position.x, origin.position.z)
	swing = maxf(0.0, swing - dt)
	desk_axe.rotation.x = 0.2 - sin(swing / 0.3 * PI) * 1.3


# ---------------------------------------------------------------- per frame

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	chop_cooldown = maxf(0.0, chop_cooldown - dt)
	if xr_active:
		_update_vr(dt)
	else:
		_update_desktop(dt)
	_collide()
	_pickup_logs()
	_update_day_night(dt)
	_update_fires(dt)
	_update_shake(dt)
	if msg_t > 0.0:
		msg_t -= dt
		if msg_t <= 0.0:
			msg = ""
	_update_hud()


func _collide() -> void:
	var head := camera.global_position
	for t in trees:
		if t.felled:
			continue
		var d := Vector2(head.x - t.pos.x, head.z - t.pos.z)
		var min_d: float = t.r + 0.3
		var len := d.length()
		if len < min_d and len > 0.0001:
			var push := d / len * (min_d - len)
			origin.position.x += push.x
			origin.position.z += push.y
	var lim := WORLD / 2.0 - 4.0
	origin.position.x = clampf(origin.position.x, -lim, lim)
	origin.position.z = clampf(origin.position.z, -lim, lim)


func _pickup_logs() -> void:
	var head := camera.global_position
	for i in range(logs.size() - 1, -1, -1):
		var l := logs[i]
		if Vector2(l.position.x - head.x, l.position.z - head.z).length_squared() < 1.3:
			l.queue_free()
			logs.remove_at(i)
			wood += 1
			_thunk(0.3)


const DAY_TOP := Color("5d86b5")
const DAY_HORIZON := Color("a9c3c0")
const DUSK_HORIZON := Color("d9874f")
const NIGHT_TOP := Color("03050b")
const NIGHT_HORIZON := Color("0b1220")
const MOON_COLOR := Color("8fa6d6")

func _update_day_night(dt: float) -> void:
	time_of_day = fmod(time_of_day + dt / DAY_LENGTH, 1.0)
	var ang := time_of_day * TAU
	var elev := sin(ang)
	var day := smoothstep(-0.15, 0.25, elev)
	var dusk := maxf(0.0, 1.0 - absf(elev) * 4.0) * 0.9
	var top := NIGHT_TOP.lerp(DAY_TOP, day)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, dusk * day)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = horizon.darkened(0.6)
	env.fog_light_color = horizon.darkened(0.15)
	env.fog_depth_end = 22.0 + day * 50.0
	env.ambient_light_color = Color("cfe6ff").lerp(Color("2a3a5e"), 1.0 - day)
	env.ambient_light_energy = 0.18 + day * 0.55
	# one directional light: the sun by day, a dim blue moon (opposite side) by night
	var sun_dir := Vector3(cos(ang), elev, 0.35).normalized()
	if elev > -0.05:
		sun.look_at_from_position(sun_dir * 50.0, Vector3.ZERO)
		sun.light_color = Color("fff1d0").lerp(Color("ffb070"), dusk)
		sun.light_energy = day * 1.25
	else:
		sun.look_at_from_position(-sun_dir * 50.0, Vector3.ZERO)
		sun.light_color = MOON_COLOR
		sun.light_energy = 0.22 * smoothstep(0.0, 0.3, -elev)
	sun.visible = sun.light_energy > 0.01


func _update_fires(dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for f in fires:
		f.fuel -= dt
		var life := clampf(f.fuel / 30.0, 0.0, 1.0)
		var flick := 0.85 + sin(t * 17.0 + f.node.get_instance_id()) * 0.08 + sin(t * 29.0) * 0.07
		f.light.light_energy = 2.5 * life * flick
		f.flame.scale = Vector3(1, flick * life + 0.01, 1)
		f.flame.visible = life > 0.0


func _update_shake(dt: float) -> void:
	for i in trees.size():
		var t: Dictionary = trees[i]
		if t.shake <= 0.0 or t.felled:
			continue
		t.shake = maxf(0.0, t.shake - dt)
		_set_tree(i, sin(t.shake * 60.0) * t.shake * 0.08)


func _clock() -> String:
	var h := fmod(time_of_day * 24.0 + 6.0, 24.0)
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


var _last_hud := ""

func _update_hud() -> void:
	var txt := "Wood %d · %s" % [wood, _clock()]
	if msg != "":
		txt += "\n" + msg
	if txt == _last_hud:
		return
	_last_hud = txt
	hud_3d.text = txt
	if hud_2d:
		hud_2d.text = txt
