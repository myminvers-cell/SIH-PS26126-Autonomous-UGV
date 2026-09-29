class_name PathVisualizer
extends Node3D

var immediate_mesh: ImmediateMesh
var mesh_instance: MeshInstance3D
var line_material: StandardMaterial3D

var beacon_a: Node3D
var beacon_b: Node3D

var point_a: Vector3 = Vector3(6.3, 0.4, -600.0)
var point_b: Vector3 = Vector3(6.3, 0.4, 600.0)

func _ready() -> void:
	line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(0.15, 0.95, 1.0, 0.95)
	line_material.emission_enabled = true
	line_material.emission = Color(0.1, 0.8, 1.0)
	line_material.emission_energy_multiplier = 1.0
	line_material.render_priority = 1
	line_material.no_depth_test = true  # Path line always visible

	immediate_mesh = ImmediateMesh.new()
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = immediate_mesh
	mesh_instance.material_override = line_material
	add_child(mesh_instance)

	_create_beacons()

func _create_beacons() -> void:
	beacon_a = _create_beacon(point_a, Color(0.2, 1.0, 0.35), "POINT A\nSTART")
	add_child(beacon_a)
	beacon_b = _create_beacon(point_b, Color(1.0, 0.82, 0.1), "POINT B\nGOAL")
	add_child(beacon_b)

func _create_beacon(pos: Vector3, col: Color, label_text: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.position = pos

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.2

	# Base disc
	var base_inst: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.1
	cyl.height = 0.12
	cyl.material = mat
	base_inst.mesh = cyl
	base_inst.position.y = 0.06
	root.add_child(base_inst)

	# Slender pillar
	var pillar_inst: MeshInstance3D = MeshInstance3D.new()
	var pillar: CylinderMesh = CylinderMesh.new()
	pillar.top_radius = 0.08
	pillar.bottom_radius = 0.14
	pillar.height = 2.8
	pillar.material = mat
	pillar_inst.mesh = pillar
	pillar_inst.position.y = 1.4
	root.add_child(pillar_inst)

	# Beacon sphere
	var top_inst: MeshInstance3D = MeshInstance3D.new()
	var sph: SphereMesh = SphereMesh.new()
	sph.radius = 0.38
	sph.height = 0.76
	sph.radial_segments = 12
	sph.rings = 6
	sph.material = mat
	top_inst.mesh = sph
	top_inst.position.y = 2.9
	root.add_child(top_inst)

	# Billboard label
	var lbl: Label3D = Label3D.new()
	lbl.text = label_text
	lbl.font_size = 36
	lbl.position = Vector3(0.0, 3.6, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = col
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	root.add_child(lbl)

	return root

func draw_path(path: Array[Vector3], current_ugv_pos: Vector3) -> void:
	immediate_mesh.clear_surfaces()
	if path.size() < 1:
		return

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	immediate_mesh.surface_add_vertex(current_ugv_pos + Vector3(0.0, 0.35, 0.0))
	for pt in path:
		immediate_mesh.surface_add_vertex(pt + Vector3(0.0, 0.35, 0.0))
	immediate_mesh.surface_end()
