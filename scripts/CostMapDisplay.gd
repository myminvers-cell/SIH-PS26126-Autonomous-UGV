class_name CostMapDisplay
extends Control

var cost_map: CostMap
var active_path: Array[Vector3] = []
var ugv_position: Vector3 = Vector3.ZERO
var ugv_heading_deg: float = 0.0
var point_a: Vector3 = Vector3(6.3, 0.4, -600.0)
var point_b: Vector3 = Vector3(6.3, 0.4, 600.0)
var traffic_manager: Node
var road_visuals: Node3D

var _map_image: Image
var _map_texture: ImageTexture
var _needs_texture_update: bool = true
var _last_map_revision: int = -1

const HIGHWAY_HALF_WIDTH := 13.0
const SERVICE_ROAD_CENTER_X := 40.0
const SERVICE_ROAD_HALF_WIDTH := 4.2
const JUNCTIONS := [-400.0, -200.0, 0.0, 200.0, 400.0]
const CROSSROAD_HALF_WIDTH := 118.0
const CROSSROAD_HALF_DEPTH := 4.5

func setup(map: CostMap) -> void:
	cost_map = map
	_map_image = Image.create(CostMap.GRID_WIDTH, CostMap.GRID_HEIGHT, false, Image.FORMAT_RGBA8)
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

	for x in range(CostMap.GRID_WIDTH):
		for z in range(CostMap.GRID_HEIGHT):
			var cell_type: String = cost_map.get_cell_type(x, z)
			var world_x := (float(x) + 0.5) * CostMap.CELL_SIZE - CostMap.HALF_WIDTH
			var world_z := (float(z) + 0.5) * CostMap.CELL_SIZE - CostMap.HALF_LENGTH
			var col := _terrain_color(world_x, world_z)
			if cell_type == "UNCERTAIN" or cell_type == "WALL BUFFER":
				col = Color(0.72, 0.56, 0.16, 1.0)
			elif not cost_map.is_walkable(x, z):
				col = Color(0.9, 0.2, 0.16, 1.0)
			_map_image.set_pixel(x, z, col)

	if _map_texture == null:
		_map_texture = ImageTexture.create_from_image(_map_image)
	else:
		_map_texture.update(_map_image)
	_last_map_revision = cost_map.revision

func _terrain_color(world_x: float, world_z: float) -> Color:
	for junction_z in JUNCTIONS:
		if absf(world_z - float(junction_z)) <= CROSSROAD_HALF_DEPTH and absf(world_x) <= CROSSROAD_HALF_WIDTH:
			return Color(0.19, 0.2, 0.21, 1.0)
		if absf(world_z - float(junction_z)) <= CROSSROAD_HALF_DEPTH and absf(world_x) >= HIGHWAY_HALF_WIDTH and absf(world_x) <= SERVICE_ROAD_CENTER_X:
			return Color(0.19, 0.2, 0.21, 1.0)
	if absf(world_x) <= HIGHWAY_HALF_WIDTH:
		return Color(0.13, 0.15, 0.17, 1.0)
	if absf(absf(world_x) - SERVICE_ROAD_CENTER_X) <= SERVICE_ROAD_HALF_WIDTH:
		return Color(0.16, 0.18, 0.19, 1.0)
	if (absf(world_x) >= 13.0 and absf(world_x) <= 18.5) or (absf(absf(world_x) - 40.0) >= 4.2 and absf(absf(world_x) - 40.0) <= 5.0):
		return Color(0.28, 0.29, 0.25, 1.0)
	return Color(0.16, 0.21, 0.16, 1.0)

func _world_to_ui(w_pos: Vector3, rect_size: Vector2) -> Vector2:
	# Map world bounds directly to the widget. X is expanded to use the compact
	# HUD card, but each vehicle, route, road, and obstacle uses the same mapping.
	var nx := clampf((w_pos.x + CostMap.HALF_WIDTH) / (CostMap.HALF_WIDTH * 2.0), 0.0, 1.0)
	var nz := clampf((w_pos.z + CostMap.HALF_LENGTH) / (CostMap.HALF_LENGTH * 2.0), 0.0, 1.0)
	return Vector2(nx * rect_size.x, nz * rect_size.y)

func _draw() -> void:
	var r_size: Vector2 = size
	if r_size.x <= 0 or r_size.y <= 0:
		return

	# Draw border / background
	draw_rect(Rect2(Vector2.ZERO, r_size), Color(0.08, 0.09, 0.11, 0.95), true)

	if cost_map != null and cost_map.revision != _last_map_revision:
		_needs_texture_update = true
	if _needs_texture_update:
		_update_image_from_costmap()
		_needs_texture_update = false

	# Fill the minimap card; world-to-map conversion is shared by every overlay.
	var map_size := r_size
	var map_origin := Vector2.ZERO
	var map_rect := Rect2(map_origin, map_size)
	if _map_texture != null:
		draw_texture_rect(_map_texture, map_rect, false)

	# Draw grid outline
	draw_rect(map_rect, Color(0.3, 0.4, 0.5, 0.8), false, 2.0)
	_draw_roads(map_size, map_origin)
	_draw_city(map_size, map_origin)
	_draw_traffic(map_size, map_origin)

	# Draw active A* path
	if active_path.size() > 1:
		var points: PackedVector2Array = PackedVector2Array()
		# Add UGV current pos first
		points.append(_world_to_ui(ugv_position, map_size) + map_origin)
		for pt in active_path:
			points.append(_world_to_ui(pt, map_size) + map_origin)
		draw_polyline(points, Color(0.2, 0.85, 1.0, 0.9), 2.5, true)

	# Draw Point A (Start)
	var ui_a: Vector2 = _world_to_ui(point_a, map_size) + map_origin
	draw_circle(ui_a, 5.0, Color(0.1, 0.9, 0.3, 1.0))
	draw_string(ThemeDB.fallback_font, ui_a + Vector2(7, 4), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.2, 1.0, 0.4))

	# Draw Point B (Goal)
	var ui_b: Vector2 = _world_to_ui(point_b, map_size) + map_origin
	draw_circle(ui_b, 6.0, Color(1.0, 0.8, 0.1, 1.0))
	draw_string(ThemeDB.fallback_font, ui_b + Vector2(7, 4), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.9, 0.2))

	# Draw UGV position & Heading
	var ui_ugv: Vector2 = _world_to_ui(ugv_position, map_size) + map_origin
	draw_circle(ui_ugv, 5.5, Color(1.0, 0.4, 0.1, 1.0))
	# Draw heading direction needle
	var rad: float = deg_to_rad(ugv_heading_deg)
	# Transform the UGV's -Z forward vector into the minimap's +Z-down axes.
	var dir_vec: Vector2 = Vector2(-sin(rad), -cos(rad)).normalized() * 10.0
	draw_line(ui_ugv, ui_ugv + dir_vec, Color(1.0, 1.0, 1.0, 1.0), 2.0)

func _draw_roads(map_size: Vector2, map_origin: Vector2) -> void:
	var line_width := maxf(1.0, map_size.x / (CostMap.HALF_WIDTH * 2.0) * 0.18)
	var paint_color := Color(0.85, 0.8, 0.64, 0.9)
	for lane_boundary in [-4.2, 0.0, 4.2]:
		for z in range(-590, 591, 24):
			var start := _world_to_ui(Vector3(lane_boundary, 0.0, float(z)), map_size) + map_origin
			var finish := _world_to_ui(Vector3(lane_boundary, 0.0, float(z) + 9.0), map_size) + map_origin
			draw_line(start, finish, paint_color, line_width, true)
	for edge_x in [-10.8, 10.8]:
		var start := _world_to_ui(Vector3(edge_x, 0.0, -600.0), map_size) + map_origin
		var finish := _world_to_ui(Vector3(edge_x, 0.0, 600.0), map_size) + map_origin
		draw_line(start, finish, Color(0.94, 0.72, 0.2, 0.95), line_width, true)
	for junction_z in JUNCTIONS:
		for x in range(-112, 113, 18):
			var start := _world_to_ui(Vector3(float(x), 0.0, junction_z), map_size) + map_origin
			var finish := _world_to_ui(Vector3(float(x) + 8.0, 0.0, junction_z), map_size) + map_origin
			draw_line(start, finish, paint_color, line_width, true)
	for side in [-1.0, 1.0]:
		var road_x: float = float(side) * SERVICE_ROAD_CENTER_X
		for z in range(-590, 591, 28):
			var start := _world_to_ui(Vector3(road_x, 0.0, float(z)), map_size) + map_origin
			var finish := _world_to_ui(Vector3(road_x, 0.0, float(z) + 10.0), map_size) + map_origin
			draw_line(start, finish, Color(0.72, 0.73, 0.67, 0.85), line_width, true)

func _draw_city(map_size: Vector2, map_origin: Vector2) -> void:
	if not is_instance_valid(road_visuals):
		return
	for child in road_visuals.get_children():
		if child is StaticBody3D and child.name.begins_with("Shopfront_"):
			var collider := child.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if collider != null and collider.shape is BoxShape3D:
				var shop_size := (collider.shape as BoxShape3D).size
				var center := collider.global_position
				_draw_world_rect(center.x - shop_size.x * 0.5, center.x + shop_size.x * 0.5, center.z - shop_size.z * 0.5, center.z + shop_size.z * 0.5, Color(0.61, 0.4, 0.27, 1.0), map_size, map_origin)
		elif child is Node3D and child.name == "BusShelter":
			var center := (child as Node3D).global_position
			_draw_world_rect(center.x - 3.5, center.x + 3.5, center.z - 1.7, center.z + 1.7, Color(0.28, 0.53, 0.58, 1.0), map_size, map_origin)

func _draw_world_rect(left: float, right: float, near_z: float, far_z: float, color: Color, map_size: Vector2, map_origin: Vector2) -> void:
	var top_left := _world_to_ui(Vector3(left, 0.0, near_z), map_size) + map_origin
	var bottom_right := _world_to_ui(Vector3(right, 0.0, far_z), map_size) + map_origin
	var rect := Rect2(top_left, bottom_right - top_left)
	draw_rect(rect, color, true)
	draw_rect(rect, Color(0.88, 0.72, 0.49, 0.8), false, 1.0)

func _draw_traffic(map_size: Vector2, map_origin: Vector2) -> void:
	if not is_instance_valid(traffic_manager):
		return
	var traffic: Array = traffic_manager.get("vehicles")
	for agent in traffic:
		var body = agent.get("body")
		if not is_instance_valid(body):
			continue
		var kind := str(agent.get("kind", "SEDAN"))
		var color := Color(0.2, 0.72, 0.95, 1.0)
		if bool(agent.get("wrecked", false)):
			color = Color(1.0, 0.2, 0.12, 1.0)
		elif kind == "MOTORCYCLE":
			color = Color(1.0, 0.79, 0.22, 1.0)
		elif kind == "CITY BUS" or kind == "DELIVERY TRUCK":
			color = Color(0.98, 0.55, 0.22, 1.0)
		var radius := 2.0 if kind == "MOTORCYCLE" else (3.0 if kind == "CITY BUS" else 2.4)
		var point := _world_to_ui(body.global_position, map_size) + map_origin
		draw_circle(point, radius + 1.0, Color(0.03, 0.05, 0.06, 1.0))
		draw_circle(point, radius, color)
	var walkers: Array = traffic_manager.get("pedestrians")
	for agent in walkers:
		var body = agent.get("body")
		if is_instance_valid(body):
			var point := _world_to_ui(body.global_position, map_size) + map_origin
			draw_circle(point, 1.7, Color(0.32, 1.0, 0.68, 1.0))
