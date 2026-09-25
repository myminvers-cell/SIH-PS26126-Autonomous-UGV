class_name Localization
extends RefCounted

# Simulated Visual Odometry module
# Concept: Integrates frame-to-frame vehicle displacement and yaw rotation,
# simulating feature-based visual odometry without requiring real GPU-based SLAM.

var gps_status: String = "DISABLED"
var localization_mode: String = "Simulated Visual Odometry"

var estimated_pos: Vector3 = Vector3.ZERO
var estimated_heading: float = 0.0 # in degrees [0, 360)
var total_distance_travelled: float = 0.0

var _last_pos: Vector3 = Vector3.ZERO
var _has_first_frame: bool = false

func reset(initial_pos: Vector3, initial_yaw_deg: float) -> void:
	estimated_pos = initial_pos
	estimated_heading = fposmod(initial_yaw_deg, 360.0)
	total_distance_travelled = 0.0
	_last_pos = initial_pos
	_has_first_frame = true

func update_odometry(current_world_pos: Vector3, current_yaw_deg: float) -> void:
	if not _has_first_frame:
		reset(current_world_pos, current_yaw_deg)
		return

	var frame_disp: Vector3 = current_world_pos - _last_pos
	var step_distance: float = frame_disp.length()
	
	# Only accumulate if meaningful movement occurred
	if step_distance > 0.001:
		total_distance_travelled += step_distance
		# In a pure simulation, VO directly tracks the physical movement
		estimated_pos = current_world_pos

	_last_pos = current_world_pos
	estimated_heading = fposmod(current_yaw_deg, 360.0)

func get_status_dict() -> Dictionary:
	return {
		"gps": gps_status,
		"mode": localization_mode,
		"pos_x": estimated_pos.x,
		"pos_z": estimated_pos.z,
		"heading": estimated_heading,
		"distance": total_distance_travelled
	}
