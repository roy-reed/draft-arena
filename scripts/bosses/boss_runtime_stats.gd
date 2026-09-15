class_name BossRuntimeStats
extends RefCounted

## A per-spawn value object. BossDefinition resources must never be mutated at runtime.

var max_hp: float = 1.0
var armor: float = 0.0
var speed: float = 0.0
var contact_damage: float = 0.0
var gameplay_radius: float = 1.0
var reward_coin: int = 0
var reward_xp: int = 0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if max_hp <= 0.0:
		errors.append("max_hp must be greater than zero")
	if armor < 0.0:
		errors.append("armor must not be negative")
	if speed < 0.0:
		errors.append("speed must not be negative")
	if contact_damage < 0.0:
		errors.append("contact_damage must not be negative")
	if gameplay_radius <= 0.0:
		errors.append("gameplay_radius must be greater than zero")
	if reward_coin < 0 or reward_xp < 0:
		errors.append("rewards must not be negative")
	return errors


func copy() -> BossRuntimeStats:
	var result := BossRuntimeStats.new()
	result.max_hp = max_hp
	result.armor = armor
	result.speed = speed
	result.contact_damage = contact_damage
	result.gameplay_radius = gameplay_radius
	result.reward_coin = reward_coin
	result.reward_xp = reward_xp
	return result
