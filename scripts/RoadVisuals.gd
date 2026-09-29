class_name RoadVisuals
extends Node3D

const ROAD_START := Vector3(-24.0, 0.03, -24.0)
const ROAD_END := Vector3(24.0, 0.03, 24.0)
const ROAD_WIDTH := 8.0
const SAMPLE_COUNT := 120

var _asphalt: ShaderMaterial
var _shoulder: StandardMaterial3D
var _marking: StandardMaterial3D
var _reflector: StandardMaterial3D

func _ready() -> void:
	_create_materials()
	_create_road()
	_create_markings()
	_create_roadside_markers()
	_create_sky_reflection_probe()

func _create_materials() -> void:
	_asphalt = ShaderMaterial.new()
	var asphalt_shader := Shader.new()
	asphalt_shader.code = """
	shader_type spatial;
	render_mode diffuse_burley, specular_schlick_ggx;

	uniform vec3 asphalt_color : source_color = vec3(0.105, 0.125, 0.145);

	float hash21(vec2 p) {
		p = fract(p * vec2(123.34, 456.21));
		p += dot(p, p + 45.32);
		return fract(p.x * p.y);
	}

	float noise21(vec2 p) {
		vec2 i = floor(p);
		vec2 f = fract(p);
		f = f * f * (3.0 - 2.0 * f);
		float a = hash21(i);
		float b = hash21(i + vec2(1.0, 0.0));
		float c = hash21(i + vec2(0.0, 1.0));
		float d = hash21(i + vec2(1.0, 1.0));
		return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
	}

	void fragment() {
		vec2 p = UV * 7.0;
		float aggregate = noise21(p * 0.45);
		float grain = noise21(p * 8.0);
		float fine_grit = hash21(floor(p * 36.0));
		float wet_patch = smoothstep(0.52, 0.82, noise21(p * 0.22 + vec2(8.1, 3.7)));
		float surface = 0.78 + aggregate * 0.20 + grain * 0.11 + fine_grit * 0.045;
		ALBEDO = asphalt_color * surface * mix(1.0, 0.72, wet_patch);
		ROUGHNESS = mix(0.58, 0.22, wet_patch) + grain * 0.08;
		METALLIC = mix(0.08, 0.32, wet_patch);
		SPECULAR = 0.72;
	}
	"""
	_asphalt.shader = asphalt_shader

	_shoulder = StandardMaterial3D.new()
	_shoulder.albedo_color = Color(0.38, 0.34, 0.25)
	_shoulder.roughness = 0.95

	_marking = StandardMaterial3D.new()
	_marking.albedo_color = Color(0.92, 0.78, 0.32)
	_marking.emission_enabled = true
	_marking.emission = Color(0.36, 0.2, 0.04)
	_marking.emission_energy_multiplier = 0.2

	_reflector = StandardMaterial3D.new()
	_reflector.albedo_color = Color(0.15, 0.78, 0.95)
	_reflector.emission_enabled = true
	_reflector.emission = Color(0.04, 0.42, 0.8)
	_reflector.emission_energy_multiplier = 0.8

func _road_point(t: float) -> Vector3:
	var direction := ROAD_END - ROAD_START
	var side := Vector3(direction.z, 0.0, -direction.x).normalized()
	var bend := sin(t * PI * 2.0) * 1.1
	return ROAD_START.lerp(ROAD_END, t) + side * bend

func _road_tangent(t: float) -> Vector3:
	return (_road_point(minf(t + 0.01, 1.0)) - _road_point(maxf(t - 0.01, 0.0))).normalized()

func _create_road() -> void:
	var shoulder_st := SurfaceTool.new()
	shoulder_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var road_st := SurfaceTool.new()
	road_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SAMPLE_COUNT):
		var t0 := float(i) / SAMPLE_COUNT
		var t1 := float(i + 1) / SAMPLE_COUNT
		var p0 := _road_point(t0)
		var p1 := _road_point(t1)
		var side0 := Vector3(_road_tangent(t0).z, 0.0, -_road_tangent(t0).x).normalized()
		var side1 := Vector3(_road_tangent(t1).z, 0.0, -_road_tangent(t1).x).normalized()
		_add_quad(shoulder_st, p0 - side0 * (ROAD_WIDTH * 0.5 + 0.55), p0 - side0 * (ROAD_WIDTH * 0.5), p1 - side1 * (ROAD_WIDTH * 0.5), p1 - side1 * (ROAD_WIDTH * 0.5 + 0.55))
		_add_quad(shoulder_st, p0 + side0 * (ROAD_WIDTH * 0.5), p0 + side0 * (ROAD_WIDTH * 0.5 + 0.55), p1 + side1 * (ROAD_WIDTH * 0.5 + 0.55), p1 + side1 * (ROAD_WIDTH * 0.5))
		_add_quad(road_st, p0 - side0 * ROAD_WIDTH * 0.5, p0 + side0 * ROAD_WIDTH * 0.5, p1 + side1 * ROAD_WIDTH * 0.5, p1 - side1 * ROAD_WIDTH * 0.5)
	shoulder_st.generate_normals()
	road_st.generate_normals()
	var shoulders := MeshInstance3D.new()
	shoulders.name = "RoadShoulders"
	shoulders.mesh = shoulder_st.commit()
	shoulders.mesh.surface_set_material(0, _shoulder)
	add_child(shoulders)
	var road := MeshInstance3D.new()
	road.name = "WetAsphalt"
	road.mesh = road_st.commit()
	road.mesh.surface_set_material(0, _asphalt)
	add_child(road)

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.set_uv(Vector2(a.x, a.z))
	st.add_vertex(a)
	st.set_uv(Vector2(c.x, c.z))
	st.add_vertex(c)
	st.set_uv(Vector2(b.x, b.z))
	st.add_vertex(b)
	st.set_uv(Vector2(a.x, a.z))
	st.add_vertex(a)
	st.set_uv(Vector2(d.x, d.z))
	st.add_vertex(d)
	st.set_uv(Vector2(c.x, c.z))
	st.add_vertex(c)

func _create_markings() -> void:
	for i in range(24):
		var t := 0.035 + float(i) * 0.04
		var point := _road_point(t)
		var tangent := _road_tangent(t)
		var dash := MeshInstance3D.new()
		dash.name = "CenterLine_%02d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.12, 0.035, 0.95)
		mesh.material = _marking
		dash.mesh = mesh
		dash.position = point + Vector3(0.0, 0.018, 0.0)
		dash.rotation.y = atan2(tangent.x, tangent.z)
		add_child(dash)

func _create_roadside_markers() -> void:
	for i in range(13):
		var t := 0.04 + float(i) * 0.075
		var point := _road_point(t)
		var tangent := _road_tangent(t)
		var side := Vector3(tangent.z, 0.0, -tangent.x).normalized()
		for sign in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			post.name = "RoadReflector"
			var post_mesh := CylinderMesh.new()
			post_mesh.top_radius = 0.055
			post_mesh.bottom_radius = 0.08
			post_mesh.height = 0.72
			post_mesh.material = _reflector
			post.mesh = post_mesh
			post.position = point + side * sign * (ROAD_WIDTH * 0.5 + 0.9) + Vector3(0.0, 0.36, 0.0)
			add_child(post)

func _create_sky_reflection_probe() -> void:
	var probe := ReflectionProbe.new()
	probe.name = "RoadSkyReflection"
	probe.size = Vector3(82.0, 28.0, 82.0)
	probe.origin_offset = Vector3(0.0, 4.0, 0.0)
	probe.box_projection = true
	probe.intensity = 0.55
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)
