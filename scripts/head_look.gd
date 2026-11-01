extends SkeletonModifier3D
class_name HeadLook
## Turns the neck/head (and a little of the chest) on top of whatever the animation is doing,
## so the photographer keeps looking at the reticle while his body faces where he's moving.
## yaw: + turns the head to the character's left. pitch: + tips it down.
##
## Bones the current animation doesn't key keep last frame's pose, so the turn is always
## applied to the animation's own pose (remembered here), never stacked on top of last
## frame's turn. Stacking is what left his head stuck looking over his shoulder.

var yaw:= 0.0
var pitch:= 0.0
## Share of the turn taken by each bone (adds up to 1).
const SPLIT:= {"chest": 0.2, "neck": 0.35, "head": 0.45}
const MAX_YAW:= 1.35
const MAX_PITCH:= 0.7

var _base:= {}      # bone index -> pose from the animation (before our turn)
var _written:= {}   # bone index -> pose we wrote last frame


func _process_modification() -> void:
	var sk:= get_skeleton()
	if sk == null:
		return
	var y:= clampf(yaw, -MAX_YAW, MAX_YAW)
	var p:= clampf(pitch, -MAX_PITCH, MAX_PITCH)
	for bone in SPLIT:
		var i:= sk.find_bone(bone)
		if i < 0:
			continue
		var current:= sk.get_bone_pose_rotation(i)
		# If the pose is still exactly what we wrote, the animation didn't touch this bone
		# this frame: start again from the animation's pose, not from our own output.
		if not (_written.has(i) and current.is_equal_approx(_written[i])):
			_base[i] = current
		var k: float = SPLIT[bone]
		var extra:= Quaternion(Vector3.UP, y * k) * Quaternion(Vector3.RIGHT, p * k)
		var out: Quaternion = extra * _base[i]
		sk.set_bone_pose_rotation(i, out)
		_written[i] = out
