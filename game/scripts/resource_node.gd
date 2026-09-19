class_name ResourceNode
extends Node3D
## Gatherable resource: a gold mine (original model) or a tree (placeholder model until the
## SpeedTree .spt format is converted).

signal depleted(node: ResourceNode)

var kind := "gold"
var amount := 1000
var radius := 1.0
var gatherers := 0

## Trees, rocks and mines are drawn on the minimap's terrain render, so they sit on its
## layer as well (see minimap.gd).
const MINIMAP_LAYERS := 1 | (1 << 1)

static var all_nodes: Array[ResourceNode] = []
static var _tree_meshes: Array = []


static func gold_mine(amount_left := 5000) -> ResourceNode:
	var node := ResourceNode.new()
	node.kind = "gold"
	node.amount = amount_left
	node.radius = 3.2
	var model := Assets.spawn_unit("amb_ygoldmine_01", Color(0.9, 0.75, 0.2))
	if model:
		node.add_child(model)
	return node


## Trees use the CC0 "Stylized Nature MegaKit" by Quaternius (assets/nature, see the
## license file there) - the original game's trees are SpeedTree .spt files, which are
## procedural descriptions rather than meshes and cannot be converted directly.
const TREE_SCENES := [
	"res://assets/nature/CommonTree_1.gltf",
	"res://assets/nature/CommonTree_2.gltf",
	"res://assets/nature/CommonTree_3.gltf",
	"res://assets/nature/CommonTree_4.gltf",
	"res://assets/nature/CommonTree_5.gltf",
	"res://assets/nature/TwistedTree_1.gltf",
	"res://assets/nature/TwistedTree_2.gltf",
	"res://assets/nature/TwistedTree_3.gltf",
	"res://assets/nature/TwistedTree_5.gltf",
]
const TREE_HEIGHT := 9.0

static var _tree_scenes: Array = []
static var _leaf_material: StandardMaterial3D


static func tree(amount_left := 150) -> ResourceNode:
	var node := ResourceNode.new()
	node.kind = "wood"
	node.amount = amount_left
	node.radius = 0.9
	if _tree_scenes.is_empty():
		for path in TREE_SCENES:
			if ResourceLoader.exists(path):
				_tree_scenes.append(load(path))
	if _tree_scenes.is_empty():
		push_warning("no tree models in assets/nature")
		return node
	var model: Node3D = _tree_scenes.pick_random().instantiate()
	node.add_child(model)
	_greenify(model)
	# The pack's trees are a few units tall; scale them to a believable forest height.
	var height := 1.0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		height = maxf(height, mesh.get_aabb().size.y)
	var scale := TREE_HEIGHT / height * randf_range(0.75, 1.15)
	model.scale = Vector3(scale, scale * randf_range(0.92, 1.12), scale)
	model.rotation.y = randf() * TAU
	return node


## The pack's "twisted" trees ship with autumn-red foliage; swap in the green leaf texture
## so a forest reads as one wood instead of two seasons.
static func _greenify(model: Node3D) -> void:
	if _leaf_material == null:
		_leaf_material = StandardMaterial3D.new()
		_leaf_material.albedo_texture = load("res://assets/nature/Leaves_NormalTree_C.png")
		_leaf_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_leaf_material.alpha_scissor_threshold = 0.5
		_leaf_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_leaf_material.roughness = 0.95
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(i)
			if material and "Leaves_TwistedTree" in material.resource_name:
				mesh.set_surface_override_material(i, _leaf_material)


func _ready() -> void:
	all_nodes.append(self)
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.layers = MINIMAP_LAYERS


func _exit_tree() -> void:
	all_nodes.erase(self)


func is_available() -> bool:
	return amount > 0 and is_inside_tree()


## Takes up to [param wanted] units; returns what was actually taken.
func harvest(wanted: int) -> int:
	var taken := mini(wanted, amount)
	amount -= taken
	if amount <= 0:
		depleted.emit(self)
		all_nodes.erase(self)
		if kind == "wood":
			var tween := create_tween()
			tween.tween_property(self, "rotation:x", deg_to_rad(85), 1.2).set_ease(Tween.EASE_IN)
			tween.tween_interval(3.0)
			tween.tween_property(self, "scale", Vector3.ONE * 0.01, 1.0)
			tween.tween_callback(queue_free)
		else:
			var tween := create_tween()
			tween.tween_property(self, "position:y", -3.0, 5.0)
			tween.tween_callback(queue_free)
	return taken


static func nearest(from: Vector3, resource_kind: String, max_distance := 200.0) -> ResourceNode:
	var best: ResourceNode = null
	var best_distance := max_distance
	for node in all_nodes:
		if node.kind != resource_kind or not node.is_available():
			continue
		# Spread workers a little: busy nodes count as further away.
		var d := from.distance_to(node.global_position) + node.gatherers * (1.5 if resource_kind == "wood" else 0.3)
		if d < best_distance:
			best_distance = d
			best = node
	return best
