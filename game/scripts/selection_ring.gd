extends MeshInstance3D
## Thin flat ring (or rounded rectangle for buildings) drawn on the ground by a shader,
## so the line stays crisp and slim at any size.

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform vec4 color : source_color = vec4(0.45, 1.0, 0.5, 0.95);
uniform vec2 half_size = vec2(1.0);
uniform float line_width = 0.07;
uniform float corner = 1.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * half_size;
	vec2 inner = max(half_size - vec2(corner), vec2(0.0));
	float d = length(max(abs(p) - inner, vec2(0.0))) - corner;
	float edge = abs(d + line_width * 0.5);
	float aa = fwidth(d) * 1.2;
	float a = 1.0 - smoothstep(line_width * 0.5 - aa, line_width * 0.5 + aa, edge);
	ALBEDO = color.rgb;
	ALPHA = a * color.a;
}
"""

static var _shader: Shader

var _material: ShaderMaterial


func setup_circle(radius: float, color := Color(0.45, 1.0, 0.5, 0.95)) -> void:
	_setup(Vector2(radius, radius), radius, color)


func setup_rect(size: Vector2, color := Color(0.45, 1.0, 0.5, 0.95)) -> void:
	_setup(size * 0.5, minf(size.x, size.y) * 0.12, color)


func _setup(half_size: Vector2, corner: float, color: Color) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = _shader
	_material.set_shader_parameter("half_size", half_size)
	_material.set_shader_parameter("corner", corner)
	_material.set_shader_parameter("color", color)
	_material.set_shader_parameter("line_width", clampf(half_size.x * 0.06, 0.05, 0.18))
	var plane := PlaneMesh.new()
	plane.size = half_size * 2.0
	mesh = plane
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = 0.04
