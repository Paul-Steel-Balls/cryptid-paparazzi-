extends Node
## Autoload "GameState": the save game. Money, gear, film, which map you're on,
## which nights you've survived, which maps are unlocked, and the photo album.

const FILM_MAX:= 6
var SAVE_PATH:= "user://cryptid_save.json"

const BAIT_START:= 3
const TRAPS_START:= 2
const BAIT_PRICE:= 10
const TRAP_PRICE:= 20
const MAX_ITEMS:= 5
## A photo this good (raw score) or better unlocks a cryptid's file in the Cryptid Files.
const FILE_QUALITY:= 35

var money:= 0
var film:= FILM_MAX
var unsold_photos: Array = []
var game_over:= false
## A menu is up while playing online (the world can't pause, so the player just stops).
var menu_open:= false
var bait:= BAIT_START
var traps:= TRAPS_START
## Newer gear (see Catalog): single-use tripod cams, joints (slow-mo), beers (fast but loud).
var tripods:= 0
var joints:= 0
var beers:= 0
const GEAR:= ["bait", "trap", "tripod", "joint", "beer"]
var current_map:= "woods"
var unlocked_maps: Array = ["woods"]
var night:= 1
## Album: species id -> best developed photo value. Toe Rogan checks this.
var album: Dictionary = {}
## Best raw photo score per species (Cryptid Files unlock at FILE_QUALITY).
var file_scores: Dictionary = {}

## This session's actual snapshots (photo "img" key -> Texture2D), hung up in the darkroom.
## Not saved; photos carried over from an earlier session develop as blank prints.
var photo_images: Dictionary = {}
## How the last scene ended ("sleep", "travel", ""): the next one fades in from black.
var arrival:= ""
## How many cameras Toe Rogan has thrown onto his pile (it stays there).
var cameras_thrown:= 0
## Posters and trinkets bought at the stand (see Catalog), and what hangs on the RV's poster wall.
var owned_items: Array = ["poster_believe"]
## Outfits (Skins): what you own and what you're wearing.
var owned_skins: Array = ["default"]
var skin:= "default"
signal skin_changed(id: String)
var poster_slots: Array = ["poster_believe", "", "", "", "", ""]

## Survives restarts: the player's chosen camera view.
var third_person:= false

## Video/audio/control settings, kept separate from progress.
const SETTINGS_PATH:= "user://cryptid_settings.json"
## Graphics effects are 0..1 strengths (0 = off).
const SETTING_DEFAULTS:= {"shadows": 1.0, "ssao": 0.6, "glow": 0.5, "vol_fog": 0.4, "fullscreen": false,
	"sensitivity": 1.0, "volume": 0.8, "toggle_sprint": false, "mic_enabled": false, "mic_sens": 1.0,
	"voice_open": false, "voice_volume": 1.0}
var settings:= SETTING_DEFAULTS.duplicate()

## Tests and headless tools set this so they never touch the real save.
var saving_enabled:= true


signal fullscreen_changed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_game()
	load_settings()
	apply_bindings()
	apply_system_settings()


func save_settings() -> void:
	if not saving_enabled:
		return
	var f:= FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f:= FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	if typeof(data) == TYPE_DICTIONARY:
		for k in data:
			var v = data[k]
			# v0.8 saved the effects as on/off: on = default strength, off = 0.
			if k in ["shadows", "ssao", "glow", "vol_fog"] and typeof(v) == TYPE_BOOL:
				v = float(SETTING_DEFAULTS[k]) if v else 0.0
			settings[k] = v


## Window mode and master volume (the rest is applied per scene by main.gd).
func apply_system_settings() -> void:
	if DisplayServer.get_name() != "headless":
		_apply_window_mode.call_deferred(bool(settings["fullscreen"]))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings["volume"]), 0.001)))


## True (exclusive) fullscreen on Windows; back to a centred 1600x900 window when off.
## Deferred so it never happens in the middle of the click that asked for it.
func _apply_window_mode(full: bool) -> void:
	var mode:= DisplayServer.window_get_mode()
	var is_full:= mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if full == is_full:
		return
	if full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		var scr:= DisplayServer.window_get_current_screen()
		var area:= DisplayServer.screen_get_usable_rect(scr)
		var size:= Vector2i(mini(1600, area.size.x - 40), mini(900, area.size.y - 60))
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(area.position + (area.size - size) / 2)


## F11 or Alt+Enter flips fullscreen from anywhere.
func toggle_fullscreen() -> void:
	settings["fullscreen"] = not bool(settings["fullscreen"])
	save_settings()
	apply_system_settings()
	fullscreen_changed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	var k:= event as InputEventKey
	if k and k.pressed and not k.echo and (k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed)):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


## Brand-new game.
func reset() -> void:
	money = 0
	bait = BAIT_START
	traps = TRAPS_START
	tripods = 0
	joints = 0
	beers = 0
	current_map = "woods"
	unlocked_maps = ["woods"]
	night = 1
	album = {}
	file_scores = {}
	unsold_photos = []
	photo_images.clear()
	cameras_thrown = 0
	owned_items = ["poster_believe"]
	owned_skins = ["default"]
	skin = "default"
	poster_slots = ["poster_believe", "", "", "", "", ""]
	start_night()


## Fresh film; money, gear, album and undeveloped photos carry over.
## (Getting grabbed is what costs you undeveloped photos: see end_night.)
func start_night() -> void:
	film = FILM_MAX
	game_over = false


## Night over (slept in the RV, or got grabbed). Grabbed = undeveloped photos are lost.
func end_night(caught: bool) -> void:
	if caught:
		unsold_photos.clear()
	night += 1
	start_night()
	save_game()


func develop() -> int:
	var total:= 0
	for photo in unsold_photos:
		var v:= int(photo.get("value", 0))
		total += v
		var scores: Dictionary = photo.get("scores", {})
		for id in photo.get("species", []):
			album[id] = maxi(int(album.get(id, 0)), v)
			file_scores[id] = maxi(int(file_scores.get(id, 0)), int(scores.get(id, v)))
	unsold_photos.clear()
	money += total
	return total


func has_file(id: String) -> bool:
	return int(file_scores.get(id, 0)) >= FILE_QUALITY


func undeveloped_value() -> int:
	var t:= 0
	for p in unsold_photos:
		t += int(p.get("value", 0))
	return t


func has_photo(id: String) -> bool:
	return album.has(id)


## Which of Toe Rogan's must-sees for this map are still missing.
func missing_for_unlock(map_id: String) -> Array:
	var out: Array = []
	for id in Species.required_for_unlock(map_id):
		if not has_photo(id) and id not in out:
			out.append(id)
	return out


func is_unlocked(map_id: String) -> bool:
	return map_id in unlocked_maps


func unlock(map_id: String) -> void:
	if map_id != "" and map_id not in unlocked_maps:
		unlocked_maps.append(map_id)
		save_game()


func travel(map_id: String) -> void:
	if is_unlocked(map_id):
		current_map = map_id
		start_night()
		save_game()


func item_count(kind: String) -> int:
	match kind:
		"bait": return bait
		"trap": return traps
		"tripod": return tripods
		"joint": return joints
		"beer": return beers
	return 0


func set_item_count(kind: String, n: int) -> void:
	match kind:
		"bait": bait = n
		"trap": traps = n
		"tripod": tripods = n
		"joint": joints = n
		"beer": beers = n


## Use one up. False if you're out.
func take_item(kind: String) -> bool:
	var n:= item_count(kind)
	if n <= 0:
		return false
	set_item_count(kind, n - 1)
	return true


func item_price(kind: String) -> int:
	return int(Catalog.item(kind).get("price", 0))


func buy(item: String) -> bool:
	var price:= item_price(item)
	if money < price or item_count(item) >= MAX_ITEMS:
		return false
	money -= price
	set_item_count(item, item_count(item) + 1)
	return true


## Posters and trinkets: one of each. Returns false if broke, already owned, or not in stock.
func buy_decor(id: String) -> bool:
	var it:= Catalog.item(id)
	if it.is_empty() or str(it["kind"]) == "gear" or id in owned_items or not Catalog.in_stock(id):
		return false
	var price:= int(it["price"])
	if money < price:
		return false
	money -= price
	owned_items.append(id)
	# A new poster goes up in the first empty slot.
	if str(it["kind"]) == "poster":
		var i:= poster_slots.find("")
		if i >= 0:
			poster_slots[i] = id
	return true


## DRIP CITY: false if broke or already owned.
func buy_skin(id: String) -> bool:
	if not Skins.CATALOG.has(id) or id in owned_skins:
		return false
	var price:= int(Skins.info(id)["price"])
	if money < price:
		return false
	money -= price
	owned_skins.append(id)
	save_game()
	return true


func wear_skin(id: String) -> void:
	if not id in owned_skins or id == skin:
		return
	skin = id
	save_game()
	skin_changed.emit(id)


func save_game() -> void:
	if not saving_enabled:
		return
	var data:= {"money": money, "bait": bait, "traps": traps, "tripods": tripods, "joints": joints, "beers": beers, "current_map": current_map,
		"unlocked_maps": unlocked_maps, "night": night, "album": album, "file_scores": file_scores, "third_person": third_person,
		"unsold_photos": unsold_photos, "cameras_thrown": cameras_thrown,
		"owned_items": owned_items, "poster_slots": poster_slots, "owned_skins": owned_skins, "skin": skin}
	var f:= FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f:= FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	money = int(data.get("money", 0))
	bait = int(data.get("bait", BAIT_START))
	traps = int(data.get("traps", TRAPS_START))
	tripods = int(data.get("tripods", 0))
	joints = int(data.get("joints", 0))
	beers = int(data.get("beers", 0))
	current_map = str(data.get("current_map", "woods"))
	if not Species.MAPS.has(current_map):
		current_map = "woods"
	unlocked_maps = data.get("unlocked_maps", ["woods"])
	night = int(data.get("night", 1))
	album = data.get("album", {})
	file_scores = data.get("file_scores", {})
	third_person = bool(data.get("third_person", false))
	unsold_photos = data.get("unsold_photos", [])
	cameras_thrown = int(data.get("cameras_thrown", 0))
	owned_items = data.get("owned_items", ["poster_believe"])
	owned_skins = data.get("owned_skins", ["default"])
	if not "default" in owned_skins:
		owned_skins.append("default")
	skin = str(data.get("skin", "default"))
	if not Skins.CATALOG.has(skin) or not skin in owned_skins:
		skin = "default"
	poster_slots = data.get("poster_slots", ["poster_believe", "", "", "", "", ""])
	while poster_slots.size() < 6:
		poster_slots.append("")
	start_night()


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	reset()


func _init() -> void:
	_setup_input()


## Every rebindable control: [action, label shown in Controls, default bindings].
## A binding is a key code (int) or "mouse:<button index>".
const CONTROLS:= [
	["move_forward", "Move forward", [KEY_W, KEY_UP]],
	["move_back", "Move back", [KEY_S, KEY_DOWN]],
	["move_left", "Move left (and break out of a tractor beam)", [KEY_A, KEY_LEFT]],
	["move_right", "Move right (and break out of a tractor beam)", [KEY_D, KEY_RIGHT]],
	["sprint", "Sprint", [KEY_SHIFT]],
	["jump", "Jump", [KEY_SPACE]],
	["crouch_hold", "Crouch (hold)", [KEY_CTRL]],
	["crouch_toggle", "Crouch (toggle)", [KEY_C]],
	["aim", "Raise camera", ["mouse:2"]],
	["snap", "Take photo (while raised)", ["mouse:1"]],
	["interact", "Interact / talk / enter RV", [KEY_E]],
	["use_item", "Use selected item", [KEY_Q]],
	["select_bait", "Item: bait", [KEY_1]],
	["select_trap", "Item: trap", [KEY_2]],
	["select_tripod", "Item: tripod cam", [KEY_3]],
	["select_joint", "Item: joint", [KEY_4]],
	["select_beer", "Item: beer", [KEY_5]],
	["toggle_view", "First / third person", [KEY_V]],
	["voice_ptt", "Push to talk (online)", [KEY_T]],
	["vote_yes", "Agree to sleep / drive on (online)", [KEY_Y]],
	["vote_no", "Say no to sleeping / driving on (online)", [KEY_N]],
	["restart", "Restart after getting caught", [KEY_R]],
]


func _setup_input() -> void:
	for c in CONTROLS:
		_bind(str(c[0]), c[2])


## Apply the player's saved rebinds on top of the defaults.
func apply_bindings() -> void:
	var custom: Dictionary = settings.get("bindings", {})
	for c in CONTROLS:
		var act: String = c[0]
		_bind(act, custom[act] if custom.has(act) else c[2])


func default_bindings(action: String) -> Array:
	for c in CONTROLS:
		if c[0] == action:
			return c[2]
	return []


func bindings_of(action: String) -> Array:
	var custom: Dictionary = settings.get("bindings", {})
	return custom[action] if custom.has(action) else default_bindings(action)


## Rebind an action to one key/button. Whatever already used it gets this action's old one (a swap).
func rebind(action: String, binding) -> void:
	var custom: Dictionary = settings.get("bindings", {}).duplicate()
	var old: Array = bindings_of(action)
	for c in CONTROLS:
		var other: String = c[0]
		if other == action:
			continue
		var theirs: Array = bindings_of(other)
		var idx:= _index_of_binding(theirs, binding)
		if idx >= 0:
			var swapped:= theirs.duplicate()
			if old.is_empty():
				swapped.remove_at(idx)
			else:
				swapped[idx] = old[0]
			custom[other] = swapped
	custom[action] = [binding]
	settings["bindings"] = custom
	save_settings()
	apply_bindings()


func reset_bindings() -> void:
	settings.erase("bindings")
	save_settings()
	apply_bindings()


static func _index_of_binding(list: Array, binding) -> int:
	for i in list.size():
		if _same_binding(list[i], binding):
			return i
	return -1


static func _same_binding(a, b) -> bool:
	var a_mouse:= typeof(a) == TYPE_STRING
	var b_mouse:= typeof(b) == TYPE_STRING
	if a_mouse or b_mouse:
		return a_mouse and b_mouse and str(a) == str(b)
	return int(a) == int(b)


## "W", "Shift", "Left Mouse"...
static func binding_name(binding) -> String:
	if typeof(binding) == TYPE_STRING and str(binding).begins_with("mouse:"):
		var b:= int(str(binding).substr(6))
		return {1: "Left Mouse", 2: "Right Mouse", 3: "Middle Mouse", 8: "Mouse 4", 9: "Mouse 5"}.get(b, "Mouse %d" % b)
	return OS.get_keycode_string(int(binding))


## The binding an input event would make (null if it can't be bound).
static func binding_from_event(ev: InputEvent):
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k:= (ev as InputEventKey).keycode
		return int(k) if k != KEY_NONE else int((ev as InputEventKey).physical_keycode)
	if ev is InputEventMouseButton and ev.pressed:
		var bi:= (ev as InputEventMouseButton).button_index
		if bi == MOUSE_BUTTON_WHEEL_UP or bi == MOUSE_BUTTON_WHEEL_DOWN:
			return null
		return "mouse:%d" % bi
	return null


func _bind(action: String, list: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for b in list:
		if typeof(b) == TYPE_STRING and str(b).begins_with("mouse:"):
			var mev:= InputEventMouseButton.new()
			mev.button_index = int(str(b).substr(6)) as MouseButton
			InputMap.action_add_event(action, mev)
		else:
			var kev:= InputEventKey.new()
			kev.keycode = int(b) as Key
			InputMap.action_add_event(action, kev)

