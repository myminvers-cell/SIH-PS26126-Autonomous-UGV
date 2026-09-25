class_name AStarPlanner
extends RefCounted

var cost_map: CostMap

# 8 directional offsets and their base movement distances
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(0, 1),   # N
	Vector2i(0, -1),  # S
	Vector2i(1, 0),   # E
	Vector2i(-1, 0),  # W
	Vector2i(1, 1),   # NE
	Vector2i(-1, 1),  # NW
	Vector2i(1, -1),  # SE
	Vector2i(-1, -1)  # SW
]

const NEIGHBOR_DISTANCES: Array[float] = [
	1.0, 1.0, 1.0, 1.0,
	1.4142, 1.4142, 1.4142, 1.4142
]

func _init(map: CostMap) -> void:
	cost_map = map

func heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: float = absf(float(a.x - b.x))
	var dz: float = absf(float(a.y - b.y))
	# Octile distance
	var min_d: float = minf(dx, dz)
	var max_d: float = maxf(dx, dz)
	return 1.4142 * min_d + (max_d - min_d)

# Find path from start_pos to goal_pos (in world coordinates)
# Returns Array of Vector3 waypoints in world space
func find_path(start_pos: Vector3, goal_pos: Vector3) -> Array[Vector3]:
	var start_grid: Vector2i = cost_map.world_to_grid(start_pos)
	var goal_grid: Vector2i = cost_map.world_to_grid(goal_pos)
	
	if not cost_map.is_walkable(start_grid.x, start_grid.y):
		# Start cell might be inside an obstacle if newly spawned, find nearest walkable
		start_grid = _find_nearest_walkable(start_grid)
		
	if not cost_map.is_walkable(goal_grid.x, goal_grid.y):
		goal_grid = _find_nearest_walkable(goal_grid)
	
	if start_grid == goal_grid:
		var single_path: Array[Vector3] = [goal_pos]
		return single_path

	# Priority queue using an array sorted by f_score descending (pop from back is O(1))
	var open_set: Array[Vector2i] = [start_grid]
	var in_open_set: Dictionary = {start_grid: true}
	var came_from: Dictionary = {}

	var g_score: Dictionary = {start_grid: 0.0}
	var f_score: Dictionary = {start_grid: heuristic(start_grid, goal_grid)}
	
	var closest_node: Vector2i = start_grid
	var closest_h: float = heuristic(start_grid, goal_grid)

	var iterations: int = 0
	const MAX_ITERATIONS: int = 4000

	while open_set.size() > 0 and iterations < MAX_ITERATIONS:
		iterations += 1
		
		# Find node with lowest f_score in open_set
		var current_index: int = 0
		var lowest_f: float = f_score.get(open_set[0], 999999.0)
		for i in range(1, open_set.size()):
			var f_val: float = f_score.get(open_set[i], 999999.0)
			if f_val < lowest_f:
				lowest_f = f_val
				current_index = i
				
		var current: Vector2i = open_set[current_index]
		
		# Check if reached goal
		if current == goal_grid:
			return _reconstruct_path(came_from, current, start_pos, goal_pos)

		# Remove from open_set
		open_set.remove_at(current_index)
		in_open_set.erase(current)

		var cur_g: float = g_score.get(current, 999999.0)

		# Track closest node in case exact goal is unreachable
		var h_val: float = heuristic(current, goal_grid)
		if h_val < closest_h:
			closest_h = h_val
			closest_node = current

		# Check 8 neighbors
		for n_idx in range(8):
			var offset: Vector2i = NEIGHBORS[n_idx]
			var neighbor: Vector2i = current + offset

			if not cost_map.is_walkable(neighbor.x, neighbor.y):
				continue

			# Diagonal corner cutting check
			if offset.x != 0 and offset.y != 0:
				if not cost_map.is_walkable(current.x + offset.x, current.y) or not cost_map.is_walkable(current.x, current.y + offset.y):
					continue

			var cell_cost: float = cost_map.get_cell_cost(neighbor.x, neighbor.y)
			var move_cost: float = NEIGHBOR_DISTANCES[n_idx] * cell_cost
			var tentative_g: float = cur_g + move_cost

			if tentative_g < g_score.get(neighbor, 999999.0):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				var new_f: float = tentative_g + heuristic(neighbor, goal_grid)
				f_score[neighbor] = new_f

				if not in_open_set.has(neighbor):
					open_set.append(neighbor)
					in_open_set[neighbor] = true

	# Fallback: if exact goal wasn't reached, try to return path to the closest reachable node
	if closest_node != start_grid and came_from.has(closest_node):
		return _reconstruct_path(came_from, closest_node, start_pos, cost_map.grid_to_world(closest_node))

	return []

func _reconstruct_path(came_from: Dictionary, current: Vector2i, _start_pos: Vector3, goal_pos: Vector3) -> Array[Vector3]:
	var grid_path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		grid_path.append(current)

	grid_path.reverse()

	# Convert grid points to world points with height offset
	var world_path: Array[Vector3] = []
	for gp in grid_path:
		world_path.append(cost_map.grid_to_world(gp))

	# Ensure the last point is exactly the goal position
	if world_path.size() > 0:
		world_path[world_path.size() - 1] = goal_pos

	return world_path

func _find_nearest_walkable(target: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var check: Vector2i = target + Vector2i(dx, dz)
				if cost_map.is_walkable(check.x, check.y):
					return check
	return target
