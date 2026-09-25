extends SceneTree

var main_scene: Main
var frames: int = 0
var replan_detected: bool = false

func _init() -> void:
	print("[AVOIDANCE TEST] Starting avoidance test...")
	var main_res: PackedScene = load("res://scenes/Main.tscn")
	var instance = main_res.instantiate()
	get_root().add_child(instance)
	main_scene = instance as Main

func _process(_delta: float) -> bool:
	frames += 1
	var ugv: UGV = main_scene.ugv

	# Frame 10: Start autonomy
	if frames == 10:
		print("[AVOIDANCE TEST] Starting UGV autonomy...")
		ugv.start_autonomy()

	# Frame 30: Spawn dynamic obstacle close ahead (at waypoint index 2 or 3m ahead)
	elif frames == 30:
		var forward: Vector3 = -ugv.global_transform.basis.z.normalized()
		var obs_pos: Vector3 = ugv.global_position + forward * 3.5
		obs_pos.y = 1.0
		print("[AVOIDANCE TEST] Spawning obstacle directly in front at %s (dist = 3.5m)..." % str(obs_pos))
		main_scene.obstacle_manager.spawn_dynamic_obstacle(obs_pos, main_scene.cost_map)
		main_scene.hud.cost_map_widget.refresh_map()

	# Monitor UGV reaction
	if frames > 30 and frames < 200:
		if ugv.current_state == UGV.NavState.OBSTACLE_DETECTED or ugv.current_state == UGV.NavState.REPLANNING or ugv.current_state == UGV.NavState.AVOIDING:
			replan_detected = true
			print("[AVOIDANCE TEST] Reactive state detected at frame %d: %s (Replans: %d)" % [
				frames, ugv.get_state_string(), ugv.replans_count
			])

	if frames >= 200:
		print("[AVOIDANCE TEST] Completed 200 frames. Final replans: %d" % ugv.replans_count)
		assert(replan_detected, "Vehicle must detect obstacle and initiate replan/avoidance")
		print("[AVOIDANCE TEST] SUCCESS: Dynamic obstacle detection & replanning confirmed!")
		quit(0)
		return true

	return false
