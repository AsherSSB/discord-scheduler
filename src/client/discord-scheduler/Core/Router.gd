extends Node

#-----------------------------------------------------------------------------
# Signals
#-----------------------------------------------------------------------------
signal screen_changed(screen_name: StringName, params: Dictionary)

#-----------------------------------------------------------------------------
# Constants
#-----------------------------------------------------------------------------
const SCREEN_EVENT_SELECT: StringName = &"event_select"
const SCREEN_EVENT_SELECTED: StringName = &"event_selected"

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
var _valid_screens: Array[StringName] = [
	SCREEN_EVENT_SELECT,
	SCREEN_EVENT_SELECTED
]

var _current_screen: StringName = SCREEN_EVENT_SELECT
var _current_params: Dictionary = {}

var _history: Array[StringName] = []
var _history_params: Array[Dictionary] = []

#-----------------------------------------------------------------------------
# Public API
#-----------------------------------------------------------------------------
func goto(screen_name: StringName, params: Dictionary = {}) -> void:
	assert(_valid_screens.has(screen_name),
		"Router: Unknown screen: %s" % [screen_name])
	if screen_name == _current_screen and params == _current_params:
		return
	_history.append(_current_screen)
	_history_params.append(_current_params.duplicate(true))
	_current_screen = screen_name
	_current_params = params.duplicate(true)
	screen_changed.emit(_current_screen, _current_params)

func replace(screen_name: StringName, params: Dictionary = {}) -> void:
	assert(_valid_screens.has(screen_name),
		"Router: Unknown screen: %s" % [screen_name])
	_current_screen = screen_name
	_current_params = params.duplicate(true)
	screen_changed.emit(_current_screen, _current_params)

func back() -> void:
	if _history.is_empty():
		return
	_current_screen = _history.pop_back()
	_current_params = _history_params.pop_back()
	screen_changed.emit(_current_screen, _current_params)

func reset_to_default() -> void:
	_history.clear()
	_history_params.clear()
	_current_screen = SCREEN_EVENT_SELECT
	_current_params.clear()
	screen_changed.emit(_current_screen, _current_params)

func current_screen() -> StringName:
	return _current_screen

func current_params() -> Dictionary:
	return _current_params

func valid_screens() -> Array[StringName]:
	return _valid_screens.duplicate()

#-----------------------------------------------------------------------------
# Convenience Shortcuts
#-----------------------------------------------------------------------------
func to_event_select() -> void:
	goto(SCREEN_EVENT_SELECT)

func to_event_selected(event_id: String = "") -> void:
	var params: Dictionary = {}
	if event_id != "":
		params["id"] = event_id
	goto(SCREEN_EVENT_SELECTED, params)
