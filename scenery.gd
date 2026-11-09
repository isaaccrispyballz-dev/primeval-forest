class_name Scenery
## Meshes, materials and shaders for Primeval's look. Everything is generated in
## code (no texture files) and kept low-poly so it holds 72-90 fps on Quest 3.


static func mat(hex: String, use_instance_color := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = use_instance_color
	return m


# ---------------------------------------------------------------- terrain

const TERRAIN_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 moss : source_color = vec3(0.16, 0.27, 0.12);
uniform vec3 grass : source_color = vec3(0.30, 0.38, 0.16);
uniform vec3 dirt : source_color = vec3(0.30, 0.22, 0.14);
uniform vec3 needles : source_color = vec3(0.36, 0.25, 0.15);

varying vec3 world_pos;
varying vec3 world_n;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
	           mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return noise(p) * 0.55 + noise(p * 2.3) * 0.3 + noise(p * 5.1) * 0.15; }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float big = fbm(world_pos.xz * 0.05);
	float small = fbm(world_pos.xz * 0.6);
	vec3 c = mix(moss, grass, smoothstep(0.35, 0.7, big));
	c = mix(c, needles, smoothstep(0.55, 0.8, fbm(world_pos.xz * 0.12 + 7.0)) * 0.8);
	float slope = 1.0 - world_n.y;
	c = mix(c, dirt, smoothstep(0.08, 0.25, slope));
	c *= 0.8 + small * 0.4;
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
"""


static func terrain(world: float, segments: int, height_fn: Callable) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := world / segments
	for iz in segments + 1:
		for ix in segments + 1:
			var x := -world / 2 + ix * step
			var z := -world / 2 + iz * step
			st.set_uv(Vector2(ix, iz) / segments)
			st.add_vertex(Vector3(x, height_fn.call(x, z), z))
	var row := segments + 1
	for iz in segments:
		for ix in segments:
			var a := iz * row + ix
			st.add_index(a); st.add_index(a + 1); st.add_index(a + row)
			st.add_index(a + 1); st.add_index(a + row + 1); st.add_index(a + row)
	st.generate_normals()
	var shader := Shader.new()
	shader.code = TERRAIN_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	return mi


# ---------------------------------------------------------------- tree parts

## A cone/cylinder baked so the tree's origin sits at the base, with optional
## vertex jitter so every layer looks hand-cut rather than perfectly round.
static func layer(top: float, bottom: float, h: float, y: float, material: Material,
		segs := 7, jitter := 0.0, seed := 0) -> ArrayMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	var arr := c.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var offsets := {}
	for i in verts.size():
		var v := verts[i]
		if jitter > 0.0 and absf(v.y + h / 2) < 0.001:
			# move bottom-ring vertices in/out and down a bit for a shaggy edge
			var key := Vector2(snappedf(v.x, 0.001), snappedf(v.z, 0.001))
			if not offsets.has(key):
				offsets[key] = Vector2(r.randf_range(1.0 - jitter, 1.0 + jitter), r.randf_range(-jitter, 0.0) * h)
			v.x *= offsets[key].x
			v.z *= offsets[key].x
			v.y += offsets[key].y
		v.y += y
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	var out := st.commit()
	out.surface_set_material(0, material)
	return out


static func blob(radius: float, center: Vector3, material: Material, jitter := 0.25, seed := 0) -> ArrayMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 1.7
	s.radial_segments = 8
	s.rings = 5
	var arr := s.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var offsets := {}
	for i in verts.size():
		var v := verts[i]
		var key := Vector3(snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001))
		if not offsets.has(key):
			offsets[key] = r.randf_range(1.0 - jitter, 1.0 + jitter)
		verts[i] = v * offsets[key] + center
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	var out := st.commit()
	out.surface_set_material(0, material)
	return out


## Tree kinds. Each part becomes one MultiMesh. "trunk_h" is the choppable height.
static func tree_kinds() -> Array[Dictionary]:
	var bark := mat("ffffff", true)
	var pale_bark := mat("ffffff", true)
	var needles := mat("ffffff", true)
	var leaves := mat("ffffff", true)
	var stump := mat("5e4630")
	return [
		{   # tall pine: dark trunk, four shaggy needle layers
			"name": "pine", "weight": 0.6, "radius": 0.3, "trunk_h": 5.0,
			"parts": [
				layer(0.16, 0.34, 6.0, 3.0, bark, 7),
				layer(0.0, 2.1, 2.8, 2.9, needles, 9, 0.18, 1),
				layer(0.0, 1.75, 2.6, 4.3, needles, 9, 0.18, 2),
				layer(0.0, 1.35, 2.4, 5.6, needles, 8, 0.18, 3),
				layer(0.0, 0.9, 2.0, 6.8, needles, 7, 0.15, 4),
			],
			"part_colors": ["4a3423", "1f3d26", "1f3d26", "234428", "26492b"],
			"stump": layer(0.26, 0.34, 0.45, 0.22, stump, 7),
		},
		{   # pale-barked broadleaf with a lumpy round canopy
			"name": "aspen", "weight": 0.4, "radius": 0.24, "trunk_h": 4.0,
			"parts": [
				layer(0.12, 0.26, 5.0, 2.5, pale_bark, 6),
				blob(1.5, Vector3(0, 4.6, 0), leaves, 0.25, 5),
				blob(1.1, Vector3(0.7, 5.5, 0.3), leaves, 0.25, 6),
				blob(1.0, Vector3(-0.6, 5.3, -0.4), leaves, 0.25, 7),
			],
			"part_colors": ["c9c2b0", "4f6b2a", "587530", "4a6528"],
			"stump": layer(0.2, 0.26, 0.4, 0.2, stump, 6),
		},
	]


# ---------------------------------------------------------------- grass

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform vec3 root_color : source_color = vec3(0.10, 0.16, 0.06);
uniform vec3 tip_color : source_color = vec3(0.33, 0.42, 0.16);
uniform float wind = 1.0;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.21) * 0.12 * wind;
	VERTEX.x += sway * UV.y * UV.y;
	VERTEX.z += sway * 0.5 * UV.y * UV.y;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	// blade silhouettes cut from each quad
	float blades = abs(fract(UV.x * 4.0) - 0.5) * 2.0;
	if (blades > 1.0 - (1.0 - UV.y) * 0.9) discard;
	ALBEDO = mix(root_color, tip_color, UV.y) * COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""


## Two crossed quads; UV.y is 0 at the root and 1 at the tip.
static func grass_clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in [0.0, PI / 2, PI / 4]:
		var d := Vector3(cos(a), 0, sin(a)) * 0.28
		var p := [-d, d, d + Vector3(0, 0.45, 0), -d + Vector3(0, 0.45, 0)]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[idx])
			st.add_vertex(p[idx])
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = GRASS_SHADER
	st.set_material(m)
	return st.commit()


# ---------------------------------------------------------------- rocks & logs

static func rock(seed: int) -> ArrayMesh:
	return blob(0.6, Vector3(0, 0.15, 0), mat("ffffff", true), 0.35, seed)
