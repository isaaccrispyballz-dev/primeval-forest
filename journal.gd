class_name Journal
extends Node3D
## The survey field journal: a small leather notebook that opens in front of your
## left hand. Its pages are a 2D UI drawn into a SubViewport and shown on two
## quads; you point at it with the right hand and pull the trigger to tap.

signal blueprint_chosen(id: String)

const PAGE_PX := Vector2i(1000, 634)       # both pages side by side
const SIZE_M := Vector2(0.42, 0.266)       # open book size in meters
const PAPER := Color("efe4c8")
const INK := Color("2b2118")
const FADED := Color("6e5b45")
const ACCENT := Color("8c3b1f")

var is_open := false
var open_t := 0.0
var viewport: SubViewport
var _left_pivot: Node3D
var _root_pages: Node3D
var _cursor: MeshInstance3D
var _tab := "journal"
var _selected := "campfire"
var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _status := {"day": 1, "clock": "06:00", "wood": 0}
var _blueprints: Dictionary = {}


func _init(blueprints: Dictionary) -> void:
	_blueprints = blueprints
	_build_viewport()
	_build_book()
	visible = false
	scale = Vector3.ONE * 0.001


func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.size = PAGE_PX
	viewport.transparent_bg = false
	viewport.gui_disable_input = false
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)

	var bg := ColorRect.new()
	bg.color = PAPER
	bg.size = PAGE_PX
	viewport.add_child(bg)
	# spine shadow down the middle
	var spine := ColorRect.new()
	spine.color = Color(0, 0, 0, 0.12)
	spine.position = Vector2(PAGE_PX.x / 2 - 6, 0)
	spine.size = Vector2(12, PAGE_PX.y)
	viewport.add_child(spine)

	var tabs := HBoxContainer.new()
	tabs.position = Vector2(40, 24)
	tabs.add_theme_constant_override("separation", 14)
	viewport.add_child(tabs)
	for t in [["journal", "Journal"], ["build", "Build"], ["guide", "Guide"]]:
		var b := _button(t[1], 34)
		b.pressed.connect(func(): _tab = t[0]; refresh())
		tabs.add_child(b)

	_left_box = VBoxContainer.new()
	_left_box.position = Vector2(48, 110)
	_left_box.size = Vector2(PAGE_PX.x / 2 - 96, PAGE_PX.y - 140)
	_left_box.add_theme_constant_override("separation", 10)
	viewport.add_child(_left_box)
	_right_box = VBoxContainer.new()
	_right_box.position = Vector2(PAGE_PX.x / 2 + 48, 110)
	_right_box.size = Vector2(PAGE_PX.x / 2 - 96, PAGE_PX.y - 140)
	_right_box.add_theme_constant_override("separation", 10)
	viewport.add_child(_right_box)


func _button(text: String, size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.border_color = FADED
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate()
	hover.bg_color = Color(ACCENT, 0.15)
	hover.border_color = ACCENT
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, INK if state == "font_color" else ACCENT)
	return b


func _label(text: String, size := 28, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _page_material(offset_x: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = viewport.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.uv1_scale = Vector3(0.5, 1, 1)
	m.uv1_offset = Vector3(offset_x, 0, 0)
	return m


func _build_book() -> void:
	var leather := Scenery.mat("5a3420")
	var half := SIZE_M.x / 2
	_root_pages = Node3D.new()
	add_child(_root_pages)

	# right half is fixed; the left half swings on the spine (local x = 0)
	var right_page := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(half, SIZE_M.y)
	right_page.mesh = q
	right_page.position = Vector3(half / 2, 0, 0.002)
	right_page.material_override = _page_material(0.5)
	_root_pages.add_child(right_page)
	var right_cover := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(half + 0.01, SIZE_M.y + 0.016, 0.012)
	cm.material = leather
	right_cover.mesh = cm
	right_cover.position = Vector3(half / 2, 0, -0.005)
	_root_pages.add_child(right_cover)

	_left_pivot = Node3D.new()
	_root_pages.add_child(_left_pivot)
	var left_page := MeshInstance3D.new()
	left_page.mesh = q
	left_page.position = Vector3(-half / 2, 0, 0.002)
	left_page.material_override = _page_material(0.0)
	_left_pivot.add_child(left_page)
	var left_cover := MeshInstance3D.new()
	left_cover.mesh = cm
	left_cover.position = Vector3(-half / 2, 0, -0.005)
	_left_pivot.add_child(left_cover)
	# a ribbon bookmark for character
	var ribbon := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.008, 0.06, 0.002)
	rm.material = Scenery.mat("8c3b1f")
	ribbon.mesh = rm
	ribbon.position = Vector3(0.01, -SIZE_M.y / 2 - 0.025, 0.003)
	_root_pages.add_child(ribbon)

	_cursor = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.004
	s.height = 0.008
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = ACCENT
	s.material = cmat
	_cursor.mesh = s
	_cursor.visible = false
	add_child(_cursor)


func toggle() -> void:
	is_open = not is_open
	if is_open:
		visible = true
		refresh()


func set_status(day: int, clock: String, wood: int) -> void:
	var changed: bool = _status.wood != wood or _status.day != day
	_status = {"day": day, "clock": clock, "wood": wood}
	if is_open and changed:
		refresh()


func _process(dt: float) -> void:
	open_t = move_toward(open_t, 1.0 if is_open else 0.0, dt * 3.5)
	var e := ease(open_t, -2.0)   # ease in-out
	scale = Vector3.ONE * maxf(0.001, minf(1.0, open_t * 3.0))
	# closed: left half folded over the right half (rotated about the spine)
	_left_pivot.rotation.y = lerpf(PI - 0.02, 0.0, e)
	_root_pages.position.x = lerpf(-SIZE_M.x / 4, 0.0, e)
	if open_t <= 0.0:
		visible = false


## Point at the pages with a ray. Returns true if the ray hits the open book.
func point(from: Vector3, dir: Vector3) -> bool:
	_cursor.visible = false
	if open_t < 0.98:
		return false
	var local_from := _root_pages.to_local(from)
	var local_dir := (_root_pages.global_transform.basis.inverse() * dir).normalized()
	if absf(local_dir.z) < 0.0001:
		return false
	var t := -local_from.z / local_dir.z
	if t < 0.0 or t > 1.5:
		return false
	var hit := local_from + local_dir * t
	var u := (hit.x + SIZE_M.x / 2) / SIZE_M.x
	var v := 0.5 - hit.y / SIZE_M.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return false
	_cursor.global_position = _root_pages.to_global(hit + Vector3(0, 0, 0.004))
	_cursor.visible = true
	_mouse_at = Vector2(u * PAGE_PX.x, v * PAGE_PX.y)
	var ev := InputEventMouseMotion.new()
	ev.position = _mouse_at
	ev.global_position = _mouse_at
	viewport.push_input(ev)
	return true


var _mouse_at := Vector2.ZERO

func click(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _mouse_at
	ev.global_position = _mouse_at
	viewport.push_input(ev)


# ---------------------------------------------------------------- pages

func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func refresh() -> void:
	_clear(_left_box)
	_clear(_right_box)
	match _tab:
		"journal": _page_journal()
		"build": _page_build()
		"guide": _page_guide()


const ENTRIES := [
	"The drone came down hard. The valley isn't on any of our maps, and the GPS just spins. The trees are older than anything I've seen.",
	"Something walked around the camp last night. It kept to the edge of the firelight and never came closer.",
	"Fire is the only thing it respects. More wood, bigger fires. I'm starting a shelter.",
	"Found claw marks high on the pines, far above where anything should reach. I sleep near the coals now.",
]


func _page_journal() -> void:
	var day: int = _status.day
	_left_box.add_child(_label("Day %d · %s" % [day, _status.clock], 40, ACCENT))
	_left_box.add_child(_label(ENTRIES[min(day - 1, ENTRIES.size() - 1)], 30))
	_right_box.add_child(_label("Supplies", 36, ACCENT))
	_right_box.add_child(_label("Logs: %d" % _status.wood, 32))
	_right_box.add_child(_label(" ", 12))
	_right_box.add_child(_label("Notes to self", 30, ACCENT))
	_right_box.add_child(_label("• Swing hard. Four good hits drop a tree.\n• Keep a fire going before dark.\n• Hands on the ground, push to move fast.\n• Climb the trunks to look around.", 26, FADED))


func _page_build() -> void:
	_left_box.add_child(_label("Blueprints", 36, ACCENT))
	for id in _blueprints:
		var bp: Dictionary = _blueprints[id]
		var b := _button("%s   (%d logs)" % [bp.name, bp.pieces.size()], 30)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _selected = id; refresh())
		_left_box.add_child(b)
	var sel: Dictionary = _blueprints[_selected]
	_right_box.add_child(_label(sel.name, 40, ACCENT))
	_right_box.add_child(_label("%d logs · you have %d" % [sel.pieces.size(), _status.wood], 28, FADED))
	_right_box.add_child(_label(sel.note, 28))
	_right_box.add_child(_label(" ", 10))
	var place := _button("Place blueprint", 34)
	place.pressed.connect(func(): blueprint_chosen.emit(_selected))
	_right_box.add_child(place)
	_right_box.add_child(_label("Aim at the ground, right stick turns it, trigger sets it down, B cancels. Bring logs to it to build.", 22, FADED))


func _page_guide() -> void:
	_left_box.add_child(_label("Moving", 34, ACCENT))
	_left_box.add_child(_label("Press your hands into the ground or a trunk and push. Let go mid-push to leap.\nLeft stick walks. Right stick turns.", 26))
	_left_box.add_child(_label("Chopping", 34, ACCENT))
	_left_box.add_child(_label("Swing the axe into a trunk. Walk to fallen logs to pick them up.", 26))
	_right_box.add_child(_label("Journal", 34, ACCENT))
	_right_box.add_child(_label("Y opens and closes this book. Point with your right hand and pull the trigger to tap.", 26))
	_right_box.add_child(_label("Building", 34, ACCENT))
	_right_box.add_child(_label("Choose a blueprint, set it down, then stand next to it. Your logs go in one at a time.", 26))
