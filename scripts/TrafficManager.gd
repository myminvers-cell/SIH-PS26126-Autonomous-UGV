class_name TrafficManager
extends Node3D

const HIGHWAY_START_Z := -600.0
const HIGHWAY_END_Z := 600.0
const HIGHWAY_LENGTH := HIGHWAY_END_Z - HIGHWAY_START_Z
const HIGHWAY_LANES := [6.3, 2.1, -2.1, -6.3]
const TOWN_JUNCTIONS := [-400.0, -200.0, 0.0, 200.0, 400.0]
const CROSSROAD_HALF_LENGTH := 114.0

var vehicles: Array[Dictionary] = []
var pedestrians: Array[Dictionary] = []
var obstacle_manager: ObstacleManager
var player_vehicle: CharacterBody3D
var _clock := 0.0
var _materials: Dictionary = {}

func setup(manager: ObstacleManager, player: CharacterBody3D) -> void:
	obstacle_manager = manager
	player_vehicle = player
	refresh_obstacle_registrations()

func _ready() -> void:
	_create_materials()
	var paint_colors := [Color(0.72, 0.08, 0.045), Color(0.1, 0.26, 0.66), Color(0.62, 0.68, 0.7), Color(0.75, 0.7, 0.55), Color(0.12, 0.37, 0.24), Color(0.46, 0.12, 0.08)]
	var types := ["SEDAN", "MOTORCYCLE", "SEDAN", "AUTO RICKSHAW", "CITY BUS", "MOTORCYCLE", "SEDAN", "DELIVERY TRUCK", "SEDAN", "MOTORCYCLE", "CITY BUS", "AUTO RICKSHAW", "SEDAN", "DELIVERY TRUCK", "MOTORCYCLE", "SEDAN", "SEDAN", "MOTORCYCLE", "AUTO RICKSHAW", "DELIVERY TRUCK"]
	for index in range(types.size()):
		var kind: String = types[index]
		var lane: float = float(HIGHWAY_LANES[index % HIGHWAY_LANES.size()])
		var direction := 1.0 if lane > 0.0 else -1.0
		var slot := int(index / HIGHWAY_LANES.size())
		var spawn_t := 0.075 + float(slot) * 0.19
		var speed := 10.0 + float((index * 7) % 10)
		_spawn_vehicle(kind, spawn_t, direction, lane, speed, paint_colors[index % paint_colors.size()])
	for intersection_index in range(TOWN_JUNCTIONS.size()):
		var junction_z: float = float(TOWN_JUNCTIONS[intersection_index])
		_spawn_cross_vehicle("SEDAN", 0.16, 1.0, -2.05, 9.0, paint_colors[intersection_index % paint_colors.size()], junction_z)
		_spawn_cross_vehicle("MOTORCYCLE", 0.72, -1.0, 2.05, 12.0, paint_colors[(intersection_index + 2) % paint_colors.size()], junction_z)
	for index in range(8):
		_spawn_pedestrian(0.08 + float(index) * 0.12, 1.0 if index % 2 == 0 else -1.0, paint_colors[index % paint_colors.size()])

func _create_materials() -> void:
	_materials["rubber"] = _material(Color(0.025, 0.03, 0.035), 0.92)
	_materials["hub"] = _material(Color(0.58, 0.62, 0.65), 0.35, 0.65)
	_materials["glass"] = _material(Color(0.08, 0.2, 0.27, 1.0), 0.16, 0.3)
	_materials["chrome"] = _material(Color(0.55, 0.58, 0.57), 0.22, 0.72)
	_materials["trim"] = _material(Color(0.06, 0.065, 0.07), 0.7)
	_materials["lamp"] = _emissive_material(Color(1.0, 0.78, 0.38), Color(1.0, 0.56, 0.18), 0.8)
	_materials["tail"] = _emissive_material(Color(0.85, 0.035, 0.02), Color(0.9, 0.025, 0.01), 0.55)
	_materials["rickshaw_yellow"] = _material(Color(0.95, 0.64, 0.08), 0.4, 0.18)
	_materials["skin"] = _material(Color(0.67, 0.39, 0.23), 0.82)
	_materials["helmet"] = _material(Color(0.92, 0.53, 0.09), 0.35)
	_materials["road_frame"] = _material(Color(0.75, 0.08, 0.04), 0.44, 0.15)

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _emissive_material(color: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color, 0.25)
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material

func _spawn_vehicle(kind: String, t: float, direction: float, lane: float, speed: float, color: Color, route: String = "highway", street_z: float = 0.0) -> Dictionary:
	var body := CharacterBody3D.new()
	body.name = kind.replace(" ", "_")
	# Traffic occupies layer 3 and checks the player, terrain, other vehicles,
	# and pedestrians. AI predicts conflicts first; physics catches rare impacts.
	body.collision_layer = 4
	body.collision_mask = 7
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.set_meta("obstacle_type", kind)
	add_child(body)
	var paint := _material(color, 0.34, 0.18)
	var specs := _vehicle_specs(kind)
	var visual := Node3D.new()
	visual.name = "Model"
	body.add_child(visual)
	match kind:
		"CITY BUS":
			_build_bus(visual, paint, specs)
		"DELIVERY TRUCK":
			_build_truck(visual, paint, specs)
		"AUTO RICKSHAW":
			_build_rickshaw(visual, specs)
		"MOTORCYCLE":
			_build_motorcycle(visual, paint)
		_:
			_build_sedan(visual, paint, specs)
	_batch_vehicle_meshes(visual)
	_configure_vehicle_render_budget(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(specs["width"] * 0.92, specs["height"] * 0.8, specs["length"] * 0.86)
	collision.shape = shape
	collision.position.y = specs["height"] * 0.42
	body.add_child(collision)
	var left_lane := 2.1 if direction > 0.0 else -2.1
	var agent := {"body": body, "kind": kind, "route": route, "street_z": street_z, "t": t, "direction": direction, "lane": lane, "base_lane": left_lane if route == "highway" else lane, "speed": speed, "current_speed": speed, "width": specs["width"], "length": specs["length"], "replans": 0, "phase": randf() * TAU, "radius": specs["length"] * 0.55, "wrecked": false}
	vehicles.append(agent)
	_place_vehicle(agent)
	return agent

func _spawn_cross_vehicle(kind: String, t: float, direction: float, lane: float, speed: float, color: Color, street_z: float) -> void:
	_spawn_vehicle(kind, t, direction, lane, speed, color, "cross", street_z)

func _vehicle_specs(kind: String) -> Dictionary:
	match kind:
		"CITY BUS": return {"width": 2.35, "height": 2.8, "length": 8.0}
		"DELIVERY TRUCK": return {"width": 2.45, "height": 3.2, "length": 7.1}
		"AUTO RICKSHAW": return {"width": 1.5, "height": 2.15, "length": 2.75}
		"MOTORCYCLE": return {"width": 0.9, "height": 1.55, "length": 2.05}
		_: return {"width": 1.82, "height": 1.65, "length": 4.15}

func _batch_vehicle_meshes(container: Node3D) -> void:
	# Combine each static vehicle part by material. This preserves its silhouette
	# and materials while reducing dozens of box/sphere draw calls to a few.
	var source_meshes: Array[MeshInstance3D] = []
	for child in container.get_children():
		if child is MeshInstance3D and child.mesh != null:
			source_meshes.append(child)
		elif child is Node3D:
			_batch_vehicle_meshes(child)
	if source_meshes.is_empty():
		return
	var batches: Dictionary = {}
	var container_inverse := container.global_transform.affine_inverse()
	for instance in source_meshes:
		for surface in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(surface)
			if material == null:
				continue
			var material_id: int = material.get_instance_id()
			if not batches.has(material_id):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tool.set_material(material)
				batches[material_id] = {"tool": tool}
			var batch: Dictionary = batches[material_id]
			var transform_to_container := container_inverse * instance.global_transform
			(batch["tool"] as SurfaceTool).append_from(instance.mesh, surface, transform_to_container)
		instance.queue_free()
	for batch in batches.values():
		var merged := MeshInstance3D.new()
		merged.mesh = (batch["tool"] as SurfaceTool).commit()
		container.add_child(merged)

func _configure_vehicle_render_budget(root: Node) -> void:
	for node in root.get_children():
		if node is GeometryInstance3D:
			var geometry := node as GeometryInstance3D
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geometry.visibility_range_end = 220.0
			# Keep moving road users out of baked update-once cubemaps so they do
			# not leave stale car-shaped ghosts in reflections.
			geometry.layers = 2
		_configure_vehicle_render_budget(node)

func _spawn_pedestrian(t: float, direction: float, shirt: Color) -> void:
	var person := CharacterBody3D.new()
	person.name = "Pedestrian"
	person.collision_layer = 4
	person.collision_mask = 3
	person.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	person.set_meta("obstacle_type", "PEDESTRIAN")
	add_child(person)
	var shirt_mat := _material(shirt, 0.82)
	var visual := Node3D.new()
	person.add_child(visual)
	_add_capsule(visual, "Body", 0.25, 0.78, Vector3(0.0, 1.0, 0.0), shirt_mat)
	_add_sphere(visual, "Head", 0.19, Vector3(0.0, 1.58, 0.0), _materials["skin"])
	_add_sphere(visual, "Hair", 0.2, Vector3(0.0, 1.69, 0.015), _materials["trim"])
	var legs: Array[MeshInstance3D] = []
	for side in [-1.0, 1.0]:
		var leg := _add_box(visual, "Leg", Vector3(0.16, 0.52, 0.18), Vector3(side * 0.13, 0.38, 0.0), _materials["trim"])
		legs.append(leg)
		_add_capsule(visual, "Arm", 0.075, 0.55, Vector3(side * 0.32, 1.02, 0.0), _materials["skin"])
	_configure_vehicle_render_budget(visual)
	var hitbox := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	hitbox.shape = capsule
	hitbox.position.y = 0.85
	person.add_child(hitbox)
	var agent := {"body": person, "t": t, "direction": direction, "offset": 19.5 * direction, "speed": 1.05, "legs": legs, "phase": randf() * TAU}
	pedestrians.append(agent)
	_place_pedestrian(agent)

func refresh_obstacle_registrations() -> void:
	if not is_instance_valid(obstacle_manager):
		return
	for agent in vehicles:
		obstacle_manager.register_mobile_obstacle(agent["body"], agent["kind"], agent["radius"])
	for agent in pedestrians:
		obstacle_manager.register_mobile_obstacle(agent["body"], "PEDESTRIAN", 0.55)

func _physics_process(delta: float) -> void:
	_clock += delta
	for i in range(vehicles.size()):
		var agent := vehicles[i]
		if bool(agent.get("wrecked", false)):
			continue
		var old_t: float = float(agent["t"])
		var route_length: float = HIGHWAY_LENGTH if agent["route"] == "highway" else CROSSROAD_HALF_LENGTH * 2.0
		var direction: float = float(agent["direction"])
		var next_t: float = old_t + direction * float(agent["current_speed"]) * delta / route_length
		var wrapping := false
		if direction > 0.0 and next_t >= 0.985:
			next_t = 0.015
			wrapping = true
		elif direction < 0.0 and next_t <= 0.015:
			next_t = 0.985
			wrapping = true
		var body: CharacterBody3D = agent["body"]
		var gap: float = _nearest_ahead_gap(agent)
		var safe_gap: float = maxf(7.0, float(agent["length"]) * 0.8 + 4.0)
		var target_speed: float = float(agent["speed"])
		var player_gap := _player_ahead_gap(agent)
		var player_rear_gap := _player_rear_gap(agent)
		if player_gap < 40.0:
			# Begin braking from the actual stopping-distance envelope, rather
			# than waiting until the UGV is almost at the bumper.
			var ugv_speed := player_vehicle.velocity.length() if is_instance_valid(player_vehicle) else 0.0
			var safe_follow_speed := sqrt(ugv_speed * ugv_speed + 2.0 * 7.0 * maxf(player_gap - safe_gap, 0.0))
			target_speed = minf(target_speed, safe_follow_speed)
		if gap < 20.0:
			target_speed = minf(target_speed, maxf(0.0, (gap - safe_gap) * 0.85))
		if agent["route"] == "cross" and _junction_conflict(agent):
			target_speed = 0.0
			agent["replans"] = int(agent["replans"]) + 1
		if agent["route"] == "highway" and gap < 28.0:
			_try_change_lane(agent, next_t, body)
		elif agent["route"] == "highway" and absf(float(agent["lane"]) - float(agent["base_lane"])) > 0.1 and (gap > 48.0 or player_rear_gap < 45.0):
			_try_return_to_left_lane(agent, next_t, body)
		agent["current_speed"] = move_toward(float(agent["current_speed"]), target_speed, (7.0 if target_speed < float(agent["current_speed"]) else 3.0) * delta)
		next_t = old_t + direction * float(agent["current_speed"]) * delta / route_length
		if direction > 0.0 and next_t >= 0.985:
			next_t = 0.015
			wrapping = true
		elif direction < 0.0 and next_t <= 0.015:
			next_t = 0.985
			wrapping = true
		var desired_position: Vector3 = _vehicle_position(agent, next_t)
		var motion: Vector3 = desired_position - body.global_position
		var collision := KinematicCollision3D.new()
		var blocked := body.test_move(body.global_transform, motion, collision) if motion.length_squared() > 0.000025 else false
		if wrapping or not blocked:
			agent["t"] = next_t
			body.global_position = desired_position
		else:
			var collider = collision.get_collider()
			if _is_traffic_vehicle(collider) and float(agent["current_speed"]) > 1.0:
				_wreck_vehicle(agent, collision.get_normal())
				_wreck_vehicle_by_body(collider, -collision.get_normal())
				vehicles[i] = agent
				continue
			var rerouted := _try_change_lane(agent, next_t, body) if agent["route"] == "highway" else _try_crossroad_replan(agent, next_t, body)
			if rerouted:
				var reroute_target := _vehicle_position(agent, next_t)
				if not body.test_move(body.global_transform, reroute_target - body.global_position):
					agent["t"] = next_t
					body.global_position = reroute_target
				else:
					agent["current_speed"] = move_toward(float(agent["current_speed"]), 0.0, 10.0 * delta)
			else:
				agent["current_speed"] = move_toward(float(agent["current_speed"]), 0.0, 10.0 * delta)
				agent["replans"] = int(agent["replans"]) + 1
		agent["phase"] = float(agent["phase"]) + delta * float(agent["current_speed"]) * 1.8
		vehicles[i] = agent
		_place_vehicle(agent)
	for i in range(pedestrians.size()):
		var agent := pedestrians[i]
		var old_t: float = float(agent["t"])
		var next_t := old_t + float(agent["direction"]) * float(agent["speed"]) * delta / HIGHWAY_LENGTH
		if next_t < 0.015:
			next_t = 0.985
		elif next_t > 0.985:
			next_t = 0.015
		var person: CharacterBody3D = agent["body"]
		var desired_position: Vector3 = _pedestrian_position(agent, next_t)
		if person.test_move(person.global_transform, desired_position - person.global_position):
			agent["direction"] = -float(agent["direction"])
		else:
			agent["t"] = next_t
		agent["phase"] = float(agent["phase"]) + delta * 7.0
		pedestrians[i] = agent
		_place_pedestrian(agent)

func _nearest_ahead_gap(agent: Dictionary, lane_override: float = INF) -> float:
	var current_lane: float = float(agent["lane"]) if is_inf(lane_override) else lane_override
	var best_gap := INF
	var route: String = str(agent["route"])
	var direction: float = float(agent["direction"])
	var pos: Vector3 = _vehicle_position_for_lane(agent, float(agent["t"]), current_lane)
	for other in vehicles:
		if other["body"] == agent["body"] or other["route"] != route or absf(float(other["direction"]) - direction) > 0.1:
			continue
		var other_pos: Vector3 = (other["body"] as Node3D).global_position
		var same_lane := absf(other_pos.x - pos.x) < 2.5 if route == "highway" else absf(other_pos.z - pos.z) < 2.5
		if not same_lane:
			continue
		var gap: float
		if route == "highway":
			gap = (other_pos.z - pos.z) * direction
			if gap <= 0.0:
				gap += HIGHWAY_LENGTH
		else:
			gap = (other_pos.x - pos.x) * direction
			if gap <= 0.0:
				gap += CROSSROAD_HALF_LENGTH * 2.0
			gap -= (float(agent["length"]) + float(other["length"])) * 0.5
		if gap > 0.0:
			best_gap = minf(best_gap, gap)
	var player_gap := _player_ahead_gap(agent)
	if player_gap < INF:
		best_gap = minf(best_gap, player_gap)
	return best_gap

func report_player_collision(other_body: Object, impact_normal: Vector3) -> void:
	# The UGV calls this after a real CharacterBody slide collision. Stop and mark
	# the struck traffic vehicle as a permanent physical road hazard.
	_wreck_vehicle_by_body(other_body, -impact_normal)

func _is_traffic_vehicle(candidate: Object) -> bool:
	if not (candidate is Node) or not candidate.has_meta("obstacle_type"):
		return false
	var kind := str(candidate.get_meta("obstacle_type"))
	return kind in ["SEDAN", "CITY BUS", "DELIVERY TRUCK", "AUTO RICKSHAW", "MOTORCYCLE"]

func _wreck_vehicle_by_body(target: Object, impact_normal: Vector3) -> void:
	if not _is_traffic_vehicle(target):
		return
	for index in range(vehicles.size()):
		var agent := vehicles[index]
		if agent["body"] == target and not bool(agent.get("wrecked", false)):
			_wreck_vehicle(agent, impact_normal)
			vehicles[index] = agent
			return

func _wreck_vehicle(agent: Dictionary, impact_normal: Vector3) -> void:
	if bool(agent.get("wrecked", false)):
		return
	var body: CharacterBody3D = agent["body"]
	agent["wrecked"] = true
	agent["current_speed"] = 0.0
	body.velocity = Vector3.ZERO
	# Keep the wreck on the vehicle collision layer so traffic and the UGV must
	# route around it. It no longer participates as a moving physics body.
	body.collision_layer = 4
	body.collision_mask = 0
	var model := body.get_node_or_null("Model") as Node3D
	if model != null:
		var roll_sign := signf(impact_normal.x)
		if is_zero_approx(roll_sign):
			roll_sign = 1.0 if int(agent["replans"]) % 2 == 0 else -1.0
		model.rotation.z = roll_sign * 0.11
		model.rotation.x = -0.045
		model.scale = Vector3(0.97, 0.98, 0.97)
	_emit_crash_smoke(body)

func _emit_crash_smoke(body: CharacterBody3D) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "CrashSmoke"
	particles.amount = 12
	particles.lifetime = 1.5
	particles.one_shot = true
	particles.explosiveness = 0.72
	particles.position = Vector3(0.0, 0.8, 0.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.18
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 24.0
	process.initial_velocity_min = 0.25
	process.initial_velocity_max = 0.75
	process.gravity = Vector3(0.0, 0.18, 0.0)
	process.scale_min = 0.18
	process.scale_max = 0.38
	process.color = Color(0.24, 0.25, 0.23, 0.58)
	particles.process_material = process
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.22
	smoke_mesh.height = 0.44
	smoke_mesh.radial_segments = 8
	smoke_mesh.rings = 4
	var smoke_material := StandardMaterial3D.new()
	smoke_material.albedo_color = Color(0.24, 0.25, 0.23, 0.58)
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mesh.material = smoke_material
	particles.draw_pass_1 = smoke_mesh
	body.add_child(particles)
	particles.emitting = true
	var cleanup := Timer.new()
	cleanup.one_shot = true
	cleanup.wait_time = 2.0
	cleanup.timeout.connect(particles.queue_free)
	body.add_child(cleanup)
	cleanup.start()

func _player_ahead_gap(agent: Dictionary) -> float:
	if agent["route"] != "highway" or not is_instance_valid(player_vehicle):
		return INF
	var vehicle_pos: Vector3 = (agent["body"] as Node3D).global_position
	var player_pos := player_vehicle.global_position
	if absf(player_pos.x - vehicle_pos.x) >= 2.5:
		return INF
	var gap := (player_pos.z - vehicle_pos.z) * float(agent["direction"])
	# Do not wrap the UGV to the far end of the traffic loop. A negative gap
	# means the UGV is behind this vehicle and is not a lead-vehicle hazard.
	if gap <= 0.0 or gap >= 100.0:
		return INF
	return gap - (float(agent["length"]) + 2.0) * 0.5

func _player_rear_gap(agent: Dictionary) -> float:
	if agent["route"] != "highway" or not is_instance_valid(player_vehicle):
		return INF
	var vehicle_pos: Vector3 = (agent["body"] as Node3D).global_position
	var player_pos := player_vehicle.global_position
	if absf(player_pos.x - vehicle_pos.x) >= 2.5:
		return INF
	var gap := (vehicle_pos.z - player_pos.z) * float(agent["direction"])
	if gap <= 0.0 or gap >= 65.0:
		return INF
	var traffic_forward := Vector3.BACK * float(agent["direction"])
	var closing_speed := player_vehicle.velocity.dot(traffic_forward) - float(agent["current_speed"])
	return gap if closing_speed > 0.5 else INF

func predict_player_conflict(player_pos: Vector3, player_forward: Vector3, player_speed: float, horizon: float = 3.5) -> Dictionary:
	var player_velocity := player_forward.normalized() * player_speed
	player_velocity.y = 0.0
	var earliest_time := INF
	var closest_distance := INF
	var hazard: Dictionary = {}
	for agent in vehicles:
		var other_body: Node3D = agent["body"]
		if not is_instance_valid(other_body):
			continue
		var other_forward := Vector3.RIGHT * float(agent["direction"]) if agent["route"] == "cross" else Vector3.BACK * float(agent["direction"])
		var other_velocity := other_forward * float(agent["current_speed"])
		var relative_position := other_body.global_position - player_pos
		relative_position.y = 0.0
		var relative_velocity := other_velocity - player_velocity
		var velocity_sq := relative_velocity.length_squared()
		var time_to_closest := 0.0
		if velocity_sq > 0.01:
			time_to_closest = clampf(-relative_position.dot(relative_velocity) / velocity_sq, 0.0, horizon)
		var separation := (relative_position + relative_velocity * time_to_closest).length()
		# UGV half-width plus the traffic vehicle half-width and a safe buffer.
		# Keep this under the 4.2 m lane spacing so parallel-lane traffic does
		# not cause needless stops.
		var clearance := 1.45 + float(agent["width"]) * 0.5 + 0.45
		if separation <= clearance and (time_to_closest < earliest_time or (is_equal_approx(time_to_closest, earliest_time) and separation < closest_distance)):
			earliest_time = time_to_closest
			closest_distance = separation
			hazard = {
				"kind": str(agent["kind"]),
				"time": time_to_closest,
				"distance": relative_position.length(),
				"separation": separation
			}
	return hazard

func _nearest_rear_gap(agent: Dictionary, candidate_t: float, candidate_lane: float) -> float:
	var candidate_pos := _vehicle_position_for_lane(agent, candidate_t, candidate_lane)
	var direction := float(agent["direction"])
	var best_gap := INF
	for other in vehicles:
		if other["body"] == agent["body"] or other["route"] != "highway" or absf(float(other["direction"]) - direction) > 0.1:
			continue
		var other_pos: Vector3 = (other["body"] as Node3D).global_position
		if absf(other_pos.x - candidate_pos.x) >= 2.5:
			continue
		var signed_gap := (candidate_pos.z - other_pos.z) * direction
		signed_gap = fposmod(signed_gap + HIGHWAY_LENGTH * 0.5, HIGHWAY_LENGTH) - HIGHWAY_LENGTH * 0.5
		if signed_gap > 0.0:
			best_gap = minf(best_gap, signed_gap - (float(agent["length"]) + float(other["length"])) * 0.5)
	# Do not merge into the UGV's lane when it is already closing from behind.
	if is_instance_valid(player_vehicle):
		var player_pos := player_vehicle.global_position
		if absf(player_pos.x - candidate_pos.x) < 2.5:
			var player_gap := (candidate_pos.z - player_pos.z) * direction
			if player_gap > 0.0 and player_gap < 40.0:
				best_gap = minf(best_gap, player_gap - (float(agent["length"]) + 2.0) * 0.5)
	return best_gap

func _try_change_lane(agent: Dictionary, next_t: float, body: CharacterBody3D) -> bool:
	var direction: float = float(agent["direction"])
	var current_lane: float = float(agent["lane"])
	# Keep traffic on its own carriageway and pass only through the right-hand
	# overtaking lane, as expected for Indian left-hand traffic.
	var candidate_lane := 6.3 if direction > 0.0 else -6.3
	var left_lane := 2.1 if direction > 0.0 else -2.1
	if is_equal_approx(current_lane, candidate_lane):
		return false
	if not is_equal_approx(current_lane, left_lane):
		return false
	if _nearest_ahead_gap(agent, candidate_lane) < 16.0 or _nearest_rear_gap(agent, next_t, candidate_lane) < 20.0:
		return false
	var target := _vehicle_position_for_lane(agent, next_t, candidate_lane)
	if body.test_move(body.global_transform, target - body.global_position):
		return false
	agent["lane"] = candidate_lane
	agent["replans"] = int(agent["replans"]) + 1
	return true

func _try_return_to_left_lane(agent: Dictionary, next_t: float, body: CharacterBody3D) -> void:
	var base_lane: float = float(agent["base_lane"])
	if _nearest_ahead_gap(agent, base_lane) < 28.0 or _nearest_rear_gap(agent, next_t, base_lane) < 18.0:
		return
	var target := _vehicle_position_for_lane(agent, next_t, base_lane)
	if not body.test_move(body.global_transform, target - body.global_position):
		agent["lane"] = base_lane

func _try_crossroad_replan(agent: Dictionary, next_t: float, body: CharacterBody3D) -> bool:
	var direction: float = float(agent["direction"])
	var candidate_lane: float = clampf(float(agent["lane"]) - direction * 0.85, -3.3, 3.3)
	if absf(candidate_lane - float(agent["lane"])) < 0.1:
		return false
	if _nearest_ahead_gap(agent, candidate_lane) < 12.0:
		return false
	var target := _vehicle_position_for_lane(agent, next_t, candidate_lane)
	if body.test_move(body.global_transform, target - body.global_position):
		return false
	agent["lane"] = candidate_lane
	agent["replans"] = int(agent["replans"]) + 1
	return true

func _junction_conflict(agent: Dictionary) -> bool:
	var pos: Vector3 = (agent["body"] as Node3D).global_position
	if absf(pos.x) > 42.0:
		return false
	for other in vehicles:
		if other["route"] != "highway":
			continue
		var other_pos: Vector3 = (other["body"] as Node3D).global_position
		if absf(other_pos.x - pos.x) < 42.0 and absf(other_pos.z - pos.z) < 18.0:
			return true
	if is_instance_valid(player_vehicle):
		var player_pos := player_vehicle.global_position
		if absf(player_pos.x - pos.x) < 42.0 and absf(player_pos.z - pos.z) < 18.0:
			return true
	return false

func _vehicle_position(agent: Dictionary, t: float) -> Vector3:
	return _vehicle_position_for_lane(agent, t, float(agent["lane"]))

func _vehicle_position_for_lane(agent: Dictionary, t: float, lane: float) -> Vector3:
	if agent["route"] == "cross":
		var x := lerpf(-CROSSROAD_HALF_LENGTH, CROSSROAD_HALF_LENGTH, t)
		return Vector3(x, 0.03, float(agent["street_z"]) + lane)
	return Vector3(lane, 0.03, lerpf(HIGHWAY_START_Z, HIGHWAY_END_Z, t))

func _place_vehicle(agent: Dictionary) -> void:
	var body: CharacterBody3D = agent["body"]
	var heading := Vector3.RIGHT * float(agent["direction"]) if agent["route"] == "cross" else Vector3.BACK * float(agent["direction"])
	body.global_position = _vehicle_position(agent, float(agent["t"]))
	body.look_at(body.global_position + heading, Vector3.UP)
	if agent["kind"] == "MOTORCYCLE":
		var rider: Node3D = body.get_node("Model/Rider")
		rider.rotation.z = sin(float(agent["phase"])) * 0.035

func _place_pedestrian(agent: Dictionary) -> void:
	var body: CharacterBody3D = agent["body"]
	body.global_position = _pedestrian_position(agent, float(agent["t"]))
	var heading := Vector3.BACK * float(agent["direction"])
	body.look_at(body.global_position + heading, Vector3.UP)
	for index in range(agent["legs"].size()):
		var leg: MeshInstance3D = agent["legs"][index]
		leg.rotation.x = sin(float(agent["phase"]) + float(index) * PI) * 0.34

func _pedestrian_position(agent: Dictionary, t: float) -> Vector3:
	return Vector3(float(agent["offset"]), 0.03, lerpf(HIGHWAY_START_Z, HIGHWAY_END_Z, t))

func _build_sedan(root: Node3D, paint: StandardMaterial3D, specs: Dictionary) -> void:
	var w: float = specs["width"]
	_add_box(root, "LowerBody", Vector3(w, 0.48, 4.0), Vector3(0.0, 0.62, 0.0), paint)
	_add_box(root, "Hood", Vector3(w * 0.94, 0.2, 1.05), Vector3(0.0, 0.88, -1.25), paint)
	_add_box(root, "Cabin", Vector3(w * 0.78, 0.65, 1.9), Vector3(0.0, 1.12, 0.22), paint)
	_add_box(root, "Roof", Vector3(w * 0.72, 0.09, 1.5), Vector3(0.0, 1.48, 0.22), paint)
	_add_box(root, "Windshield", Vector3(w * 0.68, 0.36, 0.035), Vector3(0.0, 1.16, -0.77), _materials["glass"])
	_add_box(root, "RearWindow", Vector3(w * 0.67, 0.32, 0.035), Vector3(0.0, 1.16, 1.16), _materials["glass"])
	_add_box(root, "FrontBumper", Vector3(w * 0.92, 0.14, 0.13), Vector3(0.0, 0.43, -2.02), _materials["chrome"])
	_add_box(root, "RearBumper", Vector3(w * 0.92, 0.14, 0.13), Vector3(0.0, 0.43, 2.02), _materials["chrome"])
	_add_vehicle_wheels(root, w * 0.51, 0.3, 1.28, 0.3, 0.2, 4)
	for side in [-1.0, 1.0]:
		for z in [-0.25, 0.65]:
			_add_box(root, "SideWindow", Vector3(0.035, 0.31, 0.68), Vector3(side * w * 0.4, 1.17, z), _materials["glass"])
		_add_sphere(root, "Headlight", 0.13, Vector3(side * w * 0.36, 0.82, -1.92), _materials["lamp"])
		_add_sphere(root, "TailLamp", 0.105, Vector3(side * w * 0.36, 0.79, 1.96), _materials["tail"])
		_add_box(root, "Mirror", Vector3(0.2, 0.1, 0.16), Vector3(side * w * 0.53, 1.0, -0.58), _materials["trim"])

func _build_bus(root: Node3D, paint: StandardMaterial3D, specs: Dictionary) -> void:
	_add_box(root, "BusShell", Vector3(2.32, 2.2, 7.5), Vector3(0.0, 1.38, 0.0), paint)
	_add_box(root, "Roof", Vector3(2.28, 0.13, 7.42), Vector3(0.0, 2.54, 0.0), _materials["trim"])
	_add_box(root, "FrontGlass", Vector3(1.82, 0.78, 0.04), Vector3(0.0, 2.05, -3.77), _materials["glass"])
	_add_box(root, "DestinationBoard", Vector3(1.55, 0.24, 0.05), Vector3(0.0, 2.58, -3.8), _materials["trim"])
	_add_box(root, "FrontBumper", Vector3(2.2, 0.2, 0.15), Vector3(0.0, 0.34, -3.83), _materials["chrome"])
	_add_vehicle_wheels(root, 1.16, 0.48, 2.55, 0.36, 0.25, 6)
	for side in [-1.0, 1.0]:
		for index in range(6):
			var z := -2.95 + float(index) * 1.15
			_add_box(root, "PassengerWindow", Vector3(0.035, 0.68, 0.88), Vector3(side * 1.17, 1.9, z), _materials["glass"])
		_add_sphere(root, "Headlight", 0.14, Vector3(side * 0.82, 0.67, -3.86), _materials["lamp"])
		_add_sphere(root, "TailLamp", 0.13, Vector3(side * 0.86, 0.75, 3.8), _materials["tail"])
		_add_box(root, "Mirror", Vector3(0.32, 0.12, 0.22), Vector3(side * 1.28, 2.12, -3.25), _materials["trim"])
	var route_sign := Label3D.new()
	route_sign.text = "CITY BUS  •  DELHI"
	route_sign.visibility_range_end = 220.0
	route_sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	route_sign.font_size = 32
	route_sign.pixel_size = 0.006
	route_sign.position = Vector3(0.0, 2.59, -3.84)
	route_sign.modulate = Color(1.0, 0.78, 0.2)
	root.add_child(route_sign)

func _build_truck(root: Node3D, paint: StandardMaterial3D, specs: Dictionary) -> void:
	_add_box(root, "Chassis", Vector3(2.28, 0.42, 6.85), Vector3(0.0, 0.52, 0.0), _materials["trim"])
	_add_box(root, "CargoBox", Vector3(2.38, 2.72, 4.35), Vector3(0.0, 2.05, 0.95), paint)
	_add_box(root, "CargoRoof", Vector3(2.42, 0.14, 4.42), Vector3(0.0, 3.48, 0.95), _materials["chrome"])
	_add_box(root, "Cabin", Vector3(2.25, 1.82, 1.78), Vector3(0.0, 1.46, -2.38), paint)
	_add_box(root, "Windshield", Vector3(1.78, 0.68, 0.05), Vector3(0.0, 1.93, -3.29), _materials["glass"])
	_add_box(root, "FrontBumper", Vector3(2.35, 0.2, 0.16), Vector3(0.0, 0.49, -3.3), _materials["chrome"])
	_add_box(root, "FrontGrille", Vector3(0.92, 0.44, 0.06), Vector3(0.0, 1.05, -3.31), _materials["trim"])
	for side in [-1.0, 1.0]:
		_add_sphere(root, "Headlight", 0.16, Vector3(side * 0.82, 0.93, -3.35), _materials["lamp"])
		_add_box(root, "CargoRib", Vector3(0.035, 2.4, 0.09), Vector3(side * 1.21, 2.05, float(side) * 0.0), _materials["chrome"])
		_add_box(root, "CabinMirror", Vector3(0.34, 0.12, 0.12), Vector3(side * 1.25, 1.92, -2.86), _materials["trim"])
	_add_vehicle_wheels(root, 1.13, 0.48, 2.5, 0.34, 0.25, 6)

func _build_rickshaw(root: Node3D, specs: Dictionary) -> void:
	_add_box(root, "Chassis", Vector3(1.42, 0.45, 2.58), Vector3(0.0, 0.52, 0.0), _materials["rickshaw_yellow"])
	_add_box(root, "Cabin", Vector3(1.3, 0.85, 1.55), Vector3(0.0, 1.11, 0.28), _material(Color(0.07, 0.36, 0.17), 0.5))
	_add_box(root, "Canopy", Vector3(1.52, 0.18, 1.55), Vector3(0.0, 1.72, 0.18), _materials["rickshaw_yellow"])
	_add_box(root, "FrontGlass", Vector3(1.05, 0.52, 0.04), Vector3(0.0, 1.27, -0.55), _materials["glass"])
	for side in [-1.0, 1.0]:
		_add_box(root, "CanopyPillar", Vector3(0.07, 0.8, 0.07), Vector3(side * 0.6, 1.25, -0.54), _materials["trim"])
		_add_sphere(root, "Headlight", 0.12, Vector3(side * 0.46, 0.82, -1.35), _materials["lamp"])
		_add_box(root, "PassengerBench", Vector3(0.08, 0.43, 0.75), Vector3(side * 0.61, 1.18, 0.35), _materials["glass"])
	_add_vehicle_wheels(root, 0.67, 0.29, 0.85, 0.28, 0.18, 3)
	_add_box(root, "FrontFender", Vector3(0.72, 0.1, 0.15), Vector3(0.0, 0.64, -0.93), _materials["trim"])

func _build_motorcycle(root: Node3D, paint: StandardMaterial3D) -> void:
	_add_box(root, "Frame", Vector3(0.22, 0.22, 1.0), Vector3(0.0, 0.48, 0.0), _materials["chrome"])
	_add_box(root, "FuelTank", Vector3(0.48, 0.42, 0.58), Vector3(0.0, 0.88, -0.2), paint)
	_add_box(root, "Seat", Vector3(0.43, 0.14, 0.65), Vector3(0.0, 0.83, 0.39), _materials["trim"])
	_add_box(root, "Fork", Vector3(0.1, 0.64, 0.12), Vector3(0.0, 0.58, -0.78), _materials["chrome"])
	_add_sphere(root, "HeadLamp", 0.17, Vector3(0.0, 0.96, -0.93), _materials["lamp"])
	_add_box(root, "HandleBar", Vector3(0.95, 0.08, 0.1), Vector3(0.0, 1.1, -0.75), _materials["chrome"])
	_add_motorcycle_wheel(root, -0.82)
	_add_motorcycle_wheel(root, 0.82)
	var rider := Node3D.new()
	rider.name = "Rider"
	root.add_child(rider)
	_add_capsule(rider, "RiderBody", 0.24, 0.66, Vector3(0.0, 1.35, 0.12), _material(Color(0.06, 0.11, 0.18), 0.75))
	_add_sphere(rider, "RiderHelmet", 0.22, Vector3(0.0, 1.88, -0.12), _materials["helmet"])
	for side in [-1.0, 1.0]:
		_add_capsule(rider, "RiderArm", 0.07, 0.56, Vector3(side * 0.27, 1.35, -0.28), _materials["skin"])

func _add_vehicle_wheels(root: Node3D, x: float, radius: float, z_offset: float, spacing: float, width: float, count: int) -> void:
	for index in range(count):
		var z: float
		var wheel_x: float
		if count == 6:
			z = -z_offset + float(index % 3) * z_offset
			wheel_x = absf(x) if index >= 3 else -absf(x)
		elif count == 4:
			# Two front tires and two rear tires; avoid duplicate diagonal positions.
			z = -z_offset if index < 2 else z_offset
			wheel_x = -absf(x) if index % 2 == 0 else absf(x)
		elif count == 3:
			# Auto-rickshaw: one centered front wheel and a rear axle pair.
			z = -z_offset if index == 0 else z_offset
			wheel_x = 0.0 if index == 0 else (-absf(x) if index == 1 else absf(x))
		else:
			z = -z_offset if index % 2 == 0 else z_offset
			wheel_x = -absf(x) if index % 2 == 0 else absf(x)
		# Move the tires outside the body panels so both sides remain visible.
		if not is_zero_approx(wheel_x):
			wheel_x += signf(wheel_x) * width * 0.6
		var wheel := MeshInstance3D.new()
		wheel.name = "RoadWheel"
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = width
		mesh.radial_segments = 16
		mesh.material = _materials["rubber"]
		wheel.mesh = mesh
		wheel.position = Vector3(wheel_x, radius + 0.015, z)
		wheel.rotation.z = PI * 0.5
		root.add_child(wheel)
		var hub := MeshInstance3D.new()
		var hub_mesh := CylinderMesh.new()
		hub_mesh.top_radius = radius * 0.48
		hub_mesh.bottom_radius = radius * 0.48
		hub_mesh.height = width + 0.02
		hub_mesh.radial_segments = 12
		hub_mesh.material = _materials["hub"]
		hub.mesh = hub_mesh
		hub.position = wheel.position
		hub.rotation.z = PI * 0.5
		root.add_child(hub)

func _add_motorcycle_wheel(root: Node3D, z: float) -> void:
	var tire := MeshInstance3D.new()
	var tire_mesh := TorusMesh.new()
	tire_mesh.inner_radius = 0.2
	tire_mesh.outer_radius = 0.31
	tire_mesh.ring_segments = 18
	tire_mesh.rings = 8
	tire_mesh.material = _materials["rubber"]
	tire.mesh = tire_mesh
	tire.position = Vector3(0.0, 0.33, z)
	tire.rotation.y = PI * 0.5
	root.add_child(tire)

func _add_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = pos
	parent.add_child(instance)
	return instance

func _add_sphere(parent: Node3D, node_name: String, radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	mesh.material = material
	instance.mesh = mesh
	instance.position = pos
	parent.add_child(instance)
	return instance

func _add_capsule(parent: Node3D, node_name: String, radius: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = material
	instance.mesh = mesh
	instance.position = pos
	parent.add_child(instance)
	return instance
