extends Node
## Resolves game assets. Every lookup checks res://assets/overrides/ first, then
## res://assets/original/ (the converter's output), so any texture or model can be
## replaced by dropping a file with the same relative path into the overrides folder.

const OVERRIDES := "res://assets/overrides/"
const ORIGINAL := "res://assets/original/"
const UNIT_SHADER := preload("res://shaders/unit.gdshader")

var _units: Dictionary = {}
var _materials: Dictionary = {}


func resolve(relative_path: String) -> String:
	var override_path := OVERRIDES + relative_path
	if ResourceLoader.exists(override_path):
		return override_path
	return ORIGINAL + relative_path


func unit_def(id: String) -> Dictionary:
	if not _units.has(id):
		var path := resolve("units/%s.json" % id)
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("unit definition missing or invalid: %s" % path)
			return {}
		_units[id] = parsed
	return _units[id]


## Instantiates a unit/building model with the player-colour material applied.
func spawn_unit(id: String, player_color: Color) -> Node3D:
	var def := unit_def(id)
	if def.is_empty():
		return null
	var scene: PackedScene = load(resolve(def["model"]))
	var node: Node3D = scene.instantiate()
	node.name = id
	if def.get("texture") != null:
		# One material per unit type and colour, shared by every instance: a material of its
		# own for each of a hundred soldiers costs memory and draw call setup for nothing.
		var key := "%s|%s" % [id, player_color.to_html(false)]
		var material: ShaderMaterial = _materials.get(key)
		if material == null:
			material = ShaderMaterial.new()
			material.shader = UNIT_SHADER
			material.set_shader_parameter("skin", load(resolve(def["texture"])))
			material.set_shader_parameter("player_color", player_color)
			_materials[key] = material
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node


## Plays an animation on a spawned unit. Looping is decided by name (walk/run/idle...).
func play(unit: Node, animation: String) -> void:
	var player: AnimationPlayer = unit.find_child("AnimationPlayer", true, false)
	if player == null or not player.has_animation(animation):
		push_warning("%s: no animation '%s'" % [unit.name, animation])
		return
	var anim := player.get_animation(animation)
	anim.loop_mode = Animation.LOOP_LINEAR if _is_looping(animation) else Animation.LOOP_NONE
	player.play(animation)


func _is_looping(animation: String) -> bool:
	for token in ["walk", "run", "fidget", "idle", "swim", "tread", "trdw", "cheer", "talk", "charge"]:
		if token in animation:
			return true
	return false
