extends Control
## Minimap in the original's manner.
##
## The original paints the map from a 64x64 texture per terrain type (textures\ui_x*.sst -
## the "ui" twin of every ground texture), so the map itself looks like the real ground,
## and then stamps everything that belongs to somebody on top as a plain white square
## (textures\ui_square.sst) in the player's colour - which is why buildings show up as a
## handful of coarse pixels. It is shown as a diamond, the square map turned by 45°.
##
## Here the ground is not made of tiles, so the map is a real top down render of the
## terrain, taken now and then into a small texture (felled forests disappear from it);
## buildings, soldiers and the camera are drawn over it every frame.

const ROTATION := 45.0        # the original shows the map as a diamond
const BASE_RESOLUTION := 512
const REFRESH := 2.0          # how often the terrain is checked for changes
const TERRAIN_LAYER := 2      # render layer of the ground, trees, rocks and mines
const BUILDING_MIN := 5.0     # a building is never smaller than this, in pixels
const UNIT_SIZE := 3.0
## The original's own stone diamond, cut out of the Greek interface atlas. Its middle is
## painted black there - that is where the map goes, so it is made see-through here.
const FRAME_REGION := Rect2i(53, 0, 312, 308)
const FRAME_TEXTURE := "textures/ui_ymrtst.png"
const MAP_INSET := 0.93       # the map sits a little inside the frame
const VIEW_COLOR := Color(0.55, 1.0, 0.6, 0.85)

var extent := 95.0           # half the edge of the mapped area, in metres
var camera_rig: Node3D
var selection: Node           # selection_controller.gd

var _map: Texture2D           # the baked terrain picture
var _baking: SubViewport
var _timer := 0.0
var _rendered_nodes := -1     # resource nodes at the last terrain render

static var _frame: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bake_terrain()


## Renders the ground from straight above into a picture and throws the viewport away
## again: keeping a second 3D viewport around all the time costs a good part of a frame,
## while the terrain only changes when a forest is felled.
func _bake_terrain() -> void:
	if _baking != null:
		return
	_rendered_nodes = ResourceNode.all_nodes.size()
	_baking = SubViewport.new()
	_baking.size = Vector2i(BASE_RESOLUTION, BASE_RESOLUTION)
	_baking.transparent_bg = false
	_baking.render_target_update_mode = SubViewport.UPDATE_ONCE
	_baking.world_3d = get_viewport().find_world_3d()
	add_child(_baking)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = extent * 2.0
	camera.position = Vector3(0.0, 300.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.far = 600.0
	camera.cull_mask = 1 << (TERRAIN_LAYER - 1)
	camera.environment = _flat_environment()
	_baking.add_child(camera)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(_baking):
		_map = ImageTexture.create_from_image(_baking.get_texture().get_image())
		_baking.queue_free()
		_baking = null


## The map render wants flat daylight, not the atmosphere of the game camera: no fog over
## 200 metres, no glow, no ambient occlusion.
static func _flat_environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.1, 0.12, 0.1)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1, 1, 1)
	environment.ambient_light_energy = 1.1
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return environment


func _process(delta: float) -> void:
	# The terrain only changes when a forest is felled, so it is re-rendered then and not
	# on a timer - a full render of the ground costs a visible part of a frame.
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		if _rendered_nodes != ResourceNode.all_nodes.size():
			_bake_terrain()
	queue_redraw()


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	var side := size.x / sqrt(2.0) * MAP_INSET   # a square turned by 45° needs this much room
	var metres := side / (2.0 * extent)
	draw_set_transform(size * 0.5, deg_to_rad(ROTATION), Vector2.ONE)
	var square := Rect2(Vector2(-side, -side) * 0.5, Vector2(side, side))
	if _map:
		draw_texture_rect(_map, square, false)
	else:
		draw_rect(square, Color(0.13, 0.16, 0.12))
	_draw_view(metres)
	for node in ResourceNode.all_nodes:
		if node.kind == "gold":
			_draw_marker(node.global_position, metres, 4.0, 4.0, Color(1.0, 0.85, 0.3))
	for building in Building.all_buildings:
		if not building.is_alive():
			continue
		var color := GameState.team_color(building.team)
		_draw_marker(building.global_position, metres,
			maxf(building.footprint.size.x * metres, BUILDING_MIN),
			maxf(building.footprint.size.y * metres, BUILDING_MIN), color, true)
	for unit in Unit.all_units:
		if not unit.is_alive():
			continue
		var color := GameState.team_color(unit.team)
		if unit.is_hero:
			_draw_marker(unit.global_position, metres, 5.0, 5.0, color.lightened(0.55), true)
		else:
			_draw_marker(unit.global_position, metres, UNIT_SIZE, UNIT_SIZE, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var frame := _frame_texture()
	if frame:
		draw_texture_rect(frame, Rect2(Vector2.ZERO, size), false)


## Cuts the stone diamond out of the interface atlas once and drops its black middle.
static func _frame_texture() -> Texture2D:
	if _frame != null:
		return _frame
	var path := Assets.resolve(FRAME_TEXTURE)
	if not ResourceLoader.exists(path):
		return null
	var atlas: Texture2D = load(path)
	var image := atlas.get_image().get_region(FRAME_REGION)
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.r + pixel.g + pixel.b < 0.22:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	_frame = ImageTexture.create_from_image(image)
	return _frame


func _draw_marker(at: Vector3, metres: float, width: float, height: float, color: Color,
		outline := false) -> void:
	var point := Vector2(at.x, at.z) * metres
	var rect := Rect2(point - Vector2(width, height) * 0.5, Vector2(width, height))
	if outline:
		draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.7), true)
	draw_rect(rect, color, true)


## The piece of ground the game camera is looking at.
func _draw_view(metres: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var view := get_viewport().get_visible_rect().size
	var corners := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(view.x, 0.0), view, Vector2(0.0, view.y)]:
		var origin := camera.project_ray_origin(corner)
		var hit = Plane(Vector3.UP, 0.0).intersects_ray(origin, camera.project_ray_normal(corner))
		if hit == null:  # looking at the horizon: fall back to the far edge of the map
			hit = origin + camera.project_ray_normal(corner) * (extent * 2.0)
		var point: Vector3 = hit
		corners.append(Vector2(clampf(point.x, -extent, extent), clampf(point.z, -extent, extent)) * metres)
	corners.append(corners[0])
	draw_polyline(corners, VIEW_COLOR, 1.5)


# --- orders -----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_look_at_point(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and selection:
			selection.order_selected_move(_world_at(event.position),
				event.meta_pressed or event.ctrl_pressed)
		else:
			return
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_look_at_point(event.position)
		accept_event()


func _look_at_point(local: Vector2) -> void:
	if camera_rig:
		camera_rig.position = _world_at(local)


func _world_at(local: Vector2) -> Vector3:
	var side := size.x / sqrt(2.0) * MAP_INSET
	var point := (local - size * 0.5).rotated(-deg_to_rad(ROTATION)) / (side / (2.0 * extent))
	return Vector3(clampf(point.x, -extent, extent), 0.0, clampf(point.y, -extent, extent))
