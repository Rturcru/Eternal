extends Node3D
## Ponto de entrada: cria o mundo, o jogador e a interface.

const WorldScript := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/hud.gd")


func _ready() -> void:
	_setup_input()

	var world = WorldScript.new()
	world.name = "World"
	add_child(world)

	var player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	player.global_position = world.spawn_point()
	world.follow_target = player

	var hud = HudScript.new()
	hud.name = "Hud"
	add_child(hud)
	hud.player = player
	player.hud = hud

	_maybe_screenshot(player)


# --- Captura automática (usada para testar sem abrir o jogo) ---------------------
# Uso: godot --path . -- --shot=saida.png [--yaw=0.0] [--pitch=-0.18] [--attack] [--frames=90]

func _maybe_screenshot(player) -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if not args.has("shot"):
		return
	if args.has("yaw"):
		player.cam_yaw = float(args["yaw"])
	if args.has("pitch"):
		player.cam_pitch = float(args["pitch"])
	if args.has("pos"):
		var c: PackedStringArray = args["pos"].split(",")
		var w = get_node("World")
		player.global_position = Vector3(float(c[0]), w.height_at(float(c[0]), float(c[1])) + 1.0, float(c[1]))
	var frames := int(args.get("frames", "90"))
	for i in frames:
		if args.has("attack") and i == frames - 14:
			Input.action_press("attack")
		if args.has("attack") and i == frames - 12:
			Input.action_release("attack")
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(args["shot"])
	get_tree().quit()


# --- Controles (teclado, mouse e controle) --------------------------------

func _setup_input() -> void:
	_add("move_forward", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add("move_back", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_add("look_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_add("look_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_add("look_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_add("look_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_add("jump", [_key(KEY_SPACE), _btn(JOY_BUTTON_A)])
	_add("sprint", [_key(KEY_SHIFT), _btn(JOY_BUTTON_LEFT_STICK)])
	_add("dodge", [_key(KEY_CTRL), _key(KEY_C), _btn(JOY_BUTTON_B)])
	_add("attack", [_mouse(MOUSE_BUTTON_LEFT), _key(KEY_J), _btn(JOY_BUTTON_X), _btn(JOY_BUTTON_RIGHT_SHOULDER)])
	_add("pause", [_key(KEY_ESCAPE), _btn(JOY_BUTTON_START)])


func _add(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for e in events:
		InputMap.action_add_event(action, e)


func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e


func _mouse(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e


func _btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	return e
