extends CanvasLayer
## Interface: barras de vida e estamina, título de abertura e controles de toque
## (joystick à esquerda, arrastar à direita para girar a câmera, botões de ação).
## O toque é tratado manualmente para suportar vários dedos ao mesmo tempo.

var player                     # definido pelo main.gd
var move_vector := Vector2.ZERO
var sprint_on := false         # corrida em modo "liga/desliga" no celular

var _ui: Control
var _fps: Label
var _title: Control
var _title_t := 0.0
var _touch_mode := false

var _joy_finger := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_finger := -1
var _look_delta := Vector2.ZERO
var _btn_fingers := {}         # dedo -> nome do botão
var _shown_hp := 100.0
var _shown_st := 100.0

const JOY_RADIUS := 85.0

# [nome, ação, rótulo, posição relativa ao canto inferior direito, raio]
var _buttons := [
	["attack", "attack", "⚔", Vector2(-120, -120), 62.0],
	["dodge", "dodge", "↻", Vector2(-245, -80), 46.0],
	["jump", "jump", "▲", Vector2(-95, -255), 42.0],
	["sprint", "", "»", Vector2(-230, -205), 38.0],
]


func _ready() -> void:
	layer = 10
	_touch_mode = DisplayServer.is_touchscreen_available()

	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	add_child(_ui)

	_fps = Label.new()
	_fps.position = Vector2(-90, 8)
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.add_theme_font_size_override("font_size", 14)
	_fps.modulate = Color(1, 1, 1, 0.5)
	_ui.add_child(_fps)

	_build_title()


func consume_look() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


func _process(delta: float) -> void:
	if player:
		_shown_hp = lerpf(_shown_hp, player.hp, clampf(6 * delta, 0, 1))
		_shown_st = lerpf(_shown_st, player.st, clampf(12 * delta, 0, 1))
	_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if _title:
		_title_t += delta
		var a := 1.0 - smoothstep(4.0, 6.0, _title_t)
		_title.modulate.a = a
		if a <= 0.0:
			_title.queue_free()
			_title = null
	_ui.queue_redraw()


# --- Toque --------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch_mode = true
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _joy_finger:
			_joy_pos = event.position
			var v: Vector2 = (_joy_pos - _joy_origin) / JOY_RADIUS
			move_vector = v.limit_length(1.0)
		elif event.index == _look_finger:
			_look_delta += event.relative


func _touch_down(finger: int, pos: Vector2) -> void:
	var size := _ui.size
	for b in _buttons:
		var center: Vector2 = size + b[3]
		if pos.distance_to(center) <= b[4] * 1.15:
			if b[0] == "sprint":
				sprint_on = not sprint_on
			else:
				Input.action_press(b[1])
			_btn_fingers[finger] = b[0]
			return
	if pos.x < size.x * 0.4 and pos.y > size.y * 0.3 and _joy_finger == -1:
		_joy_finger = finger
		_joy_origin = pos
		_joy_pos = pos
		move_vector = Vector2.ZERO
	elif _look_finger == -1:
		_look_finger = finger


func _touch_up(finger: int) -> void:
	if finger == _joy_finger:
		_joy_finger = -1
		move_vector = Vector2.ZERO
	elif finger == _look_finger:
		_look_finger = -1
	elif _btn_fingers.has(finger):
		var bname: String = _btn_fingers[finger]
		_btn_fingers.erase(finger)
		for b in _buttons:
			if b[0] == bname and b[1] != "":
				Input.action_release(b[1])


# --- Desenho --------------------------------------------------------------------------

func _draw_ui() -> void:
	# barras
	var x := 24.0
	var y := 22.0
	_bar(Vector2(x, y), Vector2(300, 14), _shown_hp / 100.0, Color(0.62, 0.06, 0.05))
	_bar(Vector2(x, y + 22), Vector2(240, 9), _shown_st / 100.0, Color(0.75, 0.62, 0.25))

	if not _touch_mode:
		return
	var size := _ui.size
	# joystick
	if _joy_finger != -1:
		_ui.draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.07))
		_ui.draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
		_ui.draw_circle(_joy_origin + move_vector * JOY_RADIUS, 34, Color(1, 1, 1, 0.3))
	else:
		var home := Vector2(150, size.y - 150)
		_ui.draw_arc(home, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0, true)
		_ui.draw_circle(home, 30, Color(1, 1, 1, 0.1))
	# botões
	var font := ThemeDB.fallback_font
	for b in _buttons:
		var center: Vector2 = size + b[3]
		var r: float = b[4]
		var pressed: bool = _btn_fingers.values().has(b[0]) or (b[0] == "sprint" and sprint_on)
		_ui.draw_circle(center, r, Color(0.5, 0.08, 0.05, 0.45) if pressed else Color(0, 0, 0, 0.35))
		_ui.draw_arc(center, r, 0, TAU, 40, Color(0.85, 0.6, 0.35, 0.6), 2.0, true)
		var fs := int(r * 0.8)
		var label: String = b[2]
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		_ui.draw_string(font, center + Vector2(-tw * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.95, 0.85, 0.7, 0.9))


func _bar(pos: Vector2, sz: Vector2, value: float, col: Color) -> void:
	_ui.draw_rect(Rect2(pos - Vector2(2, 2), sz + Vector2(4, 4)), Color(0, 0, 0, 0.6))
	_ui.draw_rect(Rect2(pos, Vector2(sz.x * clampf(value, 0, 1), sz.y)), col)
	_ui.draw_rect(Rect2(pos - Vector2(2, 2), sz + Vector2(4, 4)), Color(0.75, 0.6, 0.4, 0.5), false, 1.0)


func _build_title() -> void:
	_title = Control.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	var t := Label.new()
	t.text = "ETERNAL NIGHT"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.set_anchors_preset(Control.PRESET_CENTER)
	t.add_theme_font_size_override("font_size", 64)
	t.add_theme_color_override("font_color", Color(0.9, 0.78, 0.6))
	t.add_theme_color_override("font_outline_color", Color(0.25, 0.02, 0.02))
	t.add_theme_constant_override("outline_size", 10)
	t.grow_horizontal = Control.GROW_DIRECTION_BOTH
	t.grow_vertical = Control.GROW_DIRECTION_BOTH
	t.position.y -= 60
	_title.add_child(t)
	var s := Label.new()
	s.text = "O sol não nasce há mil anos"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.set_anchors_preset(Control.PRESET_CENTER)
	s.add_theme_font_size_override("font_size", 22)
	s.add_theme_color_override("font_color", Color(0.75, 0.6, 0.5))
	s.grow_horizontal = Control.GROW_DIRECTION_BOTH
	s.grow_vertical = Control.GROW_DIRECTION_BOTH
	s.position.y += 10
	_title.add_child(s)
