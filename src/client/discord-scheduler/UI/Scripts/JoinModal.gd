extends Control

#-----------------------------------------------------------------------------
# Signals
#-----------------------------------------------------------------------------
signal join_submitted(code: String)
signal closed()

#-----------------------------------------------------------------------------
# Exports
#-----------------------------------------------------------------------------
@export var close_on_scrim: bool = true
@export var clear_on_close: bool = true
@export var auto_focus: bool = true
@export var debug_print: bool = false

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
@onready var _scrim: ColorRect = $JoinScrim
@onready var _edit: LineEdit = $JoinDialog/JoinMargin/JoinVBox/JoinEdit
@onready var _btn_cancel: Button = $JoinDialog/JoinMargin/JoinVBox/JoinButtons/JoinCancel
@onready var _btn_confirm: Button = $JoinDialog/JoinMargin/JoinVBox/JoinButtons/JoinConfirm

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	assert(_scrim != null, "JoinModal: JoinScrim not found")
	assert(_edit != null, "JoinModal: JoinEdit not found")
	assert(_btn_cancel != null, "JoinModal: JoinCancel not found")
	assert(_btn_confirm != null, "JoinModal: JoinConfirm not found")

	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_gui_input)

	_btn_cancel.pressed.connect(_on_cancel_pressed)
	_btn_confirm.pressed.connect(_on_confirm_pressed)
	_edit.text_submitted.connect(_on_text_submitted)
	visibility_changed.connect(_on_visibility_changed)

	if auto_focus:
		_edit.grab_focus()
		_edit.select_all()

#-----------------------------------------------------------------------------
# Public API
#-----------------------------------------------------------------------------
func open() -> void:
	visible = true
	if auto_focus:
		_edit.grab_focus()
		_edit.select_all()

func close() -> void:
	visible = false
	if clear_on_close:
		_edit.clear()
	closed.emit()
	if debug_print:
		print("JoinModal: closed")

#-----------------------------------------------------------------------------
# Input
#-----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE:
			close()

func _on_scrim_gui_input(event: InputEvent) -> void:
	if not visible or not close_on_scrim:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		close()

#-----------------------------------------------------------------------------
# UI Callbacks
#-----------------------------------------------------------------------------
func _on_cancel_pressed() -> void:
	close()

func _on_confirm_pressed() -> void:
	var code: String = _edit.text.strip_edges()
	if code.is_empty():
		_edit.grab_focus()
		return
	join_submitted.emit(code)
	close()
	if debug_print:
		print("JoinModal: submitted -> ", code)

func _on_text_submitted(_text: String) -> void:
	_on_confirm_pressed()

func _on_visibility_changed() -> void:
	if visible and auto_focus:
		_edit.grab_focus()
		_edit.select_all()
