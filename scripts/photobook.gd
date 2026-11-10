extends RefCounted
class_name Photobook
## The photo book in the RV: developed prints you chose to keep. Stored as PNGs plus an index in
## their own folder, apart from the save, so a new game doesn't throw your photos away.

const MAX_PHOTOS:= 120
static var dir:= "user://photobook/"
static var _entries: Array = []      # [{id, caption, when}]
static var _loaded_from:= ""
static var _cache: Dictionary = {}   # id -> Texture2D


static func _ensure() -> void:
	if _loaded_from == dir:
		return
	_loaded_from = dir
	_entries = []
	_cache = {}
	var f:= FileAccess.open(dir + "index.json", FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_ARRAY:
		_entries = data


static func _write_index() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var f:= FileAccess.open(dir + "index.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_entries))


static func entries() -> Array:
	_ensure()
	return _entries


static func count() -> int:
	return entries().size()


static func is_full() -> bool:
	return count() >= MAX_PHOTOS


## Paste a print in. Returns the new entry's id, or "" if the book is full or there's no picture.
static func add(tex: Texture2D, caption: String) -> String:
	_ensure()
	if is_full() or tex == null:
		return ""
	var img:= tex.get_image()
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var id:= "pb%d" % Time.get_ticks_usec()
	if img.save_png(dir + id + ".png") != OK:
		return ""
	_entries.append({"id": id, "caption": caption, "when": Time.get_datetime_string_from_system(false, true)})
	_cache[id] = tex
	_write_index()
	return id


static func remove(id: String) -> void:
	_ensure()
	for i in _entries.size():
		if str(_entries[i].get("id", "")) == id:
			_entries.remove_at(i)
			break
	_cache.erase(id)
	DirAccess.remove_absolute(dir + id + ".png")
	_write_index()


static func texture(id: String) -> Texture2D:
	_ensure()
	if _cache.has(id):
		return _cache[id]
	var img:= Image.load_from_file(dir + id + ".png") if FileAccess.file_exists(dir + id + ".png") else null
	if img == null:
		return null
	var t:= ImageTexture.create_from_image(img)
	_cache[id] = t
	return t


## Tests: wipe whatever is in the current folder.
static func clear_all() -> void:
	_ensure()
	for e in _entries.duplicate():
		remove(str(e.get("id", "")))
	_entries = []
	_write_index()
