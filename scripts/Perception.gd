class_name Perception
extends Node

# Simulated Vision Perception System
# Represents front-facing camera AI module
# Scans forward sector, classifies obstacles, and estimates distances.

@export var max_detection_range: float = 9.0
@export var field_of_view_deg: float = 70.0
@export var ray_count: int = 9

var active: bool = true
var nearest_obstacle_type: String = "NONE"
var nearest_obstacle_dist: float = 999.0
var current_risk: String = "LOW"
var is_front_blocked: bool = false
var detected_obstacles: Array[Dictionary] = []

# Reference to UGV node
var ugv: Node3D = null

func setup(vehicle: Node3D) -> void:
	ugv = vehicle

func scan_environment(world_space: PhysicsDirectSpaceState3D, obstacle_manager: Node) -> void:
	if not active or ugv == null:
		return

	detected_obstacles.clear()
	nearest_obstacle_dist = 999.0
	nearest_obstacle_type = "NONE"
	is_front_blocked = false

	var ugv_pos: Vector3 = ugv.global_position
	# UGV forward vector (in Godot forward is -Z in local space)
	var forward: Vector3 = -ugv.global_transform.basis.z.normalized()
	
	# 1. Multi-raycast sector scan using PhysicsDirectSpaceState3D
	var half_fov: float = field_of_view_deg * 0.5
	var angle_step: float = field_of_view_deg / float(ray_count - 1)
	
	for i in range(ray_count):
		var angle_deg: float = -half_fov + float(i) * angle_step
		var ray_dir: Vector3 = forward.rotated(Vector3.UP, deg_to_rad(angle_deg)).normalized()
		var ray_start: Vector3 = ugv_pos + Vector3(0, 0.4, 0)
		var ray_end: Vector3 = ray_start + ray_dir * max_detection_range

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.exclude = [ugv.get_rid()]
		query.collide_with_areas = true
		query.collide_with_bodies = true
		
		var result: Dictionary = world_space.intersect_ray(query)
		if result.size() > 0:
			var hit_collider = result.get("collider", null)
			var hit_pos: Vector3 = result.get("position", Vector3.ZERO)
			var dist: float = (hit_pos - ray_start).length()
			
			var obj_type: String = "OBSTACLE"
			if hit_collider != null and hit_collider.has_meta("obstacle_type"):
				obj_type = str(hit_collider.get_meta("obstacle_type"))
			elif hit_collider != null and hit_collider.name.contains("Tree"):
				obj_type = "TREE"
			elif hit_collider != null and hit_collider.name.contains("Rock"):
				obj_type = "ROCK"
			elif hit_collider != null and hit_collider.name.contains("Boulder"):
				obj_type = "BOULDER"
			elif hit_collider != null and hit_collider.name.contains("Ditch"):
				obj_type = "DITCH"
			elif hit_collider != null and hit_collider.name.contains("Blocked"):
				obj_type = "BLOCKED AREA"

			detected_obstacles.append({
				"type": obj_type,
				"distance": dist,
				"position": hit_pos,
				"angle": angle_deg
			})

			if dist < nearest_obstacle_dist:
				nearest_obstacle_dist = dist
				nearest_obstacle_type = obj_type

			# If center rays (between -20 and +20 deg) hit obstacle within close distance
			if absf(angle_deg) <= 20.0 and dist <= 3.2:
				is_front_blocked = true

	# 2. Also check dynamic obstacles and terrain hazards registered in obstacle manager
	if obstacle_manager != null and obstacle_manager.has_method("get_obstacles_in_cone"):
		var cone_items: Array = obstacle_manager.get_obstacles_in_cone(ugv_pos, forward, max_detection_range, half_fov)
		for item in cone_items:
			var item_dist: float = float(item["distance"])
			if item_dist < nearest_obstacle_dist:
				nearest_obstacle_dist = item_dist
				nearest_obstacle_type = str(item["type"])
			if item_dist <= 3.2:
				is_front_blocked = true

	# 3. Determine current risk category
	if nearest_obstacle_dist > 6.0:
		current_risk = "LOW"
	elif nearest_obstacle_dist > 3.5:
		current_risk = "MEDIUM"
	elif nearest_obstacle_dist > 2.0:
		current_risk = "HIGH"
	else:
		current_risk = "CRITICAL"

func get_telemetry() -> Dictionary:
	return {
		"status": "ACTIVE" if active else "OFFLINE",
		"nearest_type": nearest_obstacle_type,
		"nearest_dist": nearest_obstacle_dist if nearest_obstacle_dist < 900.0 else 0.0,
		"risk": current_risk,
		"front_blocked": is_front_blocked,
		"count": detected_obstacles.size()
	}
