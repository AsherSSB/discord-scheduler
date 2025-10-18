extends Node

#-----------------------------------------------------------------------------
# Exports
#-----------------------------------------------------------------------------
@export var event_select_path: NodePath
@export var event_selected_path: NodePath
@export var test_cycle_seconds: float = 5.0
@export var debug_cycle_enabled: bool = false 

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
var _event_select: CanvasItem
var _event_selected: CanvasItem
var _event_selected_ui: EventSelected
var _test_timer: Timer

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	assert(event_select_path != NodePath(""), "AppRoot: event_select_path must be assigned")
	assert(event_selected_path != NodePath(""), "AppRoot: event_selected_path must be assigned")

	_event_select = get_node(event_select_path) as CanvasItem
	_event_selected = get_node(event_selected_path) as CanvasItem
	_event_selected_ui = _event_selected as EventSelected

	assert(_event_select != null, "AppRoot: EventSelect node not found")
	assert(_event_selected != null, "AppRoot: EventSelected node not found")

	Router.screen_changed.connect(_on_screen_changed)
	_apply_screen(Router.current_screen(), Router.current_params())

	if debug_cycle_enabled:
		_start_test_cycle()

#-----------------------------------------------------------------------------
# Private
#-----------------------------------------------------------------------------
func _apply_screen(screen_name: StringName, params: Dictionary) -> void:
	_event_select.visible = false
	_event_selected.visible = false

	if screen_name == Router.SCREEN_EVENT_SELECT:
		_event_select.visible = true
		if _event_select.has_method("on_show"):
			_event_select.call_deferred("on_show")
	elif screen_name == Router.SCREEN_EVENT_SELECTED:
		_event_selected.visible = true
		if _event_selected_ui and _event_selected_ui.has_method("show_screen"):
			_event_selected_ui.call_deferred("show_screen", params)
	else:
		assert(false, "AppRoot: Unknown screen '%s'" % [screen_name])

func _start_test_cycle() -> void:
	if _test_timer != null:
		return
	_test_timer = Timer.new()
	_test_timer.wait_time = test_cycle_seconds
	_test_timer.one_shot = false
	add_child(_test_timer)
	_test_timer.timeout.connect(_on_test_timeout)
	_test_timer.start()

func _stop_test_cycle() -> void:
	if _test_timer == null:
		return
	_test_timer.stop()
	_test_timer.queue_free()
	_test_timer = null

#-----------------------------------------------------------------------------
# Autoload Callbacks
#-----------------------------------------------------------------------------
func _on_screen_changed(screen_name: StringName, params: Dictionary) -> void:
	_apply_screen(screen_name, params)

#-----------------------------------------------------------------------------
# Test Harness
#-----------------------------------------------------------------------------
func _on_test_timeout() -> void:
	var current: StringName = Router.current_screen()
	if current == Router.SCREEN_EVENT_SELECT:
		Router.to_event_selected("demo-event")
	else:
		Router.to_event_select()

#-----------------------------------------------------------------------------
# Debug Control
#-----------------------------------------------------------------------------
func set_debug_cycle_enabled(enabled: bool) -> void:
	debug_cycle_enabled = enabled
	if enabled:
		_start_test_cycle()
	else:
		_stop_test_cycle()
