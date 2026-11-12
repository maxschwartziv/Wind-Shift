shader_type canvas_item;
// Wind speed as a smooth color field over the water, blended between the WindPalette colors.
// Reads the same wind and depth textures as the wind particles. The node sits at the world origin,
// so local vertex positions are world units.

uniform vec2 world_origin;
uniform float world_size = 1048576.0;
uniform float alpha = 0.45;

uniform sampler2D wind_tex : filter_nearest;
uniform vec2 wind_size;
uniform float lat_north;
uniform float lon_west;
uniform float dlat;
uniform float dlon;

uniform sampler2D depth_tex : filter_nearest;
uniform vec2 depth_size;
uniform float d_lat_north;
uniform float d_lon_west;
uniform float d_dlat;
uniform float d_dlon;


// Wind the boat measures: inside a circle around it the actual wind replaces the map's wind.
uniform float obs_on = 0.0;
uniform vec2 obs_center;   // world units
uniform float obs_radius;  // world units
uniform vec2 obs_wind;     // m/s east, north

vec2 observed(vec2 world, vec2 w) {
	float m = obs_on * (1.0 - smoothstep(obs_radius * 0.85, obs_radius, distance(world, obs_center)));
	return mix(w, obs_wind, m);
}

uniform vec4 bin_colors[7];
uniform float bin_edges[7];

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

vec2 latlon(vec2 local) {
	vec2 w = local + world_origin;
	float lon = w.x / world_size * 360.0 - 180.0;
	float lat = degrees(atan(sinh(PI * (1.0 - 2.0 * w.y / world_size))));
	return vec2(lat, lon);
}

vec2 wind_cell(ivec2 c) {
	return texelFetch(wind_tex, clamp(c, ivec2(0), ivec2(wind_size) - 1), 0).rg;
}

// Catmull-Rom weights for the four grid points around a fraction t.
vec4 cr_weights(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return vec4(-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2);
}

// Bicubic wind between the grid points, so the color field has no creases along grid lines.
vec2 wind_at(vec2 ll) {
	vec2 f = vec2((ll.y - lon_west) / dlon, (lat_north - ll.x) / dlat);
	f = clamp(f, vec2(0.0), wind_size - 1.001);
	ivec2 c = ivec2(floor(f));
	vec4 wx = cr_weights(f.x - float(c.x));
	vec4 wy = cr_weights(f.y - float(c.y));
	vec2 sum = vec2(0.0);
	for (int j = 0; j < 4; j++) {
		vec2 row = vec2(0.0);
		for (int i = 0; i < 4; i++) {
			row += wind_cell(c + ivec2(i - 1, j - 1)) * wx[i];
		}
		sum += row * wy[j];
	}
	return sum;
}

float elevation(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(depth_size) - 1);
	vec4 t = texelFetch(depth_tex, c, 0);
	float v = round(t.r * 255.0) + round(t.g * 255.0) * 256.0;
	if (v >= 32768.0) { v -= 65536.0; }
	return v;
}

// 1 over water, 0 over land: elevation interpolated between grid points, then cut at sea level with
// a one-pixel soft edge, so the coast is a smooth line.
float water(vec2 ll) {
	vec2 f = clamp(vec2((ll.y - d_lon_west) / d_dlon, (d_lat_north - ll.x) / d_dlat), vec2(0.0), depth_size - 1.001);
	ivec2 c = ivec2(floor(f));
	vec2 t = f - vec2(c);
	float e = mix(mix(elevation(c), elevation(c + ivec2(1, 0)), t.x),
			mix(elevation(c + ivec2(0, 1)), elevation(c + ivec2(1, 1)), t.x), t.y);
	float w = max(fwidth(e), 1e-3);
	return 1.0 - smoothstep(-w, w, e);
}

vec3 ramp(float kn) {
	vec3 c = bin_colors[0].rgb;
	for (int i = 1; i < 7; i++) {
		float span = (i < 6) ? bin_edges[i] - bin_edges[i - 1] : 5.0;
		c = mix(c, bin_colors[i].rgb, clamp((kn - bin_edges[i - 1]) / span, 0.0, 1.0));
	}
	return c;
}

void fragment() {
	vec2 ll = latlon(world_pos);
	float kn = length(observed(world_pos, wind_at(ll))) / 0.514444;
	COLOR = vec4(ramp(kn), alpha * water(ll));
}
