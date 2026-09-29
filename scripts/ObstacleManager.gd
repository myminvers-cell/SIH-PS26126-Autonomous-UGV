class_name ObstacleManager
extends Node3D

signal obstacle_added(pos: Vector3, type_name: String)

@export var terrain_size: float = 80.0

var registered_obstacles: Array[Dictionary] = []
var dynamic_obstacles: Array[Node3D] = []

# Cached materials (created in _ready after Node3D is in tree)
var mat_rock: StandardMaterial3D
var mat_tree_trunk: StandardMaterial3D
var mat_tree_leaves: StandardMaterial3D
var mat_boulder: StandardMaterial3D
var mat_dynamic: StandardMaterial3D
var _materials_ready: bool = false

func _ready() -> void:
	_init_materials()

func _init_materials() -> void:
	if _materials_ready:
		return
	_materials_ready = true

	mat_rock = StandardMaterial3D.new()
	mat_rock.albedo_color = Color(0.52, 0.49, 0.43)
	mat_rock.roughness = 0.88
	mat_rock.metallic = 0.08

	mat_tree_trunk = StandardMaterial3D.new()
	mat_tree_trunk.albedo_color = Color(0.28, 0.18, 0.10)
	mat_tree_trunk.roughness = 0.95

	mat_tree_leaves = StandardMaterial3D.new()
	mat_tree_leaves.albedo_color = Color(0.15, 0.45, 0.18)
	mat_tree_leaves.roughness = 0.9
	mat_tree_leaves.metallic = 0.0

	mat_boulder = StandardMaterial3D.new()
	mat_boulder.albedo_color = Color(0.30, 0.29, 0.32)
	mat_boulder.roughness = 0.85
	mat_boulder.metallic = 0.12

	mat_dynamic = StandardMaterial3D.new()
	mat_dynamic.albedo_color = Color(0.9, 0.15, 0.1)
	mat_dynamic.roughness = 0.3
	mat_dynamic.metallic = 0.5
	mat_dynamic.emission_enabled = true
	mat_dynamic.emission = Color(1.0, 0.3, 0.1)
	mat_dynamic.emission_energy_multiplier = 1.5


func populate_environment(cost_map: CostMap) -> void:
	_init_materials()
	for child in get_children():
		child.queue_free()
	registered_obstacles.clear()
	dynamic_obstacles.clear()
	# Keep the driving area clear of generated static props. Moving road users are
	# registered by TrafficManager and the perimeter walls remain in Main.tscn.
# ── Object Factories ───────────────────────────────────────────────────────────

func _create_rock(pos: Vector3, scale_f: float, rng: RandomNumberGenerator, cost_map: CostMap) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Rock_%d" % registered_obstacles.size()
	body.position = pos
	body.set_meta("obstacle_type", "ROCK")

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.2 * scale_f, 0.8 * scale_f, 1.1 * scale_f)
	box.material = mat_rock
	mesh_inst.mesh = box
	mesh_inst.rotation.y = rng.randf_range(0.0, PI)
	body.add_child(mesh_inst)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)

	add_child(body)
	registered_obstacles.append({"type": "ROCK", "pos": pos, "radius": 0.8 * scale_f})
	var gp: Vector2i = cost_map.world_to_grid(pos)
	cost_map.set_obstacle(gp.x, gp.y, "ROCK", int(ceil(0.8 * scale_f)))

func _create_tree(pos: Vector3, scale_f: float, cost_map: CostMap) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Tree_%d" % registered_obstacles.size()
	body.position = pos
	body.set_meta("obstacle_type", "TREE")

	# Trunk
	var trunk: MeshInstance3D = MeshInstance3D.new()
	var trunk_mesh: CylinderMesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.22 * scale_f
	trunk_mesh.bottom_radius = 0.32 * scale_f
	trunk_mesh.height = 2.2 * scale_f
	trunk_mesh.material = mat_tree_trunk
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.1 * scale_f
	body.add_child(trunk)

	# Lower foliage
	var leaves_low: MeshInstance3D = MeshInstance3D.new()
	var leaves_low_mesh: CylinderMesh = CylinderMesh.new()
	leaves_low_mesh.top_radius = 0.05
	leaves_low_mesh.bottom_radius = 1.4 * scale_f
	leaves_low_mesh.height = 2.0 * scale_f
	leaves_low_mesh.material = mat_tree_leaves
	leaves_low.mesh = leaves_low_mesh
	leaves_low.position.y = 2.6 * scale_f
	body.add_child(leaves_low)

	# Upper foliage (narrower cone)
	var leaves_top: MeshInstance3D = MeshInstance3D.new()
	var leaves_top_mesh: CylinderMesh = CylinderMesh.new()
	leaves_top_mesh.top_radius = 0.02
	leaves_top_mesh.bottom_radius = 0.9 * scale_f
	leaves_top_mesh.height = 1.5 * scale_f
	leaves_top_mesh.material = mat_tree_leaves
	leaves_top.mesh = leaves_top_mesh
	leaves_top.position.y = 3.9 * scale_f
	body.add_child(leaves_top)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = 0.45 * scale_f
	shape.height = 2.2 * scale_f
	col.shape = shape
	col.position.y = 1.1 * scale_f
	body.add_child(col)

	add_child(body)
	registered_obstacles.append({"type": "TREE", "pos": pos, "radius": 0.9 * scale_f})
	var gp: Vector2i = cost_map.world_to_grid(pos)
	cost_map.set_obstacle(gp.x, gp.y, "TREE", int(ceil(0.9 * scale_f)))

func _create_boulder(pos: Vector3, scale_f: float, cost_map: CostMap) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Boulder_%d" % registered_obstacles.size()
	body.position = pos
	body.set_meta("obstacle_type", "BOULDER")

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.85 * scale_f
	sphere.height  = 1.5 * scale_f
	sphere.radial_segments = 10
	sphere.rings = 6
	sphere.material = mat_boulder
	mesh_inst.mesh = sphere
	body.add_child(mesh_inst)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.85 * scale_f
	col.shape = shape
	body.add_child(col)

	add_child(body)
	registered_obstacles.append({"type": "BOULDER", "pos": pos, "radius": 0.9 * scale_f})
	var gp: Vector2i = cost_map.world_to_grid(pos)
	cost_map.set_obstacle(gp.x, gp.y, "BOULDER", int(ceil(0.9 * scale_f)))

func register_mobile_obstacle(body: Node3D, type_name: String, radius: float) -> void:
	if not is_instance_valid(body):
		return
	if not dynamic_obstacles.has(body):
		dynamic_obstacles.append(body)
	registered_obstacles.append({
		"type": type_name,
		"pos": body.global_position,
		"radius": radius,
		"node": body,
		"mobile": true
	})

func spawn_dynamic_obstacle(pos: Vector3, cost_map: CostMap) -> Node3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "DynamicObstacle_%d" % (dynamic_obstacles.size() + 1)
	body.position = pos
	body.set_meta("obstacle_type", "DYNAMIC OBSTACLE")

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.15
	sphere.height  = 2.1
	sphere.radial_segments = 12
	sphere.rings = 7
	sphere.material = mat_dynamic
	mesh_inst.mesh = sphere
	body.add_child(mesh_inst)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 1.15
	col.shape = shape
	body.add_child(col)

	add_child(body)
	dynamic_obstacles.append(body)
	registered_obstacles.append({"type": "DYNAMIC OBSTACLE", "pos": pos, "radius": 1.3})

	var gp: Vector2i = cost_map.world_to_grid(pos)
	cost_map.set_obstacle(gp.x, gp.y, "DYNAMIC OBSTACLE", 2)
	obstacle_added.emit(pos, "DYNAMIC OBSTACLE")
	return body

# ── Cone Query for Perception ──────────────────────────────────────────────────

func get_obstacles_in_cone(ugv_pos: Vector3, forward: Vector3, max_range: float, half_fov_deg: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cos_half: float = cos(deg_to_rad(half_fov_deg))
	for index in range(registered_obstacles.size()):
		var obs: Dictionary = registered_obstacles[index]
		var obstacle_pos: Vector3 = obs["pos"] as Vector3
		var obstacle_node: Node3D = obs.get("node") as Node3D
		if is_instance_valid(obstacle_node):
			obstacle_pos = obstacle_node.global_position
			obs["pos"] = obstacle_pos
			registered_obstacles[index] = obs
		var to_obs: Vector3 = obstacle_pos - ugv_pos
		to_obs.y = 0.0
		var dist: float = to_obs.length()
		if dist > 0.05 and dist <= max_range:
			var dot: float = forward.dot(to_obs.normalized())
			if dot >= cos_half:
				result.append({"type": obs["type"], "distance": dist, "position": obstacle_pos})
	return result
