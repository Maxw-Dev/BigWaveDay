## Player-facing overlay: the drop-in prompt, timed hints, the end-of-wave card, and the fade.
## Built in code so the layout cannot drift; the run script drives it.
class_name RunUi
extends CanvasLayer

var _fade: ColorRect
var _card: Control
var _card_bg: ColorRect
var _title: Label
var _subtitle: Label
var _highlights: Label
var _continue: Label
var _prompt: Label
var _hint: Label
var _hint_tween: Tween
var _speed_lines: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _mode: Label
var _title_box: Control
var _title_mode: Label

const SPEED_SHADER := preload("res://shaders/speed_lines.gdshader")

@export var surfer: Surfer
@export var cam: ChaseCamera
var _board_background: MeshInstance3D
var board_look := {}                      ## deck, stripe, tip colours and length, rolled per spawn.


func _ready() -> void:
	layer = 5
	_speed_lines = _full_rect(ColorRect.new())
	_speed_lines.color = Color.WHITE
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = SPEED_SHADER
	_speed_lines.material = sm
	add_child(_speed_lines)
	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar_top.anchor_bottom = 0.0
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color.BLACK
	_bar_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.anchor_top = 1.0
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_bottom)
	_fade = _full_rect(ColorRect.new())
	_fade.color = Color(0.02, 0.05, 0.1, 1.0)
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	# Prompt: centred, pushed below the middle by a spacer so the rider stays clear.
	var prompt_centre := CenterContainer.new()
	_full_rect(prompt_centre)
	prompt_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt_centre)
	var prompt_box := VBoxContainer.new()
	prompt_centre.add_child(prompt_box)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 260)
	prompt_box.add_child(spacer)
	_prompt = _label(40, Color(1, 1, 1))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	prompt_box.add_child(_prompt)

	# Hint: bottom centre.
	var hint_margin := MarginContainer.new()
	_full_rect(hint_margin)
	hint_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_margin.add_theme_constant_override("margin_bottom", 80)
	add_child(hint_margin)
	var hint_box := VBoxContainer.new()
	hint_box.alignment = BoxContainer.ALIGNMENT_END
	hint_margin.add_child(hint_box)
	_hint = _label(28, Color(1, 0.95, 0.7))
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint.modulate.a = 0.0
	hint_box.add_child(_hint)

	_card = _full_rect(Control.new())
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	_card_bg = _full_rect(ColorRect.new())
	_card_bg.color = Color(0.0, 0.03, 0.08, 0.55)
	_card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_bg)
	var centre := CenterContainer.new()
	_full_rect(centre)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(centre)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	centre.add_child(box)
	_title = _label(52, Color(1, 1, 1))
	_subtitle = _label(24, Color(0.9, 0.95, 1.0))
	_highlights = _label(24, Color(1, 1, 1))
	_continue = _label(22, Color(0.8, 0.9, 1.0))
	_mode = _label(20, Color(0.75, 0.85, 0.95))
	for l in [_title, _subtitle, _highlights, _continue, _mode]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	_continue.modulate.a = 0.0
	
	_board_background = MeshInstance3D.new()
	_card.add_child(_board_background)
	_board_background.rotation_order=EULER_ORDER_ZYX
	_board_background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	

	# Title screen.
	_title_box = _full_rect(Control.new())
	_title_box.visible = false
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_box)
	var tc := CenterContainer.new()
	_full_rect(tc)
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.add_child(tc)
	var tb := VBoxContainer.new()
	tb.alignment = BoxContainer.ALIGNMENT_CENTER
	tb.add_theme_constant_override("separation", 18)
	tc.add_child(tb)
	var name := _label(84, Color(1, 1, 1))
	name.text = "BIG WAVE DAY"
	var go := _label(32, Color(0.9, 0.95, 1.0))
	go.text = "TAP to surf"
	_title_mode = _label(22, Color(0.75, 0.85, 0.95))
	for l in [name, go, _title_mode]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tb.add_child(l)


func show_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = true


func hide_prompt() -> void:
	_prompt.visible = false


func show_hint(text: String, seconds: float) -> void:
	_hint.text = text
	if _hint_tween != null:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 0.25)
	_hint_tween.tween_interval(seconds)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.4)


func show_card(title: String, colour: Color, subtitle: String, lines: PackedStringArray, continue_text: String, continue_after: float) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", colour)
	_subtitle.text = subtitle
	_highlights.text = "\n".join(lines)
	_continue.text = continue_text
	_continue.modulate.a = 0.0
	_card.visible = true
	_card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.3)
	tw.tween_interval(maxf(continue_after - 0.3, 0.0))
	tw.tween_property(_continue, "modulate:a", 1.0, 0.3)
	
	#var mesh = BoxMesh.new()
	board_look = surfer.board_look
	_board_background.material_override = surfer.board.material_override
	
	_board_background.mesh = _build_board_mesh(board_look.length, surfer.board_width, surfer.board_thickness)
	
	_board_background.quaternion = cam.quaternion
	_board_background.rotate(cam.basis.x, -PI/2)
	_board_background.rotate(cam.basis.z, PI/2)
	_board_background.position = cam.position + cam.global_basis.z * lerpf(-0.9, -1.7, (board_look.length - 2.15) / 1.25)
	_board_background.position += cam.global_basis.x * lerpf(0.1, -0.05, (board_look.length - 2.15) / 1.25)

func _build_board_mesh(length: float, width: float, thick: float) -> ArrayMesh:
	# A surfboard lofted from elliptical rail sections: pointed nose at -Z (forward), wider ahead of the
	# middle, narrower rounded tail at +Z, a little rocker. No modelling tool needed.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_len := 28
	var n_around := 14
	for i in range(n_len + 1):
		var t := float(i) / n_len                     # 0 = tail, 1 = nose
		var z := (0.5 - t) * length
		var half_w := width * 0.5 * _board_outline(t)
		var half_t := thick * 0.5 * _board_thickness(t)
		var rocker := 0.045 * length * pow(absf(t - 0.45) / 0.55, 2.2)
		for j in range(n_around):
			var a := TAU * float(j) / n_around
			var col: Color = board_look.get("deck", Color(1.0, 0.45, 0.05))
			if t > 0.86:
				col = board_look.get("tip", col)
			elif board_look.get("has_stripe", false) and sin(a) > 0.0 and absf(cos(a)) < 0.28:
				col = board_look.get("stripe", col)
			st.set_color(col)
			st.add_vertex(Vector3(cos(a) * half_w, sin(a) * half_t + rocker, z))
	for i in range(n_len):
		for j in range(n_around):
			var a := i * n_around + j
			var b := i * n_around + (j + 1) % n_around
			var c := a + n_around
			var d := b + n_around
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	return st.commit()

func _board_outline(t: float) -> float:
	# Half-width factor along the board. Widest at 45% from the tail, elliptical taper to the nose point,
	# gentle pull-in to a rounded tail.
	var nose := 1.0
	if t > 0.45:
		var q := (t - 0.45) / 0.55
		nose = sqrt(maxf(1.0 - q * q, 0.0))
	var tail := lerpf(0.62, 1.0, smoothstep(0.0, 0.45, t)) * sqrt(smoothstep(0.0, 0.07, t))
	return nose * tail

func _board_thickness(t: float) -> float:
	var q := (t - 0.5) / 0.5
	return maxf(sqrt(maxf(1.0 - q * q, 0.0)), 0.12)

func _process(_delta: float) -> void:
	if (_card.visible):
		_board_background.quaternion = cam.quaternion
		_board_background.rotate(cam.basis.x, -PI/2)
		_board_background.rotate(cam.basis.z, PI/2)
		_board_background.position = cam.position + cam.global_basis.z * lerpf(-0.9, -1.7, (board_look.length - 2.15) / 1.25)
		_board_background.position += cam.global_basis.x * lerpf(0.1, -0.05, (board_look.length - 2.15) / 1.25)

func hide_card() -> void:
	_card.visible = false
	_board_background.mesh = null


func show_title(mode_text: String) -> void:
	_title_mode.text = mode_text
	_title_box.visible = true
	_title_box.modulate.a = 0.0
	create_tween().tween_property(_title_box, "modulate:a", 1.0, 0.4)


func set_title_mode(mode_text: String) -> void:
	_title_mode.text = mode_text


func hide_title() -> void:
	var tw := create_tween()
	tw.tween_property(_title_box, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func(): _title_box.visible = false)


func set_letterbox(on: bool) -> void:
	# Cinema bars say "replay" without a word on screen.
	var tw := create_tween().set_parallel(true)
	var h := 0.11 if on else 0.0
	tw.tween_property(_bar_top, "anchor_bottom", h, 0.35)
	tw.tween_property(_bar_bottom, "anchor_top", 1.0 - h, 0.35)


func set_mode_text(text: String) -> void:
	_mode.text = text


func set_speed_lines(strength: float) -> void:
	(_speed_lines.material as ShaderMaterial).set_shader_parameter("strength", clampf(strength, 0.0, 1.0))




func fade_to(alpha: float, seconds: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", alpha, seconds)
	return tw


func _full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
