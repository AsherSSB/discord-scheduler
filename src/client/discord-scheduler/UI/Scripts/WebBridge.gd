extends Node

var _cb: JavaScriptObject

func _ready() -> void:
	if OS.has_feature("web"):
		_cb = JavaScriptBridge.create_callback(_on_js_token)
		var js: String = "window.godotReceiveToken=(t)=>%s(t);" % [_cb]
		JavaScriptBridge.eval(js)

func _on_js_token(args: Array) -> void:
	if args.size() < 1:
		return
	var token: String = String(args[0])
	DiscordSession.set_session_token(token)
