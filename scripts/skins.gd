extends RefCounted
class_name Skins
## Outfits from DRIP CITY, the costume shop in the City (models: tools/skins.py ->
## models/photographer_<id>.glb). Buy them there; change into anything you own at the shop
## or the closet in the RV. Purely for looks (and for your friends' photos of you).
##
## cam_z / face_z: how far in front of the body the camera hangs (chest) or sits when raised
## (face), so it isn't swallowed by a big costume.

const DEFAULT:= "default"
const CATALOG:= {
	"default": {"name": "Field Vest", "price": 0, "cam_z": 0.19, "face_z": 0.205,
		"blurb": "The classic: vest, jeans, lucky red cap. Pockets for film, none for dignity."},
	"hawaiian": {"name": "Hawaiian Dad", "price": 600, "cam_z": 0.19, "face_z": 0.205,
		"blurb": "Loud shirt, cargo shorts, socks with sandals, zinc on the nose, fanny pack. Blends in with the tourists. The alien ones."},
	"superfan": {"name": "Toe Superfan", "price": 900, "cam_z": 0.19, "face_z": 0.205,
		"blurb": "Official Toe Rogan merch and a giant foam toe hat. Toe has never been prouder. Toe has never been more uncomfortable."},
	"ghillie": {"name": "Ghillie Suit", "price": 1200, "cam_z": 0.24, "face_z": 0.215,
		"blurb": "Military-grade shrubbery. Cryptids still see you fine; it's the principle of the thing."},
	"bigfoot": {"name": "Bigfoot Onesie", "price": 1500, "cam_z": 0.23, "face_z": 0.215,
		"blurb": "Fleece, googly eyes, slippers with toes. Bigboobs will be either flattered or furious."},
	"clown": {"name": "Clown", "price": 1800, "cam_z": 0.22, "face_z": 0.24,
		"blurb": "Rainbow wig, honking red nose, shoes you can't run in (you can, it's a game). Scares the Rake. Maybe."},
	"banana": {"name": "Banana", "price": 2000, "cam_z": 0.31, "face_z": 0.215,
		"blurb": "Ripe. Peelable. Do not slip on the photographer."},
	"hotdog": {"name": "Hot Dog", "price": 2000, "cam_z": 0.26, "face_z": 0.215,
		"blurb": "All-beef, full-body, mustard AND ketchup. The hot dog cart guy is taking it personally."},
	"disco": {"name": "Disco King", "price": 2500, "cam_z": 0.19, "face_z": 0.215,
		"blurb": "Gold sequins, an afro you could lose a trap in, bell-bottoms, platforms. Night fever, cryptid fever."},
	"pirate": {"name": "Pirate Captain", "price": 2800, "cam_z": 0.19, "face_z": 0.205,
		"blurb": "Tricorn, eye patch (hope it's your bad eye), ginger beard, and a parrot who's seen things."},
	"astronaut": {"name": "Astronaut", "price": 3000, "cam_z": 0.26, "face_z": 0.29,
		"blurb": "Gold visor, life support, a flag on the shoulder. The UFO will have SO many questions."},
	"shark": {"name": "Shark Attack", "price": 3200, "cam_z": 0.31, "face_z": 0.225,
		"blurb": "Your face, in a shark's mouth, with all the teeth. Oh-Go-Pogo's natural enemy."},
	"trex": {"name": "Inflatable T-Rex", "price": 3500, "cam_z": 0.36, "face_z": 0.215,
		"blurb": "Eight feet of air and attitude. Tiny arms. Huge tail. Zero stealth."},
	"tux": {"name": "Tinfoil Tux", "price": 4000, "cam_z": 0.19, "face_z": 0.205,
		"blurb": "Black tie, monocle, and a hand-crimped tinfoil hat with antenna. For when you finally get invited to the saucer."},
}


static func ids() -> Array:
	var out:= CATALOG.keys()
	out.sort_custom(func(a, b): return int(CATALOG[a]["price"]) < int(CATALOG[b]["price"]))
	return out


static func info(id: String) -> Dictionary:
	return CATALOG.get(id, CATALOG[DEFAULT])


static func model_path(id: String) -> String:
	if id == DEFAULT or not CATALOG.has(id):
		return "res://models/photographer.glb"
	return "res://models/photographer_%s.glb" % id


## The team cap goes on top of the sculpted red one: only the classic outfit has a cap.
static func has_cap(id: String) -> bool:
	return id == DEFAULT or not CATALOG.has(id)


## How each kind of floppy bit behaves: [stiffness, drag, gravity, length of the last piece].
## Low stiffness = floppier. (Bones named jig_<chain><side>_<n> in tools/skins.py.)
const SPRINGS:= {
	"neck": [0.9, 0.25, 0.25, 0.3], "tail": [0.55, 0.22, 0.5, 0.2], "arm": [0.7, 0.2, 0.9, 0.16],
	"stem": [1.4, 0.35, 0.2, 0.14], "top": [1.1, 0.3, 0.2, 0.12], "bun": [2.2, 0.45, 0.0, 0.5],
	"fin": [1.3, 0.35, 0.1, 0.18], "dorsal": [1.5, 0.35, 0.0, 0.2], "ear": [1.1, 0.3, 0.3, 0.1],
	"puff": [0.9, 0.22, 0.3, 0.12], "pufft": [0.9, 0.22, 0.3, 0.12], "parrot": [1.6, 0.4, 0.1, 0.16],
	"coat": [0.8, 0.3, 1.0, 0.2], "toe": [0.6, 0.2, 0.4, 0.2], "ant": [0.7, 0.12, 0.3, 0.12],
	"fro": [1.6, 0.4, 0.2, 0.2], "pack": [1.4, 0.4, 0.6, 0.08], "leaf": [1.0, 0.3, 0.5, 0.08],
	"beard": [1.8, 0.45, 0.4, 0.1],
}


## Give every floppy bone in a costume a spring (Godot's SpringBoneSimulator3D), so dino heads
## flop, tails swish, ears and wigs bounce. Call after any HeadLook / ArmAim so the springs
## react to the final pose. Returns null for outfits with nothing floppy.
static func add_springs(model: CharacterModel) -> SpringBoneSimulator3D:
	if model == null or model.skeleton == null:
		return null
	var sk:= model.skeleton
	var chains:= {}   # chain id -> [[n, bone name], ...]
	for i in sk.get_bone_count():
		var bn:= sk.get_bone_name(i)
		if not bn.begins_with("jig_"):
			continue
		var parts:= bn.split("_")
		if parts.size() < 3:
			continue
		var chain:= parts[1]
		if not chains.has(chain):
			chains[chain] = []
		chains[chain].append([int(parts[2]), bn])
	if chains.is_empty():
		return null
	var sim:= SpringBoneSimulator3D.new()
	sim.name = "CostumeSprings"
	sim.set_setting_count(chains.size())
	var k:= 0
	for chain: String in chains:
		var list: Array = chains[chain]
		list.sort_custom(func(a, b): return a[0] < b[0])
		# "earl" / "finr" / "leaf12" -> the kind of bit it is.
		var kind:= chain
		for key: String in SPRINGS:
			if chain.begins_with(key) and key.length() > (kind.length() if SPRINGS.has(kind) else 0):
				kind = key
		var p: Array = SPRINGS.get(kind, [1.0, 0.3, 0.3, 0.12])
		sim.set_root_bone_name(k, str(list[0][1]))
		sim.set_end_bone_name(k, str(list.back()[1]))
		sim.set_extend_end_bone(k, true)
		sim.set_end_bone_direction(k, SpringBoneSimulator3D.BONE_DIRECTION_FROM_PARENT)
		sim.set_end_bone_length(k, float(p[3]))
		sim.set_stiffness(k, float(p[0]))
		sim.set_drag(k, float(p[1]))
		sim.set_gravity(k, float(p[2]))
		k += 1
	sk.add_child(sim)
	return sim
