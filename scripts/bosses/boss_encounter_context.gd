class_name BossEncounterContext
extends RefCounted

enum Mode {
	CAMPAIGN,
	ENDLESS,
}

var mode: Mode = Mode.CAMPAIGN
var region_index: int = 0
var endless_rank: int = 0
var arena: Rect2 = Rect2()
var spawn_position: Vector2 = Vector2.ZERO
var player: Node2D
var rng := RandomNumberGenerator.new()

## Negative means use BossDefinition.base_max_hp. This preserves the existing
## endless rule without teaching BossDefinition about run progression.
var base_hp_override: float = -1.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if region_index < 0:
		errors.append("region_index must not be negative")
	if endless_rank < 0:
		errors.append("endless_rank must not be negative")
	if arena.size.x <= 0.0 or arena.size.y <= 0.0:
		errors.append("arena must have a positive size")
	if player == null or not is_instance_valid(player):
		errors.append("player must be a valid Node2D")
	if base_hp_override == 0.0:
		errors.append("base_hp_override must be negative or greater than zero")
	return errors
