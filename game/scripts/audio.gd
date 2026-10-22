extends Node
## Sounds and voices, played from the original's own recordings (see data/sounds.json for
## which recording belongs to what, and the converter's ExportSounds for where they come
## from).
##
## Voices are the player's own men answering - selected, ordered, a building finished,
## gold running out - and are played flat, one at a time, like in the original. Effects
## (swords, arrows, axes, deaths) come from where they happen in the world and fade with
## distance to the camera.

const TABLE_PATH := "res://data/sounds.json"
const VOICE_DIR := "sounds/voice/"
const SFX_DIR := "sounds/sfx/"
const EFFECT_PLAYERS := 24
const VOICE_GAP := 0.35        # seconds of quiet a voice keeps before the next may start
const REPEAT_GAP := 0.07       # the same effect does not start twice within this
const EFFECT_RANGE := 70.0     # metres from the camera at which effects fall silent

const BUSES := ["Music", "Voice", "Effects"]

var _table := {}
var _variants := {}            # "dir|pattern" -> Array[AudioStream]
var _voice: AudioStreamPlayer
var _voice_free_at := 0.0
var _effects: Array[AudioStreamPlayer3D] = []
var _next_effect := 0
var _last := {}                # effect key -> time it last started
var _alarm_quiet_until := 0.0


func _ready() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	_table = parsed if parsed is Dictionary else {}
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	add_child(_voice)
	for i in EFFECT_PLAYERS:
		var player := AudioStreamPlayer3D.new()
		player.bus = "Effects"
		player.unit_size = 12.0
		player.max_distance = EFFECT_RANGE
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_effects.append(player)


# --- voices -----------------------------------------------------------------

## A voice from the table by its path, e.g. "command/move" or "alert/gold".
func voice(path: String) -> void:
	var pattern = _lookup(_table.get("voice", {}), path)
	if pattern is String:
		_say(pattern)


## The answer a unit gives when it is picked: every kind of soldier has lines of its own.
func select(unit) -> void:
	_say(_first_match(_table.get("voice", {}).get("select", []), _identity(unit)))


func group_select() -> void:
	_say(str(_table.get("voice", {}).get("group", "")))


## "Barracks complete" and the like, for the player's own buildings.
func building_complete(building_id: String) -> void:
	_say(_first_match(_table.get("voice", {}).get("complete", []), building_id))


func _say(pattern: String) -> void:
	if pattern == "" or _now() < _voice_free_at:
		return
	var stream := _pick(VOICE_DIR, pattern)
	if stream == null:
		return
	_voice.stream = stream
	_voice.play()
	_voice_free_at = _now() + stream.get_length() + VOICE_GAP


## "We are under attack!" - at most every twenty seconds, or it would never stop.
func under_attack() -> void:
	if _now() < _alarm_quiet_until:
		return
	_alarm_quiet_until = _now() + 20.0
	_voice_free_at = 0.0  # this one may interrupt
	voice("alert/under_attack")


# --- effects ----------------------------------------------------------------

## An effect where it happens. Far from the camera it is not started at all, and the same
## effect is not started twice in the same instant - forty swords landing at once would
## otherwise be forty times as loud.
func effect(key: String, at: Vector3, volume_db := 0.0, pitch_spread := 0.08) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_to(at) > EFFECT_RANGE * 1.5:
		return
	var now := _now()
	if now - float(_last.get(key, -1.0)) < REPEAT_GAP:
		return
	var pattern: String = str(_table.get("sfx", {}).get(key, ""))
	var stream := _pick(SFX_DIR, pattern)
	if stream == null:
		return
	_last[key] = now
	var player := _effects[_next_effect]
	_next_effect = (_next_effect + 1) % _effects.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	player.global_position = at
	player.play()


## The call when a building sends out new men: every kind of soldier has its own.
func trained(unit_id: String, at: Vector3) -> void:
	var pairs: Array = _table.get("sfx", {}).get("trained", [])
	var pattern := _first_match(pairs, unit_id.to_lower())
	var stream := _pick(SFX_DIR, pattern)
	if stream == null:
		return
	var player := _effects[_next_effect]
	_next_effect = (_next_effect + 1) % _effects.size()
	player.stream = stream
	player.volume_db = -4.0
	player.pitch_scale = 1.0
	player.global_position = at
	player.play()


## A death: the scream everybody shares, and the thud of the fall.
func death(at: Vector3) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_to(at) > EFFECT_RANGE:
		return
	var pattern: String = str(_table.get("voice", {}).get("death", ""))
	var stream := _pick(VOICE_DIR, pattern)
	if stream and _now() - float(_last.get("scream", -1.0)) > 0.25:
		_last["scream"] = _now()
		var player := _effects[_next_effect]
		_next_effect = (_next_effect + 1) % _effects.size()
		player.stream = stream
		player.volume_db = -3.0
		player.pitch_scale = randf_range(0.94, 1.06)
		player.global_position = at
		player.play()
	effect("death", at, -6.0)


# --- lookup -----------------------------------------------------------------

func _pick(directory: String, pattern: String) -> AudioStream:
	if pattern == "":
		return null
	var key := directory + "|" + pattern
	if not _variants.has(key):
		_variants[key] = _load_matching(directory, pattern)
	var found: Array = _variants[key]
	return found.pick_random() if not found.is_empty() else null


## Every recording whose name fits the pattern - one sound, several takes.
static func _load_matching(directory: String, pattern: String) -> Array:
	var result := []
	var path := Assets.resolve(directory)
	var dir := DirAccess.open(path)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.ends_with(".import"):
			continue
		if file.match(pattern):
			var stream = load(path + file)
			if stream is AudioStream:
				result.append(stream)
	return result


static func _first_match(pairs: Array, identity: String) -> String:
	for pair in pairs:
		if pair is Array and pair.size() >= 2 and str(pair[0]) in identity:
			return str(pair[1])
	return ""


static func _lookup(tree: Dictionary, path: String):
	var node = tree
	for part in path.split("/"):
		if not node is Dictionary or not node.has(part):
			return null
		node = node[part]
	return node


static func _identity(unit) -> String:
	return ("%s %s" % [unit.definition_id, unit.line]).to_lower()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
