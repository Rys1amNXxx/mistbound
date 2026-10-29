extends RefCounted
class_name SaveStore

const Catalog = preload("res://scripts/systems/item_catalog.gd")
const WORLD_VERSION: int = 1
const CHARACTER_VERSION: int = Catalog.PROFILE_VERSION
const MAX_SAVE_BYTES: int = 4 * 1024 * 1024
const REGIONS: Array[String] = ["camp", "wilds", "mine", "crypt"]


static func load_character() -> Dictionary:
	return Catalog.sanitize_profile(_load("character.json", false))


static func save_character(data: Dictionary) -> Error:
	if _has_future_version(data, CHARACTER_VERSION):
		return ERR_FILE_UNRECOGNIZED
	return _save("character.json", Catalog.sanitize_profile(data), false)


static func load_world() -> Dictionary:
	return _sanitize_world(_load("world.json", true))


static func save_world(data: Dictionary) -> Error:
	if _has_future_version(data, WORLD_VERSION):
		return ERR_FILE_UNRECOGNIZED
	return _save("world.json", _sanitize_world(data), true)


static func default_world() -> Dictionary:
	return {"version": WORLD_VERSION, "boss_kills": 0, "visited": ["camp"]}


static func _sanitize_world(raw: Dictionary) -> Dictionary:
	var result: Dictionary = default_world()
	result["boss_kills"] = Catalog.bounded_count(raw.get("boss_kills", 0), 999999999)
	var raw_visited: Variant = raw.get("visited", [])
	if raw_visited is Array:
		for region: Variant in raw_visited:
			if region is String and region in REGIONS and region not in result["visited"]:
				result["visited"].append(region)
	return result


static func _save_directory() -> String:
	var override: String = OS.get_environment("MISTBOUND_SAVE_DIR").strip_edges()
	if override.is_empty():
		return ProjectSettings.globalize_path("user://saves")
	if not override.is_absolute_path() or override.begins_with("res://") or override.begins_with("user://"):
		push_warning("MISTBOUND_SAVE_DIR must be an absolute filesystem directory.")
		return ""
	return override.simplify_path()


static func _load(filename: String, world: bool) -> Dictionary:
	var directory: String = _save_directory()
	if directory.is_empty():
		return {}
	var path: String = directory.path_join(filename)
	var primary: Dictionary = _read_valid(path, world)
	if not primary.is_empty():
		return primary
	# Reading never overwrites either file. A valid backup remains recoverable.
	return _read_valid(path + ".bak", world)


static func _read_valid(path: String, world: bool) -> Dictionary:
	var data: Dictionary = _read_dictionary(path)
	var version: Variant = data.get("version")
	if world:
		if version != WORLD_VERSION or not data.get("visited") is Array or not _is_number(data.get("boss_kills")):
			return {}
	else:
		if version != 1 and version != CHARACTER_VERSION:
			return {}
		if not data.get("inventory") is Dictionary or not data.get("name") is String:
			return {}
		if not _is_number(data.get("coins")) or not _is_number(data.get("xp")):
			return {}
		if version == 1:
			if not data.get("equipped") is String:
				return {}
		elif not data.get("equipped_weapon") is String or not data.get("equipped_relic") is String:
			return {}
	return data


static func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return {}
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {}
	return parser.data


static func _has_future_version(data: Dictionary, supported: int) -> bool:
	var version: Variant = data.get("version")
	return _is_number(version) and float(version) > float(supported)


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _save(filename: String, data: Dictionary, world: bool) -> Error:
	var directory: String = _save_directory()
	if directory.is_empty():
		return ERR_INVALID_PARAMETER
	var path: String = directory.path_join(filename)
	var supported: int = WORLD_VERSION if world else CHARACTER_VERSION
	# Loading may fall back to an older backup, but autosave must never replace
	# an unknown newer format. Preserve both primary and backup for recovery.
	if _has_future_version(_read_dictionary(path), supported) or _has_future_version(_read_dictionary(path + ".bak"), supported):
		return ERR_FILE_UNRECOGNIZED
	var result: Error = DirAccess.make_dir_recursive_absolute(directory)
	if result != OK:
		return result
	var temporary: String = path + ".tmp"
	result = _write_json(temporary, data)
	if result != OK:
		return result
	if _read_valid(temporary, world).is_empty():
		return ERR_FILE_CORRUPT
	# Replace the backup only from a valid primary. In particular, saving after
	# recovering a corrupt primary must not copy that corruption over the backup.
	var previous: Dictionary = _read_valid(path, world)
	if not previous.is_empty():
		var backup_temporary: String = path + ".bak.tmp"
		# Copy the valid original bytes, including a legacy v1 save, before the
		# migrated v2 primary replaces it.
		result = DirAccess.copy_absolute(path, backup_temporary)
		if result != OK:
			return result
		if _read_valid(backup_temporary, world).is_empty():
			return ERR_FILE_CORRUPT
		result = DirAccess.rename_absolute(backup_temporary, path + ".bak")
		if result != OK:
			return result
	# Same-directory rename keeps the old primary intact until the new file is
	# completely written. The backup covers an interrupted replacement.
	return DirAccess.rename_absolute(temporary, path)


static func _write_json(path: String, data: Dictionary) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var result: Error = file.get_error()
	file.close()
	return result
