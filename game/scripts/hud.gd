extends CanvasLayer
## Heads-up display: resource bar, messages, and the bottom panel with the selection
## (portrait, name, hit points / group overview) and the command grid (train units,
## found buildings) using the original button icons.

const PANEL_HEIGHT := 176.0
const BUTTON_SIZE := 58.0
const GOLD := Color(0.93, 0.79, 0.42)
const TEXT := Color(0.93, 0.9, 0.82)

var selection: Node  # selection_controller.gd
var team := 0

var _font: Font
var _gold_label: Label
var _wood_label: Label
var _pop_label: Label
var _message: Label
var _message_time := 0.0
var _portrait: TextureRect
var _name_label: Label
var _info_label: Label
var _hp_bar: ProgressBar
var _group_grid: GridContainer
var _command_grid: GridContainer
var _queue_box: HBoxContainer
var _queue_bar: ProgressBar
var _tooltip: Label
var _refresh_timer := 0.0
var _speed_buttons: Control


func _ready() -> void:
	_font = load(Assets.resolve("fonts/rafc.ttf")) if ResourceLoader.exists(Assets.resolve("fonts/rafc.ttf")) else null
	_build_top_bar()
	_build_message()
	_build_bottom_panel()
	GameState.resources_changed.connect(func(t): if t == team: _update_resources())
	GameState.message.connect(show_message)
	_update_resources()


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time / 0.6, 0.0, 1.0)
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
	if selection == null:
		return
	var units: Array[Unit] = selection.selected_units()
	var building: Building = selection.selected_building
	if building and not is_instance_valid(building):
		building = null
	_update_population()
	_clear(_group_grid)
	if building == null or building.queue.is_empty():
		_queue_box.set_meta("signature", "")
	_queue_box.visible = false
	_queue_bar.visible = false

	if building:
		_show_single(building.display_name, _icon_for(building.definition_id), building.hit_points, building.max_hit_points,
			"Im Bau: %d %%" % int(building.build_progress * 100) if not building.is_complete() else "")
		_show_queue(building)
		_fill_commands(_train_commands(building) if building.team == team and building.is_complete() else [])
	elif units.size() == 1:
		var u := units[0]
		var extra := ""
		if u.carrying > 0:
			extra = "Trägt %d %s" % [u.carrying, "Gold" if u.carry_kind == "gold" else "Holz"]
		elif u.is_worker:
			extra = "Bürger – sammelt Gold/Holz, baut Gebäude"
		else:
			extra = "Schaden %d · Reichweite %.0f m" % [u.damage, u.attack_range]
		_show_single(u.display_name, _icon_for(u.definition_id), u.hit_points, u.max_hit_points, extra)
		_fill_commands(_build_commands() if u.is_worker else [])
	elif units.size() > 1:
		_show_group(units)
		var any_worker := units.any(func(u): return u.is_worker)
		_fill_commands(_build_commands() if any_worker else [])
	else:
		_portrait.texture = null
		_name_label.text = ""
		_info_label.text = ""
		_hp_bar.visible = false
		_fill_commands([])


# --- content ----------------------------------------------------------------

func _show_single(title: String, icon: Texture2D, hp: float, max_hp: float, extra: String) -> void:
	_portrait.texture = icon
	_name_label.text = title
	_hp_bar.visible = true
	_hp_bar.max_value = max_hp
	_hp_bar.value = maxf(hp, 0.0)
	_info_label.text = "%d / %d" % [maxf(hp, 0.0), max_hp] + ("\n" + extra if extra != "" else "")
	_group_grid.visible = false


func _show_group(units: Array[Unit]) -> void:
	var counts := {}
	for u in units:
		counts[u.definition_id] = counts.get(u.definition_id, 0) + 1
	_portrait.texture = _icon_for(units[0].definition_id)
	_name_label.text = "%d Einheiten" % units.size()
	_hp_bar.visible = false
	_info_label.text = ""
	_group_grid.visible = true
	for id in counts:
		var cell := TextureRect.new()
		cell.texture = _icon_for(id)
		cell.custom_minimum_size = Vector2(44, 44)
		cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var count := Label.new()
		count.text = str(counts[id])
		_style_label(count, 15, TEXT)
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		count.position -= Vector2(4, 2)
		cell.add_child(count)
		_group_grid.add_child(cell)


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
	for i in building.queue.size():
		var entry: Dictionary = building.queue[i]
		var b := TextureButton.new()
		b.texture_normal = _icon_for(entry["unit"])
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(36, 36)
		var count := int(entry.get("count", 1))
		b.tooltip_text = "Klicken zum Abbrechen" if count == 1 else "%d Einheiten – klicken zum Abbrechen" % count
		if count > 1:
			var badge := Label.new()
			badge.text = str(count)
			_style_label(badge, 13, GOLD)
			badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			badge.position -= Vector2(2, 0)
			b.add_child(badge)
		b.pressed.connect(func(): building.cancel_last())
		_queue_box.add_child(b)


func _train_commands(building: Building) -> Array:
	var commands := []
	for entry in building.trains:
		var def := Assets.unit_def(entry["unit"])
		var unit_cost: Dictionary = def.get("cost", {})
		var count: int = building.batch_size(entry["unit"])
		var cost := {}
		for key in unit_cost:
			cost[key] = unit_cost[key] * count if key != "time_s" else unit_cost[key]
		commands.append({
			"icon": def.get("icon", ""),
			"title": entry["name"] if count == 1 else "%d x %s" % [count, entry["name"]],
			"cost": cost,
			"key": "%s@%d" % [entry["unit"], building.get_instance_id()],
			"action": func(): building.enqueue(entry["unit"]),
		})
	return commands


## What citizens can found: the original build menu, minus entries whose prerequisite
## building the player does not have yet.
func _build_commands() -> Array:
	var commands := []
	var built := {}
	for b in Building.all_buildings:
		if b.team == team and b.is_complete():
			built[b.definition_id] = true
	var builds: Array = GameState.civ(team).get("builds", [])
	builds = builds.duplicate()
	builds.sort_custom(func(a, b): return int(a.get("slot", 99)) < int(b.get("slot", 99)))
	for entry in builds:
		var requires = entry.get("requires")
		if requires != null and requires != "" and not built.has(requires):
			continue
		var id: String = entry["building"]
		var def := Assets.unit_def(id)
		commands.append({
			"icon": def.get("icon", ""), "title": str(entry["name"]) + " bauen", "cost": def.get("cost", {}),
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
	for c in commands:
		var button := TextureButton.new()
		button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_SCALE
		if c["icon"] != "" and c["icon"] != null:
			button.texture_normal = load(Assets.resolve(c["icon"]))
		button.set_meta("cost", c["cost"])
		var cost: Dictionary = c["cost"]
		var parts := []
		if int(cost.get("gold", 0)) > 0:
			parts.append("%d Gold" % cost["gold"])
		if int(cost.get("wood", 0)) > 0:
			parts.append("%d Holz" % cost["wood"])
		var tip: String = c["title"] + ("  –  " + ", ".join(parts) if parts.size() > 0 else "")
		button.mouse_entered.connect(func(): _tooltip.text = tip)
		button.mouse_exited.connect(func(): _tooltip.text = "")
		button.pressed.connect(c["action"])
		var frame := Panel.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = GOLD.darkened(0.3)
		style.set_border_width_all(1)
		frame.add_theme_stylebox_override("panel", style)
		button.add_child(frame)
		_command_grid.add_child(button)
	_update_affordability()


func _update_affordability() -> void:
	for button in _command_grid.get_children():
		var ok := GameState.can_afford(team, button.get_meta("cost", {}))
		button.modulate = Color.WHITE if ok else Color(0.55, 0.45, 0.45)


func _icon_for(id: String) -> Texture2D:
	var def := Assets.unit_def(id)
	var icon = def.get("icon")
	if icon == null or icon == "":
		return null
	return load(Assets.resolve(icon))


func _update_resources() -> void:
	var p := GameState.player(team)
	_gold_label.text = str(p["gold"])
	_wood_label.text = str(p["wood"])


func _update_population() -> void:
	var n := 0
	for u in Unit.all_units:
		if u.team == team:
			n += 1
	_pop_label.text = str(n)


# --- layout -----------------------------------------------------------------

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Vector4(0, 0, 0, 14)))
	panel.position = Vector2(0, 0)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)
	_gold_label = _resource_entry(row, "Gold", Color(1.0, 0.82, 0.25))
	_wood_label = _resource_entry(row, "Holz", Color(0.62, 0.43, 0.25))
	_pop_label = _resource_entry(row, "Einheiten", Color(0.6, 0.75, 0.95))
	_build_speed_controls(row)


func _build_speed_controls(row: Control) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = "Tempo"
	_style_label(label, 15, TEXT.darkened(0.25))
	box.add_child(label)
	for speed in [0.0, 0.5, 1.0, 2.0, 3.0]:
		var button := Button.new()
		button.text = "II" if speed == 0.0 else String.num(speed, 1) + "x"
		button.custom_minimum_size = Vector2(38, 24)
		button.focus_mode = Control.FOCUS_NONE
		if _font:
			button.add_theme_font_override("font", _font)
		button.add_theme_font_size_override("font_size", 14)
		button.set_meta("speed", speed)
		button.pressed.connect(func(): GameState.set_speed(speed))
		box.add_child(button)
	row.add_child(box)
	_speed_buttons = box
	GameState.speed_changed.connect(_highlight_speed)
	_highlight_speed(GameState.speed)


func _highlight_speed(current: float) -> void:
	for button in _speed_buttons.get_children():
		if button is Button:
			button.modulate = GOLD if is_equal_approx(button.get_meta("speed"), current) else Color(0.75, 0.73, 0.68)


func _resource_entry(parent: Control, title: String, color: Color) -> Label:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(dot)
	var name := Label.new()
	name.text = title
	_style_label(name, 15, TEXT.darkened(0.25))
	box.add_child(name)
	var value := Label.new()
	_style_label(value, 19, TEXT)
	value.custom_minimum_size.x = 44
	box.add_child(value)
	parent.add_child(box)
	return value


func _build_message() -> void:
	_message = Label.new()
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.position.y = 70
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_message, 24, GOLD)
	_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_message.add_theme_constant_override("outline_size", 6)
	_message.modulate.a = 0.0
	add_child(_message)


func _build_bottom_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -PANEL_HEIGHT
	panel.add_theme_stylebox_override("panel", _panel_style(Vector4(18, 16, 18, 14)))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(128, 128)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_portrait)

	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 320
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	_name_label = Label.new()
	_style_label(_name_label, 26, GOLD)
	info.add_child(_name_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(260, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.8, 0.35)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	_hp_bar.add_theme_stylebox_override("background", back)
	info.add_child(_hp_bar)
	_info_label = Label.new()
	_style_label(_info_label, 15, TEXT)
	info.add_child(_info_label)
	_queue_bar = ProgressBar.new()
	_queue_bar.show_percentage = false
	_queue_bar.custom_minimum_size = Vector2(260, 6)
	var queue_fill := StyleBoxFlat.new()
	queue_fill.bg_color = GOLD
	_queue_bar.add_theme_stylebox_override("fill", queue_fill)
	_queue_bar.add_theme_stylebox_override("background", back)
	info.add_child(_queue_bar)
	_queue_box = HBoxContainer.new()
	info.add_child(_queue_box)

	_group_grid = GridContainer.new()
	_group_grid.columns = 8
	_group_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_group_grid)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var commands := VBoxContainer.new()
	row.add_child(commands)
	_tooltip = Label.new()
	_style_label(_tooltip, 15, TEXT)
	_tooltip.custom_minimum_size = Vector2(7 * (BUTTON_SIZE + 6), 20)
	commands.add_child(_tooltip)
	_command_grid = GridContainer.new()
	_command_grid.columns = 7
	_command_grid.add_theme_constant_override("h_separation", 6)
	_command_grid.add_theme_constant_override("v_separation", 6)
	commands.add_child(_command_grid)


func _panel_style(padding: Vector4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.065, 0.06, 0.86)
	style.border_color = GOLD.darkened(0.45)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = padding.x + 12
	style.content_margin_top = padding.y + 6
	style.content_margin_right = padding.z + 12
	style.content_margin_bottom = padding.w
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 8
	return style


func _style_label(label: Label, size: int, color: Color) -> void:
	if _font:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
