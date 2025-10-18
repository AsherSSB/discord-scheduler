extends PanelContainer
class_name EventCard

signal open_requested(event_id: String, record: Dictionary)
signal delete_requested(event_id: String, record: Dictionary)

@export var debug_print: bool = false

@onready var _title: Label = %CardTitle
@onready var _meta: Label = %CardMeta
@onready var _btn_open: Button = %Open
@onready var _btn_delete: Button = %Delete

var _record: Dictionary = {}
var _event_id: String = ""

func _ready() -> void:
	assert(_btn_open != null, "EventCard: Open not found")
	assert(_btn_delete != null, "EventCard: Delete not found")
	_btn_open.pressed.connect(_on_open_pressed)
	_btn_delete.pressed.connect(_on_delete_pressed)
	_ensure_buttons_state()
	_update_ui()

func set_record(rec: Dictionary) -> void:
	_record = rec.duplicate()
	_event_id = String(_record.get("id", ""))
	name = "EventCard_%s" % _event_id
	_ensure_buttons_state()
	if is_inside_tree():
		_update_ui()
	else:
		call_deferred("_update_ui")

func get_record() -> Dictionary:
	return _record

func get_event_id() -> String:
	return _event_id

func _ensure_buttons_state() -> void:
	var has_record := not _record.is_empty()
	if _btn_open:
		_btn_open.disabled = not has_record
	if _btn_delete:
		_btn_delete.disabled = not has_record

func _update_ui() -> void:
	if _title == null or _meta == null:
		return
	var title_txt: String = String(_record.get("name", "Untitled Event"))
	_title.text = title_txt
	var start_label_raw: String = String(_record.get("start_label", ""))
	var end_label_raw: String = String(_record.get("end_label", ""))
	var tz: String = String(_record.get("timezone", ""))
	var slot_minutes: int = int(_record.get("slot_minutes", 30))
	var start_label: String = _format_time_compact(start_label_raw)
	var end_label: String = _format_time_compact(end_label_raw)
	var dates: PackedStringArray = _record.get("dates_iso", PackedStringArray())
	var main_line: String = _compose_main_line(dates, start_label, end_label)
	var bits: PackedStringArray = []
	if main_line != "":
		bits.append(main_line)
	if slot_minutes > 0:
		bits.append("%d min slots" % slot_minutes)
	if tz != "":
		bits.append(tz)
	_meta.text = " • ".join(bits)

func _compose_main_line(dates: PackedStringArray, start_label: String, end_label: String) -> String:
	if dates.size() == 0:
		return _compose_from_range_dict(start_label, end_label)
	if dates.size() == 1:
		var date_str: String = _format_iso_date(dates[0])
		if start_label != "" and end_label == "":
			return "%s at %s" % [date_str, start_label]
		if start_label != "" and end_label != "":
			return "%s %s–%s" % [date_str, start_label, end_label]
		if end_label != "":
			return "%s at %s" % [date_str, end_label]
		return date_str
	var range_str: String = _format_date_range(dates[0], dates[dates.size() - 1])
	if start_label != "" and end_label != "":
		return "%s • %s–%s" % [range_str, start_label, end_label]
	return range_str

func _compose_from_range_dict(start_label: String, end_label: String) -> String:
	var range_block: Dictionary = _record.get("range", {})
	if range_block.is_empty():
		return ""
	var s: Dictionary = range_block.get("start", {})
	var e: Dictionary = range_block.get("end", {})
	if s.is_empty() or e.is_empty():
		return ""
	var s_txt: String = _format_date_from_parts(int(s.get("y", 0)), int(s.get("m", 0)), int(s.get("d", 0)))
	var e_txt: String = _format_date_from_parts(int(e.get("y", 0)), int(e.get("m", 0)), int(e.get("d", 0)))
	if s_txt == "" or e_txt == "":
		return ""
	if s_txt == e_txt:
		if start_label != "" and end_label == "":
			return "%s at %s" % [s_txt, start_label]
		if start_label != "" and end_label != "":
			return "%s %s–%s" % [s_txt, start_label, end_label]
		if end_label != "":
			return "%s at %s" % [s_txt, end_label]
		return s_txt
	if start_label != "" and end_label != "":
		return "%s – %s • %s–%s" % [s_txt, e_txt, start_label, end_label]
	return "%s – %s" % [s_txt, e_txt]

func _format_iso_date(iso: String) -> String:
	var parts: PackedStringArray = iso.split("-")
	if parts.size() != 3:
		return iso
	var y: int = int(parts[0])
	var m: int = int(parts[1])
	var d: int = int(parts[2])
	return _format_date_from_parts(y, m, d)

func _format_date_range(a_iso: String, b_iso: String) -> String:
	var ap: PackedStringArray = a_iso.split("-")
	var bp: PackedStringArray = b_iso.split("-")
	if ap.size() != 3 or bp.size() != 3:
		return "%s – %s" % [a_iso, b_iso]
	var ay: int = int(ap[0])
	var am: int = int(ap[1])
	var ad: int = int(ap[2])
	var by: int = int(bp[0])
	var bm: int = int(bp[1])
	var bd: int = int(bp[2])
	if ay == by and am == bm:
		var month: String = _month_abbrev(am)
		return "%s %d%s–%d%s" % [month, ad, _ordinal_suffix(ad), bd, _ordinal_suffix(bd)]
	var left: String = _format_date_from_parts(ay, am, ad)
	var right: String = _format_date_from_parts(by, bm, bd)
	return "%s – %s" % [left, right]

func _format_date_from_parts(y: int, m: int, d: int) -> String:
	if y <= 0 or m <= 0 or d <= 0:
		return ""
	return "%s %d%s" % [_month_abbrev(m), d, _ordinal_suffix(d)]

func _ordinal_suffix(d: int) -> String:
	var tens: int = d % 100
	if tens >= 11 and tens <= 13:
		return "th"
	var ones: int = d % 10
	if ones == 1:
		return "st"
	if ones == 2:
		return "nd"
	if ones == 3:
		return "rd"
	return "th"

func _month_abbrev(m: int) -> String:
	var names: PackedStringArray = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
	if m < 1 or m > 12:
		return "Mon"
	return names[m - 1]

func _format_time_compact(label: String) -> String:
	var s: String = label.strip_edges()
	if s == "":
		return ""
	var parts: PackedStringArray = s.split(" ")
	if parts.size() < 2:
		return s
	var t: String = parts[0]
	var mer: String = parts[1]
	var hhmm: PackedStringArray = t.split(":")
	var hh: String = hhmm[0]
	var out: String = hh
	if hhmm.size() > 1:
		var mm: String = hhmm[1]
		var mm_i: int = 0
		var ok: bool = false
		if mm != "":
			mm_i = int(mm)
			ok = true
		if ok and mm_i != 0:
			out = "%s:%s" % [hh, mm]
	var mer_out: String = mer.to_upper()
	mer_out = mer_out.replace(".", "")
	mer_out = mer_out.replace(" ", "")
	return "%s%s" % [out, mer_out]

func _on_open_pressed() -> void:
	if _record.is_empty():
		if debug_print:
			push_warning("EventCard: open pressed before record set; ignoring.")
		return
	if debug_print:
		print("EventCard: open -> ", _event_id)
	open_requested.emit(_event_id, _record)

func _on_delete_pressed() -> void:
	if _record.is_empty():
		if debug_print:
			push_warning("EventCard: delete pressed before record set; ignoring.")
		return
	if debug_print:
		print("EventCard: delete -> ", _event_id)
	delete_requested.emit(_event_id, _record)
