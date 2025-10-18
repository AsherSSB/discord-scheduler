extends IEventService
class_name MockEventService

#-----------------------------------------------------------------------------
# Exports
#-----------------------------------------------------------------------------
@export var simulate_latency_ms: int = 200
@export var simulate_fail_rate: float = 0.0

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
var _events: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _availability: Dictionary = {}
# Structure:
# {
#   "EVT-...": {
#     "total_cells": int,
#     "users": { "user_id": PackedInt32Array }
#   }
# }

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	_rng.randomize()
	_load_state()
	_load_availability()

#-----------------------------------------------------------------------------
# API: Events
#-----------------------------------------------------------------------------
func create_event(payload: Dictionary) -> DeferredRequest:
	var req: DeferredRequest = DeferredRequest.new()
	_simulate(func() -> void:
		if _rng.randf() < simulate_fail_rate:
			req.reject("Simulated failure")
			return
		var rec: Dictionary = _make_record(payload)
		_events.append(rec)
		_save_state()
		req.resolve(rec)
	)
	return req

func list_events() -> DeferredRequest:
	var req: DeferredRequest = DeferredRequest.new()
	_simulate(func() -> void:
		var out: Array[Dictionary] = []
		for d: Dictionary in _events:
			out.append(d)
		req.resolve({"items": out})
	)
	return req

func delete_event(event_id: String) -> DeferredRequest:
	var req: DeferredRequest = DeferredRequest.new()
	_simulate(func() -> void:
		var removed: bool = false
		for i: int in range(_events.size()):
			var id: String = String(_events[i].get("id", ""))
			if id == event_id:
				_events.remove_at(i)
				removed = true
				break
		if removed:
			_save_state()
			_availability.erase(event_id)
			_save_availability()
			req.resolve({"ok": true})
		else:
			req.reject("Not found")
	)
	return req

func clear_all() -> DeferredRequest:
	var req: DeferredRequest = DeferredRequest.new()
	_simulate(func() -> void:
		_events.clear()
		_save_state()
		_availability.clear()
		_save_availability()
		req.resolve({"ok": true})
	)
	return req

#-----------------------------------------------------------------------------
# API: Availability / Heatmap
#-----------------------------------------------------------------------------
func set_availability(event_id: String, user_id: String, indices: PackedInt32Array, total_cells: int) -> DeferredRequest:
	var req: DeferredRequest = DeferredRequest.new()
	_simulate(func() -> void:
		if total_cells <= 0:
			req.reject("total_cells must be > 0")
			return
		var filtered: PackedInt32Array = PackedInt32Array()
		var seen: Dictionary = {}
		for k: int in indices:
			if k >= 0 and k < total_cells and not seen.has(k):
				seen[k] = true
				filtered.append(k)

		if not _availability.has(event_id):
			_availability[event_id] = {
				"total_cells": total_cells,
				"users": {}
			}
		var slot: Dictionary = _availability[event_id]
		slot["total_cells"] = total_cells
		var users: Dictionary = slot.get("users", {})
		users[user_id] = filtered
		slot["users"] = users
		_availability[event_id] = slot
		_save_availability()
		req.resolve({"ok": true})
	)
	return req

func get_heat(event_id: String) -> DeferredRequest:
	var req: DeferredRequest = DeferredRequest.new()
	_simulate(func() -> void:
		if not _availability.has(event_id):
			req.resolve({"counts": PackedInt32Array()})
			return
		var slot: Dictionary = _availability[event_id]
		var total: int = int(slot.get("total_cells", 0))
		var counts: PackedInt32Array = PackedInt32Array()
		if total <= 0:
			req.resolve({"counts": counts})
			return
		counts.resize(total)
		for i: int in range(total):
			counts[i] = 0
		var users: Dictionary = slot.get("users", {})
		for _k in users.keys():
			var arr: PackedInt32Array = users[_k]
			for idx: int in arr:
				if idx >= 0 and idx < total:
					counts[idx] += 1
		req.resolve({"counts": counts})
	)
	return req

func get_user_availability(event_id: String, user_id: String) -> DeferredRequest:
	var req: DeferredRequest = DeferredRequest.new()
	_simulate(func() -> void:
		if not _availability.has(event_id):
			req.resolve({"indices": PackedInt32Array(), "total_cells": 0})
			return
		var slot: Dictionary = _availability[event_id]
		var users: Dictionary = slot.get("users", {})
		if not users.has(user_id):
			req.resolve({"indices": PackedInt32Array(), "total_cells": int(slot.get("total_cells", 0))})
			return
		var arr: PackedInt32Array = users[user_id]
		req.resolve({"indices": arr, "total_cells": int(slot.get("total_cells", 0))})
	)
	return req

#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------
func _simulate(action: Callable) -> void:
	var t: SceneTreeTimer = get_tree().create_timer(float(simulate_latency_ms) / 1000.0)
	await t.timeout
	action.call()

func _make_record(payload: Dictionary) -> Dictionary:
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var rec: Dictionary = payload.duplicate()
	var rid: String = "EVT-%d-%d" % [now_ms, _rng.randi()]
	rec["id"] = rid
	rec["created_at_ms"] = now_ms
	return rec

#-----------------------------------------------------------------------------
# Persistence: Events
#-----------------------------------------------------------------------------
func _save_state() -> void:
	var f: FileAccess = FileAccess.open("user://events.json", FileAccess.WRITE)
	if f == null:
		return
	var data: Dictionary = {"items": _events}
	f.store_string(JSON.stringify(data))
	f.close()

func _load_state() -> void:
	if not FileAccess.file_exists("user://events.json"):
		return
	var f: FileAccess = FileAccess.open("user://events.json", FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var items_raw: Variant = parsed.get("items", [])
	if typeof(items_raw) != TYPE_ARRAY:
		return
	var casted: Array[Dictionary] = []
	for v in items_raw:
		if typeof(v) == TYPE_DICTIONARY:
			casted.append(v)
	_events = casted

#-----------------------------------------------------------------------------
# Persistence: Availability
#-----------------------------------------------------------------------------
func _save_availability() -> void:
	var outer: Dictionary = {}
	for eid in _availability.keys():
		var slot: Dictionary = _availability[eid]
		var users: Dictionary = slot.get("users", {})
		var users_out: Dictionary = {}
		for uid in users.keys():
			var a: PackedInt32Array = users[uid]
			var arr: Array = []
			for v: int in a:
				arr.append(v)
			users_out[uid] = arr
		outer[eid] = {
			"total_cells": int(slot.get("total_cells", 0)),
			"users": users_out
		}
	var f: FileAccess = FileAccess.open("user://availability.json", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"events": outer}))
	f.close()

func _load_availability() -> void:
	_availability.clear()
	if not FileAccess.file_exists("user://availability.json"):
		return
	var f: FileAccess = FileAccess.open("user://availability.json", FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var events_raw: Variant = parsed.get("events", {})
	if typeof(events_raw) != TYPE_DICTIONARY:
		return
	for eid in (events_raw as Dictionary).keys():
		var slot_in: Dictionary = (events_raw as Dictionary)[eid]
		var total_cells: int = int(slot_in.get("total_cells", 0))
		var users_in: Variant = slot_in.get("users", {})
		var users_out: Dictionary = {}
		if typeof(users_in) == TYPE_DICTIONARY:
			for uid in (users_in as Dictionary).keys():
				var arr_any: Variant = (users_in as Dictionary)[uid]
				var out: PackedInt32Array = PackedInt32Array()
				if typeof(arr_any) == TYPE_ARRAY:
					for v in (arr_any as Array):
						out.append(int(v))
				users_out[uid] = out
		_availability[eid] = {"total_cells": total_cells, "users": users_out}
