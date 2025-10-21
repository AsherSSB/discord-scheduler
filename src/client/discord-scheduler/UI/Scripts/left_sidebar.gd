extends Panel

#-----------------------------------------------------------------------------
# Exports
#-----------------------------------------------------------------------------
@export var debug_print: bool = false

#-----------------------------------------------------------------------------
# Cached Nodes
#-----------------------------------------------------------------------------
@onready var _search: LineEdit = ($"ParticipantsPane/Search" as LineEdit)
@onready var _list: VBoxContainer = ($"ParticipantsPane/Scroll/ParticipantList" as VBoxContainer)

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
var _all_participants: Array[Dictionary] = []
var _filtered: Array[Dictionary] = []

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	assert(_search != null, "LeftSidebar: Missing node ParticipantsPane/Search")
	assert(_list != null, "LeftSidebar: Missing node ParticipantsPane/Scroll/ParticipantList")
	_connect_search()

	# Optional: only wire the Activity bridge on Web builds so editor runs clean
	if OS.has_feature("web"):
		_wire_web_callback()
		_request_initial_participants()

#-----------------------------------------------------------------------------
# Web Bridge (only on Web)
#-----------------------------------------------------------------------------
func _wire_web_callback() -> void:
	var cb: JavaScriptObject = JavaScriptBridge.create_callback(_on_js_participants)
	var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
	if win:
		win.set("godotOnParticipants", cb)
		if debug_print:
			print("LeftSidebar: JS callback registered.")

func _request_initial_participants() -> void:
	JavaScriptBridge.eval("window.requestParticipants && window.requestParticipants();")

func _on_js_participants(args: Array) -> void:
	if args.size() != 1:
		return
	var incoming: Variant = args[0]
	if typeof(incoming) != TYPE_ARRAY:
		return
	var raw: Array = incoming as Array
	_all_participants.clear()
	for item in raw:
		if typeof(item) == TYPE_DICTIONARY:
			_all_participants.append(item as Dictionary)
	_apply_filter(_search.text)

#-----------------------------------------------------------------------------
# UI
#-----------------------------------------------------------------------------
func _connect_search() -> void:
	_search.text_changed.connect(_on_search_changed)

func _on_search_changed(new_text: String) -> void:
	_apply_filter(new_text)

func _apply_filter(q: String) -> void:
	var query: String = q.strip_edges()
	_filtered = []
	if query.is_empty():
		_filtered.assign(_all_participants)
	else:
		var q_lower: String = query.to_lower()
		for p in _all_participants:
			var name: String = _best_name(p).to_lower()
			if name.find(q_lower) >= 0:
				_filtered.append(p)
	_rebuild_list()

func _rebuild_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for p in _filtered:
		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label: Label = Label.new()
		var id_str: String = str(p.get("id", ""))
		var name: String = _best_name(p)
		label.text = "%s (%s)" % [name, id_str]
		row.add_child(label)
		_list.add_child(row)

func _best_name(p: Dictionary) -> String:
	var nickname: String = str(p.get("nickname", ""))
	var global_name: String = str(p.get("global_name", ""))
	var username: String = str(p.get("username", ""))
	if nickname != "":
		return nickname
	if global_name != "":
		return global_name
	return username
