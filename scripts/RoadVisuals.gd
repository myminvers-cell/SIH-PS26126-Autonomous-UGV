class_name RoadVisuals
extends Node3D

const HIGHWAY_HALF_LENGTH := 600.0
const HIGHWAY_HALF_WIDTH := 13.0
const WORLD_HALF_WIDTH := 128.0
const JUNCTIONS := [-400.0, -200.0, 0.0, 200.0, 400.0]
const LAMP_STEP := 80.0
const ROAD_ALBEDO_PATH := "res://assets/textures/road/road_albedo.jpg"
const ROAD_NORMAL_PATH := "res://assets/textures/road/road_normal.png"
const ROAD_ROUGHNESS_PATH := "res://assets/textures/road/road_roughness.png"
const MAX_ROAD_TEXTURE_SIZE := 1024

var _asphalt: ShaderMaterial
var _road_albedo_texture: Texture2D
var _road_normal_texture: Texture2D
var _road_roughness_texture: Texture2D
var _concrete: StandardMaterial3D
var _lane_paint: StandardMaterial3D
var _edge_paint: StandardMaterial3D
var _lamp_glow: StandardMaterial3D
var _building_palette: Array[StandardMaterial3D] = []
var _shop_glass: StandardMaterial3D
var _shop_roof: StandardMaterial3D
var _shop_shutter: StandardMaterial3D
var _shop_sign_palette: Array[StandardMaterial3D] = []

func _ready() -> void:
	_create_materials()
	_create_road_network()
	_create_markings()
	_create_city_blocks()
	_create_street_lights()
	_create_reflection_probes()

func _create_materials() -> void:
	_road_albedo_texture = _load_road_texture(ROAD_ALBEDO_PATH, false, true)
	if _road_albedo_texture == null:
		_road_albedo_texture = _make_solid_texture(Color(0.15, 0.16, 0.17))
	_road_normal_texture = _load_road_texture(ROAD_NORMAL_PATH, true)
	_road_roughness_texture = _load_road_texture(ROAD_ROUGHNESS_PATH, false)
	var asphalt_shader := Shader.new()
	# Sample in world space instead of relying on imported UV channels. This keeps
	# the texture visible on the procedurally-built road and junction meshes.
	asphalt_shader.code = """
	shader_type spatial;

	uniform sampler2D road_albedo : source_color, repeat_enable, filter_linear_mipmap;
	uniform sampler2D road_normal : hint_normal, repeat_enable, filter_linear_mipmap;
	uniform sampler2D road_roughness : repeat_enable, filter_linear_mipmap;
	uniform bool has_normal_map = false;
	uniform bool has_roughness_map = false;
	varying vec2 road_uv;

	void vertex() {
		vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		road_uv = world_position.xz / 9.0;
	}

	void fragment() {
		vec3 sampled = texture(road_albedo, road_uv).rgb;
		// The source-color sampler is converted to linear light; shape its low
		// asphalt values there so the grain survives both lighting and distance.
		ALBEDO = clamp((sampled - vec3(0.075)) * 1.55 + vec3(0.105), vec3(0.045), vec3(0.22));
		ROUGHNESS = has_roughness_map ? texture(road_roughness, road_uv).r : 0.88;
		SPECULAR = 0.28;
		if (has_normal_map) {
			NORMAL_MAP = texture(road_normal, road_uv).rgb;
			NORMAL_MAP_DEPTH = 0.68;
		}
	}
	"""
	_asphalt = ShaderMaterial.new()
	_asphalt.shader = asphalt_shader
	_asphalt.set_shader_parameter("road_albedo", _road_albedo_texture)
	_asphalt.set_shader_parameter("has_normal_map", _road_normal_texture != null)
	_asphalt.set_shader_parameter("has_roughness_map", _road_roughness_texture != null)
	if _road_normal_texture != null:
		_asphalt.set_shader_parameter("road_normal", _road_normal_texture)
	if _road_roughness_texture != null:
		_asphalt.set_shader_parameter("road_roughness", _road_roughness_texture)
	_shop_glass = _mat(Color(0.16, 0.32, 0.38), 0.23, 0.12)
	_shop_roof = _mat(Color(0.19, 0.2, 0.2), 0.92)
	_shop_shutter = _mat(Color(0.28, 0.31, 0.32), 0.68, 0.12)
	for sign_color in [Color(0.66, 0.13, 0.07), Color(0.08, 0.29, 0.47), Color(0.12, 0.38, 0.23), Color(0.58, 0.34, 0.08)]:
		_shop_sign_palette.append(_mat(sign_color, 0.48))

	_concrete = _mat(Color(0.36, 0.35, 0.31), 0.92)
	_lane_paint = _mat(Color(0.93, 0.91, 0.79), 0.7)
	_edge_paint = _mat(Color(0.96, 0.78, 0.17), 0.62)
	_lamp_glow = _mat(Color(1.0, 0.77, 0.39), 0.28)
	_lamp_glow.emission_enabled = true
	_lamp_glow.emission = Color(1.0, 0.55, 0.2)
	_lamp_glow.emission_energy_multiplier = 2.6
	for color in [Color(0.72, 0.42, 0.25), Color(0.72, 0.68, 0.54), Color(0.58, 0.65, 0.62), Color(0.76, 0.72, 0.61), Color(0.68, 0.5, 0.37)]:
		_building_palette.append(_mat(color, 0.91))

func _load_road_texture(path: String, is_normal_map: bool, required: bool = false) -> Texture2D:
	# Load through ResourceLoader first so imported resources remain available in
	# standalone exports where res:// paths are packed into the PCK. In the editor,
	# imported resources also avoid bypassing Godot's import pipeline.
	var imported: Texture2D
	if ResourceLoader.exists(path):
		imported = ResourceLoader.load(path) as Texture2D
	if imported != null:
		var imported_image := imported.get_image()
		if imported_image != null and not imported_image.is_empty():
			if imported_image.get_width() > MAX_ROAD_TEXTURE_SIZE or imported_image.get_height() > MAX_ROAD_TEXTURE_SIZE:
				return _resize_road_texture(imported_image, path, is_normal_map, required)
		if required:
			print("Road texture loaded from Godot resource: %s (%d x %d)" % [path, imported.get_width(), imported.get_height()])
		return imported

	# Keep a source-file fallback for an unimported first editor launch and for
	# user-provided textures before Godot has generated its import cache.
	var absolute_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		if required:
			push_warning("Required road texture is missing: %s" % path)
		return null
	var image := Image.load_from_file(absolute_path)
	if image == null or image.is_empty():
		push_warning("Road texture could not be read: %s" % path)
		return null
	return _resize_road_texture(image, path, is_normal_map, required)

func _resize_road_texture(image: Image, path: String, is_normal_map: bool, required: bool) -> Texture2D:
	image.convert(Image.FORMAT_RGBA8)
	if image.get_width() > MAX_ROAD_TEXTURE_SIZE or image.get_height() > MAX_ROAD_TEXTURE_SIZE:
		var scale := float(MAX_ROAD_TEXTURE_SIZE) / float(maxi(image.get_width(), image.get_height()))
		var resized_width := maxi(1, roundi(float(image.get_width()) * scale))
		var resized_height := maxi(1, roundi(float(image.get_height()) * scale))
		image.resize(resized_width, resized_height, Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps(is_normal_map)
	if required:
		print("Road texture loaded: %s (%d x %d)" % [path, image.get_width(), image.get_height()])
	return ImageTexture.create_from_image(image)

func _make_solid_texture(color: Color) -> Texture2D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func _mat(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _create_road_network() -> void:
	var road_st := SurfaceTool.new()
	road_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_rect(road_st, -HIGHWAY_HALF_WIDTH, HIGHWAY_HALF_WIDTH, -HIGHWAY_HALF_LENGTH, HIGHWAY_HALF_LENGTH, 0.025)
	for side in [-1.0, 1.0]:
		var center_x: float = side * 40.0
		_add_rect(road_st, center_x - 4.2, center_x + 4.2, -HIGHWAY_HALF_LENGTH, HIGHWAY_HALF_LENGTH, 0.022)
	for junction_z in JUNCTIONS:
		_add_rect(road_st, -118.0, 118.0, junction_z - 4.5, junction_z + 4.5, 0.028)
		# Short ramps join the carriageway to each service road at every junction.
		for side in [-1.0, 1.0]:
			_add_rect(road_st, side * 13.0, side * 40.0, junction_z - 4.5, junction_z + 4.5, 0.03)
	road_st.generate_normals()
	road_st.generate_tangents()
	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "IndianNationalHighwayAndTownRoads"
	road_mesh.mesh = road_st.commit()
	road_mesh.material_override = _asphalt
	road_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("Road world-space shader applied: albedo=%s normal=%s roughness=%s" % [str(_road_albedo_texture != null), str(_road_normal_texture != null), str(_road_roughness_texture != null)])
	add_child(road_mesh)

	var shoulder_st := SurfaceTool.new()
	shoulder_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		_add_rect(shoulder_st, side * 13.0, side * 18.5, -HIGHWAY_HALF_LENGTH, HIGHWAY_HALF_LENGTH, 0.012)
		_add_rect(shoulder_st, side * 34.5, side * 45.0, -HIGHWAY_HALF_LENGTH, HIGHWAY_HALF_LENGTH, 0.012)
	_add_rect(shoulder_st, -WORLD_HALF_WIDTH, WORLD_HALF_WIDTH, -HIGHWAY_HALF_LENGTH - 1.5, -HIGHWAY_HALF_LENGTH + 1.5, 0.01)
	_add_rect(shoulder_st, -WORLD_HALF_WIDTH, WORLD_HALF_WIDTH, HIGHWAY_HALF_LENGTH - 1.5, HIGHWAY_HALF_LENGTH + 1.5, 0.01)
	shoulder_st.generate_normals()
	var shoulder_mesh := MeshInstance3D.new()
	shoulder_mesh.name = "GravelShouldersAndWalkways"
	shoulder_mesh.mesh = shoulder_st.commit()
	shoulder_mesh.material_override = _concrete
	shoulder_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shoulder_mesh)

func _add_rect(st: SurfaceTool, x1: float, x2: float, z1: float, z2: float, y: float) -> void:
	var left := minf(x1, x2)
	var right := maxf(x1, x2)
	var near := minf(z1, z2)
	var far := maxf(z1, z2)
	var a := Vector3(left, y, near)
	var b := Vector3(left, y, far)
	var c := Vector3(right, y, far)
	var d := Vector3(right, y, near)
	const road_texture_scale := 1.0 / 18.0
	st.set_uv(Vector2(left, near) * road_texture_scale); st.add_vertex(a)
	st.set_uv(Vector2(left, far) * road_texture_scale); st.add_vertex(b)
	st.set_uv(Vector2(right, far) * road_texture_scale); st.add_vertex(c)
	st.set_uv(Vector2(left, near) * road_texture_scale); st.add_vertex(a)
	st.set_uv(Vector2(right, far) * road_texture_scale); st.add_vertex(c)
	st.set_uv(Vector2(right, near) * road_texture_scale); st.add_vertex(d)

func _create_markings() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Four northbound lanes, left-hand traffic, with two overtaking lanes to the right.
	for lane_boundary in [-4.2, 0.0, 4.2]:
		for z in range(-590, 591, 24):
			_add_rect(st, lane_boundary - 0.075, lane_boundary + 0.075, float(z), float(z) + 9.0, 0.052)
	for edge_x in [-10.8, 10.8]:
		_add_rect(st, edge_x - 0.09, edge_x + 0.09, -600.0, 600.0, 0.053)
	# Town roads use paired lanes with the broken line centered between opposing flows.
	for junction_z in JUNCTIONS:
		for x in range(-112, 113, 18):
			_add_rect(st, float(x), float(x) + 8.0, junction_z - 0.065, junction_z + 0.065, 0.054)
		_add_rect(st, -118.0, -118.0 + 0.11, junction_z - 4.0, junction_z + 4.0, 0.054)
		_add_rect(st, 118.0 - 0.11, 118.0, junction_z - 4.0, junction_z + 4.0, 0.054)
	# Service road lane separators and junction stop bars.
	for side in [-1.0, 1.0]:
		var x: float = side * 40.0
		for z in range(-590, 591, 28):
			_add_rect(st, x - 0.05, x + 0.05, float(z), float(z) + 10.0, 0.05)
		for junction_z in JUNCTIONS:
			_add_rect(st, x - 4.0, x + 4.0, junction_z - 5.0, junction_z - 4.82, 0.055)
	st.generate_normals()
	var paint := MeshInstance3D.new()
	paint.name = "LaneLinesAndJunctionMarkings"
	paint.mesh = st.commit()
	paint.material_override = _lane_paint
	add_child(paint)

func _create_city_blocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 92871
	for side in [-1.0, 1.0]:
		var z := -570.0
		while z <= 570.0:
			var near_junction := false
			for junction_z in JUNCTIONS:
				if absf(z - junction_z) < 36.0:
					near_junction = true
			if not near_junction:
				_create_shop(side, z, rng)
			z += rng.randf_range(58.0, 82.0)
	for junction_z in JUNCTIONS:
		_create_bus_stop(-1.0, junction_z)
		_create_bus_stop(1.0, junction_z)
	_batch_city_geometry()

func _batch_city_geometry() -> void:
	# Static shop/shelter parts share a small material palette. Merge each
	# material into a single surface to avoid hundreds of separate draw calls.
	var batches: Dictionary = {}
	var root_inverse := global_transform.affine_inverse()
	for root in get_children():
		if not ((root is StaticBody3D and root.name.begins_with("Shopfront_")) or root.name == "BusShelter"):
			continue
		_collect_static_meshes(root, root_inverse, batches)
	for batch in batches.values():
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = (batch["tool"] as SurfaceTool).commit()
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_instance)

func _collect_static_meshes(container: Node, root_inverse: Transform3D, batches: Dictionary) -> void:
	for child in container.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var instance := child as MeshInstance3D
			var transform_to_root := root_inverse * instance.global_transform
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
				(batch["tool"] as SurfaceTool).append_from(instance.mesh, surface, transform_to_root)
			instance.queue_free()
		else:
			_collect_static_meshes(child, root_inverse, batches)

func _create_shop(side: float, z: float, rng: RandomNumberGenerator) -> void:
	var width := rng.randf_range(11.0, 17.0)
	var height := rng.randf_range(7.0, 14.0)
	var depth := rng.randf_range(16.0, 23.0)
	var center_x: float = side * rng.randf_range(59.0, 66.0)
	var root := StaticBody3D.new()
	root.name = "Shopfront_%s_%03d" % ["East" if side > 0.0 else "West", int(z + 600.0)]
	root.position = Vector3(center_x, height * 0.5, z)
	root.collision_layer = 1
	root.collision_mask = 0
	root.set_meta("obstacle_type", "SHOP BUILDING")
	add_child(root)
	var wall_mat := _building_palette[rng.randi_range(0, _building_palette.size() - 1)]
	_add_box(root, "PaintedFacade", Vector3(width, height, depth), Vector3.ZERO, wall_mat)
	_add_box(root, "FlatRoofAndParapet", Vector3(width + 0.45, 0.55, depth + 0.45), Vector3(0.0, height * 0.48, 0.0), _shop_roof)
	var frontage_x: float = -side * (width * 0.5 + 0.055)
	var sign_color := _shop_sign_palette[rng.randi_range(0, _shop_sign_palette.size() - 1)]
	_add_box(root, "ShopSignboard", Vector3(0.16, 0.9, depth * 0.72), Vector3(frontage_x, height * 0.22, 0.0), sign_color)
	var shop_sign := Label3D.new()
	shop_sign.text = ["KIRANA STORE", "TEA & TIFFIN", "MOBILE REPAIR", "SPARE PARTS", "FAMILY DHABA"][rng.randi_range(0, 4)]
	shop_sign.visibility_range_end = 320.0
	shop_sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shop_sign.font_size = 34
	shop_sign.pixel_size = 0.009
	shop_sign.position = Vector3(frontage_x - side * 0.1, height * 0.22, 0.0)
	shop_sign.rotation.y = PI * 0.5 * side
	shop_sign.modulate = Color(1.0, 0.9, 0.68)
	shop_sign.outline_size = 5
	shop_sign.outline_modulate = Color(0.08, 0.07, 0.06)
	root.add_child(shop_sign)
	_add_box(root, "RollingShutter", Vector3(0.08, 2.8, depth * 0.38), Vector3(frontage_x - side * 0.08, 1.65, 0.0), _shop_shutter)
	for floor_y in [4.0, 7.2, 10.4]:
		if floor_y > height - 1.7:
			continue
		for window_z in [-depth * 0.28, depth * 0.28]:
			_add_box(root, "TintedWindow", Vector3(0.09, 1.25, 2.25), Vector3(frontage_x - side * 0.065, floor_y, window_z), _shop_glass)
			_add_box(root, "WindowAwning", Vector3(0.32, 0.12, 2.5), Vector3(frontage_x - side * 0.2, floor_y + 0.72, window_z), sign_color)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height + 0.55, depth)
	collision.shape = shape
	collision.position.y = -0.14
	root.add_child(collision)

func _create_bus_stop(side: float, z: float) -> void:
	var stop := Node3D.new()
	stop.name = "BusShelter"
	stop.position = Vector3(side * 49.0, 0.0, z + 16.0)
	add_child(stop)
	var frame := _mat(Color(0.16, 0.22, 0.25), 0.52, 0.45)
	var glass := _mat(Color(0.26, 0.48, 0.55, 0.54), 0.2, 0.22)
	_add_box(stop, "ShelterRoof", Vector3(7.0, 0.22, 3.4), Vector3(0.0, 2.65, 0.0), frame)
	_add_box(stop, "ShelterBack", Vector3(6.8, 2.15, 0.12), Vector3(0.0, 1.35, 1.58), glass)
	_add_box(stop, "Bench", Vector3(5.0, 0.12, 0.52), Vector3(0.0, 0.62, 1.05), frame)
	var sign := Label3D.new()
	sign.text = "BUS STOP  •  लोकल"
	sign.visibility_range_end = 320.0
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign.font_size = 30
	sign.pixel_size = 0.008
	sign.position = Vector3(0.0, 2.0, -1.65)
	sign.modulate = Color(1.0, 0.83, 0.29)
	stop.add_child(sign)

func _create_street_lights() -> void:
	var pole_mat := _mat(Color(0.19, 0.22, 0.23), 0.43, 0.55)
	for z in range(-560, 561, int(LAMP_STEP)):
		for side in [-1.0, 1.0]:
			_create_lamp(side * 16.0, float(z), side, pole_mat, side < 0.0 and z % 320 == 0)
		for side in [-1.0, 1.0]:
			_create_lamp(side * 46.0, float(z), -side, pole_mat, false)

func _create_lamp(x: float, z: float, arm_direction: float, pole_mat: StandardMaterial3D, add_light: bool) -> void:
	var root := Node3D.new()
	root.name = "LEDStreetLight"
	root.position = Vector3(x, 0.0, z)
	add_child(root)
	_add_cylinder(root, "GalvanizedPole", 0.11, 0.15, 8.5, Vector3(0.0, 4.25, 0.0), pole_mat)
	_add_box(root, "CantileverArm", Vector3(2.2, 0.11, 0.12), Vector3(arm_direction * 1.0, 8.15, 0.0), pole_mat)
	var lamp := _add_box(root, "LEDHead", Vector3(0.62, 0.18, 0.34), Vector3(arm_direction * 1.92, 8.02, 0.0), _lamp_glow)
	if add_light:
		var light := OmniLight3D.new()
		light.position = lamp.position + Vector3(0.0, -0.2, 0.0)
		light.light_color = Color(1.0, 0.75, 0.46)
		light.light_energy = 1.25
		light.omni_range = 22.0
		light.shadow_enabled = false
		root.add_child(light)

func _create_reflection_probes() -> void:
	# Bake one low-cost local cubemap at each town segment. Compatibility
	# supports local probes (up to two affecting a mesh); update-once keeps their
	# cost out of the driving loop while adding visible reflections to glass and
	# vehicle paint.
	for junction_z in JUNCTIONS:
		var probe := ReflectionProbe.new()
		probe.name = "TownReflectionProbe_%s" % str(int(junction_z))
		probe.position = Vector3(0.0, 6.0, junction_z)
		probe.size = Vector3(132.0, 24.0, 190.0)
		probe.origin_offset = Vector3(0.0, 3.0, 0.0)
		probe.box_projection = true
		probe.intensity = 0.7
		probe.cull_mask = 1
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		add_child(probe)

func _add_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 320.0
	parent.add_child(instance)
	return instance

func _add_cylinder(parent: Node3D, node_name: String, top: float, bottom: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = material
	instance.mesh = mesh
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 320.0
	parent.add_child(instance)
	return instance
