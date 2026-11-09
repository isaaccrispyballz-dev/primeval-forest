extends SceneTree
# headless smoke test: chop a tree, pick up logs, light a fire, simulate a hand push
func _initialize():
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var t = main.trees[0]
	for i in 4:
		main.chop_cooldown = 0.0
		main._try_hit(t.pos + Vector3(0, 1, 0), 4.0)
	print("felled=", t.felled, " logs=", main.logs.size())
	main.origin.position = t.pos + Vector3(0.6, 0, 0.6)
	for i in 10: await process_frame
	print("wood=", main.wood)
	main.wood = 5
	main._place_fire()
	print("fires=", main.fires.size(), " wood=", main.wood)
	# arm locomotion: hand pressed into ground, then pulled back -> body moves forward
	main.origin.position = Vector3(0, main.height_at(0, 0), 0)
	main.left.position = Vector3(0, -0.2, -0.4)   # below floor => contact
	main._arm_locomotion(0.016)
	var p0 = main.origin.position
	for i in 10:
		main.left.position += Vector3(0, 0, 0.03)  # pull hand toward body
		main._arm_locomotion(0.016)
	print("moved=", (main.origin.position - p0))
	main.left.position += Vector3(0, 0.5, 0)       # lift hand -> release
	main._arm_locomotion(0.016)
	print("launch vel=", main.velocity)
	quit()
