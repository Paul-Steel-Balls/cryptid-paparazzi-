extends RefCounted
class_name PhotoScoring



enum CryptidState {WANDER, INVESTIGATE, CHASE, CAUGHT, EATING, TRAPPED, FLEE}

const GROUP_BONUS:= 0.25   # each extra cryptid in the same shot

const TRAPPED_MULT:= 1.3

const MAX_RANGE:= 35.0
const HALF_FRAME_ANGLE_DEG:= 40.0


## zoom: the zoom lens (1-2x) narrows the frame and makes the subject count as zoom times closer.
static func evaluate(cryptid_pos: Vector3, cryptid_facing: Vector3, camera_pos: Vector3, camera_forward: Vector3, cryptid_state: int, zoom: float = 1.0) -> Dictionary:
	var result:= {
		"in_frame": false,
		"score": 0,
		"reason": "",
		"facing": false,
		"danger": false,
		"distance": 0.0,
	}
	var to_cryptid:= cryptid_pos - camera_pos
	var real_dist:= to_cryptid.length()
	result["distance"] = real_dist
	var dist:= real_dist / maxf(zoom, 1.0)
	if dist > MAX_RANGE:
		result["reason"] = "Too far away!"
		return result
	if real_dist < 0.5:
		result["reason"] = "Too close to see!"
		return result
	var dir:= to_cryptid / real_dist
	var dot:= dir.dot(camera_forward.normalized())
	var angle_deg:= rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
	if angle_deg > HALF_FRAME_ANGLE_DEG / maxf(zoom, 1.0):
		result["reason"] = "Cryptid not in frame"
		return result
	var to_camera:= (camera_pos - cryptid_pos).normalized()
	var facing:= cryptid_facing.normalized().dot(to_camera) > 0.3
	var dist_score: float
	if dist <= 8.0:
		dist_score = 30.0
	elif dist <= 25.0:
		dist_score = 30.0 - (dist - 8.0) * (25.0 / 17.0)
	else:
		dist_score = 5.0
	var base:= 20.0 + dist_score
	if facing:
		base += 15.0
	var danger:= cryptid_state == CryptidState.CHASE or cryptid_state == CryptidState.INVESTIGATE
	var mult:= 1.5 if danger else 1.0
	var trapped:= cryptid_state == CryptidState.TRAPPED
	if trapped:
		mult = TRAPPED_MULT
	var score:= int(round(base * mult))
	result["in_frame"] = true
	result["score"] = score
	result["facing"] = facing
	result["danger"] = danger
	result["trapped"] = trapped
	if trapped:
		result["reason"] = "TRAPPED! TABLOID GOLD!" if score >= 50 else "Caught in a trap!"
	elif score >= 60:
		result["reason"] = "AMAZING SHOT!"
	elif score >= 35:
		result["reason"] = "GREAT SHOT!"
	else:
		result["reason"] = "Got it!"
	return result
