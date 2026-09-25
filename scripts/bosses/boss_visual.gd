class_name BossVisual
extends Node2D

## Presentation-only adapter. Combat code talks in semantic cues and anchors;
## artwork can change without changing hit radius, attacks, or encounter rules.

@export var skin_name: StringName
@export var placeholder_color := Color(0.85, 0.25, 0.2)

@onready var _placeholder: Polygon2D = get_node_or_null("Placeholder") as Polygon2D
@onready var _artwork: CanvasItem = get_node_or_null("Artwork") as CanvasItem
@onready var _animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer


func setup(gameplay_radius: float, tint_color: Color, fallback_color: Color) -> void:
	if _placeholder != null:
		_placeholder.polygon = _make_octagon(gameplay_radius)
		_placeholder.color = fallback_color if fallback_color.a > 0.0 else placeholder_color

	var artwork_ready := _setup_artwork(gameplay_radius, tint_color)
	if _placeholder != null:
		_placeholder.visible = not artwork_ready

	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.35)


func validate_contract() -> PackedStringArray:
	var errors := PackedStringArray()
	if _placeholder == null:
		errors.append("VisualRoot/Placeholder must be a Polygon2D")
	if _artwork == null:
		errors.append("VisualRoot/Artwork must be a CanvasItem")
	for anchor_name in [&"Center", &"ProjectileOrigin", &"EffectOrigin"]:
		if get_node_or_null("../Anchors/%s" % anchor_name) is not Marker2D:
			errors.append("Anchors/%s must be a Marker2D" % anchor_name)
	if get_node_or_null("../TelegraphLayer") is not Node2D:
		errors.append("TelegraphLayer must be a Node2D")
	return errors


func play_semantic(cue: StringName) -> void:
	if _animation_player != null and _animation_player.has_animation(cue):
		_animation_player.play(cue)
		return
	var animated := _artwork as AnimatedSprite2D
	if animated != null and animated.sprite_frames != null and animated.sprite_frames.has_animation(cue):
		animated.play(cue)


func face_direction(direction: Vector2) -> void:
	if _artwork == null or is_zero_approx(direction.x):
		return
	if _artwork is Sprite2D:
		(_artwork as Sprite2D).flip_h = direction.x < 0.0
	elif _artwork is AnimatedSprite2D:
		(_artwork as AnimatedSprite2D).flip_h = direction.x < 0.0


func anchor_global_position(anchor_name: StringName) -> Vector2:
	var anchor := get_node_or_null("../Anchors/%s" % anchor_name) as Marker2D
	return anchor.global_position if anchor != null else global_position


func placeholder_polygon() -> Polygon2D:
	return _placeholder


func _setup_artwork(gameplay_radius: float, tint_color: Color) -> bool:
	if _artwork is Sprite2D:
		var sprite := _artwork as Sprite2D
		if sprite.texture == null and not skin_name.is_empty():
			sprite.texture = ArtS.skin(String(skin_name))
			if sprite.texture != null:
				var width := float(sprite.texture.get_width())
				if width > 0.0:
					sprite.scale = Vector2.ONE * (gameplay_radius * 2.0 / width)
		if sprite.texture != null:
			sprite.modulate = tint_color
			sprite.visible = true
			return true
		sprite.visible = false
		return false

	if _artwork is AnimatedSprite2D:
		var animated := _artwork as AnimatedSprite2D
		var has_frames := false
		if animated.sprite_frames != null:
			for animation_name in animated.sprite_frames.get_animation_names():
				if animated.sprite_frames.get_frame_count(animation_name) > 0:
					has_frames = true
					break
		animated.visible = has_frames
		animated.modulate = tint_color
		return has_frames

	return _artwork != null and _artwork.visible


func _make_octagon(gameplay_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 8:
		points.append(Vector2.RIGHT.rotated(TAU * index / 8.0) * gameplay_radius)
	return points
