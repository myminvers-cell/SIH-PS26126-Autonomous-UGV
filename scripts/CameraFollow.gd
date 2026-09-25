class_name CameraFollow
extends Camera3D

enum CamMode { CHASE, FRONT, TOP_DOWN }

@export var target: Node3D
@export var smooth_speed: float = 6.0

var current_mode: CamMode = CamMode.CHASE

func _ready() -> void:
	set_mode(CamMode.CHASE)

func set_mode(mode: CamMode) -> void:
	current_mode = mode
	match current_mode:
		CamMode.CHASE:
			fov = 70.0
		CamMode.FRONT:
			fov = 75.0
		CamMode.TOP_DOWN:
			fov = 55.0

func _process(delta: float) -> void:
	if target == null:
		return

	match current_mode:
		CamMode.CHASE:
			var t_pos: Vector3 = target.global_position
			var fwd: Vector3 = -target.global_transform.basis.z.normalized()
			var desired: Vector3 = t_pos - fwd * 6.5 + Vector3(0.0, 4.8, 0.0)
			global_position = global_position.lerp(desired, smooth_speed * delta)
			look_at(t_pos + Vector3(0.0, 0.6, 0.0), Vector3.UP)

		CamMode.FRONT:
			if target.has_node("FrontCamera3D"):
				var fc: Camera3D = target.get_node("FrontCamera3D") as Camera3D
				global_transform = global_transform.interpolate_with(fc.global_transform, smooth_speed * delta)
			else:
				var t_pos: Vector3 = target.global_position
				var fwd: Vector3 = -target.global_transform.basis.z.normalized()
				global_position = t_pos + fwd * 0.8 + Vector3(0.0, 0.8, 0.0)
				look_at(t_pos + fwd * 12.0, Vector3.UP)

		CamMode.TOP_DOWN:
			# FIX: Use Vector3(0, 0, -1) as up direction for top-down (avoids gimbal lock)
			var target_cam_pos: Vector3 = Vector3(0.0, 52.0, 0.0)
			global_position = global_position.lerp(target_cam_pos, smooth_speed * delta)
			look_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0))
