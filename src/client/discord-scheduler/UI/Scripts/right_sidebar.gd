extends Panel
class_name RightSidebar

@onready var _count: Label = $Details/CountLabel
@onready var _time: Label = $Details/TimeLabel
@onready var _avail_list: VBoxContainer = $Details/Columns/Available/Names
@onready var _unavail_list: VBoxContainer = $Details/Columns/Unavailable/Names

func clear_hover() -> void:
	if is_inside_tree():
		_count.text = ""
		_time.text = ""
		_rebuild_names(_avail_list, [])
		_rebuild_names(_unavail_list, [])

func show_hover(count_available: int, total_people: int, time_line: String, available: Array, unavailable: Array) -> void:
	if not is_inside_tree():
		return
	_count.text = "%d/%d Available" % [count_available, total_people]
	_time.text = time_line
	_rebuild_names(_avail_list, available)
	_rebuild_names(_unavail_list, unavailable)

func _rebuild_names(container: VBoxContainer, names: Array) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()
	for n in names:
		var lab := Label.new()
		lab.text = String(n)
		container.add_child(lab)
