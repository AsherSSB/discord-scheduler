extends Node

#-----------------------------------------------------------------------------
# Exports
#-----------------------------------------------------------------------------
@export var debug_print: bool = false

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
var _state: Dictionary = {}
var _path: String = "user://availability.json"
var _legacy_path: String = "user://avail.json"

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	_load_state()
	if not _state.has("events"):
		_state["events"] = {}
		_save_state()

#-----------------------------------------------------------------------------
# Public API
#-----------------------------------------------------------------------------
func ensure_event(event_id: String, total_cells: int) -> void:
	if event_id == "":
		return
	var ev: Dictionary = _get_event(event_id)
	if ev.is_empty():
		ev = {"total_cells": total_cells, "users": {}}
		_state["events"][event_id] = ev
	else:
		ev["total_cells"] = total_cells
	_save_state()

func set_user_indices(
	event_id: String,
	user_id: String,
	indices: PackedInt32Array
) -> void:
	if event_id == "" or user_id == "":
		return
	var ev: Dictionary = _get_event(event_id)
	if ev.is_empty():
		return
	var total: int = int(ev.get("total_cells", 0))
	var arr: Array[int] = []
	for k: int in indices:
		if k >= 0 and k < total:
			arr.append(k)
	ev["users"][user_id] = arr
	_save_state()
	if debug_print:
		print(
			"Availability: set_user_indices event=",
			event_id,
			" user=",
			user_id,
			" count=",
			arr.size()
		)

func get_user_indices(event_id: String, user_id: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var ev: Dictionary = _get_event(event_id)
	if ev.is_empty():
		return out
	if not ev["users"].has(user_id):
		return out
	var arr_any: Variant = ev["users"][user_id]
	if typeof(arr_any) != TYPE_ARRAY:
		return out
	var arr: Array = arr_any
	out.resize(arr.size())
	for i: int in range(arr.size()):
		out[i] = int(arr[i])
	return out

func compute_heat_counts(
	event_id: String,
	exclude_user_id: String = ""
) -> PackedInt32Array:
	var ev: Dictionary = _get_event(event_id)
	var total: int = int(ev.get("total_cells", 0))
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(total)
	for i: int in range(total):
		out[i] = 0
	if total == 0:
		return out
	var users: Dictionary = ev.get("users", {})
	for uid_any: String in users.keys():
		var uid: String = String(uid_any)
		if exclude_user_id != "" and uid == exclude_user_id:
			continue
		var arr_any: Variant = users[uid]
		if typeof(arr_any) != TYPE_ARRAY:
			continue
		for k_any: Variant in arr_any:
			var k: int = int(k_any)
			if k >= 0 and k < total:
				out[k] = out[k] + 1
	return out

func seed_fake_users(
	event_id: String,
	usernames: PackedStringArray,
	density: float = 0.12
) -> void:
	var ev: Dictionary = _get_event(event_id)
	if ev.is_empty():
		return
	var total: int = int(ev.get("total_cells", 0))
	if total <= 0:
		return
	if density < 0.0:
		density = 0.0
	if density > 0.9:
		density = 0.9
	for uname: String in usernames:
		if ev["users"].has(uname):
			continue
		var want: int = int(roundi(float(total) * density))
		if want < 1:
			want = 1
		var picks: Dictionary = {}
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		var seed_val: int = _hash32(uname + "|" + event_id) & 0x7fffffff
		rng.seed = seed_val
		var attempts: int = 0
		while picks.size() < want and attempts < want * 8:
			var k: int = rng.randi_range(0, total - 1)
			if not picks.has(k):
				picks[k] = 1
			attempts += 1
		var arr: Array[int] = []
		for k_any: Variant in picks.keys():
			arr.append(int(k_any))
		arr.sort()
		ev["users"][uname] = arr
	_save_state()
	if debug_print:
		print(
			"Availability: seeded users=",
			usernames,
			" event=",
			event_id
		)

func users_for_event(event_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var ev: Dictionary = _get_event(event_id)
	if ev.is_empty():
		return out
	for uid_any: String in ev.get("users", {}).keys():
		out.append(String(uid_any))
	return out

#-----------------------------------------------------------------------------
# Persistence
#-----------------------------------------------------------------------------
func _load_state() -> void:
	if FileAccess.file_exists(_path):
		_state = _load_from_file(_path)
		return
	if FileAccess.file_exists(_legacy_path):
		_state = _load_from_file(_legacy_path)
		_save_state()
		DirAccess.remove_absolute(_legacy_path)
		return
	_state = {"events": {}}
	_save_state()

func _save_state() -> void:
	var f: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_state))
	f.close()

func _load_from_file(p: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"events": {}}
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {"events": {}}

#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------
func _get_event(event_id: String) -> Dictionary:
	if not _state.has("events"):
		_state["events"] = {}
	if not _state["events"].has(event_id):
		return {}
	return _state["events"][event_id]

func _hash32(s: String) -> int:
	var h: int = 2166136261
	var prime: int = 16777619
	for i: int in range(s.length()):
		h = h ^ int(s.unicode_at(i))
		h = (h * prime) & 0xFFFFFFFF
	return h & 0xFFFFFFFF
