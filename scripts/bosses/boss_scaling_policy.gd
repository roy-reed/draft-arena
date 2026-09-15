class_name BossScalingPolicy
extends RefCounted

## Current pre-Issue-#7 GDD policy. Future balance changes replace this policy,
## not the spawn lifecycle or individual Boss scripts.

const HP_MULTIPLIER := 2.0
const ARMOR_MULTIPLIER := 1.5
const ARMOR_FLAT_BONUS := 2.0
const SPEED_MULTIPLIER := 1.2
const REGION_ONE_DAMAGE_MULTIPLIER := 2.0


func build_stats(definition: BossDefinition, context: BossEncounterContext) -> BossRuntimeStats:
	var stats := BossRuntimeStats.new()
	var base_hp := context.base_hp_override if context.base_hp_override > 0.0 else definition.base_max_hp
	var endless_multiplier := 1.0
	if context.mode == BossEncounterContext.Mode.ENDLESS:
		endless_multiplier = 1.6 + 0.8 * float(context.endless_rank)
	stats.max_hp = base_hp * endless_multiplier * HP_MULTIPLIER
	stats.armor = definition.base_armor * ARMOR_MULTIPLIER + ARMOR_FLAT_BONUS
	stats.speed = definition.base_speed * SPEED_MULTIPLIER
	stats.contact_damage = definition.base_contact_damage
	if context.mode == BossEncounterContext.Mode.CAMPAIGN and context.region_index == 0:
		stats.contact_damage *= REGION_ONE_DAMAGE_MULTIPLIER
	stats.gameplay_radius = definition.gameplay_radius
	stats.reward_coin = 25 if context.mode == BossEncounterContext.Mode.ENDLESS else definition.reward_coin
	stats.reward_xp = definition.reward_xp
	return stats
