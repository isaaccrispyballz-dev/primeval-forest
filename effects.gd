class_name Effects
extends Node3D
## Short-lived animations: falling trees, wood chips, logs flying to the player.

signal tree_landed(at: Vector3, dir: Vector3, length: float)

var main: Node3D
var _falling: Array[Dictionary] = []
var _flying: Array[Dictionary] = []
var _chip_mesh: BoxMesh


func _init(owner_main: Node3D) -> void:
	main = owner_main
	_chip_mesh = BoxMesh.new()
	_chip_mesh.size = Vector3(0.05, 0.02, 0.08)
	_chip_mesh.material = Scenery.mat("c8a070")


## Builds a standalone copy of a tree (one MeshInstance per part, colored like
## the instance it replaces) and tips it over away from `away_from`.
func fell_tree(t: Dictionary, kind: Dictionary, away_from: Vector3) -> void:
	var pivot := Node3D.new()
	pivot.position = t.pos
	add_child(pivot)
	var body := Node3D.new()
	body.basis = Basis.from_euler(Vector3(t.tilt.x, t.rot, t.tilt.y)).scaled(Vector3.ONE * t.s)
	pivot.add_child(body)
	for pi in kind.parts.size():
		var mi := MeshInstance3D.new()
		mi.mesh = kind.parts[pi]
		var c := Color(kind.part_colors[pi])
		var m := Scenery.mat("ffffff")
		m.albedo_color = Color(c.r * t.tint, c.g * t.tint, c.b * t.tint)
		mi.material_override = m
		body.add_child(mi)
	var dir := Vector3(t.pos.x - away_from.x, 0, t.pos.z - away_from.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	_falling.append({
		"pivot": pivot, "axis": Vector3.UP.cross(dir).normalized(), "dir": dir,
		"angle": 0.02, "speed": 0.15, "landed": false, "t": 0.0,
		"length": kind.trunk_h * t.s, "base": t.pos,
	})


func chips(at: Vector3, toward: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _chip_mesh
	p.amount = 14
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.9
	p.direction = toward
	p.spread = 55.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func dust(at: Vector3, radius: float) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	p.amount = 24
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.2, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.47, 0.35, 0.5))
	grad.set_color(1, Color(0.55, 0.47, 0.35, 0.0))
	p.color_ramp = grad
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## Animate a ground log flying into the player's hand, then call `done`.
func fly_log(log: Node3D, target: Callable, done: Callable) -> void:
	_flying.append({"node": log, "target": target, "done": done, "t": 0.0, "from": log.global_position})


func _process(dt: float) -> void:
	for f in _falling.duplicate():
		f.t += dt
		if not f.landed:
			# angular acceleration grows as the tree leans, like a real fall
			f.speed += (1.2 + sin(f.angle) * 6.0) * dt
			f.angle += f.speed * dt
			var limit := PI / 2 - 0.06
			if f.angle >= limit:
				f.angle = limit
				f.landed = true
				f.t = 0.0
				f.speed = -f.speed * 0.15   # small bounce
				var tip_center: Vector3 = f.base + f.dir * f.length * 0.5
				dust(tip_center + Vector3(0, 0.3, 0), f.length * 0.3)
				tree_landed.emit(f.base, f.dir, f.length)
		else:
			f.angle = clampf(f.angle + f.speed * dt, 0.0, PI / 2 - 0.06)
			f.speed += 3.0 * dt
			if f.t > 0.9:
				# shrink away; the logs left behind replace it
				var s := maxf(0.0, 1.0 - (f.t - 0.9) / 0.5)
				f.pivot.scale = Vector3(s, s, s)
				if s <= 0.0:
					f.pivot.queue_free()
					_falling.erase(f)
					continue
		f.pivot.basis = Basis(f.axis, f.angle) * Basis().scaled(f.pivot.scale)

	for l in _flying.duplicate():
		l.t += dt * 3.0
		var to: Vector3 = l.target.call()
		var k := clampf(l.t, 0.0, 1.0)
		var p: Vector3 = l.from.lerp(to, k * k)
		p.y += sin(k * PI) * 0.6
		l.node.global_position = p
		l.node.scale = Vector3.ONE * (1.0 - k * 0.7)
		l.node.rotate_y(dt * 8.0)
		if k >= 1.0:
			l.node.queue_free()
			_flying.erase(l)
			l.done.call()
