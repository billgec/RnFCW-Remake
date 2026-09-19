extends CanvasLayer
## Heads-up display: a resource bar with the game speed control at the top, and a bottom
## panel holding the selection (portrait, name, hit points, group overview), its command
## grid (train, research, build) and the production queue.
##
## Icons: unit, building and upgrade icons come from the original game; the interface icons
## (resources, speed) are CC BY 3.0 from game-icons.net, see assets/icons/NOTICE.md.

const Minimap := preload("res://scripts/minimap.gd")

const PANEL_HEIGHT := 178.0
const MINIMAP_SIZE := 162.0
const SLOT := 58.0
const COLUMNS := 7

const GOLD := Color(0.93, 0.79, 0.42)
const TEXT := Color(0.93, 0.9, 0.82)
const DIM := Color(0.66, 0.63, 0.57)
const INK := Color(0.055, 0.05, 0.045, 0.92)

const RESOURCE_STYLE := {
	"gold": {"icon": "gold", "label": "Gold", "color": Color(1.0, 0.84, 0.4)},
	"wood": {"icon": "wood", "label": "Holz", "color": Color(0.78, 0.56, 0.33)},
	"glory": {"icon": "glory", "label": "Ruhm", "color": Color(0.85, 0.65, 1.0)},
}

var selection: Node  # selection_controller.gd
var hero_mode: Node  # hero_mode.gd
var camera_rig: Node3D  # the minimap steers it
var team := 0

var _font: Font
var _values := {}
var _pop_value: Label
var _batch_value: Label
var _message: Label
var _message_time := 0.0
var _portrait: TextureRect
var _name_label: Label
var _subtitle: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _group_grid: GridContainer
var _command_grid: GridContainer
var _queue_box: HBoxContainer
var _queue_bar: ProgressBar
var _tooltip: Label
var _speed_buttons: Control
var _panel: Control
var _hero_overlay: Control
var _hero_name: Label
var _hero_hp: ProgressBar
var _hero_hp_text: Label
var _hero_special: ProgressBar
var _hero_retinue: Label
var _refresh_timer := 0.0


func _ready() -> void:
	var font_path := Assets.resolve("fonts/rafc.ttf")
	_font = load(font_path) if ResourceLoader.exists(font_path) else null
	_build_top_bar()
	_build_message()
	_build_bottom_panel()
	_build_hero_overlay()
	if hero_mode:
		hero_mode.mode_changed.connect(_set_hero_mode)
	GameState.resources_changed.connect(func(t): if t == team: _update_resources())
	GameState.message.connect(show_message)
	_update_resources()


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time / 0.6, 0.0, 1.0)
	if hero_mode and hero_mode.active:
		_update_hero_overlay()
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.2
		refresh()


func show_message(text: String) -> void:
	_message.text = text
	_message_time = 3.0
	_message.modulate.a = 1.0


## Rebuilds the bottom panel from the current selection.
func refresh() -> void:
	if hero_mode and hero_mode.active:
		_update_hero_overlay()
		_update_counters()
		return
	if selection == null:
		return
	var units: Array[Unit] = selection.selected_units()
	var building: Building = selection.selected_building
	if building and not is_instance_valid(building):
		building = null
	_update_counters()
	_clear(_group_grid)
	if building == null or building.queue.is_empty():
		_queue_box.set_meta("signature", "")
		_queue_box.visible = false
		_queue_bar.visible = false

	if building:
		var state := "Im Bau: %d %%" % int(building.build_progress * 100) if not building.is_complete() else ""
		_show_single(building.display_name, _icon_for(building.definition_id), building.hit_points,
			building.max_hit_points, state)
		_show_queue(building)
		_fill_commands(_panel_commands(building) if building.team == team and building.is_complete() else [])
	elif units.size() == 1:
		var u := units[0]
		_show_single(u.display_name, _icon_for(u.definition_id), u.hit_points, u.max_hit_points, _unit_subtitle(u))
		if u.is_hero:
			_fill_commands(_hero_commands(u))
		else:
			_fill_commands(_build_commands() if u.is_worker else [])
	elif units.size() > 1:
		_show_group(units)
		_fill_commands(_build_commands() if units.any(func(x): return x.is_worker) else [])
	else:
		_show_empty()


# --- selection panel --------------------------------------------------------

func _unit_subtitle(u: Unit) -> String:
	if u.is_hero:
		return "Held · Stufe %d" % GameState.hero_level(team)
	if u.carrying > 0:
		return "Trägt %d %s" % [u.carrying, "Gold" if u.carry_kind == "gold" else "Holz"]
	if u.is_worker:
		return "Bürger · sammelt, baut und repariert"
	return "Schaden %d · Reichweite %.0f m" % [u.damage, u.attack_range]


func _show_single(title: String, icon: Texture2D, hp: float, max_hp: float, subtitle: String) -> void:
	_portrait.texture = icon
	_name_label.text = title
	_subtitle.text = subtitle
	_hp_bar.visible = true
	_hp_text.visible = true
	_hp_bar.max_value = max_hp
	_hp_bar.value = maxf(hp, 0.0)
	_hp_text.text = "%d / %d" % [maxf(hp, 0.0), max_hp]
	_group_grid.visible = false


func _show_group(units: Array[Unit]) -> void:
	var counts := {}
	for u in units:
		counts[u.definition_id] = counts.get(u.definition_id, 0) + 1
	_portrait.texture = _icon_for(units[0].definition_id)
	_name_label.text = "%d Einheiten" % units.size()
	_subtitle.text = "%d Typen" % counts.size()
	_hp_bar.visible = false
	_hp_text.visible = false
	_group_grid.visible = true
	for id in counts:
		_group_grid.add_child(_icon_tile(_icon_for(id), counts[id]))


func _show_empty() -> void:
	_portrait.texture = null
	_name_label.text = ""
	_subtitle.text = ""
	_hp_bar.visible = false
	_hp_text.visible = false
	_fill_commands([])


func _show_queue(building: Building) -> void:
	if building.queue.is_empty():
		return
	_queue_box.visible = true
	var signature := "%d:%d" % [building.get_instance_id(), building.queue.size()]
	if _queue_box.get_meta("signature", "") != signature:
		_queue_box.set_meta("signature", signature)
		_rebuild_queue_icons(building)
	var first: Dictionary = building.queue[0]
	_queue_bar.visible = true
	_queue_bar.max_value = first["time"]
	_queue_bar.value = first["elapsed"]


func _rebuild_queue_icons(building: Building) -> void:
	_clear(_queue_box)
	for entry in building.queue:
		var icon: Texture2D = null
		var count := int(entry.get("count", 1))
		var tip := ""
		if entry.has("research"):
			var path := str(entry.get("icon", ""))
			if path != "" and ResourceLoader.exists(Assets.resolve(path)):
				icon = load(Assets.resolve(path))
			tip = "%s – klicken zum Abbrechen" % entry.get("name", "Aufwertung")
		else:
			icon = _icon_for(entry["unit"])
			tip = "Klicken zum Abbrechen" if count == 1 else "%d Einheiten – klicken zum Abbrechen" % count
		var tile := _icon_tile(icon, count if count > 1 else 0, 38.0)
		var button := Button.new()
		button.flat = true
		button.tooltip_text = tip
		button.pressed.connect(func(): building.cancel_last())
		tile.add_child(button)
		button.set_anchors_preset(Control.PRESET_FULL_RECT)
		_queue_box.add_child(tile)


# --- command grid -----------------------------------------------------------

func _panel_commands(building: Building) -> Array:
	var commands := _upgrade_commands(building)
	commands.append_array(_become_commands(building))
	commands.append_array(_train_commands(building))
	return commands


## Rebuilding into a stronger building - the improved tower, the town defense, the bazaar.
func _become_commands(building: Building) -> Array:
	var commands := []
	for entry in building.available_becomes():
		commands.append({
			"icon": entry.get("icon", ""), "title": str(entry.get("name", "Ausbau")),
			"subtitle": "Ausbauen", "cost": entry.get("cost", {}), "row": 0,
			"key": "become%s@%d" % [entry.get("building", ""), building.get_instance_id()],
			"action": func(): building.enqueue_become(entry),
		})
	return commands


func _upgrade_commands(building: Building) -> Array:
	var commands := []
	for entry in building.available_upgrades():
		commands.append({
			"icon": entry.get("icon", ""), "title": str(entry.get("name", "Aufwertung")),
			"subtitle": "Aufwertung", "cost": entry.get("cost", {}), "row": 0,
			"key": "up%d@%d" % [int(entry.get("id", 0)), building.get_instance_id()],
			"action": func(): building.enqueue_research(entry),
		})
	return commands


func _train_commands(building: Building) -> Array:
	var commands := []
	for entry in building.available_trains():
		var def := Assets.unit_def(entry["unit"])
		var unit_cost: Dictionary = def.get("cost", {})
		var count: int = building.batch_size(entry["unit"])
		var cost := {}
		for key in unit_cost:
			cost[key] = unit_cost[key] * count if key != "time_s" else unit_cost[key]
		commands.append({
			"icon": def.get("icon", ""), "title": entry["name"], "cost": cost, "row": 1,
			"badge": count if count > 1 else 0,
			"subtitle": "Ausbilden" if count == 1 else "%d Einheiten" % count,
			"key": "%s@%d" % [entry["unit"], building.get_instance_id()],
			"action": func(): building.enqueue(entry["unit"]),
		})
	return commands


## The hero carries the epoch techs: spending glory here raises the hero's level, which is
## what unlocks the next tier of unit upgrades, buildings and siege engines.
func _hero_commands(hero: Unit) -> Array:
	var commands := []
	if hero_mode:
		commands.append({
			"icon": Assets.unit_def(hero.definition_id).get("icon", ""), "title": "Heldenmodus",
			"subtitle": "Alexander selbst steuern (H)", "cost": {}, "row": 1, "key": "heromode",
			"action": func(): hero_mode.enter(),
		})
	for entry in Assets.unit_def(hero.definition_id).get("hero_levels", []):
		var level := int(entry.get("hero_level", 0))
		if level != GameState.hero_level(team) + 1:
			continue
		commands.append({
			"icon": entry.get("icon", ""), "title": "Heldenstufe %d" % level,
			"subtitle": "Schaltet die nächste Stufe frei", "cost": entry.get("cost", {}),
			"row": 0, "key": "hero%d" % level,
			"action": func(): _level_hero(entry),
		})
	return commands


func _level_hero(entry: Dictionary) -> void:
	if not GameState.spend(team, entry.get("cost", {})):
		return
	GameState.set_hero_level(team, int(entry.get("hero_level", 1)))
	GameState.complete_research(team, int(entry.get("id", 0)))


## What citizens can found: the original build menu, minus entries whose prerequisite
## building the player does not have yet. It is longer than one row, so it uses both.
func _build_commands() -> Array:
	var commands := []
	var built := {}
	for b in Building.all_buildings:
		if b.team == team and b.is_complete():
			built[b.definition_id] = true
	var builds: Array = GameState.civ(team).get("builds", []).duplicate()
	builds.sort_custom(func(a, b): return int(a.get("slot", 99)) < int(b.get("slot", 99)))
	for entry in builds:
		var requires = entry.get("requires")
		if requires != null and requires != "" and not built.has(requires):
			continue
		var id: String = entry["building"]
		var def := Assets.unit_def(id)
		commands.append({
			"icon": def.get("icon", ""), "title": str(entry["name"]), "subtitle": "Bauen",
			"cost": def.get("cost", {}), "row": 0 if commands.size() < COLUMNS else 1,
			"action": func(): selection.begin_placement(id),
		})
	return commands


func _fill_commands(commands: Array) -> void:
	var signature := ",".join(commands.map(func(c): return c.get("key", c["title"])))
	if _command_grid.get_meta("signature", "") == signature:
		_update_affordability()
		return
	_command_grid.set_meta("signature", signature)
	_clear(_command_grid)
	var rows := [[], []]
	for c in commands:
		rows[int(c.get("row", 1))].append(c)
	for row in rows:
		for column in COLUMNS:
			if column < row.size():
				_command_grid.add_child(_command_button(row[column]))
			else:
				_command_grid.add_child(_empty_slot())
	_update_affordability()


func _command_button(command: Dictionary) -> Control:
	var slot := _slot_frame()
	var button := TextureButton.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	var icon: String = str(command.get("icon", ""))
	if icon != "" and ResourceLoader.exists(Assets.resolve(icon)):
		button.texture_normal = load(Assets.resolve(icon))
	button.pressed.connect(command["action"])
	button.mouse_entered.connect(func(): _set_tooltip(command))
	button.mouse_exited.connect(func(): _tooltip.text = "")
	slot.add_child(button)
	slot.set_meta("cost", command.get("cost", {}))
	var badge := int(command.get("badge", 0))
	if badge > 0:
		slot.add_child(_badge(str(badge)))
	return slot


func _badge(text: String) -> Label:
	var label := Label.new()
	label.text = text
	_style_label(label, 14, GOLD)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	label.position -= Vector2(4, 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _set_tooltip(command: Dictionary) -> void:
	var parts := []
	var cost: Dictionary = command.get("cost", {})
	for key in ["gold", "wood", "glory"]:
		if int(cost.get(key, 0)) > 0:
			parts.append("%d %s" % [int(cost[key]), RESOURCE_STYLE[key]["label"]])
	var line: String = command["title"]
	if command.get("subtitle", "") != "":
		line += "  ·  " + str(command["subtitle"])
	if not parts.is_empty():
		line += "  ·  " + ", ".join(parts)
	_tooltip.text = line


func _update_affordability() -> void:
	for slot in _command_grid.get_children():
		if not slot.has_meta("cost"):
			continue
		var ok := GameState.can_afford(team, slot.get_meta("cost", {}))
		slot.modulate = Color.WHITE if ok else Color(0.6, 0.5, 0.5, 0.9)


# --- small building blocks --------------------------------------------------

func _icon_tile(icon: Texture2D, badge := 0, size := 46.0) -> Control:
	var tile := _slot_frame(size)
	var rect := TextureRect.new()
	rect.texture = icon
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(rect)
	if badge > 0:
		tile.add_child(_badge(str(badge)))
	return tile


func _slot_frame(size := SLOT) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(size, size)
	panel.add_theme_stylebox_override("panel", _slot_style())
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	return panel


func _empty_slot() -> Control:
	var panel := _slot_frame()
	panel.modulate = Color(1, 1, 1, 0.35)
	return panel


func _slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.1, 0.75)
	style.border_color = GOLD.darkened(0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 2
	style.content_margin_top = 2
	style.content_margin_right = 2
	style.content_margin_bottom = 2
	return style


func _panel_style(top_border := 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = GOLD.darkened(0.55)
	style.border_width_top = top_border
	style.set_corner_radius_all(8)
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 16
	style.content_margin_top = 8
	style.content_margin_right = 16
	style.content_margin_bottom = 8
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 10
	return style


func _icon(icon_name: String, color: Color, size := 22.0) -> TextureRect:
	var rect := TextureRect.new()
	var path := "res://assets/icons/%s.svg" % icon_name
	if ResourceLoader.exists(path):
		rect.texture = load(path)
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.modulate = color
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


# --- layout -----------------------------------------------------------------

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	var style := _panel_style(0)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	for key in ["gold", "wood", "glory"]:
		_values[key] = _counter(row, RESOURCE_STYLE[key]["icon"], RESOURCE_STYLE[key]["color"])
	_pop_value = _counter(row, "units", Color(0.7, 0.82, 1.0))
	_batch_value = _counter(row, "squad", Color(0.85, 0.85, 0.9))
	_build_speed_controls(row)


func _counter(parent: Control, icon: String, color: Color) -> Label:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_icon(icon, color))
	var value := Label.new()
	_style_label(value, 20, TEXT)
	value.custom_minimum_size.x = 52
	box.add_child(value)
	parent.add_child(box)
	return value


func _build_speed_controls(row: Control) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	for speed in [0.0, 1.0, 2.0, 3.0]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(34, 28)
		button.focus_mode = Control.FOCUS_NONE
		button.flat = true
		button.set_meta("speed", speed)
		button.tooltip_text = "Pause" if speed == 0.0 else "Tempo %sx" % String.num(speed, 1)
		var icon_name := "pause" if speed == 0.0 else ("play" if speed == 1.0 else "fast")
		var icon := _icon(icon_name, TEXT, 18.0)
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		if speed > 1.0:
			var label := Label.new()
			label.text = String.num(speed, 0)
			_style_label(label, 12, TEXT)
			label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			label.position -= Vector2(3, 1)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(label)
		button.pressed.connect(func(): GameState.set_speed(speed))
		box.add_child(button)
	row.add_child(box)
	_speed_buttons = box
	GameState.speed_changed.connect(_highlight_speed)
	_highlight_speed(GameState.speed)


func _highlight_speed(current: float) -> void:
	for button in _speed_buttons.get_children():
		if button is Button:
			var active: bool = is_equal_approx(button.get_meta("speed"), current)
			button.modulate = GOLD if active else DIM.darkened(0.15)


func _build_message() -> void:
	_message = Label.new()
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.position.y = 76
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_message, 26, GOLD)
	_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_message.add_theme_constant_override("outline_size", 7)
	_message.modulate.a = 0.0
	add_child(_message)


func _build_bottom_panel() -> void:
	var panel := PanelContainer.new()
	_panel = panel
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -PANEL_HEIGHT
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var minimap := Minimap.new()
	minimap.name = "Minimap"
	minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.camera_rig = camera_rig
	minimap.selection = selection
	minimap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(minimap)

	var portrait_frame := _slot_frame(118.0)
	portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait = TextureRect.new()
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_frame.add_child(_portrait)
	row.add_child(portrait_frame)

	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 300
	info.add_theme_constant_override("separation", 4)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	_name_label = Label.new()
	_style_label(_name_label, 28, GOLD)
	info.add_child(_name_label)
	_subtitle = Label.new()
	_style_label(_subtitle, 15, DIM)
	info.add_child(_subtitle)

	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.09, 0.09, 0.09, 0.9)
	back.set_corner_radius_all(3)
	back.border_color = Color(0, 0, 0, 0.6)
	back.set_border_width_all(1)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	info.add_child(hp_row)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(210, 14)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.78, 0.38)
	fill.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	_hp_bar.add_theme_stylebox_override("background", back)
	hp_row.add_child(_hp_bar)
	_hp_text = Label.new()
	_style_label(_hp_text, 14, TEXT)
	hp_row.add_child(_hp_text)

	var queue_column := VBoxContainer.new()
	queue_column.add_theme_constant_override("separation", 3)
	info.add_child(queue_column)
	_queue_bar = ProgressBar.new()
	_queue_bar.show_percentage = false
	_queue_bar.custom_minimum_size = Vector2(210, 7)
	var queue_fill := StyleBoxFlat.new()
	queue_fill.bg_color = GOLD
	queue_fill.set_corner_radius_all(2)
	_queue_bar.add_theme_stylebox_override("fill", queue_fill)
	_queue_bar.add_theme_stylebox_override("background", back)
	_queue_bar.visible = false
	queue_column.add_child(_queue_bar)
	_queue_box = HBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 4)
	_queue_box.visible = false
	queue_column.add_child(_queue_box)

	_group_grid = GridContainer.new()
	_group_grid.columns = 8
	_group_grid.add_theme_constant_override("h_separation", 4)
	_group_grid.add_theme_constant_override("v_separation", 4)
	_group_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_group_grid)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var commands := VBoxContainer.new()
	commands.alignment = BoxContainer.ALIGNMENT_END
	commands.size_flags_vertical = Control.SIZE_SHRINK_END
	commands.add_theme_constant_override("separation", 4)
	row.add_child(commands)
	_tooltip = Label.new()
	_style_label(_tooltip, 15, TEXT)
	_tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tooltip.custom_minimum_size = Vector2(COLUMNS * (SLOT + 5), 20)
	commands.add_child(_tooltip)
	_command_grid = GridContainer.new()
	_command_grid.columns = COLUMNS
	_command_grid.add_theme_constant_override("h_separation", 5)
	_command_grid.add_theme_constant_override("v_separation", 5)
	commands.add_child(_command_grid)


# --- hero mode --------------------------------------------------------------

## While the player steers the hero there is nothing to command, so the panel makes way for
## his hit points, the cooldown of his special attack and the size of his retinue.
func _set_hero_mode(active: bool) -> void:
	_panel.visible = not active
	_hero_overlay.visible = active
	if active:
		_update_hero_overlay()


func _update_hero_overlay() -> void:
	var hero: Unit = hero_mode.hero()
	if hero == null:
		return
	_hero_name.text = "%s · Stufe %d" % [hero.display_name, GameState.hero_level(team)]
	_hero_hp.max_value = hero.max_hit_points
	_hero_hp.value = maxf(hero.hit_points, 0.0)
	_hero_hp_text.text = "%d / %d" % [maxf(hero.hit_points, 0.0), hero.max_hit_points]
	_hero_special.value = hero_mode.special_ready() * 100.0
	_hero_retinue.text = "%d Gefolge" % hero_mode.retinue_size()


func _build_hero_overlay() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -132
	panel.offset_bottom = -18
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var style := _panel_style()
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_hero_overlay = panel

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	column.add_child(title)
	_hero_name = Label.new()
	_style_label(_hero_name, 24, GOLD)
	title.add_child(_hero_name)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(spacer)
	_hero_retinue = Label.new()
	_style_label(_hero_retinue, 15, DIM)
	title.add_child(_hero_retinue)

	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.09, 0.09, 0.09, 0.9)
	back.set_corner_radius_all(3)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	column.add_child(hp_row)
	_hero_hp = ProgressBar.new()
	_hero_hp.show_percentage = false
	_hero_hp.custom_minimum_size = Vector2(500, 16)
	_hero_hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.78, 0.26, 0.24)
	fill.set_corner_radius_all(3)
	_hero_hp.add_theme_stylebox_override("fill", fill)
	_hero_hp.add_theme_stylebox_override("background", back)
	hp_row.add_child(_hero_hp)
	_hero_hp_text = Label.new()
	_style_label(_hero_hp_text, 14, TEXT)
	hp_row.add_child(_hero_hp_text)

	var special_row := HBoxContainer.new()
	special_row.add_theme_constant_override("separation", 8)
	column.add_child(special_row)
	var special_label := Label.new()
	special_label.text = "Spezialangriff"
	_style_label(special_label, 13, DIM)
	special_row.add_child(special_label)
	_hero_special = ProgressBar.new()
	_hero_special.show_percentage = false
	_hero_special.custom_minimum_size = Vector2(300, 8)
	_hero_special.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hero_special.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var special_fill := StyleBoxFlat.new()
	special_fill.bg_color = GOLD
	special_fill.set_corner_radius_all(2)
	_hero_special.add_theme_stylebox_override("fill", special_fill)
	_hero_special.add_theme_stylebox_override("background", back)
	special_row.add_child(_hero_special)

	var hint := Label.new()
	hint.text = "WASD laufen · Maus umsehen · Links Angriff · Rechts Block · Leertaste Spezial · Esc zurück"
	_style_label(hint, 13, DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


# --- helpers ----------------------------------------------------------------

func _icon_for(id: String) -> Texture2D:
	var def := Assets.unit_def(id)
	var icon = def.get("icon")
	if icon == null or icon == "":
		return null
	return load(Assets.resolve(icon))


func _update_resources() -> void:
	var p := GameState.player(team)
	for key in RESOURCE_STYLE:
		_values[key].text = str(int(p.get(key, 0)))


func _update_counters() -> void:
	var n := 0
	for u in Unit.all_units:
		if u.team == team:
			n += 1
	_pop_value.text = str(n)
	_batch_value.text = str(GameState.batch_size(team))


func _style_label(label: Label, size: int, color: Color) -> void:
	if _font:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
