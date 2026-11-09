extends SceneTree
# Headless smoke test: chop a tree (with fall animation), collect logs, build from
# a blueprint, use the journal, and check hand-push movement.
# Run: godot --headless -s test.gd

func wait(sec: float) -> void:
	await create_timer(sec).timeout

func _initialize():
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var ok := true

	var t = main.trees[0]
	for i in 4:
		main.chop_cooldown = 0.0
		main._try_hit(t.pos + Vector3(0, 1, 0), 4.0)
	await wait(2.5)
	print("felled=", t.felled, " logs=", main.logs.size())
	ok = ok and t.felled and main.logs.size() == 3

	main.origin.position = main.logs[0].position
	await wait(0.2)
	for l in main.logs.duplicate():
		main.origin.position = l.position
		await wait(0.15)
	await wait(0.8)
	print("wood=", main.wood)
	ok = ok and main.wood == 3

	# journal: open, press the "Build" tab
	main.journal.toggle()
	await wait(0.6)
	main.journal._tab = "build"
	main.journal.refresh()
	print("journal open=", main.journal.is_open, " build rows=", main.journal._left_box.get_child_count())
	main.journal.toggle()

	# building: place a log wall and feed it logs
	main.wood = 6
	main.building.begin_place("wall", 0.0)
	main.building.move_ghost(main.origin.position + Vector3(0, 0, -2))
	main.building.confirm_place()
	await wait(2.5)
	var site = main.building.sites[0]
	print("wall built=", site.built, "/6 done=", site.done, " wood=", main.wood)
	ok = ok and site.done and main.wood == 0
	var top = main.building.floor_height(site.node.position.x, site.node.position.z, 10.0)
	print("can stand on wall top at y=", top)

	# arm locomotion: hand pressed into ground, then pulled back -> body moves forward
	main.origin.position = Vector3(0, main.height_at(0, 0), 0)
	main.left.position = Vector3(0, -0.2, -0.4)
	main._arm_locomotion(0.016)
	var p0 = main.origin.position
	for i in 10:
		main.left.position += Vector3(0, 0, 0.03)
		main._arm_locomotion(0.016)
	print("moved=", (main.origin.position - p0))
	ok = ok and (main.origin.position - p0).z < -0.25
	print("ALL OK" if ok else "FAILED")
	quit(0 if ok else 1)
