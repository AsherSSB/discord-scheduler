extends Control
class_name EventSelect

#-----------------------------------------------------------------------------
# Exports
#-----------------------------------------------------------------------------
@export var topbar_path: NodePath
@export var join_modal_path: NodePath
@export var create_modal_path: NodePath
@export var event_grid_path: NodePath
@export var empty_state_path: NodePath
@export var toast_anchor_path: NodePath
@export var event_card_scene: PackedScene
@export var event_selected_scene: PackedScene
@export var debug_print: bool = false
@export var refresh_toast_text: String = "Events refreshed"

#-----------------------------------------------------------------------------
# Constants
#-----------------------------------------------------------------------------
const DEFAULT_EVENT_SELECTED_SCENE: String = "res://UI/Scenes/event_selected.tscn"

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
var _topbar: Node
var _join_modal: CanvasItem
var _create_modal: CanvasItem
var _event_grid: Container
var _empty_state: CanvasItem
var _toast_anchor: Control
var _original_order: Array[Node] = []
var _api: Api = Api
var _is_loading: bool = false

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	assert(topbar_path != NodePath(""), "EventSelect: topbar_path must be set")
	assert(join_modal_path != NodePath(""), "EventSelect: join_modal_path must be set")
	assert(create_modal_path != NodePath(""), "EventSelect: create_modal_path must be set")
	assert(event_grid_path != NodePath(""), "EventSelect: event_grid_path must be set")
	assert(empty_state_path != NodePath(""), "EventSelect: empty_state_path must be set")
	assert(toast_anchor_path != NodePath(""), "EventSelect: toast_anchor_path must be set")
	assert(event_card_scene != null, "EventSelect: event_card_scene must be set")

	_topbar = get_node(topbar_path)
	_join_modal = get_node(join_modal_path) as CanvasItem
	_create_modal = get_node(create_modal_path) as CanvasItem
	_event_grid = get_node(event_grid_path) as Container
	_empty_state = get_node(empty_state_path) as CanvasItem
	_toast_anchor = get_node(toast_anchor_path) as Control

	assert(_join_modal != null, "EventSelect: JoinModal not found")
	assert(_create_modal != null, "EventSelect: CreateEventModal not found")
	assert(_event_grid != null, "EventSelect: EventGrid not found")
	assert(_empty_state != null, "EventSelect: EmptyState not found")
	assert(_toast_anchor != null, "EventSelect: ToastAnchor not found")
	assert(_api != null, "EventSelect: Api autoload missing")
	assert(_api.service != null, "EventSelect: Api.service missing")

	_connect_topbar_signals()
	_connect_create_modal_signals()

	_cache_original_order()
	_apply_empty_state()

	_load_events()

#-----------------------------------------------------------------------------
# Wiring
#-----------------------------------------------------------------------------
func _connect_topbar_signals() -> void:
	_topbar.connect("join_requested", Callable(self, "_on_join"))
	_topbar.connect("new_event_requested", Callable(self, "_on_new_event"))
	_topbar.connect("refresh_requested", Callable(self, "_on_refresh"))
	_topbar.connect("search_changed", Callable(self, "_on_search_changed"))
	_topbar.connect("sort_changed", Callable(self, "_on_sort_changed"))

func _connect_create_modal_signals() -> void:
	var n: Node = _create_modal as Node
	n.connect("create_submitted", Callable(self, "_on_create_submitted"))

#-----------------------------------------------------------------------------
# UI Intents
#-----------------------------------------------------------------------------
func _on_join() -> void:
	_join_modal.visible = true
	if debug_print:
		print("EventSelect: Join modal opened")

func _on_new_event() -> void:
	_create_modal.visible = true
	if debug_print:
		print("EventSelect: Create modal opened")

func _on_refresh() -> void:
	_load_events(true)

func _on_search_changed(query: String) -> void:
	_filter_event_cards(query)
	_apply_empty_state()

func _on_sort_changed(_index: int, text: String) -> void:
	if text == "Name A–Z":
		_sort_cards_by_title(true)
	elif text == "Most participants":
		_restore_original_order()
	else:
		_restore_original_order()

#-----------------------------------------------------------------------------
# Service Calls
#-----------------------------------------------------------------------------
func _load_events(show_toast: bool = false) -> void:
	if _is_loading:
		return
	_is_loading = true
	if debug_print:
		print("EventSelect: Loading events...")

	var req: DeferredRequest = _api.service.list_events()
	var args: Array = await req.done
	var res: Dictionary = args[0] as Dictionary
	var err: String = String(args[1])

	_is_loading = false

	if err != "":
		push_error("Load events failed: %s" % err)
		return

	var items_typed: Array[Dictionary] = []
	var items_var: Variant = res.get("items", [])
	if typeof(items_var) == TYPE_ARRAY:
		for v in items_var:
			if typeof(v) == TYPE_DICTIONARY:
				items_typed.append(v)

	_rebuild_grid(items_typed)

	if show_toast:
		_show_toast(refresh_toast_text, 2.0)
	if debug_print:
		print("EventSelect: Loaded ", items_typed.size(), " events")

func _on_create_submitted(record: Dictionary) -> void:
	var existing: Node = _event_grid.get_node_or_null(
		"EventCard_%s" % String(record.get("id", ""))
	)
	if existing != null:
		existing.queue_free()
	var card: EventCard = _make_event_card(record)
	_event_grid.add_child(card)
	_original_order.append(card)
	_apply_empty_state()
	_show_toast("Event created", 2.0)
	if debug_print:
		print("EventSelect: Event appended -> ", record.get("id", ""))

#-----------------------------------------------------------------------------
# Event Grid Build
#-----------------------------------------------------------------------------
func _rebuild_grid(items: Array[Dictionary]) -> void:
	_clear_event_grid()
	for rec in items:
		var card: EventCard = _make_event_card(rec)
		_event_grid.add_child(card)
	_cache_original_order()
	_filter_event_cards("")
	_apply_empty_state()

func _clear_event_grid() -> void:
	for child in _event_grid.get_children():
		child.queue_free()

func _make_event_card(rec: Dictionary) -> EventCard:
	var inst: Node = event_card_scene.instantiate()
	var card: EventCard = inst as EventCard
	assert(card != null, "EventSelect: event_card_scene must be EventCard")

	card.set_record(rec)  # ensure data before connecting signals
	card.open_requested.connect(_on_card_open_requested)
	card.delete_requested.connect(_on_card_delete_requested)
	return card

#-----------------------------------------------------------------------------
# Card Handlers
#-----------------------------------------------------------------------------
func _on_card_open_requested(event_id: String, record: Dictionary) -> void:
	if debug_print:
		print("EventSelect: open -> ", event_id)
	if record.is_empty():
		push_warning("Open requested with empty record; ignoring.")
		return
	_go_to_event_selected(record)

func _on_card_delete_requested(event_id: String, _record: Dictionary) -> void:
	if debug_print:
		print("EventSelect: delete requested -> ", event_id)
	var req: DeferredRequest = _api.service.delete_event(event_id)
	var args: Array = await req.done
	var _res: Dictionary = args[0] as Dictionary
	var err: String = String(args[1])
	if err != "":
		push_error("Delete failed: %s" % err)
		return
	var card: Node = _event_grid.get_node_or_null("EventCard_%s" % event_id)
	if card != null:
		var idx: int = _original_order.find(card)
		if idx != -1:
			_original_order.remove_at(idx)
		card.queue_free()
	_apply_empty_state()
	_show_toast("Event deleted", 1.5)

#-----------------------------------------------------------------------------
# Navigation (Router-based)
#-----------------------------------------------------------------------------
func _go_to_event_selected(record: Dictionary) -> void:
	Session.set_current_event(record)
	var event_id := String(record.get("id", ""))
	Router.to_event_selected(event_id)

#-----------------------------------------------------------------------------
# Event Grid Helpers
#-----------------------------------------------------------------------------
func _cache_original_order() -> void:
	_original_order.clear()
	for child in _event_grid.get_children():
		_original_order.append(child)

func _apply_empty_state() -> void:
	var any_visible: bool = false
	for child in _event_grid.get_children():
		var node_ci: CanvasItem = child as CanvasItem
		if node_ci != null and node_ci.visible:
			any_visible = true
			break
	_empty_state.visible = not any_visible

func _filter_event_cards(query: String) -> void:
	var q: String = query.strip_edges().to_lower()
	for child in _event_grid.get_children():
		var card_node: Node = child
		var title: Label = card_node.find_child("CardTitle", true, false) as Label
		var meta: Label = card_node.find_child("CardMeta", true, false) as Label
		var text_blob: String = ""
		if title != null:
			text_blob += title.text + " "
		if meta != null:
			text_blob += meta.text
		var match: bool = q.is_empty() or text_blob.to_lower().find(q) != -1
		var card_ci: CanvasItem = card_node as CanvasItem
		if card_ci != null:
			card_ci.visible = match

func _sort_cards_by_title(ascending: bool) -> void:
	var pairs: Array[Dictionary] = []
	for child in _event_grid.get_children():
		var title: Label = child.find_child("CardTitle", true, false) as Label
		var key: String = ""
		if title != null:
			key = title.text
		pairs.append({"node": child, "key": key})
	pairs.sort_custom(Callable(self, "_compare_pairs").bind(ascending))
	for item in pairs:
		var node_ref: Node = item["node"]
		if node_ref.get_parent() == _event_grid:
			_event_grid.remove_child(node_ref)
		_event_grid.add_child(node_ref)

func _compare_pairs(a: Dictionary, b: Dictionary, ascending: bool) -> bool:
	var ka: String = a["key"]
	var kb: String = b["key"]
	if ascending:
		if ka == kb:
			return false
		return ka < kb
	if ka == kb:
		return false
	return ka > kb

func _restore_original_order() -> void:
	for node_ref in _original_order:
		if node_ref.get_parent() == _event_grid:
			_event_grid.remove_child(node_ref)
		_event_grid.add_child(node_ref)

#-----------------------------------------------------------------------------
# Toast
#-----------------------------------------------------------------------------
func _show_toast(text: String, seconds: float) -> void:
	_toast_anchor.visible = true

	var panel: PanelContainer = PanelContainer.new()
	var margin: MarginContainer = MarginContainer.new()
	var label: Label = Label.new()

	label.text = text
	panel.add_child(margin)
	margin.add_child(label)

	_toast_anchor.add_child(panel)
	panel.anchor_left = 1.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -16.0
	panel.offset_top = -16.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0

	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)

	var timer: SceneTreeTimer = get_tree().create_timer(seconds)
	timer.timeout.connect(func() -> void:
		panel.queue_free()
		if _toast_anchor.get_child_count() == 0:
			_toast_anchor.visible = false
	)
