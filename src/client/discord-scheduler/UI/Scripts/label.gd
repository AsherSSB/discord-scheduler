extends Label
class_name AuthStatusLabel

#-----------------------------------------------------------------------------
# Exports
#-----------------------------------------------------------------------------
@export var debug_print: bool = false

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	text = "Waiting for Discord…"
	DiscordSession.authenticated.connect(_on_authed)
	DiscordSession.request_failed.connect(_on_failed)
	DiscordSession.reemit_authenticated()

#-----------------------------------------------------------------------------
# Handlers
#-----------------------------------------------------------------------------
func _on_authed(user: Dictionary) -> void:
	var uname: String = str(user.get("username", "Unknown"))
	text = "Hello, " + uname
	if debug_print:
		print("AuthStatusLabel: authed as ", uname)

func _on_failed(reason: String) -> void:
	text = "Discord error: " + reason
	if debug_print:
		print("AuthStatusLabel: failed ", reason)
