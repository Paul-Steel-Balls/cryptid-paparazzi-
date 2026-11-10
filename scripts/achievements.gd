extends Node
## Achievements (autoload "Achievements"). Kept in their own file, separate from the save, so
## starting a new game doesn't wipe them. Each PC tracks its own player's achievements.
## The game calls the note_* hooks; things you own or have (money, outfits, decor, nights) are
## checked once a second. A pop-up comes from the HUD on the `unlocked` signal.

signal unlocked(id: String)

const PATH:= "user://achievements.json"
const SPOOKY_RAKE_SCORE:= 60   # "AMAZING SHOT!" territory

## [id, name, description, group]
const DEFS:= [
	["field_guide", "Field Guide", "Photograph every cryptid (not counting the Where-wolf).", "completion"],
	["tourist_trap", "Tourist Trap", "Get a cryptid on film in all three places.", "completion"],
	["fashion_victim", "Fashion Victim", "Own every outfit.", "completion"],
	["interior_decorator", "Interior Decorator", "Buy every poster and trinket for the RV.", "completion"],
	["theyre_real", "They're Real", "Get the UFO on film.", "completion"],
	["seeing_spots", "Seeing Spots", "Get flashed by Grey Tourists 10 times in one night.", "funny"],
	["abducted", "Abducted", "Get flashed so much the UFO comes for you.", "funny"],
	["hold_still", "Hold Still", "Step in a bear trap. Probably your own.", "funny"],
	["nice_selfie", "Nice Selfie", "Set off your own tripod cam.", "funny"],
	["relish", "Relish the Moment", "Get flashed by a tourist while dressed as the Hot Dog.", "funny"],
	["shaky_hands", "Shaky Hands", "In one night, take a photo high and another one buzzed.", "funny"],
	["toe_rogan", "The Toe Rogan Experience", "Own the Toe Rogan bobblehead and wear the Toe Superfan outfit.", "funny"],
	["democracy", "Democracy", "Vote no on going to sleep 5 times.", "funny"],
	["rake_portrait", "Portrait of The Rake", "Get an AMAZING SHOT of The Rake.", "hard"],
	["ghost", "Ghost", "Sleep through to morning without being caught or flashed, with at least 3 photos taken.", "hard"],
	["full_moon", "Full Moon Fever", "Photograph the Where-wolf.", "hard"],
	["naughty_list", "Naughty List", "Get Santa on film.", "hard"],
	["millionaire", "Millionaire's Club", "Have $10,000 at once.", "hard"],
	["night_shift", "Night Shift", "Make it through 10 nights in one save.", "hard"],
]
const GROUP_NAMES:= {"completion": "COMPLETION", "funny": "FUNNY", "hard": "HARD"}
const MAPS:= ["woods", "lake", "city"]
const NOT_IN_GUIDE:= ["wherewolf"]

var got: Dictionary = {}           # id -> unix time unlocked
var seen_species: Array = []       # everything you've had on film, ever
var maps_with_photos: Array = []
var sleep_no_votes:= 0
## This night only (reset when the night number changes).
var _night:= -1
var _night_flags: Dictionary = {}
var _tick:= 0.0
## Tests turn this off so they never touch the real file.
var saving_enabled:= true


func _ready() -> void:
	load_data()


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	check_owned()


static func guide_species() -> Array:
	var out: Array = []
	for id in Species.DATA:
		if str(Species.DATA[id].get("behaviour", "")) != "visitor" and id not in NOT_IN_GUIDE:
			out.append(id)
	return out


func has(id: String) -> bool:
	return got.has(id)


func count() -> int:
	return got.size()


func info(id: String) -> Array:
	for d in DEFS:
		if d[0] == id:
			return d
	return []


func unlock(id: String) -> void:
	if got.has(id) or info(id).is_empty():
		return
	got[id] = int(Time.get_unix_time_from_system())
	save_data()
	unlocked.emit(id)


## "7/11"-style progress for the list, or "".
func progress(id: String) -> String:
	match id:
		"field_guide":
			var all:= guide_species()
			var n:= 0
			for s in all:
				if s in seen_species:
					n += 1
			return "%d/%d" % [n, all.size()]
		"tourist_trap":
			return "%d/%d" % [maps_with_photos.size(), MAPS.size()]
		"fashion_victim":
			return "%d/%d" % [GameState.owned_skins.size(), Skins.ids().size()]
		"interior_decorator":
			var all2:= _decor_ids()
			var n2:= 0
			for d in all2:
				if Catalog.owned(d):
					n2 += 1
			return "%d/%d" % [n2, all2.size()]
		"democracy":
			return "%d/5" % mini(sleep_no_votes, 5)
		"night_shift":
			return "%d/10" % mini(GameState.night - 1, 10)
	return ""


func _decor_ids() -> Array:
	var out: Array = []
	for id in Catalog.ITEMS:
		if str(Catalog.ITEMS[id].get("kind", "")) in ["poster", "trinket"]:
			out.append(id)
	return out


func _flags() -> Dictionary:
	if _night != GameState.night:
		_night = GameState.night
		_night_flags = {"tourist_flashes": 0, "flashed": false, "photos": 0, "high": false, "buzzed": false}
	return _night_flags


# ------------------------------------------------------------------ hooks the game calls

## A photo this player took (by hand, or their tripod cam).
func note_photo(result: Dictionary, high: bool = false, buzzed: bool = false) -> void:
	if not result.get("in_frame", false):
		return
	var f:= _flags()
	f["photos"] = int(f["photos"]) + 1
	var changed:= false
	for s in result.get("species_list", []):
		if s not in seen_species:
			seen_species.append(s)
			changed = true
	if GameState.current_map not in maps_with_photos:
		maps_with_photos.append(GameState.current_map)
		changed = true
	if changed:
		save_data()
	var who: Array = result.get("species_list", [])
	if "ufo" in who:
		unlock("theyre_real")
	if "santa" in who:
		unlock("naughty_list")
	if "wherewolf" in who:
		unlock("full_moon")
	if int((result.get("scores", {}) as Dictionary).get("the_rake", 0)) >= SPOOKY_RAKE_SCORE:
		unlock("rake_portrait")
	if high:
		f["high"] = true
	if buzzed:
		f["buzzed"] = true
	if f["high"] and f["buzzed"]:
		unlock("shaky_hands")
	var missing:= false
	for s in guide_species():
		if s not in seen_species:
			missing = true
	if not missing:
		unlock("field_guide")
	if maps_with_photos.size() >= MAPS.size():
		unlock("tourist_trap")


## Flashed by a Grey Tourist (by_tourist) or a friend's flash trap.
func note_flashed(by_tourist: bool) -> void:
	var f:= _flags()
	f["flashed"] = true
	if not by_tourist:
		return
	f["tourist_flashes"] = int(f["tourist_flashes"]) + 1
	if int(f["tourist_flashes"]) >= 10:
		unlock("seeing_spots")
	if GameState.skin == "hotdog":
		unlock("relish")


func note_ufo_summoned() -> void:
	unlock("abducted")


func note_snared() -> void:
	unlock("hold_still")


func note_selfie() -> void:
	unlock("nice_selfie")


func note_vote(kind: String, yes: bool) -> void:
	if kind != "sleep" or yes:
		return
	sleep_no_votes += 1
	save_data()
	if sleep_no_votes >= 5:
		unlock("democracy")


## Called by GameState.end_night before the night number moves on.
func note_night_end(caught: bool, slept: bool) -> void:
	var f:= _flags()
	if slept and not caught and not f["flashed"] and int(f["photos"]) >= 3:
		unlock("ghost")


## Things you have, checked every second (and by tests directly).
func check_owned() -> void:
	if GameState.money >= 10000:
		unlock("millionaire")
	if GameState.night >= 11:
		unlock("night_shift")
	if GameState.owned_skins.size() >= Skins.ids().size():
		unlock("fashion_victim")
	var all_decor:= true
	for d in _decor_ids():
		if not Catalog.owned(d):
			all_decor = false
	if all_decor:
		unlock("interior_decorator")
	if Catalog.owned("toe_bobblehead") and GameState.skin == "superfan":
		unlock("toe_rogan")


# ------------------------------------------------------------------ file

func save_data() -> void:
	if not saving_enabled:
		return
	var f:= FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"got": got, "seen": seen_species, "maps": maps_with_photos, "no_votes": sleep_no_votes}))


func load_data() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f:= FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	got = data.get("got", {})
	seen_species = data.get("seen", [])
	maps_with_photos = data.get("maps", [])
	sleep_no_votes = int(data.get("no_votes", 0))


## Tests: forget everything (in memory only).
func clear() -> void:
	got = {}
	seen_species = []
	maps_with_photos = []
	sleep_no_votes = 0
	_night = -1
