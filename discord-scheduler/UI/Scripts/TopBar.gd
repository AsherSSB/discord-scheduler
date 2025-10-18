extends HBoxContainer

#-----------------------------------------------------------------------------
# Signals
#-----------------------------------------------------------------------------
signal join_requested()
signal new_event_requested()
signal refresh_requested()
signal search_changed(query: String)
signal sort_changed(index: int, text: String)

#-----------------------------------------------------------------------------
# Exports
#-----------------------------------------------------------------------------
@export var debug_print: bool = false

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
var _title: Label
var _search: LineEdit
var _sort: OptionButton
var _btn_join: Button
var _btn_new: Button
var _btn_refresh: Button

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	_title = get_node("AppTitle") as Label
	_search = get_node("Search") as LineEdit
	_sort = get_node("SortDropdown") as OptionButton
	_btn_join = get_node("JoinButton") as Button
	_btn_new = get_node("NewEventButton") as Button
	_btn_refresh = get_node("RefreshButton") as Button

	assert(_title != null, "TopBar: AppTitle not found")
	assert(_search != null, "TopBar: Search not found")
	assert(_sort != null, "TopBar: SortDropdown not found")
	assert(_btn_join != null, "TopBar: JoinButton not found")
	assert(_btn_new != null, "TopBar: NewEventButton not found")
	assert(_btn_refresh != null, "TopBar: RefreshButton not found")

	if _sort.item_count == 0:
		_sort.add_item("Recent")
		_sort.add_item("Name A–Z")
		_sort.add_item("Most participants")

	_search.text_changed.connect(_on_search_text_changed)
	_sort.item_selected.connect(_on_sort_selected)
	_btn_join.pressed.connect(_on_join_pressed)
	_btn_new.pressed.connect(_on_new_pressed)
	_btn_refresh.pressed.connect(_on_refresh_pressed)

#-----------------------------------------------------------------------------
# Public API
#-----------------------------------------------------------------------------
func set_username(username: String) -> void:
	var base: String = _title.text
	var tag: String = "{username}"
	if base.contains(tag):
		_title.text = base.replace(tag, username)
	else:
		_title.text = "%s %s" % [base, username]

func set_search_text(text: String) -> void:
	_search.text = text
	search_changed.emit(text)

func clear_search() -> void:
	_search.clear()
	search_changed.emit("")

func focus_search() -> void:
	_search.grab_focus()

func set_sort_options(options: PackedStringArray, selected_index: int = 0) -> void:
	_sort.clear()
	for i in options.size():
		_sort.add_item(options[i])
	if selected_index >= 0 and selected_index < _sort.item_count:
		_sort.select(selected_index)
		var label: String = _sort.get_item_text(selected_index)
		sort_changed.emit(selected_index, label)

#-----------------------------------------------------------------------------
# UI Callbacks
#-----------------------------------------------------------------------------
func _on_join_pressed() -> void:
	if debug_print:
		print("TopBar: join_requested")
	join_requested.emit()

func _on_new_pressed() -> void:
	if debug_print:
		print("TopBar: new_event_requested")
	new_event_requested.emit()

func _on_refresh_pressed() -> void:
	if debug_print:
		print("TopBar: refresh_requested")
	refresh_requested.emit()

func _on_search_text_changed(text: String) -> void:
	if debug_print:
		print("TopBar: search_changed -> ", text)
	search_changed.emit(text)

func _on_sort_selected(index: int) -> void:
	var label: String = _sort.get_item_text(index)
	if debug_print:
		print("TopBar: sort_changed -> ", index, " ", label)
	sort_changed.emit(index, label)
