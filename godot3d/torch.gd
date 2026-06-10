extends OmniLight3D

var phase := randf() * TAU
var base := 0.0
var t := 0.0


func _ready() -> void:
	base = light_energy


func _process(delta: float) -> void:
	t += delta
	light_energy = base * (1.0 + 0.22 * sin(t * 11.0 + phase)
			+ 0.1 * sin(t * 23.0 + phase * 2.0))
