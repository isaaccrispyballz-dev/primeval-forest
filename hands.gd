class_name Hand
extends Node3D
## A simple low-poly hand whose fingers curl with the controller's grip and
## trigger. Fingers are three-segment chains so the curl reads as a real fist.

var is_left := false
var curl := 0.0          # 0 open .. 1 fist (middle/ring/pinky)
var index_curl := 0.0    # trigger
var thumb_curl := 0.0
var _fingers: Array = [] # each: Array[Node3D] joints
var _thumb: Array = []


func _init(left_hand: bool, skin := Color("c99a78")) -> void:
	is_left = left_hand
	var m := Scenery.mat("ffffff")
	m.albedo_color = skin
	var side := -1.0 if is_left else 1.0

	var palm := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.085, 0.028, 0.095)
	pm.material = m
	palm.mesh = pm
	palm.position = Vector3(0, 0, 0.015)
	add_child(palm)

	# fingers point toward -Z (forward out of the fist), knuckles at the palm's front
	var lengths := [0.075, 0.082, 0.077, 0.062]
	for f in 4:
		var x := (-0.03 + f * 0.02) * side
		var joints: Array[Node3D] = []
		var parent: Node3D = self
		var pos := Vector3(x, 0, -0.033)
		for seg in 3:
			var j := Node3D.new()
			j.position = pos
			parent.add_child(j)
			var seg_len: float = lengths[f] / 3.0
			var bone := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.017, 0.017, seg_len)
			bm.material = m
			bone.mesh = bm
			bone.position.z = -seg_len / 2
			j.add_child(bone)
			joints.append(j)
			parent = j
			pos = Vector3(0, 0, -seg_len)
		_fingers.append(joints)

	# thumb comes off the inner side of the palm
	var tparent: Node3D = self
	var tpos := Vector3(-0.045 * side, -0.005, 0.02)
	for seg in 2:
		var j := Node3D.new()
		j.position = tpos
		if seg == 0:
			j.rotation = Vector3(0, 0.9 * side, 0)
		tparent.add_child(j)
		var bone := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.019, 0.035)
		bm.material = m
		bone.mesh = bm
		bone.position.z = -0.0175
		j.add_child(bone)
		_thumb.append(j)
		tparent = j
		tpos = Vector3(0, 0, -0.035)


func _process(_dt: float) -> void:
	for f in 4:
		var c := index_curl if f == 0 else curl
		for j in _fingers[f]:
			j.rotation.x = -c * 1.45
	var side := -1.0 if is_left else 1.0
	_thumb[0].rotation = Vector3(-thumb_curl * 0.5, (0.9 - thumb_curl * 0.7) * side, 0)
	_thumb[1].rotation.x = -thumb_curl * 1.0
