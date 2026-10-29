extends SceneTree

const Catalog = preload("res://scripts/systems/item_catalog.gd")
const Saves = preload("res://scripts/systems/save_store.gd")

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_override: String = OS.get_environment("MISTBOUND_SAVE_DIR")
	if original_override.is_empty() or not original_override.is_absolute_path() or original_override.contains("://"):
		push_error("Persistence tests require MISTBOUND_SAVE_DIR set to an absolute test directory.")
		quit(2)
		return
	# Never run tests directly against the configured directory or real saves.
	var test_directory: String = original_override.path_join("persistence-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	OS.set_environment("MISTBOUND_SAVE_DIR", test_directory)
	_test_catalog_and_sanitization()
	_test_profile_migration()
	_test_roundtrip_and_recovery(test_directory)
	_test_legacy_files(test_directory)
	_test_future_version_protection(test_directory)
	OS.set_environment("MISTBOUND_SAVE_DIR", original_override)
	print("Persistence tests: %s checks, %s failures. Isolated files: %s" % [checks, failures, test_directory])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _test_catalog_and_sanitization() -> void:
	_check(Catalog.all_items().size() == 4, "Four item definitions load.")
	_check(Catalog.get_item("missing") == null, "Unknown items are rejected.")
	var blade: Resource = Catalog.get_item("traveler_blade")
	var crossbow: Resource = Catalog.get_item("hunter_crossbow")
	_check(blade.slot == "weapon" and blade.weapon_kind == "melee" and blade.base_damage == 22.0 and is_equal_approx(blade.attack_interval, 0.38) and blade.attack_range == 85.0, "Blade carries the melee weapon contract.")
	_check(crossbow.slot == "weapon" and crossbow.weapon_kind == "projectile" and crossbow.base_damage == 18.0 and is_equal_approx(crossbow.attack_interval, 0.60) and crossbow.attack_range == 620.0 and crossbow.projectile_speed == 760.0, "Crossbow carries the projectile weapon contract.")
	_check(Catalog.get_item("ember_relic").slot == "relic" and Catalog.get_item("ember_relic").effect_id == "burn" and Catalog.get_item("ember_relic").damage_bonus == 0.0, "Ember uses the burn effect without a flat damage bonus.")
	_check(Catalog.get_item("storm_relic").slot == "relic" and Catalog.get_item("storm_relic").effect_id == "chain" and Catalog.get_item("storm_relic").damage_bonus == 0.0, "Storm uses the chain effect without a flat damage bonus.")
	var defaults: Dictionary = Catalog.sanitize_profile({})
	_check(defaults.version == 2 and defaults.equipped_weapon == "traveler_blade" and defaults.equipped_relic == "" and not defaults.has("equipped"), "Default profile uses independent version-two equipment slots.")
	_check(defaults.inventory == {"traveler_blade": 1, "hunter_crossbow": 1}, "Both starter weapons are immediately available.")
	var clean: Dictionary = Catalog.sanitize_profile({
		"version": 2,
		"name": "\n  探索者\t  ",
		"coins": -50,
		"xp": 1.0e30,
		"inventory": {"ember_relic": 2.7, "storm_relic": -4, "unknown": 99},
		"equipped_weapon": "ember_relic",
		"equipped_relic": "storm_relic",
		"admin": true,
	})
	_check(clean.size() == 7 and not clean.has("admin") and not clean.has("equipped"), "Only version-two profile schema survives.")
	_check(clean["version"] == 2 and clean["name"] == "探索者", "Version and name sanitized.")
	_check(clean["coins"] == 0 and clean["xp"] == Catalog.MAX_CURRENCY, "Balances clamped.")
	_check(clean["inventory"] == {"traveler_blade": 1, "hunter_crossbow": 1, "ember_relic": 2}, "Only known positive counts and starter weapons survive.")
	_check(clean.equipped_weapon == "traveler_blade" and clean.equipped_relic == "", "Wrong-slot weapon and unowned relic are rejected.")
	var invalid: Dictionary = Catalog.sanitize_profile({"name": [], "coins": "999", "xp": true, "inventory": []})
	_check(invalid == Catalog.sanitize_profile({}), "Wrong field types use defaults.")
	_check(Catalog.sanitize_profile({"coins": NAN, "xp": INF})["coins"] == 0, "NaN rejected.")
	_check(Catalog.sanitize_profile({"coins": NAN, "xp": INF})["xp"] == 0, "Infinity rejected.")
	_check(Catalog.sanitize_profile({"name": "a".repeat(100)})["name"].length() == Catalog.MAX_NAME_LENGTH, "Name length capped.")
	var owned: Dictionary = Catalog.sanitize_profile({"inventory": {"storm_relic": 1}, "equipped_weapon": "hunter_crossbow", "equipped_relic": "storm_relic"})
	_check(owned.equipped_weapon == "hunter_crossbow" and owned.equipped_relic == "storm_relic", "Weapon and owned relic remain equipped independently.")
	var wrong_slots: Dictionary = Catalog.sanitize_profile({"version": 2, "inventory": {"storm_relic": 1}, "equipped_weapon": "storm_relic", "equipped_relic": "hunter_crossbow"})
	_check(wrong_slots.equipped_weapon == "traveler_blade" and wrong_slots.equipped_relic == "", "Owned items cannot occupy the wrong slot.")
	var invalid_slots: Dictionary = Catalog.sanitize_profile({"version": 2, "inventory": {"ember_relic": 0}, "equipped_weapon": [], "equipped_relic": "ember_relic"})
	_check(invalid_slots.equipped_weapon == "traveler_blade" and invalid_slots.equipped_relic == "", "Malformed slot values and zero-count relics are rejected.")
	_check(Catalog.sanitize_profile({"inventory": {"traveler_blade": -5, "hunter_crossbow": 0}}).inventory == defaults.inventory, "Starter weapons retain at least one copy.")
	_check(Catalog.sanitize_profile({"inventory": {"ember_relic": 1.0e30}})["inventory"]["ember_relic"] == Catalog.MAX_ITEM_COUNT, "Inventory count capped.")


func _test_profile_migration() -> void:
	var legacy: Dictionary = {"version": 1, "name": "旧旅人", "coins": 91, "xp": 140, "inventory": {"traveler_blade": 2, "ember_relic": 3, "storm_relic": 1}, "equipped": "ember_relic"}
	var migrated: Dictionary = Catalog.sanitize_profile(legacy)
	_check(migrated.version == 2 and not migrated.has("equipped"), "Legacy profile migrates to version two.")
	_check(migrated.equipped_weapon == "traveler_blade" and migrated.equipped_relic == "ember_relic", "Legacy equipped relic moves to its own slot with a default sword.")
	_check(migrated.name == legacy.name and migrated.coins == legacy.coins and migrated.xp == legacy.xp, "Migration preserves name, coins, and experience.")
	_check(migrated.inventory == {"traveler_blade": 2, "hunter_crossbow": 1, "ember_relic": 3, "storm_relic": 1}, "Migration preserves inventory and adds the crossbow.")
	legacy.equipped = "traveler_blade"
	var weapon: Dictionary = Catalog.sanitize_profile(legacy)
	_check(weapon.equipped_weapon == "traveler_blade" and weapon.equipped_relic == "", "Legacy equipped weapon remains a weapon with no implicit relic.")
	legacy.equipped = "storm_relic"
	_check(Catalog.sanitize_profile(legacy).equipped_relic == "storm_relic", "Both legacy relic IDs migrate.")
	legacy.inventory.erase("storm_relic")
	_check(Catalog.sanitize_profile(legacy).equipped_relic == "", "Migration cannot equip an unowned legacy relic.")
	legacy.equipped = "ember_relic"
	legacy.equipped_weapon = "hunter_crossbow"
	_check(Catalog.sanitize_profile(legacy).equipped_weapon == "traveler_blade", "Explicit v1 migration ignores unrelated new-schema fields.")
	var versionless: Dictionary = Catalog.sanitize_profile({"inventory": {"ember_relic": 1}, "equipped": "ember_relic"})
	_check(versionless.equipped_relic == "ember_relic", "Versionless legacy callers retain their equipped relic.")
	_check(Catalog.sanitize_profile(migrated) == migrated, "Migration and sanitization are idempotent.")


func _test_roundtrip_and_recovery(directory: String) -> void:
	_check(Saves.load_character() == Catalog.sanitize_profile({}), "Missing character defaults.")
	_check(Saves.load_world() == Saves.default_world(), "Missing world defaults.")
	var first: Dictionary = Catalog.sanitize_profile({"name": "岚", "coins": 41, "xp": 123, "inventory": {"ember_relic": 2}, "equipped_weapon": "hunter_crossbow", "equipped_relic": "ember_relic"})
	_check(Saves.save_character(first) == OK, "First character save succeeds.")
	_check(Saves.load_character() == first, "Character roundtrip preserves Unicode and both equipped slots.")
	_check(Saves.save_world({"version": 1, "boss_kills": 3, "visited": ["mine", "mine", "crypt", "unknown"], "coins": 999}) == OK, "World save succeeds.")
	var world: Dictionary = {"version": 1, "boss_kills": 3, "visited": ["camp", "mine", "crypt"]}
	_check(Saves.load_world() == world, "World roundtrip sanitizes regions and extra fields.")
	_check(Saves.load_character() == first, "Saving world leaves character unchanged.")
	var second: Dictionary = first.duplicate(true)
	second["coins"] = 82
	_check(Saves.save_character(second) == OK, "Second character save succeeds.")
	_check(Saves.load_character() == second, "Newest primary is loaded.")
	_check(FileAccess.file_exists(directory.path_join("character.json.bak")), "Previous valid character backed up.")
	var backup_before: String = FileAccess.get_file_as_string(directory.path_join("character.json.bak"))
	_write_text(directory.path_join("character.json"), "{ broken json")
	_check(Saves.load_character() == first, "Corrupt primary recovers previous valid backup.")
	_check(FileAccess.get_file_as_string(directory.path_join("character.json.bak")) == backup_before, "Recovery read preserves backup bytes.")
	_check(Saves.save_character(second) == OK, "Saving after recovery succeeds.")
	_check(FileAccess.get_file_as_string(directory.path_join("character.json.bak")) == backup_before, "Saving over corrupt primary preserves valid backup.")
	_write_text(directory.path_join("character.json"), "{\"version\":2}")
	_check(Saves.load_character() == first, "Malformed supported schema uses valid backup.")
	_check(Saves.load_world() == world, "Character corruption does not affect world.")
	_check(Saves.save_world({"boss_kills": 7, "visited": ["wilds"]}) == OK, "Second world save succeeds.")
	_write_text(directory.path_join("world.json"), "[]")
	_check(Saves.load_world() == world, "World independently recovers its backup.")
	_write_text(directory.path_join("character.json.bak"), "null")
	_check(Saves.load_character() == Catalog.sanitize_profile({}), "Both corrupt character files return defaults.")
	_check(Saves.load_world() == world, "Character fallback does not reset world.")
	_check(Saves.save_character({"coins": -1, "xp": "bad", "inventory": {"unknown": 200}, "equipped_weapon": "unknown", "equipped_relic": []}) == OK, "Malformed profile can be safely saved.")
	_check(Saves.load_character() == Catalog.sanitize_profile({}), "Save always sanitizes profile.")


func _test_legacy_files(directory: String) -> void:
	for equipped: String in ["traveler_blade", "ember_relic", "storm_relic"]:
		var location: String = directory.path_join("migration-" + equipped)
		_select_directory(location)
		var legacy: Dictionary = {"version": 1, "name": "存档迁移", "coins": 111, "xp": 280, "inventory": {"traveler_blade": 1, "ember_relic": 2, "storm_relic": 3}, "equipped": equipped}
		var original_text: String = JSON.stringify(legacy, "  ") + "\n"
		var primary: String = location.path_join("character.json")
		var backup: String = primary + ".bak"
		_write_text(primary, original_text)
		var expected: Dictionary = Catalog.sanitize_profile(legacy)
		_check(Saves.load_character() == expected, "Legacy primary migrates in memory: " + equipped)
		_check(FileAccess.get_file_as_string(primary) == original_text and not FileAccess.file_exists(backup), "Reading legacy primary does not modify files: " + equipped)
		_check(Saves.save_character(Saves.load_character()) == OK, "Migrated profile saves successfully: " + equipped)
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(primary))
		_check(saved.version == 2 and not saved.has("equipped"), "Primary is written in version-two format: " + equipped)
		_check(FileAccess.get_file_as_string(backup) == original_text, "Migration preserves exact legacy primary bytes in backup: " + equipped)
		_write_text(primary, "{ damaged migrated primary")
		_check(Saves.load_character() == expected, "Legacy backup also migrates during recovery: " + equipped)
		_check(Saves.save_character(expected) == OK, "Recovered legacy backup can be saved: " + equipped)
		_check(FileAccess.get_file_as_string(backup) == original_text, "Recovery save preserves the valid legacy backup: " + equipped)
		_check(Saves.save_world({"version": 1, "boss_kills": 4, "visited": ["camp", "mine"]}) == OK and Saves.load_world().version == 1, "World format remains version one after character migration.")


func _test_future_version_protection(directory: String) -> void:
	var location: String = directory.path_join("future-primary")
	_select_directory(location)
	var future: Dictionary = {"version": 3, "future_payload": {"keep": "untouched"}}
	var future_text: String = JSON.stringify(future, "  ")
	var legacy: Dictionary = {"version": 1, "name": "备份旅人", "coins": 99, "xp": 12, "inventory": {"traveler_blade": 1, "ember_relic": 1}, "equipped": "ember_relic"}
	var legacy_text: String = JSON.stringify(legacy, "  ")
	var primary: String = location.path_join("character.json")
	var backup: String = primary + ".bak"
	_write_text(primary, future_text)
	_write_text(backup, legacy_text)
	_check(Saves.load_character() == Catalog.sanitize_profile(legacy), "Future primary can fall back to a supported legacy backup.")
	_check(Saves.save_character(Saves.load_character()) == ERR_FILE_UNRECOGNIZED, "Autosave refuses to overwrite an unknown future primary.")
	_check(FileAccess.get_file_as_string(primary) == future_text and FileAccess.get_file_as_string(backup) == legacy_text, "Refused future-primary save preserves both files exactly.")
	_check(not FileAccess.file_exists(primary + ".tmp"), "Future-version refusal occurs before writing a temporary save.")
	location = directory.path_join("future-backup")
	_select_directory(location)
	primary = location.path_join("character.json")
	backup = primary + ".bak"
	var current: Dictionary = Catalog.sanitize_profile(legacy)
	var current_text: String = JSON.stringify(current)
	_write_text(primary, current_text)
	_write_text(backup, future_text)
	_check(Saves.load_character() == current, "Supported primary still loads beside a future backup.")
	_check(Saves.save_character(current) == ERR_FILE_UNRECOGNIZED, "Saving also protects a future-version backup.")
	_check(FileAccess.get_file_as_string(primary) == current_text and FileAccess.get_file_as_string(backup) == future_text, "Refused future-backup save preserves both files exactly.")
	location = directory.path_join("future-input")
	_select_directory(location)
	_check(Saves.save_character(future) == ERR_FILE_UNRECOGNIZED and not FileAccess.file_exists(location.path_join("character.json")), "Future input profile is not silently downgraded and saved.")
	var world_primary: String = location.path_join("world.json")
	var future_world: String = JSON.stringify({"version": 2, "future_world": true})
	_write_text(world_primary, future_world)
	_write_text(world_primary + ".bak", JSON.stringify(Saves.default_world()))
	_check(Saves.load_world() == Saves.default_world(), "Future world can use a supported backup.")
	_check(Saves.save_world(Saves.default_world()) == ERR_FILE_UNRECOGNIZED and FileAccess.get_file_as_string(world_primary) == future_world, "Unknown future world format is also protected.")
	_check(Saves.save_world({"version": 2}) == ERR_FILE_UNRECOGNIZED, "Future input world is not silently downgraded.")


func _select_directory(path: String) -> void:
	OS.set_environment("MISTBOUND_SAVE_DIR", path)
	_check(DirAccess.make_dir_recursive_absolute(path) == OK, "Isolated fixture directory can be created.")


func _write_text(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Test fixture can be written.")
	if file != null:
		file.store_string(content)
		file.close()
