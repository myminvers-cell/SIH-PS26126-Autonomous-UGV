class_name Main
extends Node3D

@onready var ugv: UGV = $UGV
@onready var obstacle_manager: ObstacleManager = $ObstacleManager
@onready var perception: Perception = $Perception
@onready var path_visualizer: PathVisualizer = $PathVisualizer
@onready var main_camera: CameraFollow = $MainCamera
@onready var hud: UIManager = $HUD

var cost_map: CostMap
var astar_planner: AStarPlanner
var localization: Localization

const POINT_A: Vector3 = Vector3(-24.0, 0.4, -24.0)
const POINT_B: Vector3 = Vector3(24.0, 0.4, 24.0)

func _ready() -> void:
	_setup_core_systems()
	_connect_signals()
	_initialize_scenario()

func _setup_core_systems() -> void:
	cost_map = CostMap.new()
	astar_planner = AStarPlanner.new(cost_map)
	localization = Localization.new()

	perception.setup(ugv)
	obstacle_manager.populate_environment(cost_map)

	ugv.start_position = POINT_A
	ugv.goal_position  = POINT_B
	ugv.global_position = POINT_A
	ugv.initialize_subsystems(astar_planner, cost_map, localization, perception, obstacle_manager)

	path_visualizer.point_a = POINT_A
	path_visualizer.point_b = POINT_B

	hud.cost_map_widget.point_a = POINT_A
	hud.cost_map_widget.point_b = POINT_B
	hud.cost_map_widget.setup(cost_map)

	main_camera.target = ugv

func _connect_signals() -> void:
	hud.start_autonomy_pressed.connect(func(): ugv.start_autonomy())
	hud.stop_pressed.connect(func(): ugv.stop_ugv())
	hud.spawn_obstacle_pressed.connect(_on_spawn_obstacle_pressed)
	hud.force_replan_pressed.connect(func(): ugv.force_replan())
	hud.reset_pressed.connect(_on_reset_scenario)
	hud.mode_toggle_pressed.connect(func(): ugv.toggle_mode())
	hud.camera_mode_changed.connect(func(mode_idx: int):
		main_camera.set_mode(mode_idx as CameraFollow.CamMode)
	)

	ugv.path_updated.connect(func(path: Array[Vector3]):
		path_visualizer.draw_path(path, ugv.global_position)
		hud.cost_map_widget.set_active_path(path)
	)
	ugv.goal_reached.connect(func():
		hud.show_goal_reached(
			localization.total_distance_travelled,
			ugv.replans_count,
			not ugv.has_collided
		)
	)
	ugv.obstacle_encountered.connect(func(_type: String, _dist: float):
		hud.cost_map_widget.refresh_map()
	)

func _initialize_scenario() -> void:
	var initial_path: Array[Vector3] = astar_planner.find_path(POINT_A, POINT_B)
	if initial_path.size() > 0:
		ugv.current_path = initial_path
		ugv.waypoint_index = 0
		path_visualizer.draw_path(initial_path, POINT_A)
		hud.cost_map_widget.set_active_path(initial_path)

func _process(_delta: float) -> void:
	# Continuously redraw the remaining path from UGV's current waypoint onward
	if ugv.current_path.size() > 0 and ugv.current_state != UGV.NavState.GOAL_REACHED:
		var remaining: Array[Vector3] = []
		for i in range(ugv.waypoint_index, ugv.current_path.size()):
			remaining.append(ugv.current_path[i])
		path_visualizer.draw_path(remaining, ugv.global_position)

	hud.cost_map_widget.update_ugv_state(ugv.global_position, ugv.rotation_degrees.y)

	# UI telemetry
	var dist_to_goal: float = (POINT_B - ugv.global_position).length()
	var pt: Dictionary = perception.get_telemetry()

	hud.update_telemetry(
		ugv.get_state_string(),
		ugv.current_speed,
		localization.estimated_pos,
		localization.estimated_heading,
		dist_to_goal,
		str(pt["nearest_type"]),
		float(pt["nearest_dist"]),
		str(pt["risk"]),
		maxi(0, ugv.current_path.size() - ugv.waypoint_index),
		ugv.replans_count,
		ugv.is_autonomous
	)

func _on_spawn_obstacle_pressed() -> void:
	var spawn_pos: Vector3
	if ugv.current_path.size() > 0 and ugv.waypoint_index < ugv.current_path.size():
		# Place 4 waypoints ahead of current position
		var ahead_idx: int = mini(ugv.waypoint_index + 4, ugv.current_path.size() - 1)
		spawn_pos = ugv.current_path[ahead_idx]
	else:
		var fwd: Vector3 = -ugv.global_transform.basis.z.normalized()
		spawn_pos = ugv.global_position + fwd * 5.0

	spawn_pos.y = 1.15
	obstacle_manager.spawn_dynamic_obstacle(spawn_pos, cost_map)
	hud.cost_map_widget.refresh_map()

func _on_reset_scenario() -> void:
	hud.hide_goal_reached()
	# Clear all existing obstacle children immediately before repopulating
	for child in obstacle_manager.get_children():
		obstacle_manager.remove_child(child)
		child.queue_free()
	obstacle_manager.registered_obstacles.clear()
	obstacle_manager.dynamic_obstacles.clear()

	cost_map.clear()
	obstacle_manager.populate_environment(cost_map)

	ugv.reset_ugv()
	hud.cost_map_widget.refresh_map()
	_initialize_scenario()
