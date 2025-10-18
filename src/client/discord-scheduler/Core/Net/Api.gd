extends Node
#-----------------------------------------------------------------------------
# Runtime State
#-----------------------------------------------------------------------------
var service: IEventService

#-----------------------------------------------------------------------------
# Lifecycle
#-----------------------------------------------------------------------------
func _ready() -> void:
	var mock: MockEventService = MockEventService.new()
	add_child(mock)
	service = mock

#-----------------------------------------------------------------------------
# Mutators
#-----------------------------------------------------------------------------
func use_mock(latency_ms: int, fail_rate: float) -> void:
	var mock: MockEventService = MockEventService.new()
	mock.simulate_latency_ms = latency_ms
	mock.simulate_fail_rate = fail_rate
	_swap_service(mock)

func _swap_service(new_service: IEventService) -> void:
	assert(new_service != null, "Api._swap_service received null")
	if service != null and is_instance_valid(service):
		service.queue_free()
	add_child(new_service)
	service = new_service
