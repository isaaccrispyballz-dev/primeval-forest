class_name Axe
## A hand-built felling axe: a slightly curved hickory haft with a flared butt,
## a leather grip wrap, and a bearded forged head with a polished edge.
## Built in the controller's grip space: the haft runs along -Z out of the fist,
## the blade's edge faces +Y.

const HEAD_Z := -0.5          # where the head sits along the haft
const TIP := Vector3(0, 0.145, HEAD_Z)


static func build() -> Node3D:
	var axe := Node3D.new()
	axe.add_child(_mesh(_haft(), Scenery.mat("9a7048")))
	var wrap := Scenery.mat("4a2e1c")
	wrap.roughness = 0.9
	axe.add_child(_mesh(_tube(0.085, -0.075, 0.0215, 0.0235, 8), wrap))
	for z in [0.085, -0.075]:
		axe.add_child(_mesh(_tube(z + 0.006, z - 0.006, 0.025, 0.025, 8), Scenery.mat("2e1d12")))
	var head_mat := StandardMaterial3D.new()
	head_mat.vertex_color_use_as_albedo = true
	head_mat.metallic = 0.7
	head_mat.roughness = 0.45
	axe.add_child(_mesh(_head(), head_mat))
	# a wedge driven into the top of the haft, like a real hung axe
	var wedge := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.006, 0.03, 0.01)
	wm.material = Scenery.mat("5c4026")
	wedge.mesh = wm
	wedge.position = Vector3(0, 0, HEAD_Z - 0.033)
	axe.add_child(wedge)
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = TIP
	axe.add_child(tip)
	return axe


static func _mesh(m: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	return mi


## Haft: oval cross-section, swells at the butt (knob), thins in the middle,
## thickens again under the head, with a gentle curve.
static func _haft() -> ArrayMesh:
	var rings := []
	var stations := [
		[0.13, 0.016], [0.125, 0.027], [0.11, 0.025], [0.08, 0.021], [0.0, 0.02],
		[-0.15, 0.017], [-0.3, 0.016], [-0.42, 0.018], [-0.48, 0.019], [-0.53, 0.017],
	]
	for s in stations:
		var z: float = s[0]
		var r: float = s[1]
		var bend := sin(clampf((0.13 - z) / 0.66, 0.0, 1.0) * PI) * 0.012
		rings.append({"z": z, "r": r, "y": -bend})
	return _loft(rings, 8, 1.25)


static func _tube(z0: float, z1: float, r0: float, r1: float, sides: int) -> ArrayMesh:
	return _loft([{"z": z0, "r": r0, "y": 0.0}, {"z": z1, "r": r1, "y": 0.0}], sides, 1.2)


## Lofts oval rings along Z into a closed tube.
static func _loft(rings: Array, sides: int, oval: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for ring in rings:
		var row := []
		for k in sides:
			var a := TAU * k / sides
			row.append(Vector3(cos(a) * ring.r, ring.y + sin(a) * ring.r * oval, ring.z))
		pts.append(row)
	for i in rings.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var a: Vector3 = pts[i][k]
			var b: Vector3 = pts[i][k2]
			var c: Vector3 = pts[i + 1][k2]
			var d: Vector3 = pts[i + 1][k]
			for v in [a, d, c, a, c, b]:
				st.add_vertex(v)
	for end in [0, rings.size() - 1]:
		var center := Vector3(0, rings[end].y, rings[end].z)
		for k in sides:
			var a: Vector3 = pts[end][k]
			var b: Vector3 = pts[end][(k + 1) % sides]
			if end == 0:
				for v in [center, a, b]:
					st.add_vertex(v)
			else:
				for v in [center, b, a]:
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Head: a profile in the Y/Z plane (poll at -Y, bearded blade at +Y) extruded
## in X, thick at the eye and tapering to a thin edge. Vertex colors make the
## body dark forged steel and the last bevel bright and polished.
static func _head() -> ArrayMesh:
	# [y, z_back (toward the hand), z_front, half thickness]
	var rows := [
		[-0.045, -0.475, -0.525, 0.017],
		[-0.02, -0.468, -0.532, 0.019],
		[0.025, -0.478, -0.522, 0.015],
		[0.065, -0.462, -0.548, 0.010],
		[0.105, -0.44, -0.572, 0.005],
		[0.13, -0.425, -0.585, 0.0025],
		[0.145, -0.42, -0.585, 0.0008],
	]
	var dark := Color("3c4044")
	var bright := Color("c9ced2")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color):
		st.set_color(col)
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
	for i in rows.size() - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var col := bright if i >= rows.size() - 2 else dark.lerp(Color("5a5f63"), float(i) / rows.size())
		for side in [1.0, -1.0]:
			var a := Vector3(r0[3] * side, r0[0], r0[1])
			var b := Vector3(r0[3] * side, r0[0], r0[2])
			var c := Vector3(r1[3] * side, r1[0], r1[2])
			var d := Vector3(r1[3] * side, r1[0], r1[1])
			if side > 0:
				quad.call(a, b, c, d, col)
			else:
				quad.call(a, d, c, b, col)
		# the two narrow sides (toward the hand / away)
		for zi in [1, 2]:
			var a := Vector3(r0[3], r0[0], r0[zi])
			var b := Vector3(-r0[3], r0[0], r0[zi])
			var c := Vector3(-r1[3], r1[0], r1[zi])
			var d := Vector3(r1[3], r1[0], r1[zi])
			if zi == 1:
				quad.call(a, b, c, d, col)
			else:
				quad.call(a, d, c, b, col)
	# caps: flat poll at the bottom, the cutting edge at the top
	var f: Array = rows[0]
	quad.call(Vector3(f[3], f[0], f[1]), Vector3(f[3], f[0], f[2]), Vector3(-f[3], f[0], f[2]), Vector3(-f[3], f[0], f[1]), dark)
	var l: Array = rows[rows.size() - 1]
	quad.call(Vector3(l[3], l[0], l[1]), Vector3(-l[3], l[0], l[1]), Vector3(-l[3], l[0], l[2]), Vector3(l[3], l[0], l[2]), bright)
	st.generate_normals()
	return st.commit()
