extends Node
## Graphics quality, saved between sessions and switchable in game with F5.
##
## The game renders at the window's real resolution, which on a Retina display is about
## three times as many pixels as the 1920x1080 the project asks for. At that size the
## screen space effects cost far more than everything the simulation does - measured on an
## M4: screen space indirect lighting alone took about 50 ms per frame, while all of the
## units, pathing and combat together take 3 ms. Hence real quality levels instead of one
## fixed set of effects.

signal changed(level: String)

const LEVELS := ["low", "medium", "high"]
const LABELS := {"low": "niedrig", "medium": "mittel", "high": "hoch"}
const SETTINGS_PATH := "user://settings.cfg"

var level := "medium"

var _environment: Environment


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var stored := str(config.get_value("graphics", "quality", level))
		if stored in LEVELS:
			level = stored


## Called once by the scene with its WorldEnvironment's environment.
func use(environment: Environment) -> void:
	_environment = environment
	apply()


func label() -> String:
	return LABELS.get(level, level)


func cycle() -> void:
	set_level(LEVELS[(LEVELS.find(level) + 1) % LEVELS.size()])


func set_level(value: String) -> void:
	if not value in LEVELS or value == level:
		return
	level = value
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("graphics", "quality", level)
	config.save(SETTINGS_PATH)
	apply()
	changed.emit(level)


func apply() -> void:
	# The dummy renderer of a headless run (used for the automated checks) crashes on these,
	# and there is nothing to draw there anyway.
	if DisplayServer.get_name() == "headless":
		return
	var viewport := get_viewport()
	if viewport:
		viewport.msaa_3d = {"low": Viewport.MSAA_DISABLED, "medium": Viewport.MSAA_2X,
			"high": Viewport.MSAA_4X}[level]
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if level == "low" else Viewport.SCREEN_SPACE_AA_DISABLED
		# Below native resolution only on the lowest level: it is the cheapest way to buy
		# frames on a high density display, at the price of a softer picture.
		viewport.scaling_3d_scale = 0.8 if level == "low" else 1.0
	RenderingServer.directional_shadow_atlas_set_size(
		{"low": 2048, "medium": 4096, "high": 8192}[level], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		{"low": RenderingServer.SHADOW_QUALITY_HARD, "medium": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"high": RenderingServer.SHADOW_QUALITY_SOFT_HIGH}[level])
	if _environment == null:
		return
	# Indirect lighting is the single most expensive effect and barely shows in a top down
	# view, so it is reserved for the highest level.
	_environment.ssil_enabled = level == "high"
	_environment.ssao_enabled = level != "low"
	_environment.ssao_radius = 1.2 if level == "high" else 0.9
	_environment.ssao_intensity = 1.6 if level == "high" else 1.2
	_environment.glow_enabled = level != "low"


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		cycle()
		GameState.message.emit("Grafik: %s" % label())
		get_viewport().set_input_as_handled()
