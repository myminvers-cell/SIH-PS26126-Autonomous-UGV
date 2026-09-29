class_name UIManager
extends CanvasLayer

signal start_autonomy_pressed()
signal stop_pressed()
signal force_replan_pressed()
signal spawn_obstacle_pressed()
signal reset_pressed()
signal mode_toggle_pressed()
signal retry_nav_pressed()
signal camera_mode_changed(mode_idx: int)

# Top Bar
@onready var title_label: Label = $TopBar/HBox/TitleLabel
@onready var ps_label: Label = $TopBar/HBox/PSLabel
@onready var fps_label: Label = $TopBar/HBox/FPSLabel

# Status Panel
@onready var gps_label: Label = $LeftPanel/VBox/StatusSection/GPSVal
@onready var camera_label: Label = $LeftPanel/VBox/StatusSection/CamVal
@onready var loc_label: Label = $LeftPanel/VBox/StatusSection/LocVal
@onready var perc_label: Label = $LeftPanel/VBox/StatusSection/PercVal
@onready var planner_label: Label = $LeftPanel/VBox/StatusSection/PlanVal
@onready var nav_mode_label: Label = $LeftPanel/VBox/StatusSection/NavVal

# Live Telemetry
@onready var state_val: Label = $LeftPanel/VBox/TelemetrySection/StateVal
@onready var speed_val: Label = $LeftPanel/VBox/TelemetrySection/SpeedVal
@onready var pos_val: Label = $LeftPanel/VBox/TelemetrySection/PosVal
@onready var heading_val: Label = $LeftPanel/VBox/TelemetrySection/HeadingVal
@onready var goal_dist_val: Label = $LeftPanel/VBox/TelemetrySection/GoalDistVal
@onready var obstacle_val: Label = $LeftPanel/VBox/TelemetrySection/ObstacleVal
@onready var risk_val: Label = $LeftPanel/VBox/TelemetrySection/RiskVal
@onready var path_len_val: Label = $LeftPanel/VBox/TelemetrySection/PathLenVal
@onready var replans_val: Label = $LeftPanel/VBox/TelemetrySection/ReplansVal

# Buttons
@onready var btn_start: Button = $BottomBar/HBox/BtnStart
@onready var btn_stop: Button = $BottomBar/HBox/BtnStop
@onready var btn_replan: Button = $BottomBar/HBox/BtnReplan
@onready var btn_spawn_obstacle: Button = $BottomBar/HBox/BtnSpawnObstacle
@onready var btn_reset: Button = $BottomBar/HBox/BtnReset
@onready var btn_mode: Button = $BottomBar/HBox/BtnMode

# Camera controls
@onready var btn_cam_chase: Button = $RightPanel/VBox/CamBox/BtnChase
@onready var btn_cam_front: Button = $RightPanel/VBox/CamBox/BtnFront
@onready var btn_cam_top: Button = $RightPanel/VBox/CamBox/BtnTop

# Cost map display widget
@onready var cost_map_widget: CostMapDisplay = $RightPanel/VBox/CostMapContainer/CostMapDisplay

# Goal Reached Overlay
@onready var goal_overlay: PanelContainer = $GoalOverlay
@onready var goal_stats_label: Label = $GoalOverlay/VBox/GoalStatsLabel
@onready var goal_btn_restart: Button = $GoalOverlay/VBox/BtnRestart

func _ready() -> void:
	# Connect buttons
	btn_start.pressed.connect(func(): start_autonomy_pressed.emit())
	btn_stop.pressed.connect(func(): stop_pressed.emit())
	btn_replan.pressed.connect(func(): force_replan_pressed.emit())
	btn_spawn_obstacle.pressed.connect(func(): spawn_obstacle_pressed.emit())
	btn_reset.pressed.connect(func(): reset_pressed.emit())
	btn_mode.pressed.connect(func(): mode_toggle_pressed.emit())

	btn_cam_chase.pressed.connect(func(): camera_mode_changed.emit(0))
	btn_cam_front.pressed.connect(func(): camera_mode_changed.emit(1))
	btn_cam_top.pressed.connect(func(): camera_mode_changed.emit(2))

	goal_btn_restart.pressed.connect(func():
		goal_overlay.visible = false
		reset_pressed.emit()
	)

	goal_overlay.visible = false
	set_camera_mode(0)

func set_camera_mode(mode_idx: int) -> void:
	var labels := ["CHASE", "FRONT", "TOP-DOWN"]
	var buttons := [btn_cam_chase, btn_cam_front, btn_cam_top]
	if mode_idx < 0 or mode_idx >= labels.size():
		return
	camera_label.text = labels[mode_idx]
	for i in range(buttons.size()):
		buttons[i].modulate = Color(0.3, 0.95, 1.0) if i == mode_idx else Color.WHITE

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_1:
			camera_mode_changed.emit(0)
		elif event.keycode == KEY_2:
			camera_mode_changed.emit(1)
		elif event.keycode == KEY_3:
			camera_mode_changed.emit(2)
		elif event.keycode == KEY_SPACE:
			start_autonomy_pressed.emit()
		elif event.keycode == KEY_R:
			reset_pressed.emit()

func update_telemetry(
	state: String,
	speed: float,
	pos: Vector3,
	heading: float,
	dist_to_goal: float,
	nearest_obs_type: String,
	nearest_obs_dist: float,
	risk: String,
	path_count: int,
	replans: int,
	is_auto: bool
) -> void:
	var fps := Engine.get_frames_per_second()
	fps_label.text = "FPS: %d" % fps
	fps_label.modulate = Color(0.2, 1.0, 0.4) if fps >= 55 else (Color(1.0, 0.8, 0.2) if fps >= 40 else Color(1.0, 0.35, 0.25))
	state_val.text = state
	_style_state_label(state)

	speed_val.text = "%.2f m/s" % speed
	pos_val.text = "X: %.1f | Z: %.1f" % [pos.x, pos.z]
	heading_val.text = "%.1f°" % heading
	goal_dist_val.text = "%.1f m" % dist_to_goal

	if nearest_obs_dist > 0.01:
		obstacle_val.text = "%s (%.1fm)" % [nearest_obs_type, nearest_obs_dist]
	else:
		obstacle_val.text = "CLEAR"

	risk_val.text = risk
	_style_risk_label(risk)

	path_len_val.text = "%d waypoints" % path_count
	replans_val.text = "%d" % replans

	nav_mode_label.text = "AUTONOMOUS" if is_auto else "MANUAL"
	btn_mode.text = "MODE: AUTO" if is_auto else "MODE: MANUAL"

func _style_state_label(state: String) -> void:
	match state:
		"GOAL REACHED":
			state_val.modulate = Color(0.2, 1.0, 0.4)
		"OBSTACLE DETECTED", "REPLANNING":
			state_val.modulate = Color(1.0, 0.3, 0.2)
		"AVOIDING", "BACKTRACKING", "STUCK RECOVERY":
			state_val.modulate = Color(1.0, 0.7, 0.1)
		"NAVIGATING":
			state_val.modulate = Color(0.2, 0.9, 1.0)
		_:
			state_val.modulate = Color(0.9, 0.9, 0.9)

func _style_risk_label(risk: String) -> void:
	match risk:
		"LOW":
			risk_val.modulate = Color(0.2, 0.9, 0.4)
		"MEDIUM":
			risk_val.modulate = Color(1.0, 0.85, 0.2)
		"HIGH":
			risk_val.modulate = Color(1.0, 0.5, 0.1)
		"CRITICAL":
			risk_val.modulate = Color(1.0, 0.2, 0.2)
		_:
			risk_val.modulate = Color(0.8, 0.8, 0.8)

func show_goal_reached(distance_travelled: float, replans: int, safe: bool) -> void:
	goal_overlay.visible = true
	var status_str: String = "SAFE" if safe else "WARNING - TOUCH DETECTED"
	goal_stats_label.text = "Navigation Complete!\n\nCollision Status: %s\nTotal Distance: %.2f m\nReplans Executed: %d" % [status_str, distance_travelled, replans]

func hide_goal_reached() -> void:
	goal_overlay.visible = false
