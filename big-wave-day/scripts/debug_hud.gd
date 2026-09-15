## Numbers first, feel second. Everything the tuning pass needs, in one label.
extends CanvasLayer

@export_node_path("Node3D") var surfer_path: NodePath = ^"../Surfer"
@export_node_path("Node3D") var wave_path: NodePath = ^"../Wave"
@export_node_path("Node3D") var run_path: NodePath = ^".."

var surfer: Surfer
var wave: Wave
var run: SurfPrototype

@onready var label: Label = $Label


func _ready() -> void:
	surfer = get_node_or_null(surfer_path) as Surfer
	wave = get_node_or_null(wave_path) as Wave
	run = get_node_or_null(run_path) as SurfPrototype
	if surfer == null or wave == null or run == null:
		push_warning("DebugHud: a node path did not resolve")


func _process(_delta: float) -> void:
	if surfer == null or wave == null or run == null:
		return
	var lines := PackedStringArray()
	lines.append("Wave %d   %.1f s left of %.1f s" % [run.wave_count, maxf(run.time_left, 0.0), run.wave_duration])
	lines.append("speed %.1f m/s   heading %+.0f deg   turning %s   %s   hold %.2f s" % [
		surfer.speed(), surfer.heading_deg(),
		"UP (toward lip)" if surfer.turn_dir == 1 else "DOWN (toward flats)",
		"SHARP" if surfer.is_sharp else "carve",
		surfer.hold_time])
	lines.append("last pump %.2f   (%.1f s ago)" % [surfer.last_pump_quality, minf(surfer.time_since_pump, 99.9)])
	lines.append("u %.1f   s %.1f / %.1f   foam u %.1f   lead %.1f m" % [
		surfer.pos.x, surfer.pos.y, surfer.shape.arc_length, wave.foam_u, surfer.pos.x - wave.foam_u])
	lines.append("last wave: %s (%.1f s)" % [run.last_reason, run.last_wave_time])
	lines.append("tap = flip turn   hold = sharp turn   [Space / Left mouse / Gamepad A]")
	if not surfer.is_live:
		lines.append("")
		lines.append(">>> press to drop in <<<")
	label.text = "\n".join(lines)
