extends Control

#-----------------------------------------------------------------------------
# Signals
#-----------------------------------------------------------------------------
signal create_submitted(payload: Dictionary)
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
@onready var _scrim: ColorRect = $Scrim
@onready var _name_edit: LineEdit = \
	$Dialog/DialogMargin/DialogVBox/FormScroll/Form/NameEdit
@onready var _start_time: OptionButton = \
	$Dialog/DialogMargin/DialogVBox/FormScroll/Form/TimeRow/StartTime
@onready var _start_period: OptionButton = \
	$Dialog/DialogMargin/DialogVBox/FormScroll/Form/TimeRow/StartPeriod
@onready var _end_time: OptionButton = \
	$Dialog/DialogMargin/DialogVBox/FormScroll/Form/TimeRow/EndTime
@onready var _end_period: OptionButton = \
	$Dialog/DialogMargin/DialogVBox/FormScroll/Form/TimeRow/EndPeriod
@onready var _slot_size: OptionButton = \
	$Dialog/DialogMargin/DialogVBox/FormScroll/Form/SlotRow/SlotSize
@onready var _timezone: OptionButton = \
	$Dialog/DialogMargin/DialogVBox/FormScroll/Form/TZRow/Timezone
@onready var _btn_cancel: Button = \
	$Dialog/DialogMargin/DialogVBox/ButtonsRow/CancelButton
@onready var _btn_create: Button = \
	$Dialog/DialogMargin/DialogVBox/ButtonsRow/CreateButton
@onready var _date_picker: Node = \
	$Dialog/DialogMargin/DialogVBox/FormScroll/Form/DateRangePicker

var _selected_dates: PackedStringArray = []
var _start_date: Calendar.Date = null
var _end_date: Calendar.Date = null
var _is_submitting: bool = false
var _api: Api = Api

#-----------------------------------------------------------------------------
# Constants
#-----------------------------------------------------------------------------
const STEP_MINUTES: int = 30
const MINUTES_PER_DAY: int = 24 * 60
const DEFAULT_START_INDEX: int = 16
const DEFAULT_END_INDEX: int = 12
const DEFAULT_START_PERIOD: int = 0
const DEFAULT_END_PERIOD: int = 1

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	assert(_scrim != null, "CreateEventModal: Scrim not found")
	assert(_name_edit != null, "CreateEventModal: NameEdit not found")
	assert(_start_time != null, "CreateEventModal: StartTime not found")
	assert(_start_period != null, "CreateEventModal: StartPeriod not found")
	assert(_end_time != null, "CreateEventModal: EndTime not found")
	assert(_end_period != null, "CreateEventModal: EndPeriod not found")
	assert(_slot_size != null, "CreateEventModal: SlotSize not found")
	assert(_timezone != null, "CreateEventModal: Timezone not found")
	assert(_btn_cancel != null, "CreateEventModal: Cancel not found")
	assert(_btn_create != null, "CreateEventModal: Create not found")
	assert(_api != null, "CreateEventModal: Api autoload missing")
	assert(_api.service != null, "CreateEventModal: Api.service missing")

	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_gui_input)

	_btn_cancel.pressed.connect(_on_cancel_pressed)
	_btn_create.pressed.connect(_on_create_pressed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	visibility_changed.connect(_on_visibility_changed)

	if is_instance_valid(_date_picker) and _date_picker.has_signal("range_changed"):
		_date_picker.range_changed.connect(_on_date_range_changed)

	_populate_defaults()
	_btn_create.disabled = true

	if auto_focus:
		_name_edit.grab_focus()
		_name_edit.select_all()

func open() -> void:
	visible = true
	if auto_focus:
		_name_edit.grab_focus()
		_name_edit.select_all()

func close() -> void:
	visible = false
	if clear_on_close:
		_reset_fields()
	closed.emit()
	if debug_print:
		print("CreateEventModal: closed")

#-----------------------------------------------------------------------------
# Input
#-----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE and not _is_submitting:
			close()

#-----------------------------------------------------------------------------
# Handlers
#-----------------------------------------------------------------------------
func _on_scrim_gui_input(event: InputEvent) -> void:
	if not visible or not close_on_scrim or _is_submitting:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		close()

func _on_cancel_pressed() -> void:
	if _is_submitting:
		return
	close()

func _on_create_pressed() -> void:
	if _is_submitting:
		return

	var event_name: String = _name_edit.text.strip_edges()
	if event_name.is_empty():
		_name_edit.grab_focus()
		return
	if _start_time.item_count == 0 or _end_time.item_count == 0:
		assert(false, "CreateEventModal: time dropdowns not initialized")
		return
	if _selected_dates.is_empty():
		if debug_print:
			print("CreateEventModal: select at least one date before \
creating.")
		_btn_create.disabled = true
		return

	var start_index: int = _start_time.selected
	var end_index: int = _end_time.selected
	var start_period_txt: String = _get_period_text(_start_period.selected)
	var end_period_txt: String = _get_period_text(_end_period.selected)

	var start_minutes: int = \
		_minutes_from_selection(start_index, start_period_txt)
	var end_minutes: int = \
		_minutes_from_selection(end_index, end_period_txt)

	if end_minutes <= start_minutes:
		_end_time.grab_focus()
		return

	var payload: Dictionary = _build_payload(
		event_name,
		start_index,
		end_index,
		start_period_txt,
		end_period_txt,
		start_minutes,
		end_minutes
	)

	if debug_print:
		_debug_dump_payload(payload)

	_submit_to_service(payload)

func _on_name_submitted(_text: String) -> void:
	_on_create_pressed()

func _on_visibility_changed() -> void:
	if visible and auto_focus:
		_name_edit.grab_focus()
		_name_edit.select_all()

func _on_date_range_changed(
	start_date: Calendar.Date,
	end_date: Calendar.Date,
	iso_list: PackedStringArray
) -> void:
	_start_date = start_date
	_end_date = end_date
	_selected_dates = iso_list
	_btn_create.disabled = _selected_dates.is_empty()
	if debug_print:
		print("CreateEventModal: date range -> ", iso_list)

#-----------------------------------------------------------------------------
# Service Submission
#-----------------------------------------------------------------------------
func _set_submit_enabled(enabled: bool) -> void:
	_btn_create.disabled = not enabled
	_btn_cancel.disabled = not enabled

func _submit_to_service(payload: Dictionary) -> void:
	_is_submitting = true
	_set_submit_enabled(false)

	var req: DeferredRequest = _api.service.create_event(payload)
	var done_args: Array = await req.done
	var result: Dictionary = done_args[0] as Dictionary
	var err: String = String(done_args[1])

	_is_submitting = false
	_set_submit_enabled(true)

	if err != "":
		push_error("Create failed: %s" % err)
		if debug_print:
			print("CreateEventModal: create failed -> ", err)
		return

	if debug_print:
		print("CreateEventModal: create ok -> ", result)

	create_submitted.emit(result)
	close()

#-----------------------------------------------------------------------------
# Payload
#-----------------------------------------------------------------------------
func _build_payload(
	event_name: String,
	start_index: int,
	end_index: int,
	start_period_txt: String,
	end_period_txt: String,
	start_minutes: int,
	end_minutes: int
) -> Dictionary:
	var start_label: String = "%s %s" % \
		[_start_time.get_item_text(start_index), start_period_txt]
	var end_label: String = "%s %s" % \
		[_end_time.get_item_text(end_index), end_period_txt]
	var slot_label: String = _slot_size.get_item_text(_slot_size.selected)
	var tz_label: String = _timezone.get_item_text(_timezone.selected)

	var slot_minutes: int = 30
	if slot_label.begins_with("15"):
		slot_minutes = 15
	elif slot_label.begins_with("60"):
		slot_minutes = 60

	var range_block: Dictionary = {}
	if _start_date != null and _end_date != null:
		range_block = {
			"start": {"y": _start_date.year, "m": _start_date.month,
				"d": _start_date.day},
			"end": {"y": _end_date.year, "m": _end_date.month,
				"d": _end_date.day}
		}

	return {
		"name": event_name,
		"start_index": start_index,
		"end_index": end_index,
		"start_period": start_period_txt,
		"end_period": end_period_txt,
		"start_minutes": start_minutes,
		"end_minutes": end_minutes,
		"start_label": start_label,
		"end_label": end_label,
		"slot_minutes": slot_minutes,
		"timezone": tz_label,
		"dates_iso": _selected_dates.duplicate(),
		"range": range_block
	}

#-----------------------------------------------------------------------------
# Defaults
#-----------------------------------------------------------------------------
func _populate_defaults() -> void:
	if _start_time.item_count == 0:
		_add_half_day_no_period(_start_time)
	if _end_time.item_count == 0:
		_add_half_day_no_period(_end_time)

	if _start_period.item_count == 0:
		_start_period.add_item("AM")
		_start_period.add_item("PM")
	if _end_period.item_count == 0:
		_end_period.add_item("AM")
		_end_period.add_item("PM")

	if _slot_size.item_count == 0:
		_slot_size.add_item("15 min", 15)
		_slot_size.add_item("30 min", 30)
		_slot_size.add_item("60 min", 60)
		_slot_size.select(1)

	if _timezone.item_count == 0:
		_timezone.add_item("Local (Auto)")
		_timezone.add_item("America/Chicago")
		_timezone.add_item("America/Los_Angeles")
		_timezone.add_item("UTC")
		_timezone.select(0)

	_start_time.select(DEFAULT_START_INDEX)
	_end_time.select(DEFAULT_END_INDEX)
	_start_period.select(DEFAULT_START_PERIOD)
	_end_period.select(DEFAULT_END_PERIOD)

#-----------------------------------------------------------------------------
# Mutators
#-----------------------------------------------------------------------------
func _add_half_day_no_period(target: OptionButton) -> void:
	target.clear()
	var labels: PackedStringArray = _build_12h_no_period_labels()
	for i: int in range(labels.size()):
		target.add_item(labels[i], i)

func _reset_fields() -> void:
	_name_edit.clear()
	_start_time.select(DEFAULT_START_INDEX)
	_end_time.select(DEFAULT_END_INDEX)
	_start_period.select(DEFAULT_START_PERIOD)
	_end_period.select(DEFAULT_END_PERIOD)
	if _slot_size.item_count > 0:
		_slot_size.select(1)
	if _timezone.item_count > 0:
		_timezone.select(0)
	_selected_dates.clear()
	_start_date = null
	_end_date = null
	if is_instance_valid(_date_picker) and _date_picker.has_method("clear_range"):
		_date_picker.clear_range()
	_btn_create.disabled = true

#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------
func _build_12h_no_period_labels() -> PackedStringArray:
	var labels: PackedStringArray = []
	for i: int in range(24):
		var minutes: int = i * STEP_MINUTES
		labels.append(_format_12h_no_period(minutes))
	return labels

func _format_12h_no_period(total_minutes: int) -> String:
	var hour24: int = floori(float(total_minutes) / 60.0)
	var minute: int = total_minutes % 60
	var hour12: int = hour24 % 12
	if hour12 == 0:
		hour12 = 12
	var mm: String = str(minute).pad_zeros(2)
	return "%d:%s" % [hour12, mm]

func _get_period_text(idx: int) -> String:
	if idx == 0:
		return "AM"
	return "PM"

func _minutes_from_selection(index: int, period_txt: String) -> int:
	var base: int = index * STEP_MINUTES
	if period_txt == "AM":
		return base
	return 12 * 60 + base

func _debug_dump_payload(p: Dictionary) -> void:
	var lines: PackedStringArray = []
	lines.append("CreateEventModal: payload")
	lines.append("  name: %s" % p.get("name", ""))
	lines.append("  start_label: %s" % p.get("start_label", ""))
	lines.append("  end_label: %s" % p.get("end_label", ""))
	lines.append("  start_period: %s" % p.get("start_period", ""))
	lines.append("  end_period: %s" % p.get("end_period", ""))
	lines.append("  start_index: %d" % int(p.get("start_index", -1)))
	lines.append("  end_index: %d" % int(p.get("end_index", -1)))
	lines.append("  start_minutes: %d" % int(p.get("start_minutes", -1)))
	lines.append("  end_minutes: %d" % int(p.get("end_minutes", -1)))
	lines.append("  slot_minutes: %d" % int(p.get("slot_minutes", -1)))
	lines.append("  timezone: %s" % p.get("timezone", ""))
	var dates: PackedStringArray = p.get("dates_iso", PackedStringArray())
	lines.append("  dates_iso: [%s]" % ",".join(dates))
	var range_block: Dictionary = p.get("range", {})
	lines.append("  range: %s" % str(range_block))
	print("\n".join(lines))
