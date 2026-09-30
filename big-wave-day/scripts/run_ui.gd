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
var _ring: PumpRing
var _mode: Label

const SPEED_SHADER := preload("res://shaders/speed_lines.gdshader")


## Fills as a tap becomes worth more; flashes when it is worth taking.
class PumpRing extends Control:
	var readiness := 0.0
	var pulse := 0.0

	func _process(delta: float) -> void:
		pulse += delta * 8.0
		queue_redraw()

	func _draw() -> void:
		var c := Vector2.ZERO
		var hot := readiness >= 0.72
		draw_arc(c, 30.0, 0.0, TAU, 40, Color(1, 1, 1, 0.18), 7.0, true)
		if readiness > 0.02:
			var col := Color(0.55, 0.9, 1.0, 0.85).lerp(Color(1.0, 0.85, 0.2, 1.0), clampf((readiness - 0.4) / 0.4, 0.0, 1.0))
			if hot:
				col = col.lerp(Color.WHITE, 0.5 + 0.5 * sin(pulse))
			draw_arc(c, 30.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(readiness, 0.0, 1.0), 40, col, 7.0, true)
		if hot:
			var font := ThemeDB.fallback_font
			draw_string_outline(font, Vector2(-40.0, 8.0), "TAP", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 24, 6, Color(0, 0, 0, 1))
			draw_string(font, Vector2(-40.0, 8.0), "TAP", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 24, Color(1, 1, 1, 1))


func _ready() -> void:
	layer = 5
	_speed_lines = _full_rect(ColorRect.new())
	_speed_lines.color = Color.WHITE
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = SPEED_SHADER
	_speed_lines.material = sm
	add_child(_speed_lines)
	_ring = PumpRing.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	add_child(_ring)
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


func hide_card() -> void:
	_card.visible = false


func set_mode_text(text: String) -> void:
	_mode.text = text


func set_speed_lines(strength: float) -> void:
	(_speed_lines.material as ShaderMaterial).set_shader_parameter("strength", clampf(strength, 0.0, 1.0))


func update_pump_ring(screen_pos: Vector2, readiness: float, show: bool) -> void:
	_ring.visible = show and readiness > 0.02
	_ring.position = screen_pos
	_ring.readiness = readiness


var _popup_stack := 0
var _popup_last := 0.0


func popup(text: String, screen_pos: Vector2, size: int, colour: Color) -> void:
	# A label that floats up and fades. Fire and forget. Popups within half a second stack upward.
	var now := Time.get_ticks_msec() / 1000.0
	_popup_stack = _popup_stack + 1 if now - _popup_last < 0.5 else 0
	_popup_last = now
	var l := _label(size, colour)
	l.text = text
	add_child(l)
	l.reset_size()
	l.position = screen_pos - Vector2(l.size.x * 0.5, l.size.y * 0.5) - Vector2(0.0, 44.0 * _popup_stack)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 80.0, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)


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
