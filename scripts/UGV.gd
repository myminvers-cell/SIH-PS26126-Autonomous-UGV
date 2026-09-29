class_name UGV
extends CharacterBody3D

signal state_changed(new_state: String)
signal goal_reached()
signal path_updated(path: Array[Vector3])
signal obstacle_encountered(obstacle_type: String, dist: float)

enum NavState {
	INITIALIZING,
	PLANNING,
	NAVIGATING,
	YIELDING,
	OBSTACLE_DETECTED,
	REPLANNING,
	AVOIDING,
	BACKTRACKING,
	STUCK_RECOVERY,
	GOAL_REACHED,
	STOPPED,
	MANUAL
}

@export_range(1.0, 8.0, 0.5) var max_speed: float = 7.0
@export var turn_speed: float = 1.3
@export var acceleration: float = 3.0
@export var deceleration: float = 5.2

var current_state: NavState = NavState.INITIALIZING
var is_autonomous: bool = true

# Navigation subsystems (injected by Main.gd)
var astar_planner: AStarPlanner
var cost_map: CostMap
var localization: Localization
var perception: Perception
var obstacle_manager: ObstacleManager
var traffic_manager: TrafficManager

var current_path: Array[Vector3] = []
var waypoint_index: int = 0
var goal_position: Vector3 = Vector3(6.3, 0.0, 600.0)
var start_position: Vector3 = Vector3(6.3, 0.0, -600.0)

var current_speed: float = 0.0
var replans_count: int = 0
var has_collided: bool = false
var _traffic_bypass_pending: bool = false
var _traffic_bypass_position: Vector3 = Vector3.ZERO

# Stuck detection & recovery
var _stuck_timer: float = 0.0
var _last_check_pos: Vector3 = Vector3.ZERO
var _recovery_timer: float = 0.0
var _replan_cooldown: float = 0.0
var _vertical_speed: float = 0.0
var _perception_scan_timer: float = 0.0
var _traffic_clear_timer: float = 0.0

# Headlight node
var _headlight: OmniLight3D

# Node references
@onready var front_camera: Camera3D = $FrontCamera3D
var wheel_fl: Node3D
var wheel_fr: Node3D
var wheel_rl: Node3D
var wheel_rr: Node3D

func _ready() -> void:
	_setup_mesh_references()
	_setup_headlight()
	_last_check_pos = global_position

func _setup_mesh_references() -> void:
	if has_node("Visuals/WheelFL"):
		wheel_fl = get_node("Visuals/WheelFL")
	if has_node("Visuals/WheelFR"):
		wheel_fr = get_node("Visuals/WheelFR")
	if has_node("Visuals/WheelRL"):
		wheel_rl = get_node("Visuals/WheelRL")
	if has_node("Visuals/WheelRR"):
		wheel_rr = get_node("Visuals/WheelRR")

func _setup_headlight() -> void:
	_headlight = OmniLight3D.new()
	_headlight.position = Vector3(0.0, 0.6, -1.2)
	_headlight.light_color = Color(0.95, 0.92, 0.75)
	_headlight.light_energy = 2.2
	_headlight.omni_range = 7.0
	_headlight.shadow_enabled = false  # Shadows are expensive on Intel HD 4600
	add_child(_headlight)

func initialize_subsystems(planner: AStarPlanner, map: CostMap, loc: Localization, perc: Perception, obs_mgr: ObstacleManager) -> void:
	astar_planner = planner
	cost_map = map
	localization = loc
	perception = perc
	obstacle_manager = obs_mgr
	localization.reset(global_position, rotation_degrees.y)
	set_state(NavState.STOPPED)

func set_state(new_state: NavState) -> void:
	current_state = new_state
	state_changed.emit(get_state_string())

func get_state_string() -> String:
	match current_state:
		NavState.INITIALIZING:     return "INITIALIZING"
		NavState.PLANNING:         return "PLANNING"
		NavState.NAVIGATING:       return "NAVIGATING"
		NavState.YIELDING:         return "YIELDING FOR TRAFFIC"
		NavState.OBSTACLE_DETECTED:return "OBSTACLE DETECTED"
		NavState.REPLANNING:       return "REPLANNING"
		NavState.AVOIDING:         return "AVOIDING"
		NavState.BACKTRACKING:     return "BACKTRACKING"
		NavState.STUCK_RECOVERY:   return "STUCK RECOVERY"
		NavState.GOAL_REACHED:     return "GOAL REACHED"
		NavState.STOPPED:          return "STOPPED"
		NavState.MANUAL:           return "MANUAL"
		_:                         return "UNKNOWN"

func _physics_process(delta: float) -> void:
	# Simulated Visual Odometry update
	if localization != null:
		localization.update_odometry(global_position, rotation_degrees.y)

	# Sensor rays are rate-limited; raycasting the full fan every physics tick
	# produced needless CPU spikes without making obstacle response more useful.
	if perception != null and obstacle_manager != null:
		_perception_scan_timer -= delta
		if _perception_scan_timer <= 0.0:
			_perception_scan_timer = 0.08
			var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
			perception.scan_environment(space_state, obstacle_manager)
			if current_state == NavState.OBSTACLE_DETECTED and ["SEDAN", "CITY BUS", "DELIVERY TRUCK", "AUTO RICKSHAW", "MOTORCYCLE"].has(perception.front_obstacle_type):
				_traffic_bypass_position = perception.front_obstacle_position

	if _replan_cooldown > 0.0:
		_replan_cooldown -= delta
	if is_autonomous:
		_process_autonomous(delta)
	else:
		_process_manual(delta)
	_handle_motion_collision()

	_animate_wheels(delta)

func _process_autonomous(delta: float) -> void:
	match current_state:
		NavState.STOPPED:
			current_speed = move_toward(current_speed, 0.0, deceleration * delta)
			velocity = Vector3.ZERO
			_move_with_gravity(delta)

		NavState.PLANNING:
			_execute_planning()

		NavState.NAVIGATING, NavState.AVOIDING:
			_process_navigation(delta)

		NavState.YIELDING:
			_process_traffic_yield(delta)

		NavState.OBSTACLE_DETECTED:
			# Emergency brake
			current_speed = move_toward(current_speed, 0.0, deceleration * 2.0 * delta)
			var fwd: Vector3 = -global_transform.basis.z.normalized()
			velocity = fwd * current_speed
			_move_with_gravity(delta)
			if current_speed <= 0.15:
				set_state(NavState.REPLANNING)

		NavState.REPLANNING:
			_execute_replanning()

		NavState.BACKTRACKING, NavState.STUCK_RECOVERY:
			_process_recovery(delta)

		NavState.GOAL_REACHED:
			current_speed = move_toward(current_speed, 0.0, deceleration * delta)
			velocity = Vector3.ZERO
			_move_with_gravity(delta)

func _execute_planning() -> void:
	if astar_planner == null:
		return
	var new_path: Array[Vector3] = astar_planner.find_path(global_position, goal_position)
	if new_path.size() >= 1:
		if _traffic_bypass_pending:
			new_path = _build_traffic_bypass_path(new_path)
			_traffic_bypass_pending = false
		current_path = new_path
		waypoint_index = mini(1, new_path.size() - 1)
		path_updated.emit(current_path)
		set_state(NavState.NAVIGATING)
	else:
		set_state(NavState.STOPPED)

func _execute_replanning() -> void:
	replans_count += 1
	var new_path: Array[Vector3] = astar_planner.find_path(global_position, goal_position)
	if new_path.size() >= 1:
		if _traffic_bypass_pending:
			new_path = _build_traffic_bypass_path(new_path)
			_traffic_bypass_pending = false
		current_path = new_path
		waypoint_index = mini(1, new_path.size() - 1)
		path_updated.emit(current_path)
		_replan_cooldown = 1.2
		set_state(NavState.AVOIDING)
	else:
		# No route found – try backtracking away from current cell
		set_state(NavState.BACKTRACKING)
		_recovery_timer = 1.8

func _process_navigation(delta: float) -> void:
	# ── 1. Goal arrival check ──────────────────────────────────────────────
	var dist_to_goal: float = (goal_position - global_position).length()
	if dist_to_goal <= 1.5:
		set_state(NavState.GOAL_REACHED)
		goal_reached.emit()
		return

	# Predict crossing and catching traffic before it enters the UGV's space.
	# Yielding leaves the planned route intact, so the UGV resumes as soon as
	# the moving road user has cleared instead of needlessly replanning.
	var traffic_hazard := _get_traffic_hazard()
	if not traffic_hazard.is_empty():
		_traffic_clear_timer = 0.0
		set_state(NavState.YIELDING)
		return

	# ── 2. Perception-triggered obstacle detection ─────────────────────────
	if perception != null and _replan_cooldown <= 0.0:
		# FIX: Only trigger if obstacle is truly close AND directly ahead
		if perception.is_front_blocked:
			var front_type: String = perception.front_obstacle_type
			var front_dist: float = perception.front_obstacle_dist
			obstacle_encountered.emit(front_type, front_dist)
			# FIX: Project obstacle position FORWARD (+z) from UGV, not backward
			var blocked_world_pt: Vector3 = perception.front_obstacle_position
			var moving_road_users := ["SEDAN", "CITY BUS", "DELIVERY TRUCK", "AUTO RICKSHAW", "MOTORCYCLE", "PEDESTRIAN"]
			if moving_road_users.has(front_type):
				_traffic_bypass_pending = true
				_traffic_bypass_position = blocked_world_pt
			elif ["TREE", "ROCK", "BOULDER", "BOUNDARY WALL", "BLOCKED AREA", "DYNAMIC OBSTACLE"].has(front_type):
				var gp: Vector2i = cost_map.world_to_grid(blocked_world_pt)
				cost_map.set_obstacle(gp.x, gp.y, front_type, 1)
			set_state(NavState.OBSTACLE_DETECTED)
			return

	# ── 3. Waypoint tracking ───────────────────────────────────────────────
	if waypoint_index >= current_path.size():
		if dist_to_goal <= 2.5:
			set_state(NavState.GOAL_REACHED)
			goal_reached.emit()
		else:
			set_state(NavState.PLANNING)
		return

	var target_wp: Vector3 = current_path[waypoint_index]
	var to_wp: Vector3 = target_wp - global_position
	to_wp.y = 0.0
	var dist_to_wp: float = to_wp.length()

	while dist_to_wp < 1.25 and waypoint_index < current_path.size() - 1:
		waypoint_index += 1
		target_wp = current_path[waypoint_index]
		to_wp = target_wp - global_position
		to_wp.y = 0.0
		dist_to_wp = to_wp.length()
	if dist_to_wp < 1.25 and waypoint_index == current_path.size() - 1:
		if dist_to_goal <= 2.5:
			set_state(NavState.GOAL_REACHED)
			goal_reached.emit()
		else:
			set_state(NavState.PLANNING)
		return

	# ── 4. Steering ────────────────────────────────────────────────────────
	var desired_yaw: float = atan2(-to_wp.x, -to_wp.z)
	var angle_diff: float = wrapf(desired_yaw - rotation.y, -PI, PI)
	var steering_authority := clampf(absf(current_speed) / maxf(max_speed, 0.1), 0.2, 1.0)
	var yaw_step := turn_speed * steering_authority * delta
	rotation.y += clampf(angle_diff, -yaw_step, yaw_step)

	# ── 5. Speed control ───────────────────────────────────────────────────
	var target_speed: float = max_speed
	if absf(angle_diff) > 0.55:
		target_speed = max_speed * 0.5         # Keep grid-path corners stable.
	if absf(angle_diff) > 1.0:
		target_speed = max_speed * 0.35
	elif perception != null and perception.is_front_blocked and perception.front_obstacle_dist < 8.0 and perception.front_obstacle_dist > 0.3:
		target_speed = max_speed * 0.6         # Caution near obstacles
	# Start braking for a grid-path corner before reaching its waypoint. This
	# preserves the higher straight-line speed without overshooting junctions.
	var next_corner_angle := _upcoming_path_turn_angle()
	if next_corner_angle > 0.35:
		var corner_braking_distance := maxf(dist_to_wp - 2.5, 0.0)
		var corner_speed := sqrt(2.0 * deceleration * corner_braking_distance)
		target_speed = minf(target_speed, maxf(1.0, corner_speed))

	var response_rate := acceleration if target_speed > current_speed else deceleration
	current_speed = move_toward(current_speed, target_speed, response_rate * delta)
	var fwd: Vector3 = -global_transform.basis.z.normalized()
	velocity = fwd * current_speed
	_move_with_gravity(delta)

	# ── 6. Stuck detection ─────────────────────────────────────────────────
	_stuck_timer += delta
	if _stuck_timer >= 1.5:
		var moved: float = (global_position - _last_check_pos).length()
		_last_check_pos = global_position
		_stuck_timer = 0.0
		if moved < 0.15 and current_speed > 0.5:
			set_state(NavState.BACKTRACKING)
			_recovery_timer = 1.6

func _upcoming_path_turn_angle() -> float:
	if waypoint_index < 0 or waypoint_index + 1 >= current_path.size():
		return 0.0
	var incoming := current_path[waypoint_index] - global_position
	var outgoing := current_path[waypoint_index + 1] - current_path[waypoint_index]
	incoming.y = 0.0
	outgoing.y = 0.0
	if incoming.length_squared() < 0.001 or outgoing.length_squared() < 0.001:
		return 0.0
	return acos(clampf(incoming.normalized().dot(outgoing.normalized()), -1.0, 1.0))

func _get_traffic_hazard() -> Dictionary:
	if not is_instance_valid(traffic_manager):
		return {}
	var forward := -global_transform.basis.z.normalized()
	return traffic_manager.predict_player_conflict(global_position, forward, current_speed, 3.5)

func _process_traffic_yield(delta: float) -> void:
	var hazard := _get_traffic_hazard()
	current_speed = move_toward(current_speed, 0.0, deceleration * 1.5 * delta)
	var forward := -global_transform.basis.z.normalized()
	velocity = forward * current_speed
	_move_with_gravity(delta)
	if hazard.is_empty() and current_speed <= 0.15:
		_traffic_clear_timer += delta
		if _traffic_clear_timer >= 0.55:
			_traffic_clear_timer = 0.0
			set_state(NavState.NAVIGATING)
	else:
		_traffic_clear_timer = 0.0

func _handle_motion_collision() -> void:
	if current_speed <= 0.25:
		return
	var hit_obstacle := false
	var hit_static_obstacle := false
	var collision_position := global_position
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		var collider = col.get_collider()
		if collider != null and col.get_normal().y < 0.65:
			var cname: String = collider.name
			if not (cname.contains("Terrain") or cname.contains("Ground")):
				has_collided = true
				hit_obstacle = true
				if not (collider is CharacterBody3D):
					hit_static_obstacle = true
				elif traffic_manager != null and traffic_manager.has_method("report_player_collision"):
					traffic_manager.report_player_collision(collider, col.get_normal())
				collision_position = col.get_position()
	if hit_obstacle:
		current_speed = 0.0
		velocity = Vector3.ZERO
		if cost_map != null and hit_static_obstacle:
			var blocked_cell: Vector2i = cost_map.world_to_grid(collision_position)
			cost_map.set_obstacle(blocked_cell.x, blocked_cell.y, "COLLISION", 1)
		if is_autonomous and current_state in [NavState.NAVIGATING, NavState.AVOIDING, NavState.OBSTACLE_DETECTED]:
			set_state(NavState.REPLANNING)

func _build_traffic_bypass_path(route: Array[Vector3]) -> Array[Vector3]:
	if route.is_empty():
		return route
	var forward := -global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()
	var obstacle_ahead := (_traffic_bypass_position - global_position).dot(forward)
	if obstacle_ahead < 1.0:
		return route
	# In left-hand traffic, pass to the right and merge back after the obstacle.
	var pass_offset := right * 4.2
	var first := global_position + forward * 3.0 + pass_offset
	var parallel := global_position + forward * (obstacle_ahead + 9.0) + pass_offset
	var merge := global_position + forward * (obstacle_ahead + 22.0)
	var result: Array[Vector3] = [first, parallel, merge]
	var reconnect_index := route.size() - 1
	for index in range(route.size()):
		if (route[index] - global_position).dot(forward) >= obstacle_ahead + 28.0:
			reconnect_index = index
			break
	for index in range(reconnect_index, route.size()):
		result.append(route[index])
	return result

func _process_recovery(delta: float) -> void:
	_recovery_timer -= delta
	current_speed = -1.5
	rotation.y += 1.8 * delta
	var fwd: Vector3 = -global_transform.basis.z.normalized()
	velocity = fwd * current_speed
	_move_with_gravity(delta)
	if _recovery_timer <= 0.0:
		current_speed = 0.0
		var gp: Vector2i = cost_map.world_to_grid(global_position)
		cost_map.set_obstacle(gp.x, gp.y, "STUCK RECOVERY", 1)
		set_state(NavState.REPLANNING)

func _process_manual(delta: float) -> void:
	var steer_input: float = 0.0
	var throttle_input: float = 0.0

	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		steer_input += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		steer_input -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		throttle_input += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		throttle_input -= 1.0

	var steering_authority := clampf(absf(current_speed) / maxf(max_speed, 0.1), 0.2, 1.0)
	rotation.y += steer_input * turn_speed * steering_authority * delta

	if throttle_input != 0.0:
		current_speed = move_toward(current_speed, throttle_input * max_speed, acceleration * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, deceleration * delta)

	var fwd: Vector3 = -global_transform.basis.z.normalized()
	velocity = fwd * current_speed
	_move_with_gravity(delta)

func _move_with_gravity(delta: float) -> void:
	if is_on_floor():
		if _vertical_speed < 0.0:
			_vertical_speed = 0.0
	else:
		_vertical_speed -= 18.0 * delta
	velocity.y = _vertical_speed
	move_and_slide()
	if is_on_floor() and _vertical_speed < 0.0:
		_vertical_speed = 0.0

func _animate_wheels(delta: float) -> void:
	var spin: float = (current_speed / 0.35) * delta
	if wheel_fl: wheel_fl.rotate_x(-spin)
	if wheel_fr: wheel_fr.rotate_x(-spin)
	if wheel_rl: wheel_rl.rotate_x(-spin)
	if wheel_rr: wheel_rr.rotate_x(-spin)

# ── Public control interface ───────────────────────────────────────────────────
func start_autonomy() -> void:
	is_autonomous = true
	match current_state:
		NavState.GOAL_REACHED, NavState.STOPPED, NavState.MANUAL:
			set_state(NavState.PLANNING)

func stop_ugv() -> void:
	current_speed = 0.0
	velocity = Vector3.ZERO
	if current_state != NavState.GOAL_REACHED:
		set_state(NavState.STOPPED)

func force_replan() -> void:
	if is_autonomous and current_state != NavState.GOAL_REACHED:
		set_state(NavState.REPLANNING)

func toggle_mode() -> void:
	is_autonomous = not is_autonomous
	if is_autonomous:
		set_state(NavState.PLANNING)
	else:
		current_speed = 0.0
		set_state(NavState.MANUAL)

func reset_ugv() -> void:
	global_position = start_position
	rotation = Vector3(0.0, PI, 0.0)
	current_speed = 0.0
	velocity = Vector3.ZERO
	current_path.clear()
	waypoint_index = 0
	replans_count = 0
	has_collided = false
	is_autonomous = true
	_replan_cooldown = 0.0
	_stuck_timer = 0.0
	_recovery_timer = 0.0
	_vertical_speed = 0.0
	if localization != null:
		localization.reset(start_position, 0.0)
	set_state(NavState.STOPPED)
	path_updated.emit([])
