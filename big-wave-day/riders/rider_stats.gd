## Per-animal board and feel. The animal you get decides the board's shape and how it rides;
## the board's colours are cosmetic and rolled separately every wave.
## Turning is derived from board length by the surfer (longer = slower, wider arcs); `agility`
## is a flavour multiplier on top of that, so two animals on the same length can still differ.
class_name RiderStats
extends Resource

@export var style_name := "board"         ## Shown on the card: "9'0\" red fish".
@export_group("Board shape")
@export var board_length := 2.7           ## Metres before visual_scale. Drives turn rate and snap rate.
@export var board_width := 0.62
@export_group("Feel")
@export var agility := 1.0                ## Multiplier on the length-derived turn rates. 1 = neutral.
@export var drag := 0.02                  ## Quadratic drag per metre. Lower = faster top end.
@export var pump_gain := 4.0              ## m/s added by a perfect pump.
