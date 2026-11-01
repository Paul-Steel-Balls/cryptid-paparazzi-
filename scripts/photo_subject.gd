extends Node3D
class_name PhotoSubject
## Something you can photograph that isn't a walking cryptid: the UFO, Santa on the RV roof.
## Player.extra_subjects holds these; photos score them exactly like cryptids
## (PhotoScoring + Species.pay_mult, which honours a "pay" override in Species.DATA).

var species_id:= ""
var display_name:= ""
var state: int = PhotoScoring.CryptidState.WANDER
var photo_offset:= Vector3(0, 1, 0)
var face_dir:= Vector3(0, 0, 1)


func photo_point() -> Vector3:
	return global_position + photo_offset


func get_facing() -> Vector3:
	return face_dir


func on_flash(_from: Vector3) -> void:
	pass


func on_device_flash(_pos: Vector3) -> void:
	pass


func hear_noise(_pos: Vector3, _radius: float = -1.0) -> void:
	pass
