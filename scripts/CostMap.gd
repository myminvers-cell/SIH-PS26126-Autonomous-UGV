class_name CostMap
extends RefCounted

# Grid settings: 80m x 80m terrain (-40 to +40)
const GRID_SIZE: int = 80
const CELL_SIZE: float = 1.0
const HALF_WIDTH: float = 40.0
const WALL_CLEARANCE_CELLS: int = 4

# Cell states / costs
const COST_SAFE: float = 1.0
const COST_UNCERTAIN: float = 5.0
const COST_OBSTACLE: float = 999.0

# 2D array of grid cells [x][z]
# Each element is a Dictionary: {"cost": float, "walkable": bool, "type": String}
var grid: Array = []

func _init() -> void:
	clear()

func clear() -> void:
	grid.clear()
	for x in range(GRID_SIZE):
		var column: Array = []
		for z in range(GRID_SIZE):
			column.append({
				"cost": COST_SAFE,
				"walkable": true,
				"type": "SAFE"
			})
		grid.append(column)
	# Keep the route planner inside the physical perimeter walls with room for
	# the UGV's chassis. The next cell inward is a costly safety buffer.
	for x in range(GRID_SIZE):
		for z in range(GRID_SIZE):
			var edge_distance := mini(mini(x, GRID_SIZE - 1 - x), mini(z, GRID_SIZE - 1 - z))
			if edge_distance < WALL_CLEARANCE_CELLS:
				if edge_distance < WALL_CLEARANCE_CELLS - 1:
					grid[x][z] = {"cost": COST_OBSTACLE, "walkable": false, "type": "BOUNDARY WALL"}
				else:
					grid[x][z] = {"cost": COST_UNCERTAIN, "walkable": true, "type": "WALL BUFFER"}

# Convert world Vector3 coordinate to grid coordinates Vector2i
func world_to_grid(world_pos: Vector3) -> Vector2i:
	var gx: int = int(floor(world_pos.x + HALF_WIDTH))
	var gz: int = int(floor(world_pos.z + HALF_WIDTH))
	gx = clampi(gx, 0, GRID_SIZE - 1)
	gz = clampi(gz, 0, GRID_SIZE - 1)
	return Vector2i(gx, gz)

# Convert grid coordinates Vector2i to world center Vector3
func grid_to_world(grid_pos: Vector2i) -> Vector3:
	var wx: float = (float(grid_pos.x) + 0.5) - HALF_WIDTH
	var wz: float = (float(grid_pos.y) + 0.5) - HALF_WIDTH
	return Vector3(wx, 0.2, wz)

func is_in_bounds(gx: int, gz: int) -> bool:
	return gx >= 0 and gx < GRID_SIZE and gz >= 0 and gz < GRID_SIZE

func set_obstacle(gx: int, gz: int, obstacle_type: String = "OBSTACLE", radius_cells: int = 1) -> void:
	for dx in range(-radius_cells, radius_cells + 1):
		for dz in range(-radius_cells, radius_cells + 1):
			var nx: int = gx + dx
			var nz: int = gz + dz
			if is_in_bounds(nx, nz):
				var dist: float = sqrt(float(dx * dx + dz * dz))
				if dist <= float(radius_cells):
					grid[nx][nz]["cost"] = COST_OBSTACLE
					grid[nx][nz]["walkable"] = false
					grid[nx][nz]["type"] = obstacle_type
				elif dist <= float(radius_cells + 1):
					# Uncertain / Safety margin buffer around obstacles
					if grid[nx][nz]["walkable"] and grid[nx][nz]["cost"] < COST_UNCERTAIN:
						grid[nx][nz]["cost"] = COST_UNCERTAIN
						grid[nx][nz]["type"] = "UNCERTAIN"

func set_hazard(gx: int, gz: int, hazard_type: String = "DITCH", radius_cells: int = 2) -> void:
	for dx in range(-radius_cells, radius_cells + 1):
		for dz in range(-radius_cells, radius_cells + 1):
			var nx: int = gx + dx
			var nz: int = gz + dz
			if is_in_bounds(nx, nz):
				var dist: float = sqrt(float(dx * dx + dz * dz))
				if dist <= float(radius_cells):
					# High hazard cost (can be traversed only if no alternative)
					grid[nx][nz]["cost"] = COST_UNCERTAIN * 2.0
					grid[nx][nz]["walkable"] = true
					grid[nx][nz]["type"] = hazard_type

func is_walkable(gx: int, gz: int) -> bool:
	if not is_in_bounds(gx, gz):
		return false
	return bool(grid[gx][gz]["walkable"])

func get_cell_cost(gx: int, gz: int) -> float:
	if not is_in_bounds(gx, gz):
		return 9999.0
	return float(grid[gx][gz]["cost"])

func get_cell_type(gx: int, gz: int) -> String:
	if not is_in_bounds(gx, gz):
		return "OUT_OF_BOUNDS"
	return str(grid[gx][gz]["type"])
