extends OmniLight3D
## A fire glow that won't sit still.

var _base:= -1.0
var _t:= 0.0


func _process(delta: float) -> void:
	if _base < 0.0:
		_base = light_energy
	_t += delta
	light_energy = _base * (0.8 + 0.12 * sin(_t * 11.0) + 0.08 * sin(_t * 23.7 + 1.3))
