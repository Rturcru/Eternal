extends CharacterBody3D
## Cavaleiro jogável: movimento em terceira pessoa, corrida, pulo, esquiva
## (rolamento com invencibilidade), combo de espada e estamina.
## O modelo é montado com primitivas e animado por código (sem assets).

signal attack_hit(origin: Vector3, forward: Vector3, damage: float)

const WALK_SPEED := 4.0
const RUN_SPEED := 7.6
const ACCEL := 11.0
const AIR_ACCEL := 3.0
const JUMP_VELOCITY := 5.4
const GRAVITY := 17.0
const DODGE_SPEED := 10.5
const DODGE_TIME := 0.5
const ATTACK_TIME := 0.52
const ST_RUN := 14.0        # estamina por segundo correndo
const ST_DODGE := 22.0
const ST_ATTACK := 14.0
const ST_JUMP := 8.0

var hud                      # definido pelo main.gd

var max_hp := 100.0
var hp := 100.0
var max_st := 100.0
var st := 100.0
var invulnerable := false

var cam_yaw := 0.0           # câmera começa olhando para o norte (castelo)
var cam_pitch := -0.18

var _rig: Node3D
var _pitch_node: Node3D
var _arm: SpringArm3D
var camera: Camera3D
var _shake := 0.0

var _model: Node3D           # gira para a direção do movimento
var _body: Node3D            # quadril (rola na esquiva)
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _cape: Node3D
var _blade_tip: Node3D
var _blade_base: Node3D

var _state := "move"         # move | dodge | attack
var _state_t := 0.0
var _dodge_dir := Vector3.FORWARD
var _combo := 0
var _queued_attack := false
var _hit_done := false
var _st_delay := 0.0
var _phase := 0.0
var _move_amount := 0.0
var _running := false
var _was_on_floor := true
var _land_t := 1.0

var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_pts: Array = []   # [[base, tip, age]]


func _ready() -> void:
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_build_model()
	_build_camera()
	# luz suave perto do cavaleiro (deixa a armadura legível no escuro)
	var aura := OmniLight3D.new()
	aura.light_color = Color(1.0, 0.75, 0.55)
	aura.light_energy = 0.55
	aura.omni_range = 5.5
	aura.position = Vector3(0.0, 2.2, 1.2)
	aura.light_specular = 0.6
	add_child(aura)
	_build_trail()
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * 0.0028
		cam_pitch -= event.relative.y * 0.0024
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Lógica ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# câmera (toque + controle)
	if hud:
		var look: Vector2 = hud.consume_look()
		cam_yaw -= look.x * 0.0055
		cam_pitch -= look.y * 0.0045
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	cam_yaw -= stick.x * 2.6 * delta
	cam_pitch -= stick.y * 1.8 * delta
	cam_pitch = clampf(cam_pitch, -1.25, 0.55)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if hud and hud.move_vector.length() > input.length():
		input = hud.move_vector
	var wish := Basis(Vector3.UP, cam_yaw) * Vector3(input.x, 0, input.y)
	var wish_len := minf(wish.length(), 1.0)

	_state_t += delta
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	match _state:
		"move":
			_state_move(delta, wish, wish_len)
		"dodge":
			_state_dodge(delta)
		"attack":
			_state_attack(delta, wish)

	move_and_slide()

	# estamina
	_st_delay -= delta
	if _st_delay <= 0.0 and not _running:
		st = minf(max_st, st + 32.0 * delta)

	# aterrissagem
	if is_on_floor() and not _was_on_floor:
		_land_t = 0.0
	_was_on_floor = is_on_floor()

	# caiu do mapa
	if global_position.y < -60.0:
		global_position = get_parent().get_node("World").spawn_point()
		velocity = Vector3.ZERO


func _state_move(delta: float, wish: Vector3, wish_len: float) -> void:
	var sprint_held: bool = Input.is_action_pressed("sprint") or (hud != null and hud.sprint_on)
	_running = sprint_held and wish_len > 0.3 and st > 1.0 and is_on_floor()
	if _running:
		_spend(ST_RUN * delta, 0.5)
	var speed := RUN_SPEED if _running else WALK_SPEED
	var target := wish.normalized() * speed * wish_len if wish_len > 0.01 else Vector3.ZERO
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.lerp(target, clampf((ACCEL if is_on_floor() else AIR_ACCEL) * delta, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z

	if hv.length() > 0.3:
		_face(atan2(-hv.x, -hv.z), delta, 12.0)

	if Input.is_action_just_pressed("jump") and is_on_floor() and st >= ST_JUMP:
		velocity.y = JUMP_VELOCITY
		_spend(ST_JUMP, 0.6)
	elif Input.is_action_just_pressed("dodge") and is_on_floor() and st >= ST_DODGE:
		_start_dodge(wish)
	elif Input.is_action_just_pressed("attack") and st >= ST_ATTACK * 0.5:
		_combo = 0
		_start_attack(wish)


func _start_dodge(wish: Vector3) -> void:
	_spend(ST_DODGE, 0.8)
	_state = "dodge"
	_state_t = 0.0
	_running = false
	if wish.length() > 0.2:
		_dodge_dir = wish.normalized()
	else:
		_dodge_dir = -_model.global_basis.z  # para frente
		_dodge_dir.y = 0
		_dodge_dir = _dodge_dir.normalized()
	_model.rotation.y = atan2(-_dodge_dir.x, -_dodge_dir.z)
	invulnerable = true


func _state_dodge(_delta: float) -> void:
	var k := _state_t / DODGE_TIME
	var spd := DODGE_SPEED * (1.0 - k * k) + 1.0
	velocity.x = _dodge_dir.x * spd
	velocity.z = _dodge_dir.z * spd
	invulnerable = k < 0.75
	if k >= 1.0:
		_state = "move"
		invulnerable = false
		_body.rotation.x = 0.0


func _start_attack(wish: Vector3) -> void:
	_spend(ST_ATTACK, 0.7)
	_state = "attack"
	_state_t = 0.0
	_queued_attack = false
	_hit_done = false
	_running = false
	_trail_pts.clear()
	if wish.length() > 0.2:
		_model.rotation.y = atan2(-wish.x, -wish.z)


func _state_attack(delta: float, wish: Vector3) -> void:
	var k := _state_t / ATTACK_TIME
	# avanço curto no golpe
	var fwd := -_model.global_basis.z
	var lunge := 5.0 if k > 0.2 and k < 0.45 else 0.0
	var hv := Vector3(velocity.x, 0, velocity.z).lerp(fwd * lunge, clampf(14.0 * delta, 0, 1))
	velocity.x = hv.x
	velocity.z = hv.z

	if Input.is_action_just_pressed("attack") and k > 0.25:
		_queued_attack = true
	if not _hit_done and k >= 0.38:
		_hit_done = true
		attack_hit.emit(global_position + Vector3.UP, fwd, 20.0 + _combo * 6.0)
		_shake = 0.12
	if k >= 1.0 or (k >= 0.7 and _queued_attack and st >= ST_ATTACK * 0.5):
		if _queued_attack and st >= ST_ATTACK * 0.5:
			_combo = (_combo + 1) % 3
			_start_attack(wish)
		else:
			_state = "move"
			_combo = 0
	elif k >= 0.75 and Input.is_action_just_pressed("dodge") and st >= ST_DODGE:
		_start_dodge(wish)  # cancelar o fim do golpe com esquiva


func _spend(amount: float, delay: float) -> void:
	st = maxf(0.0, st - amount)
	_st_delay = delay


func _face(target_yaw: float, delta: float, speed: float) -> void:
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, clampf(speed * delta, 0, 1))


func take_damage(amount: float) -> void:
	if invulnerable:
		return
	hp = maxf(0.0, hp - amount)
	_shake = 0.3


# --- Animação procedural, câmera e rastro da espada --------------------------------------

func _process(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_move_amount = lerpf(_move_amount, clampf(hspeed / RUN_SPEED, 0, 1), clampf(10 * delta, 0, 1))
	_phase += delta * (4.0 + hspeed * 1.35)
	_land_t = minf(_land_t + delta * 4.0, 1.0)
	_animate(delta)
	_update_camera(delta)
	_update_trail(delta)


func _animate(delta: float) -> void:
	var m := _move_amount
	var s := sin(_phase)
	var air := not is_on_floor()
	var t := clampf(10 * delta, 0, 1)

	# pernas e braços (andar/correr)
	var leg_amp := 0.15 + m * 0.75
	var target_ll := s * leg_amp
	var target_lr := -s * leg_amp
	if air:
		target_ll = 0.5
		target_lr = -0.3
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, target_ll, t)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, target_lr, t)
	var bob := absf(cos(_phase)) * 0.06 * m
	var squash := (1.0 - _land_t) * 0.12
	_body.position.y = 0.95 + bob - squash
	_torso.rotation.x = lerpf(_torso.rotation.x, 0.08 + m * 0.22, t)

	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -s * (0.1 + m * 0.6), t)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, 0.12, t)

	# capa balança com a velocidade
	_cape.rotation.x = lerpf(_cape.rotation.x, 0.15 + m * 0.9 + sin(_phase * 0.5) * 0.08, clampf(5 * delta, 0, 1))

	match _state:
		"dodge":
			var k := clampf(_state_t / DODGE_TIME, 0, 1)
			_body.rotation.x = -TAU * smoothstep(0.0, 0.85, k)
			_body.position.y = 0.95 - sin(k * PI) * 0.45
			_arm_r.rotation = _arm_r.rotation.lerp(Vector3(0.6, 0, 0), t)
		"attack":
			_animate_attack(clampf(_state_t / ATTACK_TIME, 0, 1))
		_:
			_body.rotation.x = 0.0
			_torso.rotation.y = lerpf(_torso.rotation.y, 0.0, t)
			# espada baixa em guarda
			var idle := Vector3(0.35 - s * m * 0.3, 0.0, 0.18)
			_arm_r.rotation = _arm_r.rotation.lerp(idle, t)


func _animate_attack(k: float) -> void:
	# 3 golpes: diagonal, horizontal, de cima para baixo
	var wind := smoothstep(0.0, 0.3, k)
	var strike := smoothstep(0.3, 0.48, k)
	var recover := smoothstep(0.7, 1.0, k)
	var a: Vector3
	var b: Vector3
	var c := Vector3(0.4, 0, 0.18)
	var twist_a := 0.0
	var twist_b := 0.0
	match _combo:
		0:
			a = Vector3(2.7, 0.5, 0.9); b = Vector3(0.6, -0.4, -0.5); twist_a = 0.6; twist_b = -0.5
		1:
			a = Vector3(1.5, 1.4, 0.2); b = Vector3(1.4, -1.5, 0.2); twist_a = 0.9; twist_b = -0.8
		_:
			a = Vector3(3.0, 0.0, 0.1); b = Vector3(0.5, 0.0, 0.1); twist_a = 0.0; twist_b = 0.0
	var rot := c.lerp(a, wind)
	rot = rot.lerp(b, strike)
	rot = rot.lerp(c, recover)
	_arm_r.rotation = rot
	var tw := lerpf(0.0, twist_a, wind)
	tw = lerpf(tw, twist_b, strike)
	tw = lerpf(tw, 0.0, recover)
	_torso.rotation.y = tw
	_torso.rotation.x = 0.1 + strike * (1.0 - recover) * 0.25


func _update_camera(delta: float) -> void:
	var target := global_position + Vector3(0, 1.55, 0)
	_rig.global_position = _rig.global_position.lerp(target, clampf(14 * delta, 0, 1))
	_rig.rotation.y = cam_yaw
	_pitch_node.rotation.x = cam_pitch
	var want_len := 4.6 + _move_amount * 0.8 if _running else 4.2
	_arm.spring_length = lerpf(_arm.spring_length, want_len, clampf(3 * delta, 0, 1))
	camera.fov = lerpf(camera.fov, 76.0 if _running else 70.0, clampf(3 * delta, 0, 1))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		camera.h_offset = randf_range(-1, 1) * _shake * 0.3
		camera.v_offset = randf_range(-1, 1) * _shake * 0.3
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _update_trail(delta: float) -> void:
	for p in _trail_pts:
		p[2] += delta
	while _trail_pts.size() > 0 and _trail_pts[0][2] > 0.16:
		_trail_pts.pop_front()
	if _state == "attack":
		var k := _state_t / ATTACK_TIME
		if k > 0.26 and k < 0.6:
			_trail_pts.append([_blade_base.global_position, _blade_tip.global_position, 0.0])
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _trail_pts:
		var a: float = 1.0 - p[2] / 0.16
		_trail_mesh.surface_set_color(Color(1.0, 0.55, 0.25, 0.0))
		_trail_mesh.surface_add_vertex(p[0])
		_trail_mesh.surface_set_color(Color(1.6, 0.8, 0.4, a * 0.85))
		_trail_mesh.surface_add_vertex(p[1])
	_trail_mesh.surface_end()


# --- Construção ------------------------------------------------------------------------

func _build_camera() -> void:
	_rig = Node3D.new()
	_rig.top_level = true
	add_child(_rig)
	_rig.global_position = global_position + Vector3(0, 1.55, 0)
	_pitch_node = Node3D.new()
	_rig.add_child(_pitch_node)
	_arm = SpringArm3D.new()
	_arm.spring_length = 4.2
	_arm.margin = 0.2
	_arm.position.x = 0.55
	var sph := SphereShape3D.new()
	sph.radius = 0.25
	_arm.shape = sph
	_arm.add_excluded_object(get_rid())
	_pitch_node.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.08
	camera.far = 600.0
	_arm.add_child(camera)
	camera.current = true


func _build_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	_trail.material_override = m
	add_child(_trail)
	_trail.global_transform = Transform3D.IDENTITY


func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


func _boxm(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	s.radial_segments = 12
	s.rings = 6
	return s


func _build_model() -> void:
	var steel := _mat(Color(0.42, 0.42, 0.45), 0.85, 0.32)
	var dark_steel := _mat(Color(0.16, 0.16, 0.18), 0.75, 0.45)
	var leather := _mat(Color(0.22, 0.14, 0.09), 0.0, 0.8)
	var cloth := _mat(Color(0.42, 0.04, 0.045), 0.0, 0.85)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blade_mat := _mat(Color(0.75, 0.76, 0.8), 1.0, 0.18)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(3.0, 1.2, 0.3)

	_model = Node3D.new()
	add_child(_model)
	_model.rotation.y = 0.0

	_body = Node3D.new()
	_body.position.y = 0.95
	_model.add_child(_body)

	# pernas (pivô no quadril)
	_leg_l = Node3D.new()
	_leg_l.position = Vector3(-0.13, 0, 0)
	_body.add_child(_leg_l)
	_part(_leg_l, _capsule(0.1, 0.55), dark_steel, Vector3(0, -0.25, 0))
	_part(_leg_l, _capsule(0.09, 0.5), steel, Vector3(0, -0.66, 0))
	_part(_leg_l, _boxm(Vector3(0.16, 0.1, 0.28)), leather, Vector3(0, -0.9, -0.04))
	_leg_r = Node3D.new()
	_leg_r.position = Vector3(0.13, 0, 0)
	_body.add_child(_leg_r)
	_part(_leg_r, _capsule(0.1, 0.55), dark_steel, Vector3(0, -0.25, 0))
	_part(_leg_r, _capsule(0.09, 0.5), steel, Vector3(0, -0.66, 0))
	_part(_leg_r, _boxm(Vector3(0.16, 0.1, 0.28)), leather, Vector3(0, -0.9, -0.04))

	# tronco
	_torso = Node3D.new()
	_body.add_child(_torso)
	_part(_torso, _boxm(Vector3(0.38, 0.22, 0.24)), leather, Vector3(0, 0.05, 0))     # cintura
	_part(_torso, _capsule(0.2, 0.55), dark_steel, Vector3(0, 0.38, 0), Vector3.ZERO, Vector3(1.15, 1, 0.8))
	_part(_torso, _boxm(Vector3(0.44, 0.34, 0.26)), steel, Vector3(0, 0.45, -0.02), Vector3(-0.08, 0, 0))  # peitoral
	_part(_torso, _sphere(0.13), steel, Vector3(-0.27, 0.62, 0), Vector3.ZERO, Vector3(1.1, 0.8, 1.1))   # ombreiras
	_part(_torso, _sphere(0.13), steel, Vector3(0.27, 0.62, 0), Vector3.ZERO, Vector3(1.1, 0.8, 1.1))

	# cabeça + elmo
	_head = Node3D.new()
	_head.position = Vector3(0, 0.82, 0)
	_torso.add_child(_head)
	_part(_head, _sphere(0.14), dark_steel, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.15, 1.05))
	_part(_head, _boxm(Vector3(0.2, 0.025, 0.02)), eye_mat, Vector3(0, 0.0, -0.145))  # fenda dos olhos
	_part(_head, _boxm(Vector3(0.025, 0.12, 0.25)), steel, Vector3(0, 0.12, 0))       # crista

	# capa (pivô na nuca)
	_cape = Node3D.new()
	_cape.position = Vector3(0, 0.66, 0.13)
	_torso.add_child(_cape)
	_part(_cape, _boxm(Vector3(0.5, 1.05, 0.02)), cloth, Vector3(0, -0.52, 0.02))

	# braço esquerdo
	_arm_l = Node3D.new()
	_arm_l.position = Vector3(-0.3, 0.58, 0)
	_torso.add_child(_arm_l)
	_part(_arm_l, _capsule(0.075, 0.38), dark_steel, Vector3(0, -0.17, 0))
	_part(_arm_l, _capsule(0.07, 0.36), steel, Vector3(0, -0.47, 0))
	_part(_arm_l, _sphere(0.06), leather, Vector3(0, -0.67, 0))

	# braço direito + espada
	_arm_r = Node3D.new()
	_arm_r.position = Vector3(0.3, 0.58, 0)
	_torso.add_child(_arm_r)
	_part(_arm_r, _capsule(0.075, 0.38), dark_steel, Vector3(0, -0.17, 0))
	_part(_arm_r, _capsule(0.07, 0.36), steel, Vector3(0, -0.47, 0))
	_part(_arm_r, _sphere(0.06), leather, Vector3(0, -0.67, 0))
	var sword := Node3D.new()
	sword.position = Vector3(0, -0.68, 0)
	sword.rotation = Vector3(-PI * 0.5, 0, 0)  # lâmina para frente com o braço abaixado
	_arm_r.add_child(sword)
	_part(sword, _boxm(Vector3(0.035, 0.22, 0.035)), leather, Vector3(0, -0.02, 0))      # cabo
	_part(sword, _boxm(Vector3(0.26, 0.04, 0.05)), dark_steel, Vector3(0, 0.1, 0))      # guarda
	_part(sword, _boxm(Vector3(0.06, 0.95, 0.012)), blade_mat, Vector3(0, 0.6, 0))      # lâmina
	_blade_base = Node3D.new()
	_blade_base.position = Vector3(0, 0.25, 0)
	sword.add_child(_blade_base)
	_blade_tip = Node3D.new()
	_blade_tip.position = Vector3(0, 1.07, 0)
	sword.add_child(_blade_tip)
