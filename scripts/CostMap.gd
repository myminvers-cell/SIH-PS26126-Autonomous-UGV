class_name CostMap
extends RefCounted

# Rectangular planning grid: 256m wide x 1280m long, at 4m per cell.
const GRID_WIDTH: int = 64
const GRID_HEIGHT: int = 320
const GRID_SIZE: int = GRID_WIDTH # Compatibility alias for square-only consumers.
const CELL_SIZE: float = 4.0
const HALF_WIDTH: float = 128.0
const HALF_LENGTH: float = 640.0
const WALL_CLEARANCE_CELLS: int = 2

# Cell states / costs
const COST_SAFE: float = 1.0
const COST_UNCERTAIN: float = 5.0
const COST_OBSTACLE: float = 999.0

# 2D array of grid cells [x][z]
# Each element is a Dictionary: {"cost": float, "walkable": bool, "type": String}
var grid: Array = []
var revision: int = 0

func _init() -> void:
	clear()

func clear() -> void:
	grid.clear()
	for x in range(GRID_WIDTH):
		var column: Array = []
		for z in range(GRID_HEIGHT):
			var world_x := (float(x) + 0.5) * CELL_SIZE - HALF_WIDTH
			var on_highway := absf(world_x) <= 14.0
			column.append({
				"cost": COST_SAFE if on_highway else 2.6,
				"walkable": true,
				"type": "HIGHWAY" if on_highway else "LOCAL ROAD / OPEN AREA"
			})
		grid.append(column)
	# Keep the route planner inside the physical perimeter walls with room for
	# the UGV's chassis. The next cell inward is a costly safety buffer.
	for x in range(GRID_WIDTH):
		for z in range(GRID_HEIGHT):
			var edge_distance := mini(mini(x, GRID_WIDTH - 1 - x), mini(z, GRID_HEIGHT - 1 - z))
			if edge_distance < WALL_CLEARANCE_CELLS:
				if edge_distance < WALL_CLEARANCE_CELLS - 1:
					grid[x][z] = {"cost": COST_OBSTACLE, "walkable": false, "type": "BOUNDARY WALL"}
				else:
					grid[x][z] = {"cost": COST_UNCERTAIN, "walkable": true, "type": "WALL BUFFER"}
	revision += 1

# Convert world Vector3 coordinate to grid coordinates Vector2i
func world_to_grid(world_pos: Vector3) -> Vector2i:
	var gx: int = int(floor((world_pos.x + HALF_WIDTH) / CELL_SIZE))
	var gz: int = int(floor((world_pos.z + HALF_LENGTH) / CELL_SIZE))
	gx = clampi(gx, 0, GRID_WIDTH - 1)
	gz = clampi(gz, 0, GRID_HEIGHT - 1)
	return Vector2i(gx, gz)

# Convert grid coordinates Vector2i to world center Vector3
func grid_to_world(grid_pos: Vector2i) -> Vector3:
	var wx: float = (float(grid_pos.x) + 0.5) * CELL_SIZE - HALF_WIDTH
	var wz: float = (float(grid_pos.y) + 0.5) * CELL_SIZE - HALF_LENGTH
	return Vector3(wx, 0.2, wz)

func is_in_bounds(gx: int, gz: int) -> bool:
	return gx >= 0 and gx < GRID_WIDTH and gz >= 0 and gz < GRID_HEIGHT

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
	revision += 1

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
