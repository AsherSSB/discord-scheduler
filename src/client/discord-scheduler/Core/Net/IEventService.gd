@abstract
extends Node
class_name IEventService

#-----------------------------------------------------------------------------
# Event CRUD
#-----------------------------------------------------------------------------
@abstract
func create_event(_payload: Dictionary) -> DeferredRequest

@abstract
func list_events() -> DeferredRequest

@abstract
func delete_event(_event_id: String) -> DeferredRequest

@abstract
func clear_all() -> DeferredRequest

#-----------------------------------------------------------------------------
# Availability / Heatmap
#-----------------------------------------------------------------------------
@abstract
func set_availability(_event_id: String, _user_id: String, _indices: PackedInt32Array, _total_cells: int) -> DeferredRequest

@abstract
func get_heat(_event_id: String) -> DeferredRequest

@abstract
func get_user_availability(_event_id: String, _user_id: String) -> DeferredRequest
