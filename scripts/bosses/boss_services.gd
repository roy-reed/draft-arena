class_name BossServices
extends RefCounted

## Explicit host capabilities. Boss scripts never search for Main or call it by reflection.

var spawn_enemy_projectile := Callable()
var spawn_minion := Callable()
var living_minion_count := Callable()


func has_service(service_name: StringName) -> bool:
	match service_name:
		&"spawn_enemy_projectile":
			return spawn_enemy_projectile.is_valid()
		&"spawn_minion":
			return spawn_minion.is_valid()
		&"living_minion_count":
			return living_minion_count.is_valid()
		_:
			return false


func validate(required_services: Array[StringName]) -> PackedStringArray:
	var errors := PackedStringArray()
	for service_name in required_services:
		if not has_service(service_name):
			errors.append("missing required service: %s" % service_name)
	return errors
