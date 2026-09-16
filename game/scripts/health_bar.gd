extends Node3D
## Camera-facing hit point bar. Only visible while the Option (Alt) key is held.

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;
uniform float fraction = 1.0;
uniform vec3 fill_color : source_color = vec3(0.2, 0.9, 0.3);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float border = step(UV.x, 0.03) + step(0.97, UV.x) + step(UV.y, 0.15) + step(0.85, UV.y);
	vec3 color = UV.x < fraction ? fill_color : vec3(0.08);
	ALBEDO = mix(color, vec3(0.0), clamp(border, 0.0, 1.0));
}
"""

static var _shader: Shader
static var force_visible := false

var alive := true
var _material: ShaderMaterial


func _init() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = _shader
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	set_width(1.1)
	visible = false


func set_width(width: float) -> void:
	var quad: QuadMesh = (get_child(0) as MeshInstance3D).mesh
	quad.size = Vector2(width, clampf(width * 0.12, 0.12, 0.35))


func set_fraction(fraction: float, team_color: Color) -> void:
	_material.set_shader_parameter("fraction", fraction)
	var health_color := Color(0.25, 0.9, 0.3).lerp(Color(0.95, 0.2, 0.15), 1.0 - fraction)
	_material.set_shader_parameter("fill_color", health_color.lerp(team_color, 0.15))


func _process(_delta: float) -> void:
	visible = alive and (force_visible or Input.is_key_pressed(KEY_ALT))
