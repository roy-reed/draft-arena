class_name BossDefinition
extends Resource

## Immutable design-time data. Runtime state belongs in BossRuntimeStats/BossBase.

@export var boss_id: StringName
@export var display_name: String = "Boss"
@export var scene: PackedScene

@export_group("Base combat values")
@export var base_max_hp: float = 1.0
@export var base_armor: float = 0.0
@export var base_speed: float = 0.0
@export var base_contact_damage: float = 0.0
@export var gameplay_radius: float = 34.0

@export_group("Rewards and HUD")
@export var reward_coin: int = 15
@export var reward_xp: int = 120
@export var hud_color: Color = Color(0.85, 0.25, 0.2)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if boss_id.is_empty():
		errors.append("boss_id must not be empty")
	if display_name.is_empty():
		errors.append("display_name must not be empty")
	if scene == null:
		errors.append("scene must be assigned")
	if base_max_hp <= 0.0:
		errors.append("base_max_hp must be greater than zero")
	if base_armor < 0.0 or base_speed < 0.0 or base_contact_damage < 0.0:
		errors.append("base combat values must not be negative")
	if gameplay_radius <= 0.0:
		errors.append("gameplay_radius must be greater than zero")
	if reward_coin < 0 or reward_xp < 0:
		errors.append("rewards must not be negative")
	return errors
