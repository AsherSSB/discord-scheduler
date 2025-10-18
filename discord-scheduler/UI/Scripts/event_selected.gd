extends Control
class_name EventSelected

@export var grid_pane_path: NodePath = NodePath("SafeArea/App/MainContent/GridPane")
@export var save_button_path: NodePath
@export var edit_button_path: NodePath
@export var cancel_button_path: NodePath
@export var status_label_path: NodePath
@export var back_button_path: NodePath = NodePath("SafeArea/App/ActionBar/BackToEvents")
@export var debug_print: bool = false

var _grid: GridPane
var _session: Session = Session
var _api: Api = Api

var _btn_save: Button
var _btn_edit: Button
var _btn_cancel: Button
var _btn_back: Button
var _status: Label

var _event_rec: Dictionary = {}
var _event_id: String = ""
var _editing: bool = true
var _saved_indices: PackedInt32Array = PackedInt32Array()

var _right_sidebar: RightSidebar

func _ready() -> void:
	_grid = _resolve_grid()
	assert(_grid != null, "EventSelected: GridPane not found")
	assert(_session != null, "EventSelected: Session autoload missing")

	_btn_save = get_node_or_null(save_button_path) as Button
	_btn_edit = get_node_or_null(edit_button_path) as Button
	_btn_cancel = get_node_or_null(cancel_button_path) as Button
	_btn_back = get_node_or_null(back_button_path) as Button
	_status = get_node_or_null(status_label_path) as Label

	if _btn_save != null:
		_btn_save.pressed.connect(_on_save_pressed)
	if _btn_edit != null:
		_btn_edit.pressed.connect(_on_edit_pressed)
	if _btn_cancel != null:
		_btn_cancel.pressed.connect(_on_cancel_pressed)
	if _btn_back != null:
		_btn_back.pressed.connect(_on_back_pressed)

	_right_sidebar = get_node_or_null("SafeArea/App/MainContent/RightSidebar") as RightSidebar
	if _right_sidebar != null:
		_right_sidebar.clear_hover()
		_right_sidebar.visible = true

	if _grid != null and _grid.has_signal("hover_changed"):
		if not _grid.hover_changed.is_connected(_on_grid_hover_changed):
			_grid.hover_changed.connect(_on_grid_hover_changed)

func show_screen(params: Dictionary) -> void:
	_event_rec = _session.current_event

	if _event_rec.is_empty() and params.has("id") and _api != null and _api.service != null:
		var req: DeferredRequest = _api.service.get_event(String(params["id"]))
		var args: Array = await req.done
		var res: Dictionary = args[0] as Dictionary
		var err: String = String(args[1])
		if err == "":
			_event_rec = res
			_session.set_current_event(_event_rec)

	if _event_rec.is_empty():
		push_error("EventSelected: no current event (session and params empty)")
		return

	_event_id = String(_event_rec.get("id", ""))
	_grid.set_event(_event_rec, _session.current_user_id)

	Availability.ensure_event(_event_id, _grid.get_total_cells())
	Availability.seed_fake_users(
		_event_id,
		PackedStringArray(["alex","bailey","casey","drew"]),
		0.14
	)

	await _load_user_availability()

	if _saved_indices.size() == 0:
		_enter_edit()
	else:
		_exit_edit()

	await _refresh_heat_if_view()

	if debug_print:
		print("EventSelected: loaded ", String(_event_rec.get("name", "")))

func _enter_edit() -> void:
	_editing = true
	_grid.set_edit_mode(true)
	_grid.set_heat_counts(PackedInt32Array())
	_update_buttons()

func _exit_edit() -> void:
	_editing = false
	_grid.set_edit_mode(false)
	_update_buttons()

func _update_buttons() -> void:
	if _btn_save != null:
		_btn_save.visible = _editing
	if _btn_cancel != null:
		_btn_cancel.visible = _editing
	if _btn_edit != null:
		_btn_edit.visible = not _editing
	if _status != null:
		if _editing:
			_status.text = "Select your availability, then Save"
		else:
			_status.text = "Heatmap view"

func _on_save_pressed() -> void:
	var indices: PackedInt32Array = _grid.get_selected_indices()
	_saved_indices = indices.duplicate()
	Availability.set_user_indices(_event_id, _session.current_user_id, indices)
	_exit_edit()
	await _refresh_heat_if_view()

func _on_edit_pressed() -> void:
	_grid.set_mine_indices(_saved_indices)
	_enter_edit()

func _on_cancel_pressed() -> void:
	_grid.set_mine_indices(_saved_indices)
	_exit_edit()
	await _refresh_heat_if_view()

func _on_back_pressed() -> void:
	Router.to_event_select()

func _load_user_availability() -> void:
	_saved_indices = Availability.get_user_indices(_event_id, _session.current_user_id)
	if _saved_indices.size() > 0:
		_grid.set_mine_indices(_saved_indices)
	else:
		_grid.clear_mine()

func _refresh_heat_if_view() -> void:
	if _editing:
		return
	var counts: PackedInt32Array = Availability.compute_heat_counts(
		_event_id,
		_session.current_user_id
	)
	_grid.set_heat_counts(counts)

func _on_grid_hover_changed(idx: int) -> void:
	if _right_sidebar == null:
		return
	if idx < 0:
		_right_sidebar.clear_hover()
		return

	var labels: Dictionary = _grid.labels_for_index(idx)
	var start_label: String = String(labels.get("start_label", ""))
	var end_label: String = String(labels.get("end_label", ""))
	var weekday: String = String(labels.get("weekday", ""))
	var date_line: String = String(labels.get("date_label", ""))

	var avail_ids: PackedStringArray = PackedStringArray()
	var unavail_ids: PackedStringArray = PackedStringArray()

	if Availability.has_method("users_at_cell"):
		var who: Dictionary = Availability.users_at_cell(_event_id, idx)
		avail_ids = who.get("available", PackedStringArray())
		unavail_ids = who.get("unavailable", PackedStringArray())
	else:
		var all_users: PackedStringArray = PackedStringArray()
		if Availability.has_method("get_all_user_ids"):
			all_users = Availability.get_all_user_ids(_event_id)
		else:
			all_users = PackedStringArray(["alex","bailey","casey","drew", _session.current_user_id])

		for uid: String in all_users:
			var indices: PackedInt32Array = Availability.get_user_indices(_event_id, uid)
			var found: bool = false
			for k: int in indices:
				if k == idx:
					found = true
					break
			if found:
				avail_ids.append(uid)
			else:
				unavail_ids.append(uid)

	var avail_names := _ids_to_display_names(avail_ids, true)
	var unavail_names := _ids_to_display_names(unavail_ids, true)

	var total_users: int = avail_names.size() + unavail_names.size()
	var when_line: String = "%s %s–%s" % [weekday, start_label, end_label]
	if date_line != "":
		when_line = "%s\n%s" % [when_line, date_line]

	_right_sidebar.show_hover(avail_names.size(), total_users, when_line, avail_names, unavail_names)
	_right_sidebar.visible = true

func _ids_to_display_names(ids: PackedStringArray, show_you: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids:
		var s: String = String(id)
		if show_you and s == _session.current_user_id:
			out.append("You")
		else:
			out.append(s)
	return out

func _resolve_grid() -> GridPane:
	var node_ref: Node = null
	if grid_pane_path != NodePath(""):
		node_ref = get_node_or_null(grid_pane_path)
	if node_ref == null:
		node_ref = get_node_or_null("SafeArea/App/MainContent/GridPane")
	if node_ref == null:
		node_ref = find_child("GridPane", true, false)
	return node_ref as GridPane
