extends Node3D
## O mundo: céu da noite eterna, terreno, ruínas, braseiros, árvores mortas,
## rochas e o castelo do Rei dos Demônios ao norte. Tudo gerado em código.

const SIZE := 360.0          # largura do mapa (metros)
const RES := 180             # quadrados por lado (2 m cada)
const STEP := SIZE / RES

var follow_target: Node3D    # jogador (as cinzas seguem ele)

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _noise_tex: NoiseTexture2D
var _stone_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
var _fires: Array = []       # [{light, base, phase}]
var _ash: GPUParticles3D
var _time := 0.0


func _ready() -> void:
	_rng.seed = 1337
	_noise.seed = 7
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0055
	_noise.fractal_octaves = 5
	_detail.seed = 21
	_detail.frequency = 0.06

	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 512
	_noise_tex.height = 512
	_noise_tex.seamless = true
	_noise_tex.generate_mipmaps = true
	var tn := FastNoiseLite.new()
	tn.frequency = 0.02
	tn.fractal_octaves = 4
	_noise_tex.noise = tn

	_stone_mat = StandardMaterial3D.new()
	_stone_mat.albedo_color = Color(0.32, 0.30, 0.31)
	_stone_mat.albedo_texture = _noise_tex
	_stone_mat.uv1_triplanar = true
	_stone_mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_stone_mat.roughness = 0.95

	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.13, 0.10, 0.09)
	_wood_mat.albedo_texture = _noise_tex
	_wood_mat.uv1_triplanar = true
	_wood_mat.uv1_scale = Vector3(2.0, 0.3, 2.0)
	_wood_mat.roughness = 1.0

	_build_environment()
	_build_terrain()
	_build_ruins()
	_scatter_rocks()
	_scatter_trees()
	_build_castle()
	_build_ash()


func _process(delta: float) -> void:
	_time += delta
	for f in _fires:
		var l: OmniLight3D = f.light
		var p: float = f.phase
		var flick := sin(_time * 9.0 + p) * 0.12 + sin(_time * 23.0 + p * 2.0) * 0.08 + sin(_time * 3.1 + p) * 0.1
		l.light_energy = f.base * (1.0 + flick)
	if _ash and follow_target:
		_ash.global_position = follow_target.global_position + Vector3(0, 14, 0)


# --- Altura do terreno ------------------------------------------------------

func height_at(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * 24.0
	h += _detail.get_noise_2d(x, z) * 0.9
	# área plana ao redor das ruínas iniciais
	var d := Vector2(x, z).length()
	var t := smoothstep(16.0, 60.0, d)
	h = lerpf(_detail.get_noise_2d(x, z) * 0.35, h, t)
	# montanhas nas bordas do mapa
	var edge := clampf((maxf(absf(x), absf(z)) - SIZE * 0.34) / (SIZE * 0.16), 0.0, 1.0)
	h += edge * edge * 45.0
	return h


func spawn_point() -> Vector3:
	return Vector3(0, height_at(0, 8) + 1.0, 8)


# --- Céu, névoa e luz ---------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.012, 0.012, 0.03)
	sky_mat.sky_horizon_color = Color(0.22, 0.05, 0.045)
	sky_mat.sky_curve = 0.09
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_bottom_color = Color(0.005, 0.005, 0.008)
	sky_mat.ground_horizon_color = Color(0.16, 0.04, 0.035)
	sky_mat.ground_curve = 0.05
	sky_mat.sun_angle_max = 2.0
	sky_mat.sun_curve = 0.05
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.8
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.25
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.05, 0.075)
	env.fog_light_energy = 1.0
	env.fog_density = 0.011
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.92

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Lua fria e baixa
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.63, 0.9)
	moon.light_energy = 0.75
	moon.rotation_degrees = Vector3(-28, 145, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 70.0
	moon.shadow_blur = 1.5
	add_child(moon)

	# Brilho vermelho vindo do castelo, ao norte (sem sombra)
	var hell := DirectionalLight3D.new()
	hell.light_color = Color(0.9, 0.18, 0.1)
	hell.light_energy = 0.09
	hell.rotation_degrees = Vector3(-8, 0, 0)
	hell.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(hell)


# --- Terreno ----------------------------------------------------------------

func _build_terrain() -> void:
	var n := RES + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			heights[j * n + i] = height_at(-SIZE * 0.5 + i * STEP, -SIZE * 0.5 + j * STEP)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	norms.resize(n * n)
	uvs.resize(n * n)
	for j in n:
		for i in n:
			var k := j * n + i
			var x := -SIZE * 0.5 + i * STEP
			var z := -SIZE * 0.5 + j * STEP
			verts[k] = Vector3(x, heights[k], z)
			var hl := heights[j * n + maxi(i - 1, 0)]
			var hr := heights[j * n + mini(i + 1, n - 1)]
			var hd := heights[maxi(j - 1, 0) * n + i]
			var hu := heights[mini(j + 1, n - 1) * n + i]
			norms[k] = Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			uvs[k] = Vector2(float(i) / RES, float(j) / RES)

	var idx := PackedInt32Array()
	idx.resize(RES * RES * 6)
	var w := 0
	for j in RES:
		for i in RES:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx[w] = a; idx[w + 1] = b; idx[w + 2] = c
			idx[w + 3] = b; idx[w + 4] = d; idx[w + 5] = c
			w += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("noise_tex", _noise_tex)
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Terrain"
	add_child(mi)

	# Colisão: heightmap com escala uniforme (STEP) para casar com a malha
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var scaled := PackedFloat32Array()
	scaled.resize(n * n)
	for k in n * n:
		scaled[k] = heights[k] / STEP
	shape.map_data = scaled
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(STEP, STEP, STEP)
	body.add_child(cs)
	add_child(body)


# --- Ruínas e braseiros -------------------------------------------------------

func _build_ruins() -> void:
	# Círculo de pilares quebrados ao redor do ponto inicial
	var count := 10
	for i in count:
		var a := TAU * i / count + 0.15
		var r := 13.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if i == 2 or i == 7:
			continue  # pilares que caíram
		var h := _rng.randf_range(2.0, 6.5)
		_pillar(p, h, _rng.randf_range(-0.08, 0.08))
	# pilares caídos
	_fallen_pillar(Vector3(cos(TAU * 2 / count) * 15.5, 0, sin(TAU * 2 / count) * 15.5), 1.1)
	_fallen_pillar(Vector3(cos(TAU * 7 / count) * 16.0, 0, sin(TAU * 7 / count) * 16.0), -0.6)

	# Arco ao norte, apontando para o castelo
	var ax := 0.0
	var az := -14.0
	var gy := height_at(ax, az)
	_pillar(Vector3(ax - 2.6, 0, az), 7.0, 0.0)
	_pillar(Vector3(ax + 2.6, 0, az), 7.0, 0.0)
	_box(Vector3(ax, gy + 7.4, az), Vector3(7.2, 0.9, 1.3), 0.0)

	# Altar no centro
	_box(Vector3(0, height_at(0, 0) + 0.3, 0), Vector3(3.2, 0.6, 3.2), 0.0)
	_box(Vector3(0, height_at(0, 0) + 0.9, 0), Vector3(1.4, 0.6, 1.0), 0.2)

	# Braseiros
	for pos in [Vector3(-2.6, 0, -11.8), Vector3(2.6, 0, -11.8), Vector3(-6, 0, 5), Vector3(6, 0, 4), Vector3(0, 0, 0)]:
		_brazier(pos, pos == Vector3(0, 0, 0))


func _pillar(p: Vector3, h: float, tilt: float) -> void:
	var gy := height_at(p.x, p.z)
	var body := StaticBody3D.new()
	body.position = Vector3(p.x, gy, p.z)
	body.rotation = Vector3(tilt, _rng.randf() * TAU, tilt * 0.5)
	add_child(body)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.5, 1.6)
	base.mesh = bm
	base.position.y = 0.25
	base.material_override = _stone_mat
	body.add_child(base)
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.58
	cm.height = h
	cm.radial_segments = 10
	col.mesh = cm
	col.position.y = 0.5 + h * 0.5
	col.material_override = _stone_mat
	body.add_child(col)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.6
	shape.height = h + 0.5
	cs.shape = shape
	cs.position.y = (h + 0.5) * 0.5
	body.add_child(cs)


func _fallen_pillar(p: Vector3, yaw: float) -> void:
	var gy := height_at(p.x, p.z)
	var body := StaticBody3D.new()
	body.position = Vector3(p.x, gy + 0.45, p.z)
	body.rotation = Vector3(0, yaw, PI * 0.5)
	add_child(body)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.55
	cm.height = 5.0
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = _stone_mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = 5.0
	cs.shape = shape
	body.add_child(cs)


func _box(center: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation.y = yaw
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _stone_mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)


func _brazier(p: Vector3, big: bool) -> void:
	var gy := height_at(p.x, p.z)
	var root := StaticBody3D.new()
	root.position = Vector3(p.x, gy + (1.2 if big else 0.0), p.z)
	add_child(root)

	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.08, 0.07, 0.07)
	iron.metallic = 0.8
	iron.roughness = 0.55

	if not big:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.08
		lm.bottom_radius = 0.18
		lm.height = 1.1
		leg.mesh = lm
		leg.position.y = 0.55
		leg.material_override = iron
		root.add_child(leg)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.35
		sh.height = 1.4
		cs.shape = sh
		cs.position.y = 0.7
		root.add_child(cs)

	var bowl := MeshInstance3D.new()
	var bwm := CylinderMesh.new()
	bwm.top_radius = 0.55 if big else 0.42
	bwm.bottom_radius = 0.25 if big else 0.18
	bwm.height = 0.35
	bowl.mesh = bwm
	bowl.position.y = 1.2 if not big else 0.15
	bowl.material_override = iron
	root.add_child(bowl)

	var fire_y := bowl.position.y + 0.2
	var flames := _make_flames(big)
	flames.position.y = fire_y
	root.add_child(flames)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.15)
	light.omni_range = 14.0 if big else 10.0
	light.omni_attenuation = 1.4
	light.light_energy = 3.2 if big else 2.4
	light.position.y = fire_y + 0.6
	light.shadow_enabled = big
	root.add_child(light)
	_fires.append({"light": light, "base": light.light_energy, "phase": _rng.randf() * 10.0})


func _make_flames(big: bool) -> Node3D:
	var holder := Node3D.new()
	var s := 1.4 if big else 1.0

	var glow_tex := GradientTexture2D.new()
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(0.5, 0.0)
	var gg := Gradient.new()
	gg.set_color(0, Color(1, 1, 1, 1))
	gg.set_color(1, Color(1, 1, 1, 0))
	glow_tex.gradient = gg

	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fire_mat.vertex_color_use_as_albedo = true
	fire_mat.albedo_texture = glow_tex
	fire_mat.disable_receive_shadows = true

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.5, 1.0, 0.5, 0.8), Color(1.4, 0.45, 0.1, 0.7),
		Color(0.7, 0.1, 0.03, 0.4), Color(0.15, 0.02, 0.01, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 0.6))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1, 0.1))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve

	# chamas
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.22 * s
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 1.6, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	pm.scale_curve = scale_tex
	pm.color_ramp = ramp_tex
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 2.0
	var fire := GPUParticles3D.new()
	fire.amount = int(40 * s)
	fire.lifetime = 0.9
	fire.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.7) * s
	q.material = fire_mat
	fire.draw_pass_1 = q
	fire.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	holder.add_child(fire)

	# fagulhas
	var em := ParticleProcessMaterial.new()
	em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	em.emission_sphere_radius = 0.3 * s
	em.direction = Vector3.UP
	em.spread = 25.0
	em.initial_velocity_min = 1.5
	em.initial_velocity_max = 3.5
	em.gravity = Vector3(0, 0.4, 0)
	em.turbulence_enabled = true
	em.turbulence_noise_strength = 1.5
	em.scale_min = 0.6
	em.scale_max = 1.0
	em.color_ramp = ramp_tex
	var embers := GPUParticles3D.new()
	embers.amount = int(16 * s)
	embers.lifetime = 2.4
	embers.process_material = em
	var eq := QuadMesh.new()
	eq.size = Vector2(0.06, 0.06)
	eq.material = fire_mat
	embers.draw_pass_1 = eq
	embers.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 10, 8))
	holder.add_child(embers)
	return holder


# --- Rochas -------------------------------------------------------------------

func _scatter_rocks() -> void:
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 1.6
	rock.radial_segments = 7
	rock.rings = 4
	rock.material = _stone_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rock
	var xforms: Array[Transform3D] = []
	var tries := 0
	while xforms.size() < 320 and tries < 3000:
		tries += 1
		var x := _rng.randf_range(-SIZE * 0.47, SIZE * 0.47)
		var z := _rng.randf_range(-SIZE * 0.47, SIZE * 0.47)
		if Vector2(x, z).length() < 18.0:
			continue
		var sz := _rng.randf_range(0.3, 1.4)
		if _rng.randf() < 0.08:
			sz *= 3.0
		var b := Basis.from_euler(Vector3(_rng.randf() * 0.6, _rng.randf() * TAU, _rng.randf() * 0.6))
		b = b.scaled(Vector3(sz * _rng.randf_range(0.8, 1.6), sz * _rng.randf_range(0.5, 1.0), sz * _rng.randf_range(0.8, 1.4)))
		xforms.append(Transform3D(b, Vector3(x, height_at(x, z) + sz * 0.15, z)))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


# --- Árvores mortas -------------------------------------------------------------

func _scatter_trees() -> void:
	var variants: Array[Mesh] = []
	for v in 4:
		variants.append(_make_tree_mesh(100 + v))
	var per_variant: Array = [[], [], [], []]
	var placed := 0
	var tries := 0
	while placed < 170 and tries < 4000:
		tries += 1
		var x := _rng.randf_range(-SIZE * 0.46, SIZE * 0.46)
		var z := _rng.randf_range(-SIZE * 0.46, SIZE * 0.46)
		var d := Vector2(x, z).length()
		if d < 22.0:
			continue
		# florestas mortas em manchas
		if _detail.get_noise_2d(x * 0.15, z * 0.15) < -0.05 and _rng.randf() < 0.7:
			continue
		var y := height_at(x, z)
		if y > 26.0:
			continue
		var sc := _rng.randf_range(0.8, 1.5)
		var b := Basis.from_euler(Vector3(_rng.randf_range(-0.08, 0.08), _rng.randf() * TAU, _rng.randf_range(-0.08, 0.08))).scaled(Vector3.ONE * sc)
		per_variant[placed % 4].append(Transform3D(b, Vector3(x, y - 0.2, z)))
		# colisão do tronco
		var body := StaticBody3D.new()
		body.position = Vector3(x, y, z)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.3 * sc
		sh.height = 4.0 * sc
		cs.shape = sh
		cs.position.y = 2.0 * sc
		body.add_child(cs)
		add_child(body)
		placed += 1
	for v in 4:
		var list: Array = per_variant[v]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[v]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _make_tree_mesh(seed_value: int) -> Mesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_branch(st, r, Vector3.ZERO, Vector3(r.randf_range(-0.1, 0.1), 1, r.randf_range(-0.1, 0.1)).normalized(), r.randf_range(3.0, 4.5), 0.32, 0)
	st.set_material(_wood_mat)
	return st.commit()


func _branch(st: SurfaceTool, r: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	# tronco/galho em 3 segmentos tortos
	var p := start
	var d := dir
	var segs := 3
	var rad := radius
	for s in segs:
		var nd := (d + Vector3(r.randf_range(-0.3, 0.3), r.randf_range(-0.05, 0.15), r.randf_range(-0.3, 0.3))).normalized()
		var np := p + nd * (length / segs)
		var nrad := rad * 0.72
		_tube(st, p, np, rad, nrad)
		p = np
		d = nd
		rad = nrad
		if depth < 3 and s >= 1:
			var kids := 1 if depth > 1 else 2
			for k in kids:
				var side := Vector3(r.randf_range(-1, 1), r.randf_range(0.1, 0.7), r.randf_range(-1, 1)).normalized()
				_branch(st, r, p, (d * 0.4 + side).normalized(), length * r.randf_range(0.45, 0.65), rad * 0.8, depth + 1)


func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float) -> void:
	var sides := 6
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u)
	for s in sides:
		var t0 := TAU * s / sides
		var t1 := TAU * (s + 1) / sides
		var d0 := u * cos(t0) + v * sin(t0)
		var d1 := u * cos(t1) + v * sin(t1)
		var p00 := a + d0 * ra
		var p01 := a + d1 * ra
		var p10 := b + d0 * rb
		var p11 := b + d1 * rb
		# ordem horária vista de fora (face da frente no Godot)
		st.set_normal(d0); st.add_vertex(p00)
		st.set_normal(d0); st.add_vertex(p10)
		st.set_normal(d1); st.add_vertex(p01)
		st.set_normal(d1); st.add_vertex(p01)
		st.set_normal(d0); st.add_vertex(p10)
		st.set_normal(d1); st.add_vertex(p11)


# --- Castelo do Rei dos Demônios ---------------------------------------------------

func _build_castle() -> void:
	var cz := -172.0
	var base_y := height_at(0, cz)
	var root := Node3D.new()
	root.position = Vector3(0, base_y - 2.0, cz)
	add_child(root)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.025, 0.03)
	dark.roughness = 1.0
	var win := StandardMaterial3D.new()
	win.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	win.albedo_color = Color(4.0, 0.8, 0.2)
	win.disable_fog = true

	var towers := [
		[Vector3(0, 0, 0), 9.0, 70.0], [Vector3(-22, 0, 6), 6.0, 48.0], [Vector3(22, 0, 6), 6.0, 50.0],
		[Vector3(-40, 0, 14), 4.5, 34.0], [Vector3(40, 0, 14), 4.5, 36.0], [Vector3(-11, 0, -8), 5.0, 56.0],
		[Vector3(12, 0, -10), 5.0, 60.0]]
	for t in towers:
		var pos: Vector3 = t[0]
		var rad: float = t[1]
		var h: float = t[2]
		var tower := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = rad * 0.85
		cm.bottom_radius = rad
		cm.height = h
		tower.mesh = cm
		tower.position = pos + Vector3(0, h * 0.5, 0)
		tower.material_override = dark
		root.add_child(tower)
		var roof := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.0
		rm.bottom_radius = rad * 1.15
		rm.height = rad * 3.2
		roof.mesh = rm
		roof.position = pos + Vector3(0, h + rad * 1.6, 0)
		roof.material_override = dark
		root.add_child(roof)
		for wi in 4:
			var w := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.9, 2.2, 0.3)
			w.mesh = wm
			w.material_override = win
			w.position = pos + Vector3(_rng.randf_range(-rad * 0.4, rad * 0.4), h * _rng.randf_range(0.35, 0.92), rad * 0.95)
			root.add_child(w)
	# muralha
	var wall := MeshInstance3D.new()
	var wallm := BoxMesh.new()
	wallm.size = Vector3(84, 18, 4)
	wall.mesh = wallm
	wall.position = Vector3(0, 9, 16)
	wall.material_override = dark
	root.add_child(wall)

	# brilho vermelho atrás do castelo
	var glow_tex := GradientTexture2D.new()
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(0.5, 0.0)
	var gg := Gradient.new()
	gg.set_color(0, Color(1, 1, 1, 1))
	gg.set_color(1, Color(1, 1, 1, 0))
	glow_tex.gradient = gg
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gmat.albedo_texture = glow_tex
	gmat.albedo_color = Color(0.8, 0.09, 0.04, 0.45)
	gmat.disable_fog = true
	gmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var glow := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(320, 120)
	glow.mesh = gq
	glow.material_override = gmat
	glow.position = Vector3(0, 18, -60)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)


# --- Cinzas caindo ----------------------------------------------------------------

func _build_ash() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 2, 30)
	pm.direction = Vector3(0.3, -1, 0.1)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0.2, -0.5, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var cr := Gradient.new()
	cr.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	cr.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var crt := GradientTexture1D.new()
	crt.gradient = cr
	pm.color_ramp = crt

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.55, 0.5, 0.5, 0.7)
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	q.material = mat

	_ash = GPUParticles3D.new()
	_ash.amount = 700
	_ash.lifetime = 10.0
	_ash.preprocess = 10.0
	_ash.local_coords = false
	_ash.process_material = pm
	_ash.draw_pass_1 = q
	_ash.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 40, 80))
	add_child(_ash)
