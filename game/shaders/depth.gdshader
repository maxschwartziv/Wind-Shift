shader_type canvas_item;
// Shades water shallower than the draft and shallower than 10 m, from the leg's depth grid.
// The grid is regular in lat/lon; each fragment converts its Web Mercator position back to lat/lon.
// Depth is interpolated between grid points, as the sim does, so the contours are smooth lines.

uniform sampler2D depth_tex : filter_nearest;  // RG8 bytes of int16 elevation in decimeters
uniform vec2 world_origin;
uniform vec2 rect_pos;
uniform vec2 rect_size;
uniform float lat_north;
uniform float lon_west;
uniform float dlat;
uniform float dlon;
uniform vec2 grid_size;  // cols, rows
uniform float draft = 2.0;
uniform bool show_map = false;  // depth map: shaded water and contour lines
uniform float world_size = 1048576.0;

float elev(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(grid_size) - 1);
	vec4 t = texelFetch(depth_tex, c, 0);
	float v = round(t.r * 255.0) + round(t.g * 255.0) * 256.0;
	if (v >= 32768.0) { v -= 65536.0; }
	return v / 10.0;
}

// 0 below the level, 1 above it, with a one-pixel soft edge.
float above(float value, float level) {
	float w = max(fwidth(value), 1e-4);
	return smoothstep(level - w, level + w, value);
}

void fragment() {
	vec2 w = rect_pos + UV * rect_size + world_origin;
	float lon = w.x / world_size * 360.0 - 180.0;
	float lat = degrees(atan(sinh(PI * (1.0 - 2.0 * w.y / world_size))));
	vec2 f = clamp(vec2((lon - lon_west) / dlon, (lat_north - lat) / dlat), vec2(0.0), grid_size - 1.001);
	ivec2 c = ivec2(floor(f));
	vec2 k = f - vec2(c);
	float top = mix(elev(c), elev(c + ivec2(1, 0)), k.x);
	float bottom = mix(elev(c + ivec2(0, 1)), elev(c + ivec2(1, 1)), k.x);
	float depth = -mix(top, bottom, k.y);
	float water = above(depth, 0.0);
	float shallow = 1.0 - above(depth, draft);
	float under10 = 1.0 - above(depth, 10.0);
	vec4 amber = vec4(1.0, 0.75, 0.15, 0.25 * under10);
	vec4 red = vec4(0.95, 0.15, 0.1, 0.55);
	if (show_map) {
		// Light where shallow, dark where deep, on a log scale from 1 m to 3000 m.
		float s = clamp(log(max(depth, 1.0)) / log(3000.0), 0.0, 1.0);
		vec3 col = mix(vec3(0.62, 0.86, 0.93), vec3(0.03, 0.10, 0.30), s);
		vec4 map = vec4(col, 0.72);
		// Contour lines at standard depths.
		float levels[10] = float[](2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0);
		float line = 0.0;
		float wpx = max(fwidth(depth), 1e-4);
		for (int i = 0; i < 10; i++) {
			line = max(line, 1.0 - smoothstep(0.0, 1.2 * wpx, abs(depth - levels[i])));
		}
		map = mix(map, vec4(0.92, 0.97, 1.0, 0.9), line * 0.8);
		COLOR = mix(map, red, shallow);
	} else {
		COLOR = mix(amber, red, shallow);
	}
	COLOR.a *= water;
}
