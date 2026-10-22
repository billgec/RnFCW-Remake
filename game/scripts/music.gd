extends Node
## Music the way the original lays it out in Data\Music\Song1: fifteen quiet tracks
## (Ambient01-15) for building up, fifteen for fighting (Battle01-15), a short piece for the
## calm after a battle (Aftermath1), a fanfare per civilization when the hero rises a level
## (GreekLevelUp, ...), and Victory or Mourn at the end. The main theme (EmpiresTheme)
## opens the match.
##
## A battle is the player's own soldiers fighting: once a few of them are at it the music
## turns to the battle tracks, and after a while without fighting it settles again. M turns
## the music off and on; the choice is remembered.

const DIRECTORY := "music/"
const FADE_S := 2.5
const FIGHTERS_FOR_BATTLE := 3
const CALM_S := 15.0
const VOLUME_DB := -6.0
const SETTINGS_PATH := "user://settings.cfg"

var team := 0
var enabled := true

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _mood := ""
var _last_track := ""
var _calm := 0.0
var _check := 0.0
var _sting := false            # a fanfare is playing and may not be cut off


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		enabled = bool(config.get_value("audio", "music", true))
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = -80.0
		player.finished.connect(_on_finished.bind(player))
		add_child(player)
		_players.append(player)
	GameState.hero_level_changed.connect(func(t, _level): if t == team: _play_sting(_civ_fanfare()))
	GameState.match_over.connect(func(winner): _end(winner == team))
	_play_once("empirestheme", "ambient")


func _process(delta: float) -> void:
	if _mood == "end":
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	var fighting := 0
	for unit in Unit.all_units:
		if unit.team == team and not unit.is_worker and unit.state == Unit.State.ATTACK:
			fighting += 1
	if fighting >= FIGHTERS_FOR_BATTLE:
		_calm = 0.0
		if _mood != "battle" and not _sting:
			_switch("battle")
	elif _mood == "battle":
		_calm += 1.0
		if _calm >= CALM_S:
			_play_once("aftermath", "ambient")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		enabled = not enabled
		var config := ConfigFile.new()
		config.load(SETTINGS_PATH)
		config.set_value("audio", "music", enabled)
		config.save(SETTINGS_PATH)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not enabled)
		GameState.message.emit("Musik an" if enabled else "Musik aus")
		get_viewport().set_input_as_handled()


# --- moods ------------------------------------------------------------------

## Crossfades into a random track of a mood ("ambient", "battle").
func _switch(mood: String) -> void:
	_mood = mood
	_sting = false
	_fade_to(_random_track(mood))


## One track, then back to a mood: the opening theme, the calm after a battle. A battle
## may cut either of them short - only the short fanfares are never interrupted.
func _play_once(track: String, then: String) -> void:
	_mood = then
	_sting = false
	_fade_to(track)


func _play_sting(track: String) -> void:
	if _mood == "end" or track == "":
		return
	_sting = true
	_fade_to(track)


func _end(won: bool) -> void:
	_mood = "end"
	_sting = true
	_fade_to("victory" if won else "mourn")


func _on_finished(player: AudioStreamPlayer) -> void:
	if player != _players[_active] or _mood == "end":
		return
	_sting = false
	_fade_to(_random_track(_mood if _mood != "" else "ambient"))


func _civ_fanfare() -> String:
	var civ := str(GameState.player(team).get("civ", "greek"))
	return civ + "levelup"


func _random_track(mood: String) -> String:
	var tracks := _tracks_of(mood)
	tracks.erase(_last_track)
	return tracks.pick_random() if not tracks.is_empty() else ""


static func _tracks_of(mood: String) -> Array:
	var result := []
	var dir := DirAccess.open(Assets.resolve(DIRECTORY))
	if dir == null:
		return result
	for file in dir.get_files():
		if file.begins_with(mood) and file.ends_with(".mp3"):
			result.append(file.get_basename())
	return result


func _fade_to(track: String) -> void:
	var path := Assets.resolve(DIRECTORY + track + ".mp3")
	if track == "" or not ResourceLoader.exists(path):
		return
	_last_track = track
	var outgoing := _players[_active]
	_active = 1 - _active
	var incoming := _players[_active]
	incoming.stream = load(path)
	incoming.volume_db = -40.0
	incoming.play()
	var tween := create_tween().set_parallel()
	tween.tween_property(incoming, "volume_db", VOLUME_DB, FADE_S)
	tween.tween_property(outgoing, "volume_db", -80.0, FADE_S)
	tween.chain().tween_callback(outgoing.stop)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not enabled)
