extends RefCounted
class_name Catalog
## Everything the bait & trap stand sells. One table: add a row to add an item.
##
## kind "gear":    consumables you carry (max GameState.MAX_ITEMS each)
## kind "poster":  hang on the poster wall in the RV. "needs": a species you must have
##                 photographed first (the stand only stocks cryptids you've proven exist).
## kind "trinket": decorations that show up in (or outside) the RV once bought.

const ITEMS:= {
	"bait": {"kind": "gear", "name": "MYSTERY MEAT", "price": 100, "key": 1,
		"blurb": "Drop it with Q. Hungry cryptids stop to eat. Great photos, bad smell."},
	"trap": {"kind": "gear", "name": "BEAR TRAP", "price": 200, "key": 2,
		"blurb": "Drop it with Q. Holds whatever steps in. Including you."},
	"tripod": {"kind": "gear", "name": "TRIPOD CAM", "price": 1500, "key": 3,
		"blurb": "Single-use trail camera. Q sets it up facing where you look; it snaps the first thing that walks right past it (within 6 m). Anything. Including you."},
	"joint": {"kind": "gear", "name": "JOINT", "price": 400, "key": 4,
		"blurb": "Q to light up. For about 12 seconds the world slows right down. Photos taken high pay half (shaky hands)."},
	"beer": {"kind": "gear", "name": "BEER", "price": 150, "key": 5,
		"blurb": "Q to crack one. Faster legs for 25 seconds, but louder, and photos taken buzzed pay half."},

	"poster_believe": {"kind": "poster", "name": "I WANT TO BELIEVE", "price": 0, "portrait": "bigboobs",
		"caption": "I WANT TO BELIEVE", "bg": Color(0.12, 0.1, 0.2), "ink": Color(1.0, 0.9, 0.6), "starter": true},
	"poster_corn": {"kind": "poster", "name": "CORN IS A STATE OF MIND", "price": 300, "portrait": "cornicorn", "needs": "cornicorn",
		"caption": "CORN IS A STATE OF MIND", "bg": Color(0.35, 0.65, 0.3), "ink": Color(1.0, 0.95, 0.4)},
	"poster_tourist": {"kind": "poster", "name": "THE TRUTH IS OUT THERE", "price": 300, "portrait": "grey_tourist", "needs": "grey_tourist",
		"caption": "THE TRUTH IS OUT THERE\n(ON VACATION)", "bg": Color(0.1, 0.55, 0.65), "ink": Color(1, 1, 1)},
	"poster_moth": {"kind": "poster", "name": "MOTH TO A FLAME", "price": 400, "portrait": "methman", "needs": "methman",
		"caption": "MOTH TO A FLAME", "bg": Color(0.2, 0.12, 0.08), "ink": Color(1.0, 0.7, 0.25)},
	"poster_devils": {"kind": "poster", "name": "GO DEVILS!", "price": 400, "portrait": "jersey_devil", "needs": "jersey_devil",
		"caption": "GO DEVILS!", "bg": Color(0.75, 0.1, 0.1), "ink": Color(1, 1, 1)},
	"poster_crack": {"kind": "poster", "name": "IT'S 5 O'CLOCK SOMEWHERE", "price": 300, "portrait": "crackin", "needs": "crackin",
		"caption": "IT'S 5 O'CLOCK\nSOMEWHERE", "bg": Color(0.95, 0.6, 0.2), "ink": Color(0.2, 0.08, 0.05)},
	"poster_pogo": {"kind": "poster", "name": "HANG IN THERE, EH", "price": 400, "portrait": "oh_go_pogo", "needs": "oh_go_pogo",
		"caption": "HANG IN THERE, EH", "bg": Color(0.6, 0.85, 0.95), "ink": Color(0.75, 0.1, 0.1)},
	"poster_bigboobs": {"kind": "poster", "name": "SUPPORT YOUR LOCAL BIGFOOT", "price": 600, "portrait": "bigboobs", "needs": "bigboobs",
		"caption": "SUPPORT YOUR\nLOCAL BIGFOOT", "bg": Color(0.95, 0.4, 0.7), "ink": Color(1, 1, 1)},
	"poster_wolf": {"kind": "poster", "name": "NOT ALL WHO WANDER ARE LOST", "price": 1000, "portrait": "wherewolf", "needs": "wherewolf",
		"caption": "NOT ALL WHO WANDER\nARE LOST. HE IS.", "bg": Color(0.15, 0.2, 0.4), "ink": Color(0.95, 0.95, 0.8)},
	"poster_toe": {"kind": "poster", "name": "THE TOE ROGAN EXPERIENCE", "price": 500, "portrait": "toe_rogan",
		"caption": "THE TOE ROGAN\nEXPERIENCE", "bg": Color(0.08, 0.08, 0.08), "ink": Color(0.95, 0.2, 0.15)},

	"fuzzy_dice": {"kind": "trinket", "name": "FUZZY DICE", "price": 300,
		"blurb": "Hang from the RV's mirror. +10 style. +0 everything else."},
	"lava_lamp": {"kind": "trinket", "name": "LAVA LAMP", "price": 450,
		"blurb": "Goes on the kitchen counter. Very groovy. Do not drink."},
	"toe_bobblehead": {"kind": "trinket", "name": "TOE ROGAN BOBBLEHEAD", "price": 600,
		"blurb": "For the dashboard. Nods along to every bump in the road."},
	"flamingo": {"kind": "trinket", "name": "LAWN FLAMINGO", "price": 350,
		"blurb": "Stands guard by the RV door. Cryptids find it unsettling (they don't)."},
}

const POSTER_SLOTS:= 6


static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func ids_of(kind: String) -> Array:
	var out: Array = []
	for id in ITEMS:
		if ITEMS[id]["kind"] == kind:
			out.append(id)
	return out


## Is it on the shelf yet? Posters of a cryptid appear once you've developed a photo of it.
static func in_stock(id: String) -> bool:
	var it:= item(id)
	if it.has("needs"):
		return GameState.has_photo(str(it["needs"]))
	return true


static func owned(id: String) -> bool:
	return id in GameState.owned_items
