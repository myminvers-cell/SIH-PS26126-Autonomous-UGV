class_name CameraFollow
extends Camera3D

enum CamMode { CHASE, FRONT, TOP_DOWN }

@export var target: Node3D
@export_range(0.5, 20.0, 0.5) var smooth_speed: float = 7.0
@export var chase_distance: float = 7.0
@export var chase_height: float = 5.0
@export var top_down_height: float = 125.0

var current_mode: CamMode = CamMode.CHASE
var _front_camera: Camera3D

func _ready() -> void:
	if target != null and target.has_node("FrontCamera3D"):
		_front_camera = target.get_node("FrontCamera3D") as Camera3D
	set_mode(CamMode.CHASE)
	reset_to_target()

func set_mode(mode: CamMode) -> void:
	if mode < CamMode.CHASE or mode > CamMode.TOP_DOWN:
		return
	current_mode = mode
	match current_mode:
		CamMode.CHASE:
			fov = 70.0
		CamMode.FRONT:
			fov = 75.0
		CamMode.TOP_DOWN:
			fov = 55.0

func reset_to_target() -> void:
	if target == null:
		return
	var desired := _desired_transform()
	global_transform = desired

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var desired := _desired_transform()
	# Exponential smoothing stays stable across frame rates and camera swaps.
	var weight := 1.0 - exp(-smooth_speed * delta)
	global_transform = global_transform.interpolate_with(desired, weight)

func _desired_transform() -> Transform3D:
	var target_pos := target.global_position
	var forward := -target.global_transform.basis.z.normalized()
	var camera_pos: Vector3
	var focus: Vector3
	var up := Vector3.UP

	match current_mode:
		CamMode.CHASE:
			camera_pos = target_pos - forward * chase_distance + Vector3.UP * chase_height
			focus = target_pos + Vector3.UP * 0.65
			return _look_transform(camera_pos, focus, Vector3.UP)
		CamMode.FRONT:
			if not is_instance_valid(_front_camera) and target.has_node("FrontCamera3D"):
				_front_camera = target.get_node("FrontCamera3D") as Camera3D
			if is_instance_valid(_front_camera):
				return _front_camera.global_transform
			camera_pos = target_pos + forward * 0.8 + Vector3.UP * 0.8
			return _look_transform(camera_pos, target_pos + forward * 12.0, Vector3.UP)
		CamMode.TOP_DOWN:
			camera_pos = target_pos + Vector3.UP * top_down_height
			# A vehicle-aligned up vector avoids the straight-down look_at singularity.
			up = Vector3(forward.x, 0.0, forward.z).normalized()
			return _look_transform(camera_pos, target_pos, up)
	return global_transform

func _look_transform(from: Vector3, to: Vector3, up: Vector3) -> Transform3D:
	var direction := (to - from).normalized()
	var safe_up := up
	if absf(direction.dot(safe_up.normalized())) > 0.98:
		safe_up = Vector3.FORWARD
	var basis := Basis.looking_at(direction, safe_up).orthonormalized()
	return Transform3D(basis, from)
