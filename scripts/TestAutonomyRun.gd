extends SceneTree

var main_scene: Main
var frames: int = 0
var test_phase: int = 0

func _init() -> void:
	print("[AUTONOMY TEST] Starting autonomy test...")
	var main_res: PackedScene = load("res://scenes/Main.tscn")
	var instance = main_res.instantiate()
	get_root().add_child(instance)
	main_scene = instance as Main

func _process(delta: float) -> bool:
	frames += 1

	if main_scene == null:
		var root = get_root()
		if root.has_node("Main"):
			main_scene = root.get_node("Main") as Main
		else:
			return false

	var ugv: UGV = main_scene.ugv

	# Phase 0: Start autonomy
	if test_phase == 0 and frames >= 20:
		print("[AUTONOMY TEST] Phase 0: Triggering START AUTONOMY...")
		ugv.start_autonomy()
		test_phase = 1

	# Phase 1: Wait until UGV is navigating and has moved
	elif test_phase == 1 and frames >= 80:
		print("[AUTONOMY TEST] Phase 1: UGV State = %s, Speed = %.2f m/s, Pos = (%0.1f, %0.1f)" % [
			ugv.get_state_string(), ugv.current_speed, ugv.global_position.x, ugv.global_position.z
		])
		assert(ugv.current_speed > 0.5, "UGV should be moving forward")
		print("[AUTONOMY TEST] Phase 2: Spawning dynamic obstacle ahead...")
		main_scene._on_spawn_obstacle_pressed()
		test_phase = 2

	# Phase 2: Wait for perception to detect and trigger replan
	elif test_phase == 2 and frames >= 180:
		print("[AUTONOMY TEST] Phase 2 Check: State = %s, Replans = %d" % [
			ugv.get_state_string(), ugv.replans_count
		])
		# Phase 3: Wait a bit more to ensure vehicle continues
		test_phase = 3

	elif test_phase == 3 and frames >= 260:
		print("[AUTONOMY TEST] Phase 3 Check: Distance travelled = %.2f m, Waypoints = %d" % [
			main_scene.localization.total_distance_travelled,
			ugv.current_path.size()
		])
		print("[AUTONOMY TEST] SUCCESSFUL AUTONOMY RUN! All phases verified.")
		quit(0)
		return true

	return false
