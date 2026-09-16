extends Node3D
## The original purple rally flag, shown at a building's gathering point while it is selected.

static var _scene: PackedScene
static var _material: StandardMaterial3D


static func create() -> Node3D:
	var flag := Node3D.new()
	if _scene == null:
		var path := Assets.resolve("models/sfx_ymrallyflag.glb")
		if not ResourceLoader.exists(path):
			return flag
		_scene = load(path)
		_material = StandardMaterial3D.new()
		_material.albedo_texture = load(Assets.resolve("textures/sfx_ymrallyflag_t.png"))
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_material.alpha_scissor_threshold = 0.5
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var model: Node3D = _scene.instantiate()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.scale = Vector3.ONE * 1.8
	flag.add_child(model)
	# The model's bind pose has the pole lying flat - only the waving animation stands it up.
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if player and player.get_animation_list().size() > 0:
		var name: String = player.get_animation_list()[0]
		player.get_animation(name).loop_mode = Animation.LOOP_LINEAR
		player.play(name)
	return flag
