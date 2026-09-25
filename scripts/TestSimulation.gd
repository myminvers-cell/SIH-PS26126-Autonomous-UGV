extends SceneTree

func _init() -> void:
	print("[TEST] Initializing headless simulation verification...")
	
	# 1. CostMap & Obstacles
	var map: CostMap = CostMap.new()
	var planner: AStarPlanner = AStarPlanner.new(map)
	var obs_mgr: ObstacleManager = ObstacleManager.new()
	obs_mgr.populate_environment(map)
	
	var obs_count: int = obs_mgr.registered_obstacles.size()
	print("[TEST] Obstacles generated: %d" % obs_count)
	assert(obs_count >= 50, "Expected at least 50 obstacles in 60x60 environment")

	# Check rock, tree, boulder counts
	var rocks: int = 0
	var trees: int = 0
	var boulders: int = 0
	var ditches: int = 0
	var blocked: int = 0
	for obs in obs_mgr.registered_obstacles:
		match str(obs["type"]):
			"ROCK": rocks += 1
			"TREE": trees += 1
			"BOULDER": boulders += 1
			"DITCH": ditches += 1
			"BLOCKED AREA": blocked += 1

	print("[TEST] Breakdown -> Rocks: %d, Trees: %d, Boulders: %d, Ditches: %d, Blocked: %d" % [rocks, trees, boulders, ditches, blocked])
	assert(rocks >= 20, "Expected 20+ rocks")
	assert(trees >= 10, "Expected 10+ trees")
	assert(boulders >= 5, "Expected 5+ boulders")
	assert(ditches >= 5, "Expected 5+ ditches")
	assert(blocked >= 5, "Expected 5+ blocked regions")

	# 2. A* Path from Point A to Point B
	var point_a: Vector3 = Vector3(-24.0, 0.4, -24.0)
	var point_b: Vector3 = Vector3(24.0, 0.4, 24.0)

	var initial_path: Array[Vector3] = planner.find_path(point_a, point_b)
	print("[TEST] Initial path waypoints: %d" % initial_path.size())
	assert(initial_path.size() > 5, "Initial path should contain valid waypoints from A to B")

	# Ensure waypoints do not intersect blocked cells
	for pt in initial_path:
		var gp: Vector2i = map.world_to_grid(pt)
		assert(map.is_walkable(gp.x, gp.y), "Path waypoint must be in walkable cell")

	# 3. Dynamic Obstacle & Replanning test
	var midpoint_idx: int = initial_path.size() / 2
	var obstacle_pos: Vector3 = initial_path[midpoint_idx]
	print("[TEST] Injecting dynamic obstacle at path index %d (%s)..." % [midpoint_idx, obstacle_pos])

	obs_mgr.spawn_dynamic_obstacle(obstacle_pos, map)
	var obs_grid: Vector2i = map.world_to_grid(obstacle_pos)
	assert(not map.is_walkable(obs_grid.x, obs_grid.y), "Obstacle cell must be marked unwalkable")

	# Replan
	var replanned_path: Array[Vector3] = planner.find_path(point_a, point_b)
	print("[TEST] Replanned path waypoints: %d" % replanned_path.size())
	assert(replanned_path.size() > 5, "Replanner should find alternate valid route around dynamic obstacle")

	# Check that replanned path avoids the dynamic obstacle cell
	for pt in replanned_path:
		var gp: Vector2i = map.world_to_grid(pt)
		var dist_to_dyn_obs: float = (pt - obstacle_pos).length()
		assert(dist_to_dyn_obs > 0.8, "Replanned path must route around the dynamic obstacle")

	# 4. Localization Test
	var loc: Localization = Localization.new()
	loc.reset(point_a, 45.0)
	loc.update_odometry(point_a + Vector3(5, 0, 0), 50.0)
	assert(loc.total_distance_travelled > 4.9, "Localization should accumulate distance")
	assert(loc.estimated_heading == 50.0, "Localization should track heading")
	print("[TEST] Localization verified: Distance = %.2f m, Heading = %.1f deg" % [loc.total_distance_travelled, loc.estimated_heading])

	print("[TEST] ALL SYSTEM TESTS PASSED SUCCESSFULLY!")
	quit(0)
