class_name Rider
extends Node3D

@export var y_offset: float = 0
@export var scale_mod: float = 1
@export var rider_width: float = 0.62

@export var model: Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	model.scale = Vector3(scale_mod, scale_mod, scale_mod)
