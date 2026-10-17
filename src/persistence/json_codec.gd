class_name JsonCodec
extends RefCounted
## Bidirectional converter between GDScript values and JSON-safe values.
##
## Godot 4's `JSON.stringify` does not round-trip Vector2, Color or packed
## arrays: they are converted to strings or dropped. This helper maps those
## types to/from small tagged dictionaries of JSON primitives so that a save
## file stays human-readable and survives a `JSON.parse_string` ->
## `JSON.stringify` round trip.
##
## Encoding rules (all tag keys start with `__type__` so the output stays
## diff-friendly and easy to spot in a text editor):
##
## | Source          | Encoded form                              |
## | --------------- | ----------------------------------------- |
## | `Vector2(x,y)`  | `{"__type__":"v2","x":x,"y":y}`           |
## | `Vector3(x,y,z)`| `{"__type__":"v3","x":x,"y":y,"z":z}`     |
## | `Color(r,g,b,a)`| `{"__type__":"c","r":r,"g":g,"b":b,"a":a}`|
## | `PackedVector2Array` | `{"__type__":"pv2a","v":[[x,y],...]}` |
## | `PackedStringArray` | normal JSON array of strings          |
## | Dictionaries    | recursively encoded by key                |
## | Arrays          | recursively encoded                       |
##
## Scalars (int, float, bool, String, null) are written directly.
##
## The decoder ignores any dictionary that lacks a recognised `__type__` tag,
## so a hand-edited save that adds plain keys does not get corrupted.
##
## Unit tests: `tests/unit/test_save_manager.gd`.


static func encode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_NIL:
			return value
		TYPE_VECTOR2:
			var v: Vector2 = value
			return {"__type__": "v2", "x": v.x, "y": v.y}
		TYPE_VECTOR3:
			var v: Vector3 = value
			return {"__type__": "v3", "x": v.x, "y": v.y, "z": v.z}
		TYPE_COLOR:
			var c: Color = value
			return {"__type__": "c", "r": c.r, "g": c.g, "b": c.b, "a": c.a}
		TYPE_ARRAY:
			var out: Array = []
			for item in (value as Array):
				out.append(encode(item))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var out_d: Dictionary = {}
			for k in d.keys():
				out_d[k] = encode(d[k])
			return out_d
		TYPE_PACKED_VECTOR2_ARRAY:
			var arr: PackedVector2Array = value
			var points: Array = []
			for v in arr:
				points.append([v.x, v.y])
			return {"__type__": "pv2a", "v": points}
		TYPE_PACKED_STRING_ARRAY:
			var sa: PackedStringArray = value
			var outs: Array = []
			for s in sa:
				outs.append(s)
			return outs
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			# Generic numeric packed array fallback: emit as plain arrays.
			var generic: Array = []
			for n in value:
				generic.append(n)
			return generic
		TYPE_PACKED_VECTOR3_ARRAY:
			var v3arr: Array = []
			for v in value:
				v3arr.append(encode(v))
			return {"__type__": "pv3a", "v": v3arr}
		_:
			# Unknown types: fall back to their string representation. This
			# means saves survive the addition of new types in the future:
			# they may lose that value on load (decoder returns the string),
			# but they do not fail to parse entirely.
			push_warning("JsonCodec: tipo non gestito nella codifica: %s" % typeof(value))
			return str(value)


## Decodes a value previously produced by [method encode]. If a tagged
## dictionary is recognised it is converted back to the Godot type, otherwise
## the value is returned as-is (recursively decoded for dicts/arrays).
static func decode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_NIL:
			return value
		TYPE_ARRAY:
			var out: Array = []
			for item in (value as Array):
				out.append(decode(item))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = value
			if d.has("__type__"):
				var tag := String(d["__type__"])
				match tag:
					"v2":
						return Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
					"v3":
						return Vector3(
							float(d.get("x", 0.0)),
							float(d.get("y", 0.0)),
							float(d.get("z", 0.0))
						)
					"c":
						return Color(
							float(d.get("r", 0.0)),
							float(d.get("g", 0.0)),
							float(d.get("b", 0.0)),
							float(d.get("a", 1.0))
						)
					"pv2a":
						var arr: PackedVector2Array = PackedVector2Array()
						for point in d.get("v", []):
							var p = point as Array
							if p.size() >= 2:
								arr.append(Vector2(float(p[0]), float(p[1])))
						return arr
					"pv3a":
						var arr3: PackedVector3Array = PackedVector3Array()
						for point in d.get("v", []):
							var dp = decode(point)
							if typeof(dp) == TYPE_VECTOR3:
								arr3.append(dp)
						return arr3
			# Plain dictionary: recurse.
			var out_d: Dictionary = {}
			for k in d.keys():
				out_d[k] = decode(d[k])
			return out_d
		_:
			return value


## Encodes [param data], serialises it to pretty-printed JSON.
static func to_json(data: Variant) -> String:
	return JSON.stringify(encode(data), "\t")


## Parses [param text] as JSON and decodes the result. Returns a tuple
## `[ok, value, error_string]` so callers can distinguish parse errors from
## successful null values.
static func from_json(text: String) -> Array:
	if text.strip_edges().is_empty():
		return [false, null, "JSON vuoto"]
	# `JSON.parse_string()` cannot tell a parse error from a literal `null`,
	# and the error accessors are instance methods, so use a JSON instance.
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return [false, null, "%s (riga %d)" % [json.get_error_message(), json.get_error_line()]]
	return [true, decode(json.data), ""]
