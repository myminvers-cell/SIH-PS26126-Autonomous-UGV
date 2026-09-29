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
	OBSTACLE_DETECTED,
	REPLANNING,
	AVOIDING,
	BACKTRACKING,
	STUCK_RECOVERY,
	GOAL_REACHED,
	STOPPED,
	MANUAL
}

@export var max_speed: float = 3.8
@export var turn_speed: float = 3.5
@export var acceleration: float = 5.0
@export var deceleration: float = 8.0

var current_state: NavState = NavState.INITIALIZING
var is_autonomous: bool = true

# Navigation subsystems (injected by Main.gd)
var astar_planner: AStarPlanner
var cost_map: CostMap
var localization: Localization
var perception: Perception
var obstacle_manager: ObstacleManager

var current_path: Array[Vector3] = []
var waypoint_index: int = 0
var goal_position: Vector3 = Vector3(24.0, 0.0, 24.0)
var start_position: Vector3 = Vector3(-24.0, 0.0, -24.0)

var current_speed: float = 0.0
var replans_count: int = 0
var has_collided: bool = false

# Stuck detection & recovery
var _stuck_timer: float = 0.0
var _last_check_pos: Vector3 = Vector3.ZERO
var _recovery_timer: float = 0.0
var _replan_cooldown: float = 0.0
var _pothole_cooldown: float = 0.0
var _vertical_speed: float = 0.0

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

	# Vision sensor scan (raycasts into physics world)
	if perception != null and obstacle_manager != null:
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		perception.scan_environment(space_state, obstacle_manager)

	if _replan_cooldown > 0.0:
		_replan_cooldown -= delta
	if _pothole_cooldown > 0.0:
		_pothole_cooldown -= delta

	if is_autonomous:
		_process_autonomous(delta)
	else:
		_process_manual(delta)

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

	# ── 2. Perception-triggered obstacle detection ─────────────────────────
	if perception != null and _replan_cooldown <= 0.0:
		# FIX: Only trigger if obstacle is truly close AND directly ahead
		var obs_dist: float = perception.nearest_obstacle_dist
		if perception.is_front_blocked or (obs_dist < 3.0 and obs_dist > 0.3):
			obstacle_encountered.emit(perception.nearest_obstacle_type, obs_dist)
			# FIX: Project obstacle position FORWARD (+z) from UGV, not backward
			var fwd: Vector3 = -global_transform.basis.z.normalized()
			var blocked_world_pt: Vector3 = global_position + fwd * obs_dist
			var gp: Vector2i = cost_map.world_to_grid(blocked_world_pt)
			cost_map.set_obstacle(gp.x, gp.y, perception.nearest_obstacle_type, 1)
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

	if dist_to_wp < 1.0:
		waypoint_index += 1
		if waypoint_index >= current_path.size():
			if dist_to_goal <= 2.5:
				set_state(NavState.GOAL_REACHED)
				goal_reached.emit()
			else:
				set_state(NavState.PLANNING)
			return
		target_wp = current_path[waypoint_index]
		to_wp = target_wp - global_position
		to_wp.y = 0.0

	# ── 4. Steering ────────────────────────────────────────────────────────
	var desired_yaw: float = atan2(-to_wp.x, -to_wp.z)
	var angle_diff: float = wrapf(desired_yaw - rotation.y, -PI, PI)
	rotation.y += clampf(angle_diff, -turn_speed * delta, turn_speed * delta)

	# ── 5. Speed control ───────────────────────────────────────────────────
	var target_speed: float = max_speed
	if absf(angle_diff) > 0.55:
		target_speed = max_speed * 0.4         # Slow on sharp turns
	elif perception != null and perception.nearest_obstacle_dist < 6.0 and perception.nearest_obstacle_dist > 0.3:
		target_speed = max_speed * 0.6         # Caution near obstacles

	current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	var fwd: Vector3 = -global_transform.basis.z.normalized()
	velocity = fwd * current_speed
	_move_with_gravity(delta)

	# ── 6. Collision flagging ──────────────────────────────────────────────
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		var collider = col.get_collider()
		if collider != null:
			var cname: String = collider.name
			if not (cname.contains("Terrain") or cname.contains("Ground")):
				has_collided = true

	# ── 7. Stuck detection ─────────────────────────────────────────────────
	_stuck_timer += delta
	if _stuck_timer >= 1.5:
		var moved: float = (global_position - _last_check_pos).length()
		_last_check_pos = global_position
		_stuck_timer = 0.0
		if moved < 0.15 and current_speed > 0.5:
			set_state(NavState.BACKTRACKING)
			_recovery_timer = 1.6

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

	rotation.y += steer_input * turn_speed * delta

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

func apply_pothole_impact() -> void:
	if _pothole_cooldown > 0.0:
		return
	_pothole_cooldown = 0.7
	_vertical_speed = maxf(_vertical_speed, 3.3)
	current_speed = move_toward(current_speed, 0.0, 1.2)

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
	rotation = Vector3.ZERO
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
	_pothole_cooldown = 0.0
	if localization != null:
		localization.reset(start_position, 0.0)
	set_state(NavState.STOPPED)
	path_updated.emit([])
