class_name Building
extends Node3D
## Log structures. A blueprint is a list of logs (start point, end point) in the
## structure's local space. You set a blueprint down as a ghost "site", then each
## log you bring flies into place until it's done.

signal site_completed(site: Dictionary)

const LOG_R := 0.13
const BUILD_RANGE := 2.6
const BUILD_INTERVAL := 0.28

var main: Node3D
var ghost: Node3D                 # follows your aim while placing
var ghost_id := ""
var ghost_yaw := 0.0
var sites: Array[Dictionary] = []
var _ghost_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
var _build_timer := 0.0
var _drops: Array[Dictionary] = []


static func blueprints() -> Dictionary:
	var bp := {}
	# campfire: five logs leaning together into a teepee
	var fire := []
	for k in 5:
		var a := k * TAU / 5
		fire.append([Vector3(cos(a) * 0.42, 0.02, sin(a) * 0.42), Vector3(cos(a) * 0.05, 0.62, sin(a) * 0.05)])
	bp["campfire"] = {"name": "Campfire", "pieces": fire,
		"note": "Light and warmth. Things in the dark stay out of its circle. Burns about three minutes."}

	var wall := []
	for i in 6:
		var y := LOG_R + i * LOG_R * 1.9
		wall.append([Vector3(-1.5, y, 0), Vector3(1.5, y, 0)])
	bp["wall"] = {"name": "Log wall", "pieces": wall,
		"note": "Six logs stacked. Good for a windbreak, or to climb over with your hands."}

	var floor := []
	for i in 9:
		var z := -1.1 + i * 0.275
		floor.append([Vector3(-1.2, 0.42, z), Vector3(1.2, 0.42, z)])
	floor.push_front([Vector3(-1.0, 0.15, -1.2), Vector3(-1.0, 0.15, 1.2)])
	floor.push_front([Vector3(1.0, 0.15, -1.2), Vector3(1.0, 0.15, 1.2)])
	bp["platform"] = {"name": "Platform", "pieces": floor,
		"note": "A raised log floor. Keeps you off the wet ground and is the base for anything bigger."}

	var lean := [
		[Vector3(-1.2, 0.0, 0), Vector3(-1.2, 1.9, 0)],
		[Vector3(1.2, 0.0, 0), Vector3(1.2, 1.9, 0)],
		[Vector3(-1.45, 1.8, 0), Vector3(1.45, 1.8, 0)],
	]
	for i in 8:
		var x := -1.05 + i * 0.3
		lean.append([Vector3(x, 1.95, -0.1), Vector3(x, 0.05, 1.7)])
	bp["leanto"] = {"name": "Lean-to shelter", "pieces": lean,
		"note": "A sloped log roof on two posts. Somewhere to sit out the rain and the night."}
	return bp


var BLUEPRINTS := blueprints()


func _init(owner_main: Node3D) -> void:
	main = owner_main
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.28)
	_wood_mat = Scenery.mat("5a4430")


## One log node spanning a..b (in the parent's space).
func _log_node(a: Vector3, b: Vector3, material: Material) -> Node3D:
	var n := Node3D.new()
	var d := b - a
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	n.transform = Transform3D(Basis.looking_at(d.normalized(), up), (a + b) / 2)
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = LOG_R
	c.bottom_radius = LOG_R * 1.05
	c.height = d.length()
	c.radial_segments = 7
	c.rings = 1
	mi.mesh = c
	mi.rotation.x = PI / 2      # cylinder's Y axis -> node's Z axis
	mi.material_override = material
	n.add_child(mi)
	return n


func _structure(id: String, material: Material) -> Node3D:
	var root := Node3D.new()
	for p in BLUEPRINTS[id].pieces:
		root.add_child(_log_node(p[0], p[1], material))
	return root


# ---------------------------------------------------------------- placing

func begin_place(id: String, yaw: float) -> void:
	cancel_place()
	ghost_id = id
	ghost_yaw = yaw
	ghost = _structure(id, _ghost_mat)
	add_child(ghost)


func cancel_place() -> void:
	if ghost:
		ghost.queue_free()
	ghost = null
	ghost_id = ""


func is_placing() -> bool:
	return ghost != null


func move_ghost(at: Vector3) -> void:
	if ghost:
		at.y = main.height_at(at.x, at.z)
		ghost.transform = Transform3D(Basis(Vector3.UP, ghost_yaw), at)


func confirm_place() -> void:
	if not ghost:
		return
	var site := {
		"id": ghost_id, "node": ghost, "built": 0, "done": false,
		"pieces": BLUEPRINTS[ghost_id].pieces,
	}
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 10
	label.pixel_size = 0.004
	label.position = Vector3(0, 2.3, 0)
	ghost.add_child(label)
	site.label = label
	_update_label(site)
	sites.append(site)
	ghost = null
	ghost_id = ""


func _update_label(site: Dictionary) -> void:
	var bp: Dictionary = BLUEPRINTS[site.id]
	site.label.text = "%s  %d/%d" % [bp.name, site.built, bp.pieces.size()]
	site.label.visible = not site.done


# ---------------------------------------------------------------- building

## Called every frame. Spends the player's logs on nearby unfinished sites.
## Returns how many logs were used this frame.
func update(dt: float, player_pos: Vector3, wood: int) -> int:
	_animate_drops(dt)
	_build_timer -= dt
	if wood <= 0 or _build_timer > 0.0:
		return 0
	for site in sites:
		if site.done:
			continue
		var p: Vector3 = site.node.global_position
		if Vector2(p.x - player_pos.x, p.z - player_pos.z).length() > BUILD_RANGE + 1.0:
			continue
		_build_timer = BUILD_INTERVAL
		_add_piece(site)
		return 1
	return 0


func _add_piece(site: Dictionary) -> void:
	var i: int = site.built
	var ghost_piece: Node3D = site.node.get_child(i)
	ghost_piece.visible = false
	var piece: Array = site.pieces[i]
	var real := _log_node(piece[0], piece[1], _wood_mat)
	site.node.add_child(real)
	var target := real.position
	real.position = target + Vector3(0, 1.2, 0)
	_drops.append({"node": real, "target": target, "t": 0.0})
	site.built += 1
	if site.built >= site.pieces.size():
		site.done = true
		site_completed.emit(site)
	_update_label(site)


func _animate_drops(dt: float) -> void:
	for d in _drops.duplicate():
		d.t = minf(1.0, d.t + dt * 3.0)
		# drop with a little bounce at the end
		var k: float = d.t
		var y := 1.2 * (1.0 - k * k)
		if k > 0.85:
			y = sin((k - 0.85) / 0.15 * PI) * 0.05
		d.node.position = d.target + Vector3(0, y, 0)
		if d.t >= 1.0:
			_drops.erase(d)


# ---------------------------------------------------------------- physics

## Closest built log to a point: returns {"dist", "point", "normal"} or {}.
func nearest_log(p: Vector3, max_dist: float) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for site in sites:
		var xf: Transform3D = site.node.global_transform
		for i in site.built:
			var piece: Array = site.pieces[i]
			var a: Vector3 = xf * piece[0]
			var b: Vector3 = xf * piece[1]
			var q := Geometry3D.get_closest_point_to_segment(p, a, b)
			var d := p.distance_to(q) - LOG_R
			if d < best_d:
				best_d = d
				var n := (p - q).normalized() if p.distance_to(q) > 0.0001 else Vector3.UP
				best = {"dist": d, "point": q + n * LOG_R, "normal": n}
	return best


## Highest walkable log top under (x, z) that is at most `step` above feet_y.
func floor_height(x: float, z: float, feet_y: float, step := 0.45) -> float:
	var best := -INF
	for site in sites:
		var xf: Transform3D = site.node.global_transform
		for i in site.built:
			var piece: Array = site.pieces[i]
			var a: Vector3 = xf * piece[0]
			var b: Vector3 = xf * piece[1]
			if absf(a.y - b.y) > 0.6:
				continue  # posts and roof slopes aren't floors
			var q := Geometry3D.get_closest_point_to_segment(Vector3(x, (a.y + b.y) / 2, z), a, b)
			if Vector2(q.x - x, q.z - z).length() > 0.22:
				continue
			var top := q.y + LOG_R
			if top <= feet_y + step and top > best:
				best = top
	return best
