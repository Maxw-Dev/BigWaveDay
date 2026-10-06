class_name Rider
extends Node3D

@export var y_offset: float = 0
@export var scale_mod: float = 1
@export var rider_width: float = 0.62
@export var end_screen_color: Color = Color.WHITE

@export var model: Node3D
@export var stats: RiderStats          ## Feel numbers for this rider. Null = keep the surfer's own values.

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	model.scale = Vector3(scale_mod, scale_mod, scale_mod)
