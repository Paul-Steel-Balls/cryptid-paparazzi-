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
