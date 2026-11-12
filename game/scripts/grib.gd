class_name Grib
## GRIB reader for imported weather files: GRIB edition 1 and 2, regular latitude/longitude grids.
## Reads 10 m wind (NCEP codes, or ECMWF table 128 codes 165/166 in GRIB1) and ocean surface current (east and north components). Packing supported:
## GRIB1 simple; GRIB2 simple (template 5.0) and complex with or without spatial differencing
## (5.2, 5.3). JPEG 2000 (5.40) and PNG (5.41) packing are reported as unsupported.
##
## decode() returns {"fields": [...], "skipped": int, "errors": PackedStringArray}. Each field is
## {"kind": "wind" or "current", "comp": "u" or "v", "valid_unix": float, "grid": {...}, "values":
## PackedFloat32Array} where missing points are NAN.


static func decode(bytes: PackedByteArray) -> Dictionary:
	var out := {"fields": [], "skipped": 0, "errors": PackedStringArray()}
	var pos := 0
	var n := bytes.size()
	while pos + 8 <= n:
		# Find the next "GRIB" marker.
		if not (bytes[pos] == 71 and bytes[pos + 1] == 82 and bytes[pos + 2] == 73 and bytes[pos + 3] == 66):
			pos += 1
			continue
		var edition := bytes[pos + 7]
		var length := 0
		if edition == 1:
			length = _u(bytes, pos + 4, 3)
		elif edition == 2:
			length = _u(bytes, pos + 8, 8)
		else:
			out["errors"].append("GRIB edition %d is not supported" % edition)
			pos += 4
			continue
		if length <= 0 or pos + length > n:
			out["errors"].append("A GRIB message is cut short; the file may be incomplete")
			break
		var msg := bytes.slice(pos, pos + length)
		var r: Variant = _message1(msg) if edition == 1 else _message2(msg)
		if r is String:
			if r != "":
				if not out["errors"].has(r):
					out["errors"].append(r)
			out["skipped"] += 1
		else:
			out["fields"].append(r)
		pos += length
	return out


# ---------------------------------------------------------------- GRIB edition 1

static func _message1(m: PackedByteArray) -> Variant:
	var p := 8  # product definition section
	var pds_len := _u(m, p, 3)
	var flags := m[p + 7]
	var param := m[p + 8]
	var level_type := m[p + 9]
	var level := _u(m, p + 10, 2)
	var table := m[p + 3]
	var kind := ""
	var comp := ""
	if table >= 128 and (param == 165 or param == 166):
		kind = "wind"  # ECMWF local table: 10 m wind, coded at the surface
		comp = "u" if param == 165 else "v"
	elif param == 33 or param == 34:
		if not (level_type == 105 and level == 10):
			return ""  # wind at another level
		kind = "wind"
		comp = "u" if param == 33 else "v"
	elif param == 49 or param == 50:
		kind = "current"
		comp = "u" if param == 49 else "v"
	else:
		return ""
	var century := m[p + 24]
	var year := (century - 1) * 100 + m[p + 12]
	var ref := _unix(year, m[p + 13], m[p + 14], m[p + 15], m[p + 16], 0)
	var unit_s := _time_unit_s(m[p + 17])
	var p1 := m[p + 18]
	if m[p + 20] == 10:
		p1 = _u(m, p + 18, 2)
	var dec := _sm(m, p + 26, 2)
	p += pds_len
	if (flags & 0x80) == 0:
		return "A GRIB1 message has no grid description; only regular latitude/longitude grids are supported"
	var gds_len := _u(m, p, 3)
	if m[p + 5] != 0:
		return "Only regular latitude/longitude grids are supported (GRIB1 grid type %d)" % m[p + 5]
	var grid := {
		"ni": _u(m, p + 6, 2), "nj": _u(m, p + 8, 2),
		"la1": _sm(m, p + 10, 3) / 1000.0, "lo1": _sm(m, p + 13, 3) / 1000.0,
		"la2": _sm(m, p + 17, 3) / 1000.0, "lo2": _sm(m, p + 20, 3) / 1000.0,
		"scan": m[p + 27],
	}
	p += gds_len
	var bitmap := PackedByteArray()
	if (flags & 0x40) != 0:
		var bms_len := _u(m, p, 3)
		if _u(m, p + 4, 2) != 0:
			return "A GRIB1 message uses a predefined bitmap, which is not supported"
		bitmap = m.slice(p + 6, p + bms_len)
		p += bms_len
	var bds_flag := m[p + 3]
	if (bds_flag & 0xD0) != 0:  # 0x80 spherical harmonics, 0x40 complex packing, 0x10 extra flags
		return "A GRIB1 message uses complex or spherical-harmonic packing, which is not supported"
	var e := _sm(m, p + 4, 2)
	var rv := _ibm(m, p + 6)
	var bits := m[p + 10]
	var count: int = grid["ni"] * grid["nj"]
	var present: int = count if bitmap.is_empty() else _bits_set(bitmap, count)
	var packed := _unpack_simple(m, (p + 11) * 8, bits, present)
	var values := _scale(packed, rv, e, dec)
	return {"kind": kind, "comp": comp, "valid_unix": ref + p1 * unit_s, "grid": grid,
			"values": _spread(values, bitmap, count)}


# ---------------------------------------------------------------- GRIB edition 2

static func _message2(m: PackedByteArray) -> Variant:
	var discipline := m[6]
	var p := 16
	var ref := 0.0
	var grid := {}
	var kind := ""
	var comp := ""
	var valid := 0.0
	var tmpl5 := -1
	var s5 := -1
	var s7 := -1
	var bitmap := PackedByteArray()
	var count := 0
	while p + 5 <= m.size():
		if m[p] == 55 and m[p + 1] == 55 and m[p + 2] == 55 and m[p + 3] == 55:
			break
		var slen := _u(m, p, 4)
		var num := m[p + 4]
		match num:
			1:
				ref = _unix(_u(m, p + 12, 2), m[p + 14], m[p + 15], m[p + 16], m[p + 17], m[p + 18])
			3:
				if _u(m, p + 12, 2) != 0:
					return "Only regular latitude/longitude grids are supported (GRIB2 grid template 3.%d)" % _u(m, p + 12, 2)
				var basic := _u(m, p + 38, 4)
				var sub := _u(m, p + 42, 4)
				var div := 1e6 if basic == 0 or sub == 0xFFFFFFFF or sub == 0 else float(sub) / maxf(basic, 1)
				grid = {
					"ni": _u(m, p + 30, 4), "nj": _u(m, p + 34, 4),
					"la1": _sm(m, p + 46, 4) / div, "lo1": _sm(m, p + 50, 4) / div,
					"la2": _sm(m, p + 55, 4) / div, "lo2": _sm(m, p + 59, 4) / div,
					"scan": m[p + 71],
				}
				count = grid["ni"] * grid["nj"]
			4:
				var t4 := _u(m, p + 7, 2)
				if t4 not in [0, 1, 8, 11]:
					return ""
				var cat := m[p + 9]
				var pnum := m[p + 10]
				var surface := m[p + 22]
				var sval := _u(m, p + 24, 4) * pow(10.0, -_sm(m, p + 23, 1))
				if discipline == 0 and cat == 2 and (pnum == 2 or pnum == 3):
					if not (surface == 103 and absf(sval - 10.0) < 0.01):
						return ""  # wind at another level
					kind = "wind"
					comp = "u" if pnum == 2 else "v"
				elif discipline == 10 and cat == 1 and (pnum == 2 or pnum == 3):
					kind = "current"
					comp = "u" if pnum == 2 else "v"
				else:
					return ""
				valid = ref + _sm(m, p + 18, 4) * _time_unit_s(m[p + 17])
			5:
				s5 = p
				tmpl5 = _u(m, p + 9, 2)
			6:
				if m[p + 5] == 0:
					bitmap = m.slice(p + 6, p + slen)
				elif m[p + 5] != 255:
					return "A GRIB2 message uses a predefined bitmap, which is not supported"
			7:
				s7 = p
		p += slen
	if kind == "":
		return ""
	if grid.is_empty() or s5 < 0 or s7 < 0:
		return "A GRIB2 message is missing its grid or data section"
	var present := _u(m, s5 + 5, 4)
	var rv := _ieee_be(m, s5 + 11)
	var e := _sm(m, s5 + 15, 2)
	var dec := _sm(m, s5 + 17, 2)
	var bits := m[s5 + 19]
	var packed: PackedFloat64Array
	match tmpl5:
		0:
			packed = _unpack_simple(m, (s7 + 5) * 8, bits, present)
		2, 3:
			packed = _unpack_complex(m, s5, s7, tmpl5, present)
		40:
			return "This file uses JPEG 2000 packing (GRIB2 template 5.40), which is not supported. Ask for simple or complex packing, or convert it with wgrib2 or cdo"
		41:
			return "This file uses PNG packing (GRIB2 template 5.41), which is not supported. Ask for simple or complex packing, or convert it with wgrib2 or cdo"
		_:
			return "GRIB2 data template 5.%d is not supported" % tmpl5
	var values := _scale(packed, rv, e, dec)
	return {"kind": kind, "comp": comp, "valid_unix": valid, "grid": grid, "values": _spread(values, bitmap, count)}


## Complex packing (5.2) and complex packing with spatial differencing (5.3).
static func _unpack_complex(m: PackedByteArray, s5: int, s7: int, tmpl: int, present: int) -> PackedFloat64Array:
	var bits := m[s5 + 19]
	var missing_mgmt := m[s5 + 22]
	var ng := _u(m, s5 + 31, 4)
	var width_ref := m[s5 + 35]
	var width_bits := m[s5 + 36]
	var len_ref := _u(m, s5 + 37, 4)
	var len_inc := m[s5 + 41]
	var last_len := _u(m, s5 + 42, 4)
	var len_bits := m[s5 + 46]
	var order := 0
	var extra := 0
	if tmpl == 3:
		order = m[s5 + 47]
		extra = m[s5 + 48]
	var bit := (s7 + 5) * 8
	var first := []
	var overall_min := 0
	if tmpl == 3 and order > 0:
		for k in order:
			first.append(_sm(m, bit / 8, extra))
			bit += extra * 8
		overall_min = _sm(m, bit / 8, extra)
		bit += extra * 8
	var refs := PackedInt64Array()
	refs.resize(ng)
	for g in ng:
		refs[g] = _bits(m, bit, bits)
		bit += bits
	bit = (bit + 7) / 8 * 8
	var widths := PackedInt32Array()
	widths.resize(ng)
	for g in ng:
		widths[g] = width_ref + _bits(m, bit, width_bits)
		bit += width_bits
	bit = (bit + 7) / 8 * 8
	var lens := PackedInt32Array()
	lens.resize(ng)
	for g in ng:
		lens[g] = len_ref + _bits(m, bit, len_bits) * len_inc
		bit += len_bits
	if ng > 0:
		lens[ng - 1] = last_len
	bit = (bit + 7) / 8 * 8
	var out := PackedFloat64Array()
	out.resize(present)
	var miss := PackedByteArray()
	miss.resize(present)
	var k := 0
	for g in ng:
		var w := widths[g]
		var all_ones_ref := (1 << bits) - 1
		for j in lens[g]:
			if k >= present:
				break
			if w == 0:
				out[k] = refs[g]
				if missing_mgmt >= 1 and refs[g] == all_ones_ref and bits > 0:
					miss[k] = 1
			else:
				var x := _bits(m, bit, w)
				bit += w
				var ones := (1 << w) - 1
				if (missing_mgmt == 1 and x == ones) or (missing_mgmt == 2 and (x == ones or x == ones - 1)):
					miss[k] = 1
				else:
					out[k] = refs[g] + x
			k += 1
	if tmpl == 3 and order > 0:
		# Undo spatial differencing over the non-missing values, in order.
		var idx := PackedInt32Array()
		for i in present:
			if miss[i] == 0:
				idx.append(i)
		for j in idx.size():
			var i := idx[j]
			if j < order:
				out[i] = first[j]
			elif order == 1:
				out[i] = out[i] + overall_min + out[idx[j - 1]]
			else:
				out[i] = out[i] + overall_min + 2.0 * out[idx[j - 1]] - out[idx[j - 2]]
	for i in present:
		if miss[i] == 1:
			out[i] = NAN
	return out


# ---------------------------------------------------------------- shared helpers

static func _unpack_simple(m: PackedByteArray, bit: int, bits: int, count: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(count)
	if bits == 0:
		return out  # every value equals the reference value
	for i in count:
		out[i] = _bits(m, bit, bits)
		bit += bits
	return out


## Y = (R + X * 2^E) / 10^D for every packed value X; NAN stays NAN.
static func _scale(x: PackedFloat64Array, rv: float, e: int, dec: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(x.size())
	var s := pow(2.0, e)
	var d := pow(10.0, -dec)
	for i in x.size():
		out[i] = (rv + x[i] * s) * d
	return out


## Values for grid points the bitmap marks present, NAN elsewhere.
static func _spread(values: PackedFloat32Array, bitmap: PackedByteArray, count: int) -> PackedFloat32Array:
	if bitmap.is_empty():
		return values
	var out := PackedFloat32Array()
	out.resize(count)
	var k := 0
	for i in count:
		if (bitmap[i >> 3] >> (7 - (i & 7))) & 1 == 1 and k < values.size():
			out[i] = values[k]
			k += 1
		else:
			out[i] = NAN
	return out


static func _bits_set(bitmap: PackedByteArray, count: int) -> int:
	var n := 0
	for i in count:
		n += (bitmap[i >> 3] >> (7 - (i & 7))) & 1
	return n


## Unsigned integer of n bits starting at a bit offset, most significant bit first.
static func _bits(m: PackedByteArray, bit: int, n: int) -> int:
	if n == 0:
		return 0
	var v := 0
	var byte := bit >> 3
	var off := bit & 7
	var left := n
	# First partial byte.
	var take := mini(8 - off, left)
	v = (m[byte] >> (8 - off - take)) & ((1 << take) - 1)
	left -= take
	byte += 1
	while left >= 8:
		v = (v << 8) | m[byte]
		byte += 1
		left -= 8
	if left > 0:
		v = (v << left) | (m[byte] >> (8 - left))
	return v


static func _u(m: PackedByteArray, at: int, n: int) -> int:
	var v := 0
	for i in n:
		v = (v << 8) | m[at + i]
	return v


## Sign-and-magnitude integer: the top bit is the sign.
static func _sm(m: PackedByteArray, at: int, n: int) -> int:
	var v := _u(m, at, n)
	var top := 1 << (n * 8 - 1)
	return -(v & (top - 1)) if v & top else v


static func _ieee_be(m: PackedByteArray, at: int) -> float:
	var b := PackedByteArray([m[at + 3], m[at + 2], m[at + 1], m[at]])
	return b.decode_float(0)


## IBM single-precision float used by GRIB1 reference values.
static func _ibm(m: PackedByteArray, at: int) -> float:
	var sign := -1.0 if m[at] & 0x80 else 1.0
	var ex := (m[at] & 0x7F) - 64
	var mant := float(_u(m, at + 1, 3)) / 16777216.0
	return sign * mant * pow(16.0, ex)


static func _time_unit_s(code: int) -> float:
	match code:
		0: return 60.0
		1: return 3600.0
		2: return 86400.0
		10: return 3 * 3600.0
		11: return 6 * 3600.0
		12: return 12 * 3600.0
		13: return 1.0
	return 3600.0


static func _unix(y: int, mo: int, d: int, h: int, mi: int, s: int) -> float:
	return Time.get_unix_time_from_datetime_dict({"year": y, "month": mo, "day": d, "hour": h, "minute": mi, "second": s})
