extends Node
class_name NetSync
## The map's online traffic (a child of Main called "NetSync", so it has the same path on every PC).
## Does nothing in single player.
##
## Host: runs the real cryptids and sends their positions/states ~15x a second; sends its own
## player; relays everyone else's; owns bait, traps, the pot of gold, Santa and the night.
## Joining PC: draws copies (puppets) of the host's cryptids and passes its flashes, noise and
## photos-first back; asks the host before taking gold or putting down bait/traps.

const PLAYER_HZ:= 20.0
const CRYPTID_HZ:= 15.0
const TARGET_EVERY:= 0.5

var main: Node
var remotes: Dictionary = {}      # peer id -> RemotePlayer
var _ready_peers: Dictionary = {} # host: peers that have loaded this map
var _items: Dictionary = {}       # net id -> node (bait / trap)
var _next_item:= 1
var _t_player:= 0.0
var _t_cryptid:= 0.0
var _t_target:= 0.0
var _world_received:= false


func setup(p_main: Node) -> void:
	main = p_main
	name = "NetSync"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	Net.players_changed.connect(_on_players_changed)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	if Net.is_client():
		_request_world.rpc_id(1)


func active() -> bool:
	return Net.online()


func _player() -> Player:
	return main.get("_player")


func _cryptids() -> Array:
	return main.get("_cryptids")


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not active():
		return
	_t_player -= delta
	if _t_player <= 0.0:
		_t_player = 1.0 / PLAYER_HZ
		_send_my_state()
	if Net.is_host():
		_vote_tick(delta)
		_t_cryptid -= delta
		if _t_cryptid <= 0.0:
			_t_cryptid = 1.0 / CRYPTID_HZ
			_send_cryptids()
		_t_target -= delta
		if _t_target <= 0.0:
			_t_target = TARGET_EVERY
			_pick_targets()


func _send_my_state() -> void:
	var p:= _player()
	if p == null:
		return
	var st:= p.net_state()
	if Net.is_host():
		for id in _ready_peers:
			_player_state.rpc_id(id, 1, st)
	else:
		# Which stalkers (The Rake) am I staring at? The host freezes them for everyone.
		var watching: Array = []
		for c in _cryptids():
			if c.behaviour == "stalker" and c.call("_is_watched"):
				watching.append(c.net_index)
		_client_state.rpc_id(1, st, watching)


## Client -> host: my player. The host draws it and passes it on.
@rpc("any_peer", "unreliable_ordered")
func _client_state(st: Array, watching: Array) -> void:
	if not Net.is_host() or not is_inside_tree():
		return   # (a late packet while the map reloads)
	var id:= Net.multiplayer.get_remote_sender_id()
	_apply_player(id, st)
	var cs:= _cryptids()
	for i in watching:
		if int(i) >= 0 and int(i) < cs.size():
			cs[int(i)].remote_watch_until = Time.get_ticks_msec() / 1000.0 + 0.3
	for other in _ready_peers:
		if other != id:
			_player_state.rpc_id(other, id, st)


@rpc("authority", "unreliable_ordered")
func _player_state(id: int, st: Array) -> void:
	if id == Net.my_id():
		return
	_apply_player(id, st)


func _apply_player(id: int, st: Array) -> void:
	var rp: RemotePlayer = remotes.get(id)
	if rp == null or not is_instance_valid(rp):
		rp = RemotePlayer.new()
		rp.peer_id = id
		rp.name = "Remote_%d" % id
		main.add_child(rp)
		remotes[id] = rp
		if main.has_method("on_player_arrived"):
			main.on_player_arrived(id)
	rp.apply_state(st)


func _on_players_changed() -> void:
	for id in remotes.keys():
		if not Net.players.has(id):
			_drop_remote(id)
		elif is_instance_valid(remotes[id]):
			remotes[id].refresh_name()


func _on_peer_left(id: int) -> void:
	_ready_peers.erase(id)
	_drop_remote(id)
	# Someone left mid-vote: the rest may now all have agreed.
	if Net.is_host() and not _vote.is_empty():
		_host_check_vote.call_deferred()


func _drop_remote(id: int) -> void:
	var rp = remotes.get(id)
	remotes.erase(id)
	if rp != null and is_instance_valid(rp):
		if main.has_method("on_player_left"):
			main.on_player_left(id, Net.name_of(id))
		for c in _cryptids():
			if c.player_ref == rp:
				c.player_ref = _player()
		rp.queue_free()


# ------------------------------------------------------------------ proximity voice

## This PC's mic produced a chunk while talking: send it (host relays to everyone else).
func send_voice(data: PackedByteArray) -> void:
	if not active():
		return
	if Net.is_host():
		for id in _ready_peers:
			_voice_in.rpc_id(id, 1, data)
	else:
		_voice_up.rpc_id(1, data)


@rpc("any_peer", "unreliable_ordered")
func _voice_up(data: PackedByteArray) -> void:
	if not Net.is_host() or data.size() > 4096:
		return
	var id:= Net.multiplayer.get_remote_sender_id()
	var rp = remotes.get(id)
	if rp != null and is_instance_valid(rp):
		rp.play_voice(data)
	for other in _ready_peers:
		if other != id:
			_voice_in.rpc_id(other, id, data)


@rpc("authority", "unreliable_ordered")
func _voice_in(id: int, data: PackedByteArray) -> void:
	if id == Net.my_id():
		return
	var rp = remotes.get(id)
	if rp != null and is_instance_valid(rp):
		rp.play_voice(data)


# ------------------------------------------------------------------ cryptids (host -> everyone)

func _send_cryptids() -> void:
	if _ready_peers.is_empty():
		return
	var cs:= _cryptids()
	var data:= PackedFloat32Array()
	data.resize(cs.size() * 8)
	for i in cs.size():
		var c: Cryptid = cs[i]
		var p:= c.global_position
		var o:= i * 8
		data[o] = p.x
		data[o + 1] = p.y
		data[o + 2] = p.z
		data[o + 3] = c.rotation.y
		data[o + 4] = float(c.state)
		data[o + 5] = 1.0 if c.watched else 0.0
		data[o + 6] = c.grab_progress
		data[o + 7] = float(target_id(c))
	for id in _ready_peers:
		_cryptid_states.rpc_id(id, data)


func target_id(c: Cryptid) -> int:
	if c.player_ref is RemotePlayer:
		return (c.player_ref as RemotePlayer).peer_id
	return 1


@rpc("authority", "unreliable_ordered")
func _cryptid_states(data: PackedFloat32Array) -> void:
	var cs:= _cryptids()
	var n:= mini(cs.size(), data.size() / 8)
	for i in n:
		var o:= i * 8
		var c: Cryptid = cs[i]
		c.net_apply(Vector3(data[o], data[o + 1], data[o + 2]), data[o + 3], int(data[o + 4]), data[o + 5] > 0.5, data[o + 6], int(data[o + 7]))


## Host: each cryptid goes after the nearest photographer who's outdoors (it keeps its quarry
## mid-chase unless they get away indoors).
func _pick_targets() -> void:
	var me:= _player()
	var cands: Array = []
	if me and not me.indoors:
		cands.append(me)
	for id in remotes:
		var rp: RemotePlayer = remotes[id]
		if is_instance_valid(rp) and not rp.indoors and _ready_peers.has(id):
			cands.append(rp)
	if cands.is_empty():
		return
	for c in _cryptids():
		var cur = c.player_ref
		var cur_ok: bool = cur != null and is_instance_valid(cur) and cur in cands
		if c.state == Cryptid.State.CHASE and cur_ok:
			continue
		if c.state == Cryptid.State.CAUGHT:
			continue
		var best: Node3D = null
		var bd:= INF
		for t in cands:
			var d:= (t as Node3D).global_position.distance_squared_to(c.global_position)
			if d < bd:
				bd = d
				best = t
		c.player_ref = best


# ------------------------------------------------------------------ joining a map

@rpc("any_peer", "reliable")
func _request_world() -> void:
	if not Net.is_host():
		return
	var id:= Net.multiplayer.get_remote_sender_id()
	var roster: Array = []
	for c in _cryptids():
		roster.append([c.species_id, c.global_position])
	var items: Array = []
	for k in _items:
		var n = _items[k]
		if is_instance_valid(n):
			items.append([k, "trap" if n is Trap else "bait", n.global_transform])
	var pot = main.get("_pot")
	var santa = main.get("_santa")
	var world:= {
		"roster": roster, "items": items,
		"pot": [pot.global_position, pot.taken] if pot != null and is_instance_valid(pot) else [],
		"santa": santa != null and is_instance_valid(santa) and not santa.is_leaving(),
		"night_time": main.get("_night_time"),
		"day": main.get("is_day"),
	}
	_world.rpc_id(id, world)
	_ready_peers[id] = true


@rpc("authority", "reliable")
func _world(w: Dictionary) -> void:
	_world_received = true
	main.build_puppet_world(w)
	for it in w.get("items", []):
		_make_item(int(it[0]), str(it[1]), it[2])


## A joining PC's puppet passes a reaction (flash, noise, trap...) back to the real cryptid.
func forward_for(index: int) -> Callable:
	return func(method: String, args: Array) -> void:
		if Net.is_client():
			_cryptid_call.rpc_id(1, index, method, args)


@rpc("any_peer", "reliable")
func _cryptid_call(index: int, method: String, args: Array) -> void:
	if not Net.is_host():
		return
	var cs:= _cryptids()
	if index < 0 or index >= cs.size():
		return
	if method not in ["hear_noise", "on_flash", "on_device_flash", "photographed_first"]:
		return
	var c: Cryptid = cs[index]
	var rp = remotes.get(Net.multiplayer.get_remote_sender_id())
	# Whoever flashed/made noise is who it reacts to.
	if rp != null and method != "photographed_first" and c.state != Cryptid.State.CHASE:
		c.player_ref = rp
	c.callv(method, args)


# ------------------------------------------------------------------ things that happen to one player

## Host: a cryptid grabbed / a tourist flashed / a trap caught someone who isn't the host.
func tell_caught(peer: int, who: String) -> void:
	_caught.rpc_id(peer, who)


func tell_flashed(peer: int, stun: float) -> void:
	_flashed.rpc_id(peer, stun)


func tell_snared(peer: int, duration: float) -> void:
	_snared.rpc_id(peer, duration)


@rpc("authority", "reliable")
func _caught(who: String) -> void:
	main.knocked_out(who)


@rpc("authority", "reliable")
func _flashed(stun: float) -> void:
	main.flashed_by_tourist_remote(stun)


@rpc("authority", "reliable")
func _snared(duration: float) -> void:
	_player().snare(duration)
	main.get("_hud").show_message("OUCH! You stepped in a trap!")


# ------------------------------------------------------------------ bait and traps (host-owned)

## Any PC: put an item down. Single player / host: spawn it here and tell everyone.
func place_item(kind: String, xf: Transform3D) -> void:
	if Net.is_host():
		_host_spawn_item(kind, xf)
	else:
		_place_item_req.rpc_id(1, kind, xf)


@rpc("any_peer", "reliable")
func _place_item_req(kind: String, xf: Transform3D) -> void:
	if Net.is_host() and kind in ["bait", "trap"]:
		_host_spawn_item(kind, xf)


func _host_spawn_item(kind: String, xf: Transform3D) -> void:
	var id:= _next_item
	_next_item += 1
	var n:= _make_item(id, kind, xf)
	n.tree_exiting.connect(func():
		_items.erase(id)
		if active():
			for p in _ready_peers:
				_item_gone.rpc_id(p, id))
	if n is Trap:
		(n as Trap).sprung.connect(func(victim: Node3D):
			main.call("_on_trap_sprung", victim, n)
			for p in _ready_peers:
				_trap_sprung.rpc_id(p, id))
	for p in _ready_peers:
		_spawn_item.rpc_id(p, id, kind, xf)


func _make_item(id: int, kind: String, xf: Transform3D) -> Node3D:
	var n: Node3D = Trap.new() if kind == "trap" else Bait.new()
	if kind == "trap" and Net.is_client():
		(n as Trap).visual_only = true
	main.add_child(n)
	n.global_transform = xf
	_items[id] = n
	return n


@rpc("authority", "reliable")
func _spawn_item(id: int, kind: String, xf: Transform3D) -> void:
	if not _items.has(id):
		_make_item(id, kind, xf)


@rpc("authority", "reliable")
func _item_gone(id: int) -> void:
	var n = _items.get(id)
	_items.erase(id)
	if n != null and is_instance_valid(n):
		n.queue_free()


@rpc("authority", "reliable")
func _trap_sprung(id: int) -> void:
	var n = _items.get(id)
	if n != null and is_instance_valid(n) and n is Trap:
		(n as Trap).spring_on(null)


# ------------------------------------------------------------------ tripods and UFOs (owner -> everyone)
## Each player's tripods and UFO run on their own PC; everyone else sees copies.

var _ghost_tripods: Dictionary = {}   # "owner:id" -> Tripod (look only)
var _ghost_ufos: Dictionary = {}      # owner -> UFO (look only, but you can photograph it)
var _next_tripod:= 1


## Relay helper: send to everyone but the original sender (host), or up to the host (client).
func _fanout(method: String, args: Array, from_id: int) -> void:
	if Net.is_host():
		for p in _ready_peers:
			if p != from_id:
				callv("rpc_id", [p, method] + args)


func share_tripod(t: Tripod) -> int:
	var id:= _next_tripod
	_next_tripod += 1
	if not active():
		return id
	if Net.is_host():
		_fanout("_tripod_in", [1, id, t.global_transform], 1)
	else:
		_tripod_up.rpc_id(1, id, t.global_transform)
	t.fired.connect(func(_r: Dictionary, _tg: Node3D):
		if not active():
			return
		if Net.is_host():
			_fanout("_tripod_shot", [1, id], 1)
		else:
			_tripod_fire_up.rpc_id(1, id))
	return id


@rpc("any_peer", "reliable")
func _tripod_up(id: int, xf: Transform3D) -> void:
	var from:= Net.multiplayer.get_remote_sender_id()
	_tripod_in(from, id, xf)
	_fanout("_tripod_in", [from, id, xf], from)


@rpc("any_peer", "reliable")
func _tripod_fire_up(id: int) -> void:
	var from:= Net.multiplayer.get_remote_sender_id()
	_tripod_shot(from, id)
	_fanout("_tripod_shot", [from, id], from)


@rpc("authority", "reliable")
func _tripod_in(owner: int, id: int, xf: Transform3D) -> void:
	if owner == Net.my_id():
		return
	var t:= Tripod.new()   # no player: it never fires by itself
	main.add_child(t)
	t.global_transform = xf
	_ghost_tripods["%d:%d" % [owner, id]] = t


@rpc("authority", "reliable")
func _tripod_shot(owner: int, id: int) -> void:
	var t = _ghost_tripods.get("%d:%d" % [owner, id])
	if t != null and is_instance_valid(t):
		t.fire(t)


## The owner's UFO: where it is, whether it's beaming, whether it's leaving (gone when null).
func share_ufo(u: UFO) -> void:
	if not active():
		return
	var st:= [u.global_position, u.is_beaming(), u.phase == UFO.Phase.LEAVE, u.lift]
	if Net.is_host():
		_fanout("_ufo_in", [1, st], 1)
	else:
		_ufo_up.rpc_id(1, st)


func ufo_gone() -> void:
	if not active():
		return
	if Net.is_host():
		_fanout("_ufo_gone_in", [1], 1)
	else:
		_ufo_gone_up.rpc_id(1)


@rpc("any_peer", "unreliable_ordered")
func _ufo_up(st: Array) -> void:
	var from:= Net.multiplayer.get_remote_sender_id()
	_ufo_in(from, st)
	_fanout("_ufo_in", [from, st], from)


@rpc("any_peer", "reliable")
func _ufo_gone_up() -> void:
	var from:= Net.multiplayer.get_remote_sender_id()
	_ufo_gone_in(from)
	_fanout("_ufo_gone_in", [from], from)


@rpc("authority", "unreliable_ordered")
func _ufo_in(owner: int, st: Array) -> void:
	if owner == Net.my_id():
		return
	var u: UFO = _ghost_ufos.get(owner)
	if u == null or not is_instance_valid(u):
		u = UFO.new()
		u.ghost = true
		u.ghost_owner = owner
		u.player = _player()
		main.add_child(u)
		u.global_position = st[0]
		_ghost_ufos[owner] = u
		_player().extra_subjects.append(u)
	u.ghost_apply(st[0], bool(st[1]), bool(st[2]), float(st[3]))


@rpc("authority", "reliable")
func _ufo_gone_in(owner: int) -> void:
	var u = _ghost_ufos.get(owner)
	_ghost_ufos.erase(owner)
	if u != null and is_instance_valid(u):
		u.queue_free()


## Someone photographed another player's UFO: tell its owner (their UFO bolts).
func ufo_snapped(owner: int) -> void:
	if owner == Net.my_id():
		return
	if Net.is_host():
		_ufo_spook.rpc_id(owner)
	else:
		_ufo_snap_up.rpc_id(1, owner)


@rpc("any_peer", "reliable")
func _ufo_snap_up(owner: int) -> void:
	if not Net.is_host():
		return
	if owner == 1:
		main.spook_my_ufo()
	elif _ready_peers.has(owner):
		_ufo_spook.rpc_id(owner)


@rpc("authority", "reliable")
func _ufo_spook() -> void:
	main.spook_my_ufo()


# ------------------------------------------------------------------ pot of gold, Santa, the night

func request_gold() -> void:
	_gold_req.rpc_id(1)


@rpc("any_peer", "reliable")
func _gold_req() -> void:
	if not Net.is_host():
		return
	var id:= Net.multiplayer.get_remote_sender_id()
	var ok: bool = main.host_take_gold(remotes.get(id))
	_gold_reply.rpc_id(id, ok)


@rpc("authority", "reliable")
func _gold_reply(ok: bool) -> void:
	main.gold_result(ok)


func gold_taken() -> void:
	for p in _ready_peers:
		_gold_gone.rpc_id(p)


@rpc("authority", "reliable")
func _gold_gone() -> void:
	var pot = main.get("_pot")
	if pot != null and is_instance_valid(pot):
		pot.take()


func santa_snapped() -> void:
	if Net.is_host():
		for p in _ready_peers:
			_santa_leave.rpc_id(p)
	else:
		_santa_snap_req.rpc_id(1)


@rpc("any_peer", "reliable")
func _santa_snap_req() -> void:
	if Net.is_host():
		main.santa_leave()
		santa_snapped()


@rpc("authority", "reliable")
func _santa_leave() -> void:
	main.santa_leave()


## Host's night ran out: morning for everyone.
func dawn() -> void:
	for p in _ready_peers:
		_dawn.rpc_id(p)


@rpc("authority", "reliable")
func _dawn() -> void:
	main.begin_dawn()


## Host slept or drove somewhere: everyone goes with them.
func night_over(map_id: String, night: int, how: String) -> void:
	for p in _ready_peers:
		_night_over.rpc_id(p, map_id, night, how)
	_ready_peers.clear()


@rpc("authority", "reliable")
func _night_over(map_id: String, night: int, how: String) -> void:
	main.follow_host(map_id, night, how)


# ------------------------------------------------------------------ lobby votes (sleep / drive on)
## Like Minecraft beds: nobody sleeps or drives off unless everyone in the lobby agrees.
## Anyone can ask; the host keeps the count and, once every player has said yes, does it
## (everyone else follows as before). One "no" or 45 s without everyone answering calls it off.

const VOTE_TIME:= 45.0
var _vote: Dictionary = {}        # host: {kind, map, starter, yes: {id: true}, t}
var _shown_vote: Dictionary = {}  # everyone: {kind, map, starter, yes, need}
var _my_vote_done:= false


func vote_running() -> bool:
	return not _shown_vote.is_empty()


## The local player wants to sleep ("sleep") or drive to map_id ("travel").
func start_vote(kind: String, map_id: String) -> void:
	if Net.is_host():
		_host_open_vote(Net.my_id(), kind, map_id)
	else:
		_vote_request.rpc_id(1, kind, map_id)


@rpc("any_peer", "reliable")
func _vote_request(kind: String, map_id: String) -> void:
	if Net.is_host():
		_host_open_vote(Net.multiplayer.get_remote_sender_id(), kind, map_id)


func _host_open_vote(starter: int, kind: String, map_id: String) -> void:
	if not _vote.is_empty():
		_vote_note_to(starter, "There's already a vote going. Press Y or N.")
		return
	_vote = {"kind": kind, "map": map_id, "starter": starter, "yes": {starter: true}, "t": VOTE_TIME}
	_host_check_vote()


## Local answer (Y / N).
func answer_vote(yes: bool) -> void:
	if not vote_running() or _my_vote_done:
		return
	_my_vote_done = true
	if Net.is_host():
		_host_answer(Net.my_id(), yes)
	else:
		_vote_answer.rpc_id(1, yes)


@rpc("any_peer", "reliable")
func _vote_answer(yes: bool) -> void:
	if Net.is_host():
		_host_answer(Net.multiplayer.get_remote_sender_id(), yes)


func _host_answer(id: int, yes: bool) -> void:
	if _vote.is_empty():
		return
	if not yes:
		_host_close_vote(false, "%s said no. Staying put." % Net.name_of(id))
		return
	_vote["yes"][id] = true
	_host_check_vote()


func _host_check_vote() -> void:
	var need:= Net.players.keys() if not Net.players.is_empty() else [Net.my_id()]
	var yes: Dictionary = _vote["yes"]
	for id in yes.keys():
		if id not in need:
			yes.erase(id)
	var n_yes:= yes.size()
	if n_yes >= need.size():
		var kind: String = _vote["kind"]
		var map_id: String = _vote["map"]
		_host_close_vote(true, "Everyone's in: %s" % ("lights out..." if kind == "sleep" else "driving on to %s..." % Species.MAPS[map_id]["name"]))
		if main.has_method("vote_passed"):
			main.vote_passed(kind, map_id)
		return
	_send_vote_state()


func _send_vote_state() -> void:
	var need:= Net.players.keys() if not Net.players.is_empty() else [Net.my_id()]
	var args:= [int(_vote["starter"]), str(_vote["kind"]), str(_vote["map"]), (_vote["yes"] as Dictionary).keys(), need.size()]
	for p in _ready_peers:
		_vote_state.rpc_id(p, args[0], args[1], args[2], args[3], args[4])
	_vote_state(args[0], args[1], args[2], args[3], args[4])


func _host_close_vote(passed: bool, msg: String) -> void:
	_vote.clear()
	for p in _ready_peers:
		_vote_closed.rpc_id(p, passed, msg)
	_vote_closed(passed, msg)


func _vote_note_to(id: int, msg: String) -> void:
	if id == Net.my_id():
		_vote_note(msg)
	else:
		_vote_note.rpc_id(id, msg)


@rpc("authority", "reliable")
func _vote_note(msg: String) -> void:
	if main.has_method("vote_message"):
		main.vote_message(msg)


@rpc("authority", "reliable")
func _vote_state(starter: int, kind: String, map_id: String, yes: Array, need: int) -> void:
	if _shown_vote.is_empty():
		_my_vote_done = false
	_shown_vote = {"kind": kind, "map": map_id, "starter": starter, "yes": yes, "need": need}
	if Net.my_id() in yes:
		_my_vote_done = true
	if main.has_method("show_vote"):
		main.show_vote(_shown_vote, _my_vote_done)


@rpc("authority", "reliable")
func _vote_closed(passed: bool, msg: String) -> void:
	_shown_vote.clear()
	_my_vote_done = false
	if main.has_method("vote_closed"):
		main.vote_closed(passed, msg)


func _vote_tick(delta: float) -> void:
	if _vote.is_empty():
		return
	var before:= float(_vote["t"])
	_vote["t"] = before - delta
	if float(_vote["t"]) <= 0.0:
		_host_close_vote(false, "Not everyone answered. Staying put.")
	elif int(before) != int(float(_vote["t"])):
		_send_vote_state()   # once a second, so anyone who just finished loading sees it too
