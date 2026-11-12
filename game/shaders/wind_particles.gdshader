shader_type particles;
// Wind particles: each one drifts with the wind at its own position and leaves a curved trail,
// tinted a pale version of the wind speed color (WindPalette). They run on screen time, so they look the same at every game speed.
// Wind comes from a small float texture of (east, north) m/s on the leg's lat/lon wind grid.

uniform vec2 rect_pos;     // spawn area (the camera view) in world units
uniform vec2 rect_size;
uniform vec2 bounds_pos;   // the leg's area in world units; particles outside it are not drawn
uniform vec2 bounds_size;
uniform vec2 world_origin;
uniform float world_size = 1048576.0;
uniform float world_per_px = 1.0;  // world units per screen pixel at the present zoom
uniform float px_per_kn = 6.0;     // screen pixels per second for each knot of wind

uniform sampler2D wind_tex : filter_nearest;
uniform vec2 wind_size;  // cols, rows
uniform float lat_north;
uniform float lon_west;
uniform float dlat;
uniform float dlon;

uniform sampler2D depth_tex : filter_nearest;  // RG8 bytes of int16 elevation in decimeters
uniform vec2 depth_size;
uniform float d_lat_north;
uniform float d_lon_west;
uniform float d_dlat;
uniform float d_dlon;

// Integer hash (lowbias32): even, uncorrelated values for consecutive inputs. The sin-based hash this
// replaces lost precision at large particle numbers and bunched the particles into bands.
uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float rand01(uint x) {
	return float(hash_u(x) >> 8u) / 16777216.0;
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

vec2 wind_at(vec2 ll) {
	vec2 f = vec2((ll.y - lon_west) / dlon, (lat_north - ll.x) / dlat);
	f = clamp(f, vec2(0.0), wind_size - 1.001);
	ivec2 c = ivec2(floor(f));
	vec2 t = f - vec2(c);
	vec2 top = mix(wind_cell(c), wind_cell(c + ivec2(1, 0)), t.x);
	vec2 bottom = mix(wind_cell(c + ivec2(0, 1)), wind_cell(c + ivec2(1, 1)), t.x);
	return mix(top, bottom, t.y);
}

float elevation(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(depth_size) - 1);
	vec4 t = texelFetch(depth_tex, c, 0);
	float v = round(t.r * 255.0) + round(t.g * 255.0) * 256.0;
	if (v >= 32768.0) { v -= 65536.0; }
	return v;
}

// Land test on elevation interpolated between grid points, matching the color field's coast.
bool on_land(vec2 ll) {
	vec2 f = vec2((ll.y - d_lon_west) / d_dlon, (d_lat_north - ll.x) / d_dlat);
	if (f.x < 0.0 || f.y < 0.0 || f.x >= depth_size.x - 1.0 || f.y >= depth_size.y - 1.0) {
		return false;
	}
	ivec2 c = ivec2(floor(f));
	vec2 t = f - vec2(c);
	float e = mix(mix(elevation(c), elevation(c + ivec2(1, 0)), t.x),
			mix(elevation(c + ivec2(0, 1)), elevation(c + ivec2(1, 1)), t.x), t.y);
	return e > 0.0;
}


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
uniform float alpha = 0.5;
uniform float width_px = 1.4;

vec3 ramp(float kn) {
	vec3 c = bin_colors[0].rgb;
	for (int i = 1; i < 7; i++) {
		if (kn >= bin_edges[i]) { c = bin_colors[i].rgb; }
	}
	return c;
}

void start() {
	// NUMBER is unique to each emission, so every respawn lands somewhere new.
	float a = rand01(NUMBER * 2u + uint(INDEX) * 7919u);
	float b = rand01(NUMBER * 2u + 1u + 0x9e3779b9u);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xy = rect_pos + vec2(a, b) * rect_size;
	CUSTOM = vec4(0.0);
	COLOR = vec4(0.0);
}

void process() {
	CUSTOM.x += DELTA;
	vec2 p = TRANSFORM[3].xy;
	vec2 ll = latlon(p);
	vec2 w = observed(p, wind_at(ll));
	float kn = length(w) / 0.514444;
	vec2 v = vec2(w.x, -w.y) / 0.514444 * px_per_kn * world_per_px;
	VELOCITY = vec3(v, 0.0);
	vec2 dir = length(v) > 0.0001 ? normalize(v) : vec2(1.0, 0.0);
	float wid = width_px * world_per_px;
	TRANSFORM[0] = vec4(dir * wid, 0.0, 0.0);
	TRANSFORM[1] = vec4(vec2(-dir.y, dir.x) * wid, 0.0, 0.0);
	float age = CUSTOM.x / LIFETIME;
	float fade = smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(0.7, 1.0, age));
	if (on_land(ll)) {
		fade = 0.0;
	}
	if (any(lessThan(p, bounds_pos)) || any(greaterThan(p, bounds_pos + bounds_size))) {
		fade = 0.0;
	}
	COLOR = vec4(mix(ramp(kn), vec3(1.0), 0.65), fade * alpha);
}
