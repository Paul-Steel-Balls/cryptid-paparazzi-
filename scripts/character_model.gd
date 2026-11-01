extends Node3D
class_name CharacterModel
## Loads a sculpted character (.glb from tools/characters.py), gives it toon shading
## with an ink outline, and plays its looping animations.

const OUTLINE_COLOR:= Color(0.06, 0.04, 0.08)

var anim_player: AnimationPlayer
var skeleton: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var current:= ""
## anim name -> metres/second the planted foot travels at playback speed 1 (from tools/charkit.py).
var ground_speed: Dictionary = {}
## Multiplies every playback rate (slow motion).
var time_scale:= 1.0:
	set(v):
		if is_equal_approx(v, time_scale):
			return
		var old:= time_scale
		time_scale = v
		if anim_player and old != 0.0:
			anim_player.speed_scale = anim_player.speed_scale / old * v


static func load_model(path: String, outline_width: float = 0.012) -> CharacterModel:
	var cm:= CharacterModel.new()
	var packed:= load(path) as PackedScene
	if packed == null:
		push_error("CharacterModel: can't load " + path)
		return cm
	var inst:= packed.instantiate()
	cm.add_child(inst)
	cm._setup(inst, outline_width)
	var side:= path.replace(".glb", ".anim.json")
	if FileAccess.file_exists(side):
		var data = JSON.parse_string(FileAccess.get_file_as_string(side))
		if typeof(data) == TYPE_DICTIONARY:
			cm.ground_speed = data.get("ground_speed", {})
	return cm


func _setup(root: Node, outline_width: float) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			meshes.append(n)
		if n is Skeleton3D and skeleton == null:
			skeleton = n
		if n is AnimationPlayer and anim_player == null:
			anim_player = n
		for c in n.get_children():
			stack.append(c)
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var src:= mi.mesh.surface_get_material(s) as BaseMaterial3D
			mi.set_surface_override_material(s, _toon(src, outline_width))
	if anim_player:
		for lib_name in anim_player.get_animation_library_list():
			var lib:= anim_player.get_animation_library(lib_name)
			for a in lib.get_animation_list():
				lib.get_animation(a).loop_mode = Animation.LOOP_LINEAR


static func _toon(src: BaseMaterial3D, outline_width: float) -> StandardMaterial3D:
	var m:= StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = src.roughness if src else 0.8
	m.metallic = src.metallic if src else 0.0
	# Toon specular makes a hard white patch under a nearby light (the campfire on Toe's
	# face, the porch light on the RV). Keep it a small sheen, and only on glossy bits.
	m.metallic_specular = 0.35 if m.roughness < 0.35 else 0.12
	if src and src.emission_enabled:
		m.emission_enabled = true
		m.emission = src.emission
		m.emission_energy_multiplier = 0.9
		m.disable_fog = true
	m.rim_enabled = true
	m.rim = 0.15
	m.rim_tint = 0.6
	if outline_width > 0.0:
		var o:= StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.albedo_color = OUTLINE_COLOR
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.grow = true
		o.grow_amount = outline_width
		m.next_pass = o
	return m


## Materials of glowing surfaces (eyes, lanterns, camera flash).
func glow_materials() -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for mi in meshes:
		for sidx in mi.mesh.get_surface_count():
			var m:= mi.get_surface_override_material(sidx) as StandardMaterial3D
			if m and m.emission_enabled:
				out.append(m)
	return out


func has_anim(n: String) -> bool:
	return anim_player != null and anim_player.has_animation(n)


func play(n: String, speed: float = 1.0, blend: float = 0.18) -> void:
	if anim_player == null:
		return
	if not anim_player.has_animation(n):
		return
	anim_player.speed_scale = speed * time_scale
	if n == current and anim_player.is_playing():
		return
	current = n
	anim_player.play(n, blend)


## Play a walk/run cycle so the feet stay planted: playback rate = actual speed / anim's ground speed.
## reverse: play the cycle backwards (backpedalling).
func play_locomotion(n: String, speed: float, blend: float = 0.2, reverse: bool = false) -> void:
	var gs:= float(ground_speed.get(n, 0.0))
	var rate:= clampf(speed / gs, 0.35, 2.6) if gs > 0.01 else 1.0
	if reverse:
		rate = -rate
	if anim_player == null or not anim_player.has_animation(n):
		return
	if n == current and anim_player.is_playing():
		anim_player.speed_scale = rate * time_scale
		return
	current = n
	anim_player.speed_scale = rate * time_scale
	anim_player.play(n, blend)


func set_layers(layer_mask: int) -> void:
	for mi in meshes:
		mi.layers = layer_mask


func seek(t: float) -> void:
	if anim_player and current != "":
		anim_player.seek(t, true)


## A node that follows a bone (e.g. "hand_r"), for props held in a hand. null if no such bone.
func attach(bone: String) -> BoneAttachment3D:
	if skeleton == null or skeleton.find_bone(bone) < 0:
		return null
	var ba:= BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	return ba
