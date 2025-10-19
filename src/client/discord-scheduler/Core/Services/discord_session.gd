extends Node

#-----------------------------------------------------------------------------
# Signals
#-----------------------------------------------------------------------------
signal authenticated(user: Dictionary)
signal guilds_ready(guilds: Array)
signal request_failed(reason: String)

#-----------------------------------------------------------------------------
# Exports
#-----------------------------------------------------------------------------
@export var server_base_url: String = "http://localhost:5173"
@export var debug_print: bool = false

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
var _token: String = ""
var _user: Dictionary = {}
var _http_json: HTTPRequest
var _pending_op: String = ""
var _js_cb: JavaScriptObject
var _poll_timer: Timer
var _poll_attempts: int = 0

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	_http_json = HTTPRequest.new()
	add_child(_http_json)
	_http_json.request_completed.connect(_on_http_json_completed)

	if OS.has_feature("web"):
		var origin_v: Variant = JavaScriptBridge.eval("window.location.origin", true)
		var origin_s: String = String(origin_v)
		if origin_s != "":
			server_base_url = origin_s
		if debug_print:
			print("DiscordSession: base URL = ", server_base_url)

		_wire_js_token_bridge()
		_start_token_poll()

#-----------------------------------------------------------------------------
# JS Bridge
#-----------------------------------------------------------------------------
func _wire_js_token_bridge() -> void:
	_js_cb = JavaScriptBridge.create_callback(_on_js_token)
	var js: String = """
		window.godotReceiveToken=(t)=>%s([t]);
		window.addEventListener('discord-token', e => window.godotReceiveToken(e.detail));
	"""
	JavaScriptBridge.eval(js % [_js_cb])

func _start_token_poll() -> void:
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.one_shot = false
	add_child(_poll_timer)
	_poll_timer.timeout.connect(_on_poll_timeout)
	_poll_timer.start()

func _on_poll_timeout() -> void:
	if _token != "":
		_poll_timer.stop()
		return
	_poll_attempts += 1
	var v: Variant = JavaScriptBridge.eval("window.__discordAccessToken || null", true)
	var t: String = String(v)
	if t != "":
		if debug_print:
			print("DiscordSession: pulled token from JS on attempt ", _poll_attempts)
		_poll_timer.stop()
		set_session_token(t)
	elif _poll_attempts >= 20:
		_poll_timer.stop()
		if debug_print:
			print("DiscordSession: stopped polling for token")

func _on_js_token(args: Array) -> void:
	if args.size() < 1:
		return
	var t: String = String(args[0])
	if t == "":
		return
	if debug_print:
		print("DiscordSession: received token via callback")
	set_session_token(t)

#-----------------------------------------------------------------------------
# Public API
#-----------------------------------------------------------------------------
func set_session_token(token: String) -> void:
	assert(token != "", "DiscordSession: token cannot be empty")
	_token = token
	_request_json("GET", "/api/me", {}, "me")

func clear_session() -> void:
	_token = ""
	_user = {}

func fetch_guilds() -> void:
	_request_json("GET", "/api/guilds", {}, "guilds")

func get_user() -> Dictionary:
	return _user

func reemit_authenticated() -> void:
	if _user.size() > 0:
		emit_signal("authenticated", _user)

func retry_me() -> void:
	if _token == "":
		return
	if _http_json.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_request_json("GET", "/api/me", {}, "me")
#-----------------------------------------------------------------------------
# Internal HTTP
#-----------------------------------------------------------------------------
func _request_json(method: String, path: String, payload: Dictionary, op: String) -> void:
	assert(_http_json.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED, "DiscordSession: request already running")
	_pending_op = op

	var url: String = server_base_url + path
	var headers: PackedStringArray = ["Content-Type: application/json"]
	if _token != "":
		headers.append("Authorization: Bearer " + _token)

	var body: String = ""
	if payload.size() > 0:
		body = JSON.stringify(payload)

	var err: Error = OK
	if method == "GET":
		err = _http_json.request(url, headers, HTTPClient.METHOD_GET, "")
	else:
		err = _http_json.request(url, headers, HTTPClient.METHOD_POST, body)

	if err != OK:
		_pending_op = ""
		emit_signal("request_failed", "HTTPRequest error: " + str(err))

func _on_http_json_completed(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var op: String = _pending_op
	_pending_op = ""

	if result != HTTPRequest.RESULT_SUCCESS:
		emit_signal("request_failed", "Network error " + str(result))
		return
	if code < 200 or code >= 300:
		emit_signal("request_failed", "HTTP " + str(code))
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY and typeof(parsed) != TYPE_ARRAY:
		emit_signal("request_failed", "Invalid JSON")
		return

	if op == "me":
		if typeof(parsed) != TYPE_DICTIONARY:
			emit_signal("request_failed", "Unexpected /api/me shape")
			return
		_user = parsed as Dictionary
		emit_signal("authenticated", _user)
	elif op == "guilds":
		if typeof(parsed) != TYPE_ARRAY:
			emit_signal("request_failed", "Unexpected /api/guilds shape")
			return
		emit_signal("guilds_ready", parsed as Array)
