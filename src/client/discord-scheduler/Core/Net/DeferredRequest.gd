extends RefCounted
class_name DeferredRequest

#-----------------------------------------------------------------------------
# Signals
#-----------------------------------------------------------------------------
signal done(result: Dictionary, error: String)

#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
var _completed: bool = false

#-----------------------------------------------------------------------------
# API
#-----------------------------------------------------------------------------
func resolve(result: Dictionary) -> void:
	if _completed:
		return
	_completed = true
	done.emit(result, "")

func reject(error: String) -> void:
	if _completed:
		return
	_completed = true
	done.emit({}, error)

func is_completed() -> bool:
	return _completed
