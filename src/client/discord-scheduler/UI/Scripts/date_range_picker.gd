extends Control

# ────────────────────────────────────────────────────────────────────────────
# Signals & state
# ────────────────────────────────────────────────────────────────────────────
signal range_changed(start_date: Calendar.Date, end_date: Calendar.Date, iso_list: PackedStringArray)

var cal: Calendar = Calendar.new()
var year: int
var month: int

var _start: Calendar.Date = null
var _end:   Calendar.Date = null

var _day_buttons: Array[Button] = []

# ────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	cal.set_first_weekday(Time.WEEKDAY_MONDAY)

	var today: Calendar.Date = Calendar.Date.today()
	year = today.year
	month = today.month

	if $VBox/Grid is GridContainer:
		var grid := $VBox/Grid as GridContainer
		grid.columns = 7

	_populate_weekday_row()
	_refresh_month_view()

	$VBox/Toolbar/PrevMonth.pressed.connect(_on_prev_month)
	$VBox/Toolbar/NextMonth.pressed.connect(_on_next_month)

# ────────────────────────────────────────────────────────────────────────────
# View building
# ────────────────────────────────────────────────────────────────────────────
func _populate_weekday_row() -> void:
	var row := $VBox/Weekdays
	for c in row.get_children():
		c.queue_free()
	var names: Array[String] = cal.get_weekdays_formatted(Calendar.WeekdayFormat.WEEKDAY_FORMAT_ABBR)
	for n in names:
		var lbl := Label.new()
		lbl.text = n
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

func _refresh_month_view() -> void:
	var title := "%s %d" % [cal.get_month_formatted(month, Calendar.MonthFormat.MONTH_FORMAT_FULL), year]
	$VBox/Toolbar/MonthLabel.text = title

	var grid := $VBox/Grid
	for c in grid.get_children():
		c.queue_free()
	_day_buttons.clear()

	var weeks: Array = cal.get_calendar_month(year, month, true, true)

	for week in weeks:
		for any in week:
			var d: Calendar.Date = any

			var btn := Button.new()
			btn.toggle_mode = true
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.focus_mode = Control.FOCUS_NONE

			var is_current: bool = (d.month == month)
			btn.text = str(d.day) if is_current else ""
			btn.disabled = not is_current
			btn.modulate = Color(1, 1, 1, 1) if is_current else Color(1, 1, 1, 0.35)

			btn.set_meta("date", d.duplicate())

			btn.pressed.connect(func(): _on_day_pressed(btn))

			grid.add_child(btn)
			_day_buttons.append(btn)

	_populate_weekday_row()

	_update_highlight()
	_update_summary()

# ────────────────────────────────────────────────────────────────────────────
# Interaction
# ────────────────────────────────────────────────────────────────────────────
func _on_day_pressed(btn: Button) -> void:
	var d: Calendar.Date = btn.get_meta("date")

	if _start == null or (_start != null and _end != null):
		_start = d.duplicate()
		_end = null
	elif _end == null:
		_end = d.duplicate()
		if _end.is_before(_start):
			var tmp := _start
			_start = _end
			_end = tmp

	_update_highlight()
	_update_summary()

	if _start != null and _end != null:
		emit_signal("range_changed", _start.duplicate(), _end.duplicate(), _get_selected_iso_list())

func _on_prev_month() -> void:
	month -= 1
	if month < 1:
		month = 12
		year -= 1
	_refresh_month_view()

func _on_next_month() -> void:
	month += 1
	if month > 12:
		month = 1
		year += 1
	_refresh_month_view()

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────
func _update_highlight() -> void:
	for btn in _day_buttons:
		var d: Calendar.Date = btn.get_meta("date")
		var in_range: bool = false
		if _start != null and _end != null:
			in_range = not d.is_before(_start) and not d.is_after(_end)
		elif _start != null and _end == null:
			in_range = d.is_equal(_start)
		btn.button_pressed = in_range

func _update_summary() -> void:
	if _start == null and _end == null:
		$VBox/Summary.text = "Select a start and end date…"
		return

	if _start != null and _end == null:
		var s := cal.get_date_formatted(_start.year, _start.month, _start.day, "%a, %b %-d")
		$VBox/Summary.text = "Start: %s" % s
		return

	if _start != null and _end != null:
		var s := cal.get_date_formatted(_start.year, _start.month, _start.day, "%a, %b %-d")
		var e := cal.get_date_formatted(_end.year, _end.month, _end.day, "%a, %b %-d")
		var count := _get_selected_iso_list().size()
		$VBox/Summary.text = "%s – %s  •  %d day%s" % [s, e, count, "" if count == 1 else "s"]

func _get_selected_iso_list() -> PackedStringArray:
	var out: PackedStringArray = []
	if _start == null or _end == null:
		return out
	var cur: Calendar.Date = _start.duplicate()
	while true:
		out.append(cal.get_date_formatted(cur.year, cur.month, cur.day, "%F"))
		if cur.is_equal(_end):
			break
		cur.add_days(1)
	return out

# ────────────────────────────────────────────────────────────────────────────
# Public API
# ────────────────────────────────────────────────────────────────────────────
func set_month_year(p_year: int, p_month: int) -> void:
	year = p_year
	month = p_month
	_refresh_month_view()

func set_first_weekday(weekday: Time.Weekday) -> void:
	cal.set_first_weekday(weekday)
	_populate_weekday_row()
	_refresh_month_view()

func set_range(start_date: Calendar.Date, end_date: Calendar.Date) -> void:
	_start = start_date.duplicate()
	_end = end_date.duplicate()
	year = _start.year
	month = _start.month
	_refresh_month_view()

func clear_range() -> void:
	_start = null
	_end = null
	_update_highlight()
	_update_summary()

func get_range() -> Dictionary:
	return {
		"start": _start if _start == null else _start.duplicate(),
		"end":   _end   if _end   == null else _end.duplicate(),
		"iso":   _get_selected_iso_list()
	}
