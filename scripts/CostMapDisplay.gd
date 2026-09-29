class_name CostMapDisplay
extends Control

var cost_map: CostMap
var active_path: Array[Vector3] = []
var ugv_position: Vector3 = Vector3.ZERO
var ugv_heading_deg: float = 0.0
var point_a: Vector3 = Vector3(-24.0, 0.4, -24.0)
var point_b: Vector3 = Vector3(24.0, 0.4, 24.0)

var _map_image: Image
var _map_texture: ImageTexture
var _needs_texture_update: bool = true

func setup(map: CostMap) -> void:
	cost_map = map
	_map_image = Image.create(CostMap.GRID_SIZE, CostMap.GRID_SIZE, false, Image.FORMAT_RGBA8)
	_update_image_from_costmap()

func update_ugv_state(pos: Vector3, heading: float) -> void:
	ugv_position = pos
	ugv_heading_deg = heading
	queue_redraw()

func set_active_path(path: Array[Vector3]) -> void:
	active_path = path
	queue_redraw()

func refresh_map() -> void:
	_needs_texture_update = true
	queue_redraw()

func _update_image_from_costmap() -> void:
	if cost_map == null or _map_image == null:
		return

	for x in range(CostMap.GRID_SIZE):
		for z in range(CostMap.GRID_SIZE):
			var cell_type: String = cost_map.get_cell_type(x, z)
			var col: Color = Color(0.12, 0.35, 0.15, 0.9) # Safe Green
			if cell_type == "UNCERTAIN" or cell_type == "WALL BUFFER":
				col = Color(0.8, 0.7, 0.1, 0.9) # Uncertain Yellow
			elif not cost_map.is_walkable(x, z):
				col = Color(0.85, 0.18, 0.15, 0.95) # Blocked Red
			_map_image.set_pixel(x, z, col)

	if _map_texture == null:
		_map_texture = ImageTexture.create_from_image(_map_image)
	else:
		_map_texture.update(_map_image)

func _world_to_ui(w_pos: Vector3, rect_size: Vector2) -> Vector2:
	# World (-40 to +40) -> UI (0 to rect_size)
	var nx: float = (w_pos.x + CostMap.HALF_WIDTH) / float(CostMap.GRID_SIZE * CostMap.CELL_SIZE)
	var nz: float = (w_pos.z + CostMap.HALF_WIDTH) / float(CostMap.GRID_SIZE * CostMap.CELL_SIZE)
	return Vector2(nx * rect_size.x, nz * rect_size.y)

func _draw() -> void:
	var r_size: Vector2 = size
	if r_size.x <= 0 or r_size.y <= 0:
		return

	# Draw border / background
	draw_rect(Rect2(Vector2.ZERO, r_size), Color(0.08, 0.09, 0.11, 0.95), true)

	if _needs_texture_update:
		_update_image_from_costmap()
		_needs_texture_update = false

	# Draw the 80x80 cost map texture stretched to size
	if _map_texture != null:
		draw_texture_rect(_map_texture, Rect2(Vector2.ZERO, r_size), false)

	# Draw grid outline
	draw_rect(Rect2(Vector2.ZERO, r_size), Color(0.3, 0.4, 0.5, 0.8), false, 2.0)

	# Draw active A* path
	if active_path.size() > 1:
		var points: PackedVector2Array = PackedVector2Array()
		# Add UGV current pos first
		points.append(_world_to_ui(ugv_position, r_size))
		for pt in active_path:
			points.append(_world_to_ui(pt, r_size))
		draw_polyline(points, Color(0.2, 0.85, 1.0, 0.9), 2.5, true)

	# Draw Point A (Start)
	var ui_a: Vector2 = _world_to_ui(point_a, r_size)
	draw_circle(ui_a, 5.0, Color(0.1, 0.9, 0.3, 1.0))
	draw_string(ThemeDB.fallback_font, ui_a + Vector2(7, 4), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.2, 1.0, 0.4))

	# Draw Point B (Goal)
	var ui_b: Vector2 = _world_to_ui(point_b, r_size)
	draw_circle(ui_b, 6.0, Color(1.0, 0.8, 0.1, 1.0))
	draw_string(ThemeDB.fallback_font, ui_b + Vector2(7, 4), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.9, 0.2))

	# Draw UGV position & Heading
	var ui_ugv: Vector2 = _world_to_ui(ugv_position, r_size)
	draw_circle(ui_ugv, 5.5, Color(1.0, 0.4, 0.1, 1.0))
	# Draw heading direction needle
	var rad: float = deg_to_rad(ugv_heading_deg)
	# In our world, forward is -Z (which is -Y in UI coordinates)
	var dir_vec: Vector2 = Vector2(-sin(rad), -cos(rad)).normalized() * 10.0
	draw_line(ui_ugv, ui_ugv + dir_vec, Color(1.0, 1.0, 1.0, 1.0), 2.0)
