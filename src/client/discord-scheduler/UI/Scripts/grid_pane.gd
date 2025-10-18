extends PanelContainer
class_name GridPane

signal availability_changed(user_id: String, indices: PackedInt32Array)
signal hover_changed(index: int)

@export var debug_print: bool = false
@export var header_left_px: int = 64
@export var header_top_px: int = 28
@export var cell_height_px: int = 20
@export var cell_width_px: int = 100
@export var base_color: Color = Color(0.039, 0.741, 0.89, 0.85)
@export var others_color: Color = Color(0.282, 0.859, 0.984, 0.5)
@export var grid_line_color: Color = Color(0, 0, 0, 0.08)
@export var max_days: int = 60
@export var max_rows: int = 24 * 12
@export var max_cells: int = 5000
@export var heat_opacity_cap: int = 6

@export var outline_self_color: Color = Color(0.039, 0.741, 0.89, 1.0)
@export var outline_others_color: Color = Color(0, 0, 0, 0.25)
@export var outline_self_width: float = 2.0
@export var outline_others_width: float = 1.0
@export var edit_outline_color: Color = Color(0, 0, 0, 0.08)
@export var edit_outline_width: float = 1.0

@export var enable_hover_highlight: bool = true
@export var hover_outline_color: Color = Color(1, 1, 1, 0.9)
@export var hover_outline_width: float = 2.0
@export var hover_fill_color: Color = Color(1, 1, 1, 0.12)
@export var hover_show_fill: bool = true

@export var grid_pad_x: int = 6
@export var grid_pad_y: int = 4

@export var left_gap_px: int = 8
@export var header_gap_px: int = 8

@onready var _column: Control = $Column
@onready var _grid_area: Control = $Column/GridArea
@onready var _grid_canvas: Control = $Column/GridArea/GridCanvas
@onready var _sticky: Control = $Column/GridArea/StickyHeaders
@onready var _corner: PanelContainer = $Column/GridArea/StickyHeaders/Corner
@onready var _top_header: HBoxContainer = $Column/GridArea/StickyHeaders/TopHeader
@onready var _left_header: VBoxContainer = $Column/GridArea/StickyHeaders/LeftHeader

var _event: Dictionary = {}
var _user_id: String = ""

var _days_iso: PackedStringArray = PackedStringArray()
var _start_min: int = 9 * 60
var _end_min: int = 17 * 60
var _step_min: int = 30

var _rows: int = 0
var _cols: int = 0

var _heat: PackedInt32Array = PackedInt32Array()
var _mine: PackedInt32Array = PackedInt32Array()
var _heat_max: int = 0

var _drag_active: bool = false
var _drag_set_value: int = 0
var _edit_mode: bool = true
var _hover_idx: int = -1

func _ready() -> void:
	assert(_grid_canvas != null, "GridPane: GridCanvas not found")
	assert(_sticky != null, "GridPane: StickyHeaders not found")
	assert(_corner != null, "GridPane: Corner not found")
	assert(_top_header != null, "GridPane: TopHeader not found")
	assert(_left_header != null, "GridPane: LeftHeader not found")

	mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sticky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

	set_process_unhandled_input(true)
	item_rect_changed.connect(_on_item_rect_changed)
	_grid_canvas.item_rect_changed.connect(_on_any_rect_changed)
	resized.connect(_on_any_rect_changed)
	get_viewport().size_changed.connect(_on_any_rect_changed)
	_on_item_rect_changed()

	if debug_print:
		print("GridPane: ready pane_filter=", mouse_filter, " canvas_filter=", _grid_canvas.mouse_filter, " column_filter=", _column.mouse_filter, " grid_area_filter=", _grid_area.mouse_filter)

func _on_item_rect_changed() -> void:
	_on_any_rect_changed()

func _on_any_rect_changed() -> void:
	_layout_headers()
	queue_redraw()
	if debug_print:
		var r: Rect2 = get_global_rect()
		var c: Rect2 = _grid_canvas.get_global_rect()
		print("GridPane: rect_changed pane=", r, " canvas=", c, " off=", _center_offset())

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _hover_idx != -1:
			_hover_idx = -1
			queue_redraw()
			hover_changed.emit(-1)

func set_event(rec: Dictionary, current_user_id: String) -> void:
	_event = rec.duplicate()
	_user_id = current_user_id
	_parse_event()
	_build_headers()
	_alloc_buffers()
	_update_min_size()
	_layout_headers()
	_hover_idx = -1
	queue_redraw()
	if debug_print:
		var gp: Vector2 = _grid_pixel_size()
		print("GridPane: set_event rows=", _rows, " cols=", _cols, " step=", _step_min, " cells=", _rows * _cols, " px=", gp)

func set_heat_counts(counts: PackedInt32Array) -> void:
	if counts.size() != _rows * _cols:
		_heat = PackedInt32Array()
		_heat_max = 0
		queue_redraw()
		return
	_heat = counts.duplicate()
	var m: int = 0
	for v: int in _heat:
		if v > m:
			m = v
	_heat_max = m
	queue_redraw()

func set_mine_indices(indices: PackedInt32Array) -> void:
	var total: int = _rows * _cols
	_mine = PackedInt32Array()
	_mine.resize(total)
	for i: int in range(total):
		_mine[i] = 0
	for k: int in indices:
		if k >= 0 and k < total:
			_mine[k] = 1
	queue_redraw()

func clear_mine() -> void:
	var total: int = _rows * _cols
	_mine = PackedInt32Array()
	_mine.resize(total)
	for i: int in range(total):
		_mine[i] = 0
	queue_redraw()

func set_edit_mode(edit: bool) -> void:
	_edit_mode = edit
	queue_redraw()
	if debug_print:
		print("GridPane: edit_mode=", _edit_mode)

func get_selected_indices() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in range(_mine.size()):
		if _mine[i] != 0:
			out.append(i)
	return out

func get_total_cells() -> int:
	return _rows * _cols

func get_cols() -> int: return _cols
func get_rows() -> int: return _rows
func get_step_minutes() -> int: return _step_min
func get_start_minutes() -> int: return _start_min
func get_days_iso() -> PackedStringArray: return _days_iso.duplicate()
func get_hover_index() -> int: return _hover_idx

func labels_for_index(idx: int) -> Dictionary:
	var out := {}
	if _cols <= 0 or idx < 0:
		return out
	var r: int = idx / _cols
	var c: int = idx % _cols
	if r < 0 or r >= _rows or c < 0 or c >= _cols:
		return out

	var start_min_tot: int = _start_min + r * _step_min
	var end_min_tot: int = start_min_tot + _step_min
	if end_min_tot > _end_min:
		end_min_tot = _end_min

	var iso: String = _days_iso[c]

	out["row"] = r
	out["col"] = c
	out["iso"] = iso
	out["weekday"] = _format_day_abbrev(iso)
	out["start_label"] = _format_minutes_label(start_min_tot)
	out["end_label"] = _format_minutes_label(end_min_tot)
	out["date_label"] = _format_iso_long(iso)
	return out

func _parse_event() -> void:
	_step_min = int(_event.get("slot_minutes", 30))
	if _step_min < 5:
		_step_min = 5

	_start_min = int(_event.get("start_minutes", 9 * 60))
	_end_min = int(_event.get("end_minutes", 17 * 60))
	if _end_min <= _start_min:
		_end_min = _start_min + 60

	if _event.has("dates_iso") and (_event["dates_iso"] is PackedStringArray):
		_days_iso = (_event["dates_iso"] as PackedStringArray).duplicate()
	else:
		_days_iso = _build_days_from_range(_event.get("range", {}))

	if _days_iso.size() == 0:
		_days_iso = _default_next_seven_days()

	if _days_iso.size() > max_days:
		_days_iso = _slice_psa(_days_iso, max_days)

	var span: int = _end_min - _start_min
	var steps_f: float = float(span) / float(_step_min)
	var steps_i: int = ceili(steps_f)
	if steps_i < 1:
		steps_i = 1
	_rows = steps_i
	_cols = _days_iso.size()

	if _rows > max_rows:
		var scale: float = float(_rows) / float(max_rows)
		var new_step: int = int(ceili(float(_step_min) * scale))
		if new_step < 5:
			new_step = 5
		_step_min = new_step
		var steps2: int = ceili(float(_end_min - _start_min) / float(_step_min))
		if steps2 < 1:
			steps2 = 1
		_rows = steps2

	var cells: int = _rows * _cols
	if cells > max_cells:
		var attempt: int = 0
		while cells > max_cells and attempt < 32 and _step_min < 240:
			_step_min += 5
			_rows = ceili(float(_end_min - _start_min) / float(_step_min))
			if _rows < 1:
				_rows = 1
			cells = _rows * _cols
			attempt += 1
		if cells > max_cells and _cols > 0:
			var allowed_days: int = int(floor(float(max_cells) / float(_rows)))
			if allowed_days < 1:
				allowed_days = 1
			if allowed_days < _cols:
				_days_iso = _slice_psa(_days_iso, allowed_days)
				_cols = _days_iso.size()

	assert(_rows > 0, "GridPane: rows computed as zero")
	assert(_cols > 0, "GridPane: cols computed as zero")
	assert(_rows * _cols <= max_cells, "GridPane: cells exceed safety cap")

func _alloc_buffers() -> void:
	var total: int = _rows * _cols
	_heat = PackedInt32Array()
	_mine = PackedInt32Array()
	_heat.resize(total)
	_mine.resize(total)
	for i: int in range(total):
		_heat[i] = 0
		_mine[i] = 0
	_heat_max = 0

func _grid_pixel_size() -> Vector2:
	var w: float = float(_cols * cell_width_px)
	var h: float = float(_rows * cell_height_px)
	return Vector2(w, h)

func _content_pixel_size() -> Vector2:
	var gp: Vector2 = _grid_pixel_size()
	return Vector2(float(header_left_px + left_gap_px) + gp.x, float(header_top_px + header_gap_px) + gp.y)

func _center_offset() -> Vector2:
	var avail: Vector2 = _grid_canvas.get_size()
	var need: Vector2 = _content_pixel_size()
	var ox: float = floor(max((avail.x - need.x) * 0.5, 0.0))
	return Vector2(ox, 0.0)

func _update_min_size() -> void:
	var need: Vector2 = _content_pixel_size()
	custom_minimum_size = need

func _free_children_immediate(n: Node) -> void:
	var kids: Array[Node] = n.get_children()
	for ch: Node in kids:
		n.remove_child(ch)
		ch.queue_free()

func _build_headers() -> void:
	_free_children_immediate(_top_header)
	_top_header.add_theme_constant_override("separation", 0)
	for iso: String in _days_iso:
		var pc: PanelContainer = PanelContainer.new()
		pc.custom_minimum_size = Vector2(float(cell_width_px), float(header_top_px))
		pc.size_flags_horizontal = 0
		var lbl: Label = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.text = _format_day_abbrev(iso)
		pc.add_child(lbl)
		_top_header.add_child(pc)

	_free_children_immediate(_left_header)
	_left_header.add_theme_constant_override("separation", 0)
	for r in range(_rows):
		var lab: Label = Label.new()
		lab.custom_minimum_size = Vector2(float(header_left_px), float(cell_height_px))
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var tmin: int = _start_min + r * _step_min
		lab.text = _format_minutes_label(tmin)
		_left_header.add_child(lab)

func _layout_headers() -> void:
	var gp: Vector2 = _grid_pixel_size()
	var off: Vector2 = _center_offset()

	_corner.anchor_left = 0.0
	_corner.anchor_top = 0.0
	_corner.anchor_right = 0.0
	_corner.anchor_bottom = 0.0
	_corner.offset_left = off.x
	_corner.offset_top = 0.0
	_corner.offset_right = off.x + float(header_left_px)
	_corner.offset_bottom = float(header_top_px)

	_top_header.anchor_left = 0.0
	_top_header.anchor_top = 0.0
	_top_header.anchor_right = 0.0
	_top_header.anchor_bottom = 0.0
	_top_header.offset_left = off.x + float(header_left_px + left_gap_px)
	_top_header.offset_top = 0.0
	_top_header.offset_right = _top_header.offset_left + gp.x
	_top_header.offset_bottom = float(header_top_px)

	_left_header.anchor_left = 0.0
	_left_header.anchor_top = 0.0
	_left_header.anchor_right = 0.0
	_left_header.anchor_bottom = 0.0
	_left_header.offset_left = off.x
	_left_header.offset_top = float(header_top_px + header_gap_px)
	_left_header.offset_right = off.x + float(header_left_px)
	_left_header.offset_bottom = _left_header.offset_top + gp.y

func _draw() -> void:
	var off: Vector2 = _center_offset()
	var base: Vector2 = _canvas_origin_local() + Vector2(float(header_left_px + left_gap_px) + off.x, float(header_top_px + header_gap_px))
	var w: float = float(cell_width_px)
	var h: float = float(cell_height_px)

	for r: int in range(_rows):
		for c: int in range(_cols):
			var idx: int = r * _cols + c
			var x: float = base.x + float(c) * w
			var y: float = base.y + float(r) * h
			var rect: Rect2 = Rect2(Vector2(x, y), Vector2(w, h))

			var others: int = 0
			if idx >= 0 and idx < _heat.size():
				others = _heat[idx]
			var mine: int = 0
			if idx >= 0 and idx < _mine.size():
				mine = _mine[idx]

			if _edit_mode:
				if mine != 0:
					var me: Color = base_color
					me.a = 0.85
					draw_rect(rect, me, true)
				if edit_outline_width > 0.0:
					draw_rect(rect, edit_outline_color, false, edit_outline_width)
			else:
				var denom: int = max(_heat_max + 1, heat_opacity_cap)
				var total: int = others + mine
				var alpha: float = clamp(float(total) / float(denom), 0.0, 1.0)

				var fill: Color
				if mine != 0:
					fill = base_color
				else:
					fill = others_color
				fill.a = alpha
				draw_rect(rect, fill, true)

				var stroke_color: Color
				var stroke_w: float
				if mine != 0:
					stroke_color = outline_self_color
					stroke_w = outline_self_width
				else:
					stroke_color = outline_others_color
					stroke_w = outline_others_width
				if stroke_w > 0.0:
					draw_rect(rect, stroke_color, false, stroke_w)

	if enable_hover_highlight and _hover_idx >= 0 and _hover_idx < (_rows * _cols):
		var hr: int = _hover_idx / _cols
		var hc: int = _hover_idx % _cols
		var hx: float = base.x + float(hc) * w
		var hy: float = base.y + float(hr) * h
		var hrect: Rect2 = Rect2(Vector2(hx, hy), Vector2(w, h))
		if hover_show_fill:
			draw_rect(hrect, hover_fill_color, true)
		if hover_outline_width > 0.0:
			draw_rect(hrect, hover_outline_color, false, hover_outline_width)

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		var idx_move: int = _index_from_global(get_global_mouse_position())
		var changed: bool = idx_move != _hover_idx
		_hover_idx = idx_move
		if changed:
			queue_redraw()
			hover_changed.emit(_hover_idx)

	if not _edit_mode:
		return

	if event is InputEventMouseButton and debug_print:
		var eb: InputEventMouseButton = event as InputEventMouseButton
		print("GridPane: gui_input MB btn=", eb.button_index, " pressed=", eb.pressed, " at=", get_global_mouse_position())

	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_on_press(get_global_mouse_position())
			accept_event()
		else:
			_on_release()
			accept_event()
		return

	if mm != null and _drag_active:
		_on_drag(get_global_mouse_position())
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		var idx_move: int = _index_from_global(get_global_mouse_position())
		var changed: bool = idx_move != _hover_idx
		_hover_idx = idx_move
		if changed:
			queue_redraw()
			hover_changed.emit(_hover_idx)

	if not _edit_mode:
		return

	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_on_press(mb.position)
		else:
			_on_release()
		return
	if mm != null and _drag_active:
		_on_drag(mm.position)

func _on_press(global_pos: Vector2) -> void:
	var idx: int = _index_from_global(global_pos)
	if idx == -1:
		_drag_active = false
		if debug_print:
			print("GridPane: press miss at=", global_pos)
		return
	_drag_active = true
	var before: int = 0
	if idx >= 0 and idx < _mine.size():
		before = _mine[idx]
	if before == 0:
		_drag_set_value = 1
	else:
		_drag_set_value = 0
	_set_cell(idx, _drag_set_value)
	if debug_print:
		var r: int = idx / _cols
		var c: int = idx % _cols
		print("GridPane: press idx=", idx, " r=", r, " c=", c, " set=", _drag_set_value)

func _on_drag(global_pos: Vector2) -> void:
	var idx: int = _index_from_global(global_pos)
	if idx == -1:
		return
	_set_cell(idx, _drag_set_value)
	if debug_print:
		var r: int = idx / _cols
		var c: int = idx % _cols
		print("GridPane: drag idx=", idx, " r=", r, " c=", c, " set=", _drag_set_value)

func _on_release() -> void:
	if not _drag_active:
		return
	_drag_active = false
	availability_changed.emit(_user_id, get_selected_indices())
	if debug_print:
		print("GridPane: release emitted count=", get_selected_indices().size())

func _set_cell(idx: int, v: int) -> void:
	if idx < 0 or idx >= _mine.size():
		return
	_mine[idx] = v
	queue_redraw()

func _canvas_origin_local() -> Vector2:
	var root: Rect2 = get_global_rect()
	var canvas: Rect2 = _grid_canvas.get_global_rect()
	return canvas.position - root.position

func _index_from_global(global_pos: Vector2) -> int:
	var root: Rect2 = get_global_rect()
	var canvas: Rect2 = _grid_canvas.get_global_rect()
	var local_in_root: Vector2 = global_pos - root.position
	var local_in_canvas: Vector2 = local_in_root - (canvas.position - root.position)
	var off: Vector2 = _center_offset()
	var x: float = local_in_canvas.x - float(header_left_px + left_gap_px) - off.x
	var y: float = local_in_canvas.y - float(header_top_px + header_gap_px)
	if x < 0.0 or y < 0.0:
		return -1
	var c: int = floori(x / float(cell_width_px))
	var r: int = floori(y / float(cell_height_px))
	if c < 0 or c >= _cols or r < 0 or r >= _rows:
		return -1
	return r * _cols + c

func _format_day_abbrev(iso: String) -> String:
	var parts: PackedStringArray = iso.split("-")
	if parts.size() != 3:
		return "Day"
	var y: int = int(parts[0])
	var m: int = int(parts[1])
	var d: int = int(parts[2])
	var wd: int = _weekday_from_ymd(y, m, d)
	var names: PackedStringArray = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
	if wd < 0 or wd >= names.size():
		return "Day"
	return names[wd]

func _format_hour_label(h24: int) -> String:
	var mer: String = "AM"
	var h: int = h24
	if h24 >= 12:
		mer = "PM"
	if h == 0:
		h = 12
	if h > 12:
		h -= 12
	return "%d:00 %s" % [h, mer]

func _build_days_from_range(range_block: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var s: Dictionary = range_block.get("start", {})
	var e: Dictionary = range_block.get("end", {})
	if s.is_empty() or e.is_empty():
		return out
	var sy: int = int(s.get("y", 0))
	var sm: int = int(s.get("m", 0))
	var sd: int = int(s.get("d", 0))
	var ey: int = int(e.get("y", 0))
	var em: int = int(e.get("m", 0))
	var ed: int = int(e.get("d", 0))
	if not _valid_ymd(sy, sm, sd) or not _valid_ymd(ey, em, ed):
		return out
	var start_jdn: int = _jdn_from_ymd(sy, sm, sd)
	var end_jdn: int = _jdn_from_ymd(ey, em, ed)
	if end_jdn < start_jdn:
		return out
	var span_days: int = end_jdn - start_jdn + 1
	if span_days > max_days:
		span_days = max_days
	for off in range(span_days):
		var ymd: Dictionary = _ymd_from_jdn(start_jdn + off)
		out.append(_iso_from_parts(int(ymd["y"]), int(ymd["m"]), int(ymd["d"])))
	return out

func _default_next_seven_days() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var unix_s: int = int(Time.get_unix_time_from_system())
	var now: Dictionary = _ymd_from_unix(unix_s)
	var j: int = _jdn_from_ymd(int(now["y"]), int(now["m"]), int(now["d"]))
	for i: int in range(7):
		var ymd: Dictionary = _ymd_from_jdn(j + i)
		out.append(_iso_from_parts(int(ymd["y"]), int(ymd["m"]), int(ymd["d"])))
	return out

func _iso_from_parts(y: int, m: int, d: int) -> String:
	var mm: String = str(m).pad_zeros(2)
	var dd: String = str(d).pad_zeros(2)
	return "%d-%s-%s" % [y, mm, dd]

func _weekday_from_ymd(y: int, m: int, d: int) -> int:
	var j: int = _jdn_from_ymd(y, m, d)
	var dow0sun: int = (j + 1) % 7
	if dow0sun == 0:
		return 6
	return dow0sun - 1

func _jdn_from_ymd(y: int, m: int, d: int) -> int:
	var a: int = floori(float(14 - m) / 12.0)
	var yy: int = y + 4800 - a
	var mm: int = m + 12 * a - 3
	return d \
		+ floori(float(153 * mm + 2) / 5.0) \
		+ 365 * yy \
		+ floori(float(yy) / 4.0) \
		- floori(float(yy) / 100.0) \
		+ floori(float(yy) / 400.0) \
		- 32045

func _ymd_from_jdn(jdn: int) -> Dictionary:
	var a: int = jdn + 32044
	var b: int = floori(float(4 * a + 3) / 146097.0)
	var c: int = a - floori(float(146097 * b) / 4.0)
	var d: int = floori(float(4 * c + 3) / 1461.0)
	var e: int = c - floori(float(1461 * d) / 4.0)
	var m: int = floori(float(5 * e + 2) / 153.0)
	var day: int = e - floori(float(153 * m + 2) / 5.0) + 1
	var month: int = m + 3 - 12 * floori(float(m) / 10.0)
	var year: int = int(100 * b + d - 4800 + floori(float(m) / 10.0))
	return {"y": year, "m": month, "d": day}

func _ymd_from_unix(unix_s: int) -> Dictionary:
	var days: int = floori(float(unix_s) / 86400.0)
	var jdn: int = days + 2440588
	return _ymd_from_jdn(jdn)

func _valid_ymd(y: int, m: int, d: int) -> bool:
	if y < 1970:
		return false
	if y > 2100:
		return false
	if m < 1:
		return false
	if m > 12:
		return false
	if d < 1:
		return false
	if d > 31:
		return false
	return true

func _slice_psa(src: PackedStringArray, new_len: int) -> PackedStringArray:
	var n: int = mini(new_len, src.size())
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(n):
		out.append(src[i])
	return out

func _format_minutes_label(total_min: int) -> String:
	var h24: int = total_min / 60
	var m: int = total_min % 60
	var mer: String = "AM"
	var h: int = h24
	if h24 >= 12:
		mer = "PM"
	if h == 0:
		h = 12
	if h > 12:
		h -= 12
	return "%d:%02d %s" % [h, m, mer]

func _format_iso_long(iso: String) -> String:
	var parts: PackedStringArray = iso.split("-")
	if parts.size() != 3:
		return iso
	var y: int = int(parts[0])
	var m: int = int(parts[1])
	var d: int = int(parts[2])
	var months: PackedStringArray = PackedStringArray(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"])
	var wnames: PackedStringArray = PackedStringArray(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"])
	var wd: int = _weekday_from_ymd(y, m, d)
	var wdname: String = "Day"
	if wd >= 0 and wd < wnames.size():
		wdname = wnames[wd]
	var mname: String = "Mon"
	if m >= 1 and m <= 12:
		mname = months[m - 1]
	return "%s %d %s %d" % [wdname, d, mname, y]
