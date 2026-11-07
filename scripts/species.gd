extends RefCounted
class_name Species
## Every cryptid's stats, and which maps they live on at what rarity.
## Tune the game here: this is the one table to edit.
##
## behaviour:
##   "hunter"   notices you, chases, grabs you (night over, film lost)
##   "skittish" bolts away when it notices you or gets flashed
##   "lazy"     ignores you unless flashed up close, then a slow, grumpy chase

const DATA:= {
	"bigboobs": {
		"name": "Bigboobs", "model": "res://models/bigboobs.glb", "outline": 0.014,
		"radius": 0.55, "height": 2.4, "photo_h": 1.7,
		"behaviour": "hunter", "walk": 3.5, "chase": 6.0, "hear": 25.0, "trigger": 12.0, "flash": 25.0,
		"los_break": 4.0, "lose_time": 3.0, "voice": "bigfoot", "steps": "bigstep",
	},
	"methman": {
		"name": "Methman", "model": "res://models/methman.glb", "outline": 0.012,
		"radius": 0.45, "height": 2.1, "photo_h": 1.6,
		"behaviour": "hunter", "walk": 3.8, "chase": 6.3, "hear": 32.0, "trigger": 10.0, "flash": 22.0,
		"los_break": 2.5, "lose_time": 2.0, "voice": "methman", "steps": "midstep",
		"home": "methman_camp", "home_radius": 26.0,
	},
	"jersey_devil": {
		"name": "Jersey Devil", "model": "res://models/jersey_devil.glb", "outline": 0.012,
		"radius": 0.4, "height": 2.15, "photo_h": 1.7,
		"behaviour": "hunter", "walk": 3.2, "chase": 6.4, "hear": 22.0, "trigger": 11.0, "flash": 22.0,
		"los_break": 3.5, "lose_time": 3.0, "voice": "jersey", "steps": "midstep", "victory_anim": "cheer",
		"home": "tailgate", "home_radius": 30.0,
		## Every so often he lets out a "WOOO!" you can hear from far off. Follow it.
		"call_every": [14.0, 26.0],
	},
	"oh_go_pogo": {
		"name": "Oh-Go-Pogo", "model": "res://models/oh_go_pogo.glb", "outline": 0.012,
		"radius": 0.35, "height": 1.95, "photo_h": 1.5,
		"behaviour": "hunter", "walk": 2.8, "chase": 5.8, "hear": 24.0, "trigger": 11.0, "flash": 22.0,
		"los_break": 4.0, "lose_time": 3.0, "voice": "pogo", "steps": "boing", "step_every": 1.4,
		"water_lover": true,
	},
	"grey_tourist": {
		"name": "Grey Tourist", "model": "res://models/grey_tourist.glb", "outline": 0.01,
		"radius": 0.3, "height": 1.4, "photo_h": 1.2,
		"behaviour": "skittish", "walk": 2.6, "chase": 8.2, "hear": 18.0, "trigger": 10.0, "flash": 20.0,
		"voice": "grey", "steps": "midstep", "group": [2, 3], "snaps_back": true, "stun": 2.5,
	},
	"cornicorn": {
		"name": "Cornicorn", "model": "res://models/cornicorn.glb", "outline": 0.012,
		"radius": 0.4, "height": 2.1, "photo_h": 1.5,
		"behaviour": "skittish", "walk": 2.6, "chase": 7.0, "hear": 26.0, "trigger": 11.0, "flash": 24.0,
		"voice": "corn", "steps": "hoof", "step_every": 0.5,
	},
	"crackin": {
		"name": "Crackin'", "model": "res://models/crackin.glb", "outline": 0.012,
		"radius": 0.45, "height": 2.15, "photo_h": 1.6,
		"behaviour": "lazy", "walk": 1.6, "chase": 3.2, "hear": 12.0, "trigger": 4.0, "flash": 10.0,
		"los_break": 3.0, "lose_time": 2.0, "voice": "crackin", "steps": "midstep", "water_lover": true,
	},
	"fhairy": {
		"name": "F'hairy", "model": "res://models/fhairy.glb", "outline": 0.012,
		"radius": 0.45, "height": 1.95, "photo_h": 1.5,
		"behaviour": "skittish", "walk": 2.3, "chase": 6.4, "hear": 22.0, "trigger": 10.0, "flash": 22.0,
		"voice": "fhairy", "steps": "midstep", "water_lover": true,
	},
	"leperchaun": {
		"name": "Leperchaun", "model": "res://models/leperchaun.glb", "outline": 0.01,
		"radius": 0.3, "height": 1.3, "photo_h": 0.95,
		"behaviour": "hunter", "walk": 2.8, "chase": 6.6, "hear": 24.0, "trigger": 9.0, "flash": 20.0,
		"los_break": 3.0, "lose_time": 3.0, "voice": "leper", "steps": "midstep", "step_every": 0.6,
		"home": "pot_of_gold", "home_radius": 16.0, "victory_anim": "jig",
	},
	"the_rake": {
		"name": "The Rake", "model": "res://models/the_rake.glb", "outline": 0.012,
		"radius": 0.35, "height": 2.75, "photo_h": 2.3,
		## Only moves while you're not looking at it.
		"behaviour": "stalker", "walk": 2.2, "chase": 7.5, "hear": 30.0, "trigger": 18.0, "flash": 28.0,
		"los_break": 6.0, "lose_time": 5.0, "voice": "rake", "steps": "midstep",
	},
	"bent": {
		"name": "bEnt", "model": "res://models/bent.glb", "outline": 0.014,
		"radius": 0.5, "height": 2.7, "photo_h": 1.9,
		"behaviour": "lazy", "walk": 1.1, "chase": 2.6, "hear": 12.0, "trigger": 4.5, "flash": 9.0,
		"los_break": 3.0, "lose_time": 2.0, "voice": "bent", "steps": "bigstep", "step_every": 1.3,
	},
	## Not on any roster: special visitors (see main.gd). "pay" overrides the tier multiplier.
	"santa": {"name": "Santa Claus", "model": "res://models/santa_sleigh.glb", "photo_h": 1.4, "pay": 20.0, "behaviour": "visitor"},
	"ufo": {"name": "UFO", "photo_h": 0.0, "pay": 3.0, "behaviour": "visitor"},   # built in code (scripts/ufo.gd)
	"wherewolf": {
		"name": "Where-wolf", "model": "res://models/wherewolf.glb", "outline": 0.012,
		"radius": 0.4, "height": 2.15, "photo_h": 1.7,
		"behaviour": "skittish", "walk": 2.5, "chase": 6.5, "hear": 28.0, "trigger": 12.0, "flash": 26.0,
		"voice": "wolf", "steps": "midstep",
	},
}

## Map rosters. A map is unlocked by showing Toe Rogan a photo of every
## common and uncommon cryptid on the current map.
const MAPS:= {
	"woods": {
		"name": "Deep Woods", "ambience": "woods", "where": "in these woods",
		"common": ["cornicorn", "grey_tourist"],
		"uncommon": ["leperchaun", "bent"],
		"rare": ["bigboobs"],
		"legendary": ["wherewolf"],
	},
	"lake": {
		"name": "Lakeside", "ambience": "lake", "where": "around this lake",
		"common": ["fhairy", "grey_tourist"],
		"uncommon": ["oh_go_pogo", "cornicorn"],
		"rare": ["bigboobs"],
		"legendary": ["wherewolf"],
	},
	"city": {
		"name": "The City", "ambience": "city", "where": "in this city",
		"common": ["methman", "grey_tourist"],
		"uncommon": ["crackin", "jersey_devil"],
		"rare": ["the_rake"],
		"legendary": ["wherewolf"],
	},
}
const MAP_ORDER:= ["woods", "lake", "city"]
## How many separate groups of each roaming common turn up per night.
const COMMON_HERDS:= 2
## Santa turns up on top of the RV about once a year of nights, on any map.
const SANTA_CHANCE:= 1.0 / 365.0

## How each map looks. Anything a map doesn't set comes from STYLE_DEFAULT.
## To add a map: add a MAPS entry (roster), a STYLES entry (look), and its id to MAP_ORDER.
## "terrain": "hills" (rolling woods) or "lake" (a big lake in the middle).
const STYLE_DEFAULT:= {
	"terrain": "hills", "seed": 1111,
	"trees": 420, "tree_gap": 3.0, "autumn": 0.18, "trunk": Color(0.45, 0.3, 0.15), "pine_share": 1.0,
	"rock_tint": Color(0.5, 0.5, 0.55),
	"greens": [Color(0.1, 0.55, 0.2), Color(0.18, 0.62, 0.24), Color(0.06, 0.45, 0.16), Color(0.12, 0.5, 0.3)],
	"bushes": 110, "ferns": 0, "mushrooms": 0, "flowers": 500, "rocks": 22, "fireflies": false,
	"grass": Color(0.22, 0.52, 0.22), "lush": Color(0.16, 0.44, 0.2), "dry": Color(0.42, 0.55, 0.24),
	"sky": Color(0.1, 0.08, 0.28), "fog": Color(0.16, 0.13, 0.33), "fog_density": 0.0025,
	"ambient": Color(0.35, 0.3, 0.55), "ambient_energy": 0.8, "moon_energy": 1.2,
}
const STYLES:= {
	# Deep Woods: dense, dark and close. Thick undergrowth, ferns, glowing mushrooms, fireflies.
	"woods": {
		"seed": 1111, "trees": 720, "tree_gap": 2.4, "autumn": 0.06, "rock_tint": Color(0.35, 0.5, 0.3),
		"greens": [Color(0.08, 0.5, 0.22), Color(0.12, 0.57, 0.27), Color(0.06, 0.42, 0.2), Color(0.14, 0.52, 0.33)],
		"bushes": 360, "ferns": 900, "mushrooms": 80, "flowers": 120, "rocks": 30, "fireflies": true,
		"grass": Color(0.13, 0.36, 0.17), "lush": Color(0.09, 0.3, 0.15), "dry": Color(0.25, 0.4, 0.18),
		"sky": Color(0.05, 0.05, 0.16), "fog": Color(0.08, 0.16, 0.15), "fog_density": 0.0045,
		"ambient": Color(0.25, 0.33, 0.42), "ambient_energy": 0.7, "moon_energy": 1.05,
	},
	# The City: towers, streets, a river with a bridge, an overpass with an encampment under it.
	"city": {
		"terrain": "city", "seed": 3333, "trees": 0, "bushes": 0, "ferns": 0, "mushrooms": 0, "flowers": 0, "rocks": 0,
		"grass": Color(0.2, 0.42, 0.22), "lush": Color(0.18, 0.38, 0.2), "dry": Color(0.3, 0.4, 0.22),
		"sky": Color(0.13, 0.08, 0.17), "fog": Color(0.3, 0.2, 0.26), "fog_density": 0.003,
		"ambient": Color(0.45, 0.38, 0.48), "ambient_energy": 0.9, "moon_energy": 0.9,
	},
	# Lakeside: open and airy. Pale birches in autumn colours, meadows of flowers, a big sky.
	"lake": {
		"terrain": "lake", "seed": 2222, "trees": 190, "tree_gap": 4.0, "autumn": 0.5, "trunk": Color(0.86, 0.84, 0.78),
		"pine_share": 0.3, "rock_tint": Color(0.62, 0.6, 0.55),
		"greens": [Color(0.3, 0.62, 0.25), Color(0.4, 0.7, 0.3), Color(0.25, 0.55, 0.3)],
		"bushes": 60, "ferns": 0, "mushrooms": 0, "flowers": 800, "rocks": 16,
		"grass": Color(0.36, 0.6, 0.28), "lush": Color(0.28, 0.54, 0.26), "dry": Color(0.58, 0.62, 0.32),
		"sky": Color(0.1, 0.14, 0.36), "fog": Color(0.22, 0.28, 0.5), "fog_density": 0.0016,
		"ambient": Color(0.42, 0.44, 0.65), "ambient_energy": 0.95, "moon_energy": 1.35,
	},
}


static func style(map_id: String) -> Dictionary:
	var out:= STYLE_DEFAULT.duplicate()
	out.merge(STYLES.get(map_id, {}), true)
	return out
const TIERS:= ["common", "uncommon", "rare", "legendary"]
## Chance a species of this tier shows up on a given night.
const SPAWN_CHANCE:= {"common": 1.0, "uncommon": 0.65, "rare": 0.3, "legendary": 0.005}
## Photo pay multiplier by tier.
const PAY:= {"common": 1.0, "uncommon": 1.5, "rare": 2.5, "legendary": 5.0}


static func info(id: String) -> Dictionary:
	return DATA.get(id, DATA["bigboobs"])


static func display_name(id: String) -> String:
	return str(info(id).get("name", id))


static func tier_on(map_id: String, id: String) -> String:
	var m: Dictionary = MAPS.get(map_id, {})
	for t in TIERS:
		if id in m.get(t, []):
			return t
	return "common"


static func pay_mult(map_id: String, id: String) -> float:
	var info_d:= info(id)
	if info_d.has("pay"):
		return float(info_d["pay"])
	return float(PAY[tier_on(map_id, id)])


## Who shows up tonight: [{id, count}]. Commons always; others roll.
static func roll_night(map_id: String, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var m: Dictionary = MAPS[map_id]
	for t in TIERS:
		for id in m[t]:
			if rng.randf() < float(SPAWN_CHANCE[t]):
				var g: Array = info(id).get("group", [1, 1])
				# v0.16: the maps are 3x the ground they started with, so commons
				# that roam (no fixed home) turn up in more than one spot.
				var herds:= COMMON_HERDS if t == "common" and not info(id).has("home") else 1
				for _h in herds:
					out.append({"id": id, "count": rng.randi_range(int(g[0]), int(g[1]))})
	return out


## The species Toe Rogan wants to see before unlocking the next map.
static func required_for_unlock(map_id: String) -> Array:
	var m: Dictionary = MAPS[map_id]
	return m["common"] + m["uncommon"]


static func next_map(map_id: String) -> String:
	var i:= MAP_ORDER.find(map_id)
	return MAP_ORDER[i + 1] if i >= 0 and i + 1 < MAP_ORDER.size() else ""
