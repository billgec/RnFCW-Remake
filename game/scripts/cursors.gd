extends Node
## The original game's mouse pointers (converted from db\dbmousepointer.dat).
## Call [method set_pointer] with a pointer name from the table, e.g. "Attack", "Wood",
## "Mining", "Build", "Repair", "RallyPoint", "Move", "Attack Move", "Normal".

## The table has no hotspot column; these match how the original art is drawn
## (most pointers have their tip in the upper left, the target-style ones are centred).
const CENTERED := ["Attack", "Attack Move", "Attack Ground", "Invalid Target", "Guard",
	"Calamity", "Heal", "Convert", "Garrison", "RallyPoint", "Flare", "Patrol"]

var _textures := {}
var _current := ""


func _ready() -> void:
	var path := Assets.resolve("cursors/cursors.json")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("no cursor index at %s" % path)
		return
	for name in parsed:
		var texture_path := Assets.resolve("cursors/" + parsed[name])
		if ResourceLoader.exists(texture_path):
			_textures[name] = load(texture_path)
	set_pointer("Normal")


func set_pointer(name: String) -> void:
	if name == _current:
		return
	if not _textures.has(name):
		if name != "Normal":
			set_pointer("Normal")
		return
	_current = name
	var texture: Texture2D = _textures[name]
	var hotspot := Vector2(texture.get_width(), texture.get_height()) * 0.5 if name in CENTERED else Vector2(2, 2)
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, hotspot)
