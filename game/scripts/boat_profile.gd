class_name BoatProfile
extends RefCounted
## Everything that defines a player boat.

const STARTER_DIR := "res://data/boats"
const USER_FILE := "user://boat_profiles.json"

var name: String
var polar: Polar
var draft_m: float
var tack_penalty_s: float
var gybe_penalty_s: float
var motoring_kn: float


static func from_dict(d: Dictionary) -> BoatProfile:
	var b := BoatProfile.new()
	b.name = d["name"]
	b.polar = Polar.parse(d["polar"])
	b.draft_m = d["draft_m"]
	b.tack_penalty_s = d["tack_penalty_s"]
	b.gybe_penalty_s = d["gybe_penalty_s"]
	b.motoring_kn = d["motoring_kn"]
	return b


func to_dict() -> Dictionary:
	return {"name": name, "polar": polar.to_text(), "draft_m": draft_m, "tack_penalty_s": tack_penalty_s,
			"gybe_penalty_s": gybe_penalty_s, "motoring_kn": motoring_kn}


static func starters() -> Array[BoatProfile]:
	var out: Array[BoatProfile] = []
	for f in JSON.parse_string(FileAccess.get_file_as_string(STARTER_DIR + "/index.json")):
		out.append(from_dict(JSON.parse_string(FileAccess.get_file_as_string(STARTER_DIR + "/" + f))))
	return out


## Starter profiles followed by the player's saved profiles.
static func all() -> Array[BoatProfile]:
	var out := starters()
	if FileAccess.file_exists(USER_FILE):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(USER_FILE))
		if saved is Array:
			for d in saved:
				out.append(from_dict(d))
	return out
