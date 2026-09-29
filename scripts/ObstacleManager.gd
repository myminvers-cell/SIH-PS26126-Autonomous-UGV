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
var mat_ditch: StandardMaterial3D
var mat_blocked: StandardMaterial3D
var mat_dynamic: StandardMaterial3D
var mat_pothole: StandardMaterial3D
var mat_puddle_glint: StandardMaterial3D
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

	mat_ditch = StandardMaterial3D.new()
	mat_ditch.albedo_color = Color(0.58, 0.26, 0.12)
	mat_ditch.roughness = 0.75
	mat_ditch.emission_enabled = true
	mat_ditch.emission = Color(0.9, 0.5, 0.0)
	mat_ditch.emission_energy_multiplier = 0.35   # Subtle hazard glow

	mat_blocked = StandardMaterial3D.new()
	mat_blocked.albedo_color = Color(0.38, 0.34, 0.30)
	mat_blocked.roughness = 0.88

	mat_dynamic = StandardMaterial3D.new()
	mat_dynamic.albedo_color = Color(0.9, 0.15, 0.1)
	mat_dynamic.roughness = 0.3
	mat_dynamic.metallic = 0.5
	mat_dynamic.emission_enabled = true
	mat_dynamic.emission = Color(1.0, 0.3, 0.1)
	mat_dynamic.emission_energy_multiplier = 1.5

	mat_pothole = StandardMaterial3D.new()
	mat_pothole.albedo_color = Color(0.035, 0.055, 0.07)
	mat_pothole.roughness = 0.12
	mat_pothole.metallic = 0.72
	mat_pothole.clearcoat_enabled = true
	mat_pothole.clearcoat = 0.8

	mat_puddle_glint = StandardMaterial3D.new()
	mat_puddle_glint.albedo_color = Color(0.27, 0.62, 0.78, 0.82)
	mat_puddle_glint.roughness = 0.08
	mat_puddle_glint.metallic = 0.55
	mat_puddle_glint.emission_enabled = true
	mat_puddle_glint.emission = Color(0.06, 0.18, 0.26)
	mat_puddle_glint.emission_energy_multiplier = 0.35

func populate_environment(cost_map: CostMap) -> void:
	_init_materials()
	# Safe clear: defer if children are still freeing
	for child in get_children():
		child.queue_free()
	registered_obstacles.clear()
	dynamic_obstacles.clear()

	# Seeded RNG for reproducible layout
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 26126

	# ── Rocks ──────────────────────────────────────────────────────────────
	var rock_positions: Array[Vector3] = [
		Vector3(-18.0, 0.4, -18.0), Vector3(-15.0, 0.3, -22.0),
		Vector3(-22.0, 0.4, -14.0), Vector3(-12.0, 0.5, -16.0),
		Vector3(-10.0, 0.3, -19.0), Vector3(-8.0,  0.4, -12.0),
		Vector3(-5.0,  0.6, -15.0), Vector3(-16.0, 0.4,  -6.0),
		Vector3(-12.0, 0.5,  -2.0), Vector3(-6.0,  0.3,  -7.0),
		Vector3(-2.0,  0.4, -10.0), Vector3( 0.0,  0.5, -14.0),
		Vector3( 4.0,  0.3, -16.0), Vector3( 8.0,  0.4, -12.0),
		Vector3(12.0,  0.5, -18.0), Vector3(16.0,  0.3, -14.0),
		Vector3(20.0,  0.4, -20.0), Vector3(-18.0, 0.4,   4.0),
		Vector3(-14.0, 0.3,  10.0), Vector3(-8.0,  0.5,   6.0),
		Vector3(-4.0,  0.4,  12.0), Vector3( 2.0,  0.3,   8.0),
		Vector3( 6.0,  0.5,  14.0), Vector3(10.0,  0.4,   4.0),
		Vector3(14.0,  0.3,  10.0), Vector3(18.0,  0.5,  16.0),
		Vector3(22.0,  0.4,  12.0), Vector3(15.0,  0.3,  22.0)
	]
	for pos in rock_positions:
		_create_rock(pos, rng.randf_range(0.8, 1.8), rng, cost_map)

	# ── Trees ──────────────────────────────────────────────────────────────
	var tree_positions: Array[Vector3] = [
		Vector3(-20.0, 0.0,  -8.0), Vector3(-16.0, 0.0, -20.0),
		Vector3(-10.0, 0.0, -24.0), Vector3( -4.0, 0.0, -22.0),
		Vector3(  2.0, 0.0, -22.0), Vector3( 10.0, 0.0,  -8.0),
		Vector3( 14.0, 0.0,  -4.0), Vector3( 18.0, 0.0,  -8.0),
		Vector3(-22.0, 0.0,  16.0), Vector3(-16.0, 0.0,  22.0),
		Vector3(-10.0, 0.0,  18.0), Vector3( -2.0, 0.0,  22.0),
		Vector3(  6.0, 0.0,  22.0), Vector3( 12.0, 0.0,  18.0),
		Vector3( 18.0, 0.0,   6.0)
	]
	for pos in tree_positions:
		_create_tree(pos, rng.randf_range(0.9, 1.4), cost_map)

	# ── Large Boulders ─────────────────────────────────────────────────────
	var boulder_positions: Array[Vector3] = [
		Vector3(-14.0, 1.0, -12.0), Vector3( -6.0, 1.2,  -4.0),
		Vector3(  2.0, 1.3,  -4.0), Vector3(  8.0, 1.1,   0.0),
		Vector3( -8.0, 1.2,  14.0), Vector3(  0.0, 1.4,  16.0),
		Vector3( 12.0, 1.2,   8.0), Vector3( 16.0, 1.0,  18.0)
	]
	for pos in boulder_positions:
		_create_boulder(pos, rng.randf_range(1.8, 2.6), cost_map)

	# ── Ditch Hazard Areas ─────────────────────────────────────────────────
	var ditch_positions: Array[Vector3] = [
		Vector3(-12.0, 0.05,  4.0), Vector3( -2.0, 0.05, -16.0),
		Vector3(  6.0, 0.05, -10.0), Vector3(  4.0, 0.05,   2.0),
		Vector3( -6.0, 0.05,  20.0), Vector3( 14.0, 0.05,  14.0)
	]
	for pos in ditch_positions:
		_create_ditch(pos, rng.randf_range(2.0, 3.2), cost_map)

	# Shallow road damage is rendered as wet, reflective depressions and remains
	# traversable at a high planning cost so the UGV prefers to steer around it.
	var potholes: Array[Dictionary] = [
		{"pos": Vector3(-17.0, 0.06, -11.8), "radius": 0.78},
		{"pos": Vector3(-8.8, 0.06, -5.0), "radius": 1.05},
		{"pos": Vector3(-1.0, 0.06,  1.8), "radius": 0.72},
		{"pos": Vector3( 6.0, 0.06,  8.7), "radius": 0.95},
		{"pos": Vector3(14.0, 0.06, 15.7), "radius": 0.82}
	]
	for hole in potholes:
		_create_pothole(hole["pos"], float(hole["radius"]), cost_map)

	# ── Blocked Ridge Walls (narrow passages, dead-ends) ───────────────────
	var ridge_data: Array[Dictionary] = [
		{"pos": Vector3( -8.0, 0.8, -26.0), "size": Vector3( 8.0, 1.6, 2.5)},
		{"pos": Vector3( 14.0, 0.8, -24.0), "size": Vector3(10.0, 1.6, 2.5)},
		{"pos": Vector3(-24.0, 0.8,   2.0), "size": Vector3( 3.0, 1.6, 8.0)},
		{"pos": Vector3(-14.0, 0.8,  -2.0), "size": Vector3( 6.0, 1.6, 2.0)},  # Narrow passage
		{"pos": Vector3(  2.0, 0.8,  -1.0), "size": Vector3( 5.0, 1.6, 2.0)},  # Narrow passage
		{"pos": Vector3( -2.0, 0.8,   7.0), "size": Vector3( 6.0, 1.6, 2.2)},  # Dead-end
		{"pos": Vector3( 22.0, 0.8,  -2.0), "size": Vector3( 4.0, 1.6, 10.0)}
	]
	for rd in ridge_data:
		_create_blocked_ridge(rd["pos"], rd["size"], cost_map)

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

func _create_ditch(pos: Vector3, radius: float, cost_map: CostMap) -> void:
	var body: Area3D = Area3D.new()
	body.name = "Ditch_%d" % registered_obstacles.size()
	body.position = pos
	body.set_meta("obstacle_type", "DITCH")

	# Ground disc
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.12
	cyl.material = mat_ditch
	mesh_inst.mesh = cyl
	body.add_child(mesh_inst)

	# Hazard warning ring (slightly larger, lighter color)
	var ring: MeshInstance3D = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = radius - 0.15
	ring_mesh.outer_radius = radius + 0.18
	ring_mesh.ring_segments = 14
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.7, 0.0, 1.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.6, 0.0)
	ring_mat.emission_energy_multiplier = 0.5
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mesh.material = ring_mat
	ring.mesh = ring_mesh
	ring.rotation.x = PI * 0.5
	ring.position.y = 0.08
	body.add_child(ring)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.3
	col.shape = shape
	body.add_child(col)

	add_child(body)
	registered_obstacles.append({"type": "DITCH", "pos": pos, "radius": radius})
	var gp: Vector2i = cost_map.world_to_grid(pos)
	cost_map.set_hazard(gp.x, gp.y, "DITCH", int(ceil(radius)))

func _create_pothole(pos: Vector3, radius: float, cost_map: CostMap) -> void:
	var body := Area3D.new()
	body.name = "Pothole_%d" % registered_obstacles.size()
	body.position = pos
	body.set_meta("obstacle_type", "POTHOLE")
	body.collision_layer = 4
	body.collision_mask = 2

	var depression := MeshInstance3D.new()
	var dish := CylinderMesh.new()
	dish.top_radius = radius
	dish.bottom_radius = radius * 0.82
	dish.height = 0.025
	dish.radial_segments = 24
	dish.material = mat_pothole
	depression.mesh = dish
	depression.position.y = -0.06
	body.add_child(depression)

	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = radius * 0.88
	rim_mesh.outer_radius = radius
	rim_mesh.ring_segments = 24
	rim_mesh.rings = 6
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.28, 0.24, 0.18)
	rim_mat.roughness = 0.9
	rim_mesh.material = rim_mat
	rim.mesh = rim_mesh
	rim.rotation.x = PI * 0.5
	rim.position.y = -0.05
	body.add_child(rim)

	# Thin blue sheen makes the puddle catch the bright sky in the low-detail renderer.
	var reflection := MeshInstance3D.new()
	var sheen := BoxMesh.new()
	sheen.size = Vector3(radius * 1.05, 0.012, 0.14)
	sheen.material = mat_puddle_glint
	reflection.mesh = sheen
	reflection.position = Vector3(-radius * 0.12, -0.005, -radius * 0.22)
	reflection.rotation.y = -0.42
	body.add_child(reflection)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.12
	col.shape = shape
	col.position.y = -0.02
	body.add_child(col)
	body.body_entered.connect(_on_pothole_body_entered)

	add_child(body)
	registered_obstacles.append({"type": "POTHOLE", "pos": pos, "radius": radius})
	var gp := cost_map.world_to_grid(pos)
	cost_map.set_hazard(gp.x, gp.y, "POTHOLE", int(ceil(radius)))

func _on_pothole_body_entered(body: Node3D) -> void:
	if body is UGV:
		(body as UGV).apply_pothole_impact()

func _create_blocked_ridge(pos: Vector3, size: Vector3, cost_map: CostMap) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Blocked_%d" % registered_obstacles.size()
	body.position = pos
	body.set_meta("obstacle_type", "BLOCKED AREA")

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	box.material = mat_blocked
	mesh_inst.mesh = box
	body.add_child(mesh_inst)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	add_child(body)
	registered_obstacles.append({"type": "BLOCKED AREA", "pos": pos, "radius": maxf(size.x, size.z) * 0.5})

	var min_w: Vector3 = pos - size * 0.5
	var max_w: Vector3 = pos + size * 0.5
	var min_g: Vector2i = cost_map.world_to_grid(min_w)
	var max_g: Vector2i = cost_map.world_to_grid(max_w)
	for gx in range(mini(min_g.x, max_g.x), maxi(min_g.x, max_g.x) + 1):
		for gz in range(mini(min_g.y, max_g.y), maxi(min_g.y, max_g.y) + 1):
			cost_map.set_obstacle(gx, gz, "BLOCKED AREA", 1)

# ── Dynamic Obstacle Spawner ───────────────────────────────────────────────────

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
	for obs in registered_obstacles:
		var to_obs: Vector3 = (obs["pos"] as Vector3) - ugv_pos
		to_obs.y = 0.0
		var dist: float = to_obs.length()
		if dist > 0.05 and dist <= max_range:
			var dot: float = forward.dot(to_obs.normalized())
			if dot >= cos_half:
				result.append({"type": obs["type"], "distance": dist, "position": obs["pos"]})
	return result
