extends Control
class_name LoadingOverlay

#-----------------------------------------------------------------------------
# Signals
#-----------------------------------------------------------------------------
signal gate_reached(gate_pct: float)
signal finished()

#-----------------------------------------------------------------------------
# Exports
#-----------------------------------------------------------------------------
@export var message: String = "Loading"
@export var auto_progress: bool = true
@export var debug_print: bool = false

@export var fast_speed: float = 120.0
@export var slow_speed: float = 15.0
@export var post_slow_speed: float = 80.0
@export var gate_pct: float = 90.0
@export var auto_hide_delay: float = 0.2

@export var first_fast_min: float = 10.0
@export var first_fast_max: float = 30.0
@export var slow_end_min: float = 35.0
@export var slow_end_max: float = 55.0
@export var resume_end_min: float = 80.0
@export var resume_end_max: float = 88.0

@export var retry_initial_delay: float = 0.75
@export var retry_max_delay: float = 5.0
@export var retry_backoff_factor: float = 1.6

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
@onready var _label: Label = $Center/Box/Message
@onready var _bar: ProgressBar = $Center/Box/Progress

var _progress: float = 0.0
var _active: bool = false
var _authorized: bool = false

enum Phase { FAST1, SLOW, FAST2, GATE, DONE }
var _phase: Phase = Phase.FAST1

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _t_fast1: float = 20.0
var _t_slow_end: float = 45.0
var _t_resume_end: float = 85.0

var _retry_timer: Timer
var _retry_delay: float = 0.0

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	visible = false
	set_process(false)
	if _label != null:
		_label.text = message
	if _bar != null:
		_bar.min_value = 0.0
		_bar.max_value = 100.0
		_bar.value = 0.0

	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	add_child(_retry_timer)
	_retry_timer.timeout.connect(_on_retry_timeout)

	DiscordSession.authenticated.connect(_on_session_authed)
	DiscordSession.request_failed.connect(_on_session_failed)
	DiscordSession.reemit_authenticated()

#-----------------------------------------------------------------------------
# Public API
#-----------------------------------------------------------------------------
func show_message(text: String = "") -> void:
	if text != "":
		message = text
	if _label != null:
		_label.text = message
	visible = true
	_active = true
	_authorized = false
	_progress = 0.0
	_phase = Phase.FAST1
	_seed_and_targets()
	_retry_delay = retry_initial_delay
	if _bar != null:
		_bar.value = 0.0
	set_process(auto_progress)

func set_progress(pct: float) -> void:
	var clamped: float = clamp(pct, 0.0, 100.0)
	_progress = clamped
	if _bar != null:
		_bar.value = _progress

func authorize_and_finish() -> void:
	_authorized = true
	_snap_to_gate_if_needed()
	_finish_now()

#-----------------------------------------------------------------------------
# Session Handlers
#-----------------------------------------------------------------------------
func _on_session_authed(_user: Dictionary) -> void:
	if debug_print:
		print("LoadingOverlay: session authenticated")
	_retry_timer.stop()
	_authorized = true
	_snap_to_gate_if_needed()
	_finish_now()

func _on_session_failed(reason: String) -> void:
	if debug_print:
		print("LoadingOverlay: session failed: ", reason)
	_snap_to_gate_if_needed()
	if _label != null:
		_label.text = "Authorizing…"
	_start_retry()

#-----------------------------------------------------------------------------
# Retry
#-----------------------------------------------------------------------------
func _start_retry() -> void:
	_retry_delay = min(_retry_delay, retry_max_delay)
	if _retry_delay <= 0.0:
		_retry_delay = retry_initial_delay
	_retry_timer.start(_retry_delay)
	if debug_print:
		print("LoadingOverlay: retry in ", _retry_delay, "s")
	_retry_delay = min(retry_max_delay, _retry_delay * retry_backoff_factor)

func _on_retry_timeout() -> void:
	if debug_print:
		print("LoadingOverlay: retrying /api/me")
	var sess: Object = DiscordSession
	if sess.has_method("retry_me"):
		sess.call("retry_me")
	else:
		DiscordSession.reemit_authenticated()

#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------
func _seed_and_targets() -> void:
	_rng.randomize()
	_t_fast1 = clamp(_rng.randf_range(first_fast_min, first_fast_max), 1.0, 89.0)
	_t_slow_end = clamp(_rng.randf_range(slow_end_min, slow_end_max),
		_t_fast1 + 1.0, 89.0)
	_t_resume_end = clamp(_rng.randf_range(resume_end_min, resume_end_max),
		_t_slow_end + 1.0, 89.0)
	gate_pct = clamp(gate_pct, 90.0, 99.0)

func _snap_to_gate_if_needed() -> void:
	if _phase != Phase.GATE and _phase != Phase.DONE:
		_phase = Phase.GATE
	if _progress < gate_pct:
		_progress = gate_pct
		if _bar != null:
			_bar.value = gate_pct
		emit_signal("gate_reached", gate_pct)

func _finish_now() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	_progress = 100.0
	if _bar != null:
		_bar.value = 100.0
	emit_signal("finished")
	set_process(false)
	var t: SceneTreeTimer = get_tree().create_timer(auto_hide_delay)
	t.timeout.connect(func() -> void:
		visible = false
	)

func _advance(delta: float) -> void:
	if _phase == Phase.FAST1:
		_progress += fast_speed * delta
		if _progress >= _t_fast1:
			_progress = _t_fast1
			_phase = Phase.SLOW
	elif _phase == Phase.SLOW:
		_progress += slow_speed * delta
		if _progress >= _t_slow_end:
			_progress = _t_slow_end
			_phase = Phase.FAST2
	elif _phase == Phase.FAST2:
		_progress += post_slow_speed * delta
		if _progress >= _t_resume_end:
			_progress = _t_resume_end
			_phase = Phase.GATE
	elif _phase == Phase.GATE:
		if _bar != null and _bar.value < gate_pct:
			_progress = gate_pct
			emit_signal("gate_reached", gate_pct)
		if _authorized:
			_finish_now()
	elif _phase == Phase.DONE:
		pass

	if _progress > 100.0:
		_progress = 100.0
	if _bar != null:
		_bar.value = _progress

#-----------------------------------------------------------------------------
# Process
#-----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _active:
		return
	if not auto_progress:
		return
	_advance(delta)
	if debug_print:
		print("phase=", _phase, " pct=", str(roundf(_progress)))
