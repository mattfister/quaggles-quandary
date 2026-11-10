class_name Levels
## Every level in the game, read from levels/levels.json. The level editor
## (scripts/editor) writes that file; it is plain JSON, fine to hand-edit too.
##
## The file holds a list of sets in play order, each {id, title, label,
## levels}. Each level is {id, title, hint, floors} plus an optional "stack"
## and "review".
## "floors" lists each floor bottom-up as rows of cells (see Rules for the
## cell characters). "hint", if any, is shown while playing the level.
## "stack" is the tallest stack of quaggles the level cannot be won without.
## "review" is the editor's note on how finished the level is: "ok" (happy
## with it) or "wip" (in progress); absent means not reviewed yet.

const PATH := "res://levels/levels.json"
const REVIEWS := ["ok", "wip"]

static var _sets: Array = []
static var _loaded := false


## The sets in play order: [{id, title, label, levels: [level, ...]}].
static func sets() -> Array:
	if not _loaded:
		_loaded = true
		_sets = parse(FileAccess.get_file_as_string(PATH))
		if _sets.is_empty():
			push_error("No levels could be read from " + PATH)
	return _sets


static func get_set(set_id: String) -> Dictionary:
	for s: Dictionary in sets():
		if s.id == set_id:
			return s
	return {}


static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in sets():
		for level: Dictionary in s.levels:
			out.append(level)
	return out


static func find(id: String) -> Dictionary:
	for level: Dictionary in all():
		if level.id == id:
			return level
	return {}


## The set holding level `id`, or "".
static func set_of(id: String) -> String:
	for s: Dictionary in sets():
		for level: Dictionary in s.levels:
			if level.id == id:
				return s.id
	return ""


## Swaps in a new list of sets (the editor's, after a save).
static func replace(new_sets: Array) -> void:
	_loaded = true
	_sets = parse(to_json(new_sets))


## Writes `new_sets` to the level file and starts using them.
static func save(new_sets: Array) -> Error:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json(new_sets))
	file.close()
	replace(new_sets)
	return OK


## Reads level-file text into a list of sets, or [] if it is not one.
static func parse(text: String) -> Array:
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary and data.get("sets") is Array):
		return []
	var out: Array = []
	for s: Variant in data.sets:
		if not (s is Dictionary and s.get("levels") is Array):
			continue
		var levels: Array[Dictionary] = []
		for level: Variant in s.levels:
			if level is Dictionary:
				levels.append(normalize(level))
		out.append({
			"id": str(s.get("id", "set")), "title": str(s.get("title", "Levels")),
			"label": str(s.get("label", s.get("title", "Levels"))), "levels": levels,
		})
	return out


## A level with every field present and of the right type.
static func normalize(level: Dictionary) -> Dictionary:
	var floors: Array = []
	for rows: Variant in level.get("floors", []):
		var clean: Array = []
		if rows is Array:
			for row: Variant in rows:
				clean.append(str(row))
		floors.append(clean)
	if floors.is_empty():
		floors.append([""])
	var out := {
		"id": str(level.get("id", "level")), "title": str(level.get("title", "Untitled")),
		"hint": str(level.get("hint", "")), "floors": floors,
	}
	var stack := int(level.get("stack", 1))
	if stack > 1:
		out.stack = stack
	var review := str(level.get("review", ""))
	if review in REVIEWS:
		out.review = review
	return out


## The level file text for `the_sets`, one map row per line so that diffs
## stay readable. tools/build_levels.py wrote the same layout.
static func to_json(the_sets: Array) -> String:
	var parts := PackedStringArray()
	for s: Dictionary in the_sets:
		var levels := PackedStringArray()
		for level: Dictionary in s.levels:
			levels.append(level_json(level, "\t\t\t\t"))
		parts.append("\t\t{\n\t\t\t\"id\": %s, \"title\": %s, \"label\": %s,\n\t\t\t\"levels\": [\n%s\n\t\t\t]\n\t\t}" % [
			JSON.stringify(s.id), JSON.stringify(s.title), JSON.stringify(s.get("label", s.title)),
			",\n".join(levels)])
	return "{\n\t\"sets\": [\n%s\n\t]\n}\n" % ",\n".join(parts)


static func level_json(level: Dictionary, t := "") -> String:
	var out := PackedStringArray([
		t + "{",
		"%s\t\"id\": %s, \"title\": %s," % [t, JSON.stringify(level.id), JSON.stringify(level.title)],
		"%s\t\"hint\": %s," % [t, JSON.stringify(level.get("hint", ""))],
	])
	if int(level.get("stack", 1)) > 1:
		out.append("%s\t\"stack\": %d," % [t, int(level.stack)])
	if level.get("review", "") in REVIEWS:
		out.append("%s\t\"review\": %s," % [t, JSON.stringify(level.review)])
	out.append(t + "\t\"floors\": [")
	var floors := PackedStringArray()
	for rows: Array in level.floors:
		if rows.is_empty():
			floors.append(t + "\t\t[]")
			continue
		var lines := PackedStringArray()
		for row: String in rows:
			lines.append(t + "\t\t\t" + JSON.stringify(row))
		floors.append("%s\t\t[\n%s\n%s\t\t]" % [t, ",\n".join(lines), t])
	out.append(",\n".join(floors))
	out.append(t + "\t]")
	out.append(t + "}")
	return "\n".join(out)
