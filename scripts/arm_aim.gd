extends SkeletonModifier3D
class_name ArmAim
## Another player raising their camera: both hands reach up and hold the camera at their eye
## (two-bone IK, elbows down and a little out), on top of whatever the legs are doing, so they
## can walk with the camera up. The grip points ride on the head bone, so the hands follow
## wherever they look. RemotePlayer moves the camera itself from the chest to the face.
##
## Add it after HeadLook so the head's turn is already in place when the arms reach for it.
## Like HeadLook, it remembers the animation's own pose for each bone so the blend never
## stacks on last frame's output.

## 0 = arms down (whatever the animation does), 1 = camera fully up at the eye.
var weight:= 0.0
## Where each wrist goes, in rest-pose skeleton space (the camera sits at Player.FACE_CAMERA).
## x is mirrored per side.
const GRIP:= Vector3(0.105, 1.6, 0.17)
## Which way the elbows point: down, a little out, a little back.
const POLE:= Vector3(0.45, -1.0, -0.15)

var _sides: Array = []    # [{s, e, h, sx, l1, l2}]
var _head:= -1
var _head_rest_inv:= Transform3D.IDENTITY
var _base:= {}
var _written:= {}


func setup(model: CharacterModel) -> void:
	var sk:= model.skeleton
	if sk == null:
		return
	_head = sk.find_bone("head")
	if _head < 0:
		return
	_head_rest_inv = sk.get_bone_global_rest(_head).affine_inverse()
	for side in ["l", "r"]:
		var s:= sk.find_bone("shoulder_" + side)
		var e:= sk.find_bone("elbow_" + side)
		var h:= sk.find_bone("hand_" + side)
		if s < 0 or e < 0 or h < 0:
			continue
		var ps:= sk.get_bone_global_rest(s).origin
		var pe:= sk.get_bone_global_rest(e).origin
		var ph:= sk.get_bone_global_rest(h).origin
		_sides.append({"s": s, "e": e, "h": h, "sx": signf(ps.x) if absf(ps.x) > 0.001 else 1.0,
			"l1": ps.distance_to(pe), "l2": pe.distance_to(ph)})


func has_pose() -> bool:
	return not _sides.is_empty()


func _process_modification() -> void:
	var sk:= get_skeleton()
	if sk == null or _sides.is_empty():
		return
	# Remember the animation's pose (and undo our own output if the animation left it).
	for sd: Dictionary in _sides:
		for k in ["s", "e"]:
			var i: int = sd[k]
			var cur:= sk.get_bone_pose_rotation(i)
			if not (_written.has(i) and cur.is_equal_approx(_written[i])):
				_base[i] = cur
			sk.set_bone_pose_rotation(i, _base[i])
	var w:= clampf(weight, 0.0, 1.0)
	if w <= 0.001:
		for sd: Dictionary in _sides:
			for k in ["s", "e"]:
				_written[sd[k]] = _base[sd[k]]
		return
	var head_now:= sk.get_bone_global_pose(_head)
	var to_now:= head_now * _head_rest_inv   # rest-space point -> where it is with the head turned
	for sd: Dictionary in _sides:
		var si: int = sd["s"]
		var ei: int = sd["e"]
		var hi: int = sd["h"]
		var sx: float = sd["sx"]
		var l1: float = sd["l1"]
		var l2: float = sd["l2"]
		var gs:= sk.get_bone_global_pose(si)
		var ge:= sk.get_bone_global_pose(ei)
		var gh:= sk.get_bone_global_pose(hi)
		var a:= gs.origin
		var target:= to_now * Vector3(GRIP.x * sx, GRIP.y, GRIP.z)
		var pole:= (to_now.basis * Vector3(POLE.x * sx, POLE.y, POLE.z)).normalized()
		# Two-bone IK: where the elbow has to be for the wrist to land on the target.
		var to_t:= target - a
		var d:= clampf(to_t.length(), 0.05, (l1 + l2) * 0.999)
		var dir:= to_t.normalized()
		var along:= (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var up:= sqrt(maxf(0.0, l1 * l1 - along * along))
		var pn:= pole - dir * pole.dot(dir)
		if pn.length() < 0.001:
			pn = Vector3.DOWN
		pn = pn.normalized()
		var elbow_at:= a + dir * along + pn * up
		var wrist_at:= a + dir * d
		# Swing the upper arm onto the elbow, then the forearm onto the wrist (skeleton space).
		var q1:= _arc(ge.origin - a, elbow_at - a)
		var new_s:= Basis(q1) * gs.basis
		var fore_now:= Basis(q1) * (gh.origin - ge.origin)
		var q2:= _arc(fore_now, wrist_at - elbow_at)
		var new_e:= Basis(q2) * Basis(q1) * ge.basis
		var parent_s:= sk.get_bone_parent(si)
		var pg:= sk.get_bone_global_pose(parent_s).basis if parent_s >= 0 else Basis.IDENTITY
		var local_s:= (pg.inverse() * new_s).get_rotation_quaternion()
		var local_e:= (new_s.inverse() * new_e).get_rotation_quaternion()
		var out_s: Quaternion = (_base[si] as Quaternion).slerp(local_s, w)
		var out_e: Quaternion = (_base[ei] as Quaternion).slerp(local_e, w)
		sk.set_bone_pose_rotation(si, out_s)
		sk.set_bone_pose_rotation(ei, out_e)
		_written[si] = out_s
		_written[ei] = out_e


## The rotation that turns direction u onto direction v.
static func _arc(u: Vector3, v: Vector3) -> Quaternion:
	if u.length() < 0.0001 or v.length() < 0.0001:
		return Quaternion.IDENTITY
	var a:= u.normalized()
	var b:= v.normalized()
	if a.dot(b) < -0.9999:
		var axis:= a.cross(Vector3.UP)
		if axis.length() < 0.001:
			axis = a.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(a, b)
