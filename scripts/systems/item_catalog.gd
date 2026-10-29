extends RefCounted
class_name ItemCatalog

const ITEMS: Dictionary = {
	"traveler_blade": preload("res://data/items/traveler_blade.tres"),
	"hunter_crossbow": preload("res://data/items/hunter_crossbow.tres"),
	"ember_relic": preload("res://data/items/ember_relic.tres"),
	"storm_relic": preload("res://data/items/storm_relic.tres"),
}
const PROFILE_VERSION: int = 2
const MAX_CURRENCY: int = 999999999
const MAX_ITEM_COUNT: int = 9999
const MAX_NAME_LENGTH: int = 24


static func get_item(id: String) -> Resource:
	return ITEMS.get(id) as Resource


static func all_items() -> Array:
	return ITEMS.values()


## This is also the boundary for untrusted guest character data.
## Construct a new allowlisted dictionary instead of retaining incoming fields.
static func sanitize_profile(raw: Dictionary) -> Dictionary:
	var inventory: Dictionary = {"traveler_blade": 1, "hunter_crossbow": 1}
	var raw_inventory: Variant = raw.get("inventory", {})
	if raw_inventory is Dictionary:
		for item_id: String in ITEMS:
			var count: int = bounded_count(raw_inventory.get(item_id, 0), MAX_ITEM_COUNT)
			if count > 0:
				inventory[item_id] = count
	var equipped_weapon: String = "traveler_blade"
	var equipped_relic: String = ""
	# Versionless creation dictionaries use the new fields; an old equipped-only
	# dictionary is treated as legacy for callers that predate versioned profiles.
	var inferred_version: int = 1 if raw.has("equipped") and not raw.has("equipped_weapon") and not raw.has("equipped_relic") else PROFILE_VERSION
	var legacy: bool = raw.get("version", inferred_version) == 1
	if legacy:
		var old_equipped: Variant = raw.get("equipped", "")
		if _owned_in_slot(old_equipped, inventory, "weapon"):
			equipped_weapon = old_equipped
		elif _owned_in_slot(old_equipped, inventory, "relic"):
			equipped_relic = old_equipped
	else:
		var raw_weapon: Variant = raw.get("equipped_weapon", "")
		var raw_relic: Variant = raw.get("equipped_relic", "")
		if _owned_in_slot(raw_weapon, inventory, "weapon"):
			equipped_weapon = raw_weapon
		if _owned_in_slot(raw_relic, inventory, "relic"):
			equipped_relic = raw_relic
	var player_name: String = ""
	var raw_name: Variant = raw.get("name", "旅人")
	if raw_name is String:
		for index: int in range(raw_name.length()):
			var code: int = raw_name.unicode_at(index)
			if code >= 32 and code != 127:
				player_name += String.chr(code)
			if player_name.length() >= MAX_NAME_LENGTH:
				break
	player_name = player_name.strip_edges()
	if player_name.is_empty():
		player_name = "旅人"
	return {
		"version": PROFILE_VERSION,
		"name": player_name,
		"coins": bounded_count(raw.get("coins", 0), MAX_CURRENCY),
		"xp": bounded_count(raw.get("xp", 0), MAX_CURRENCY),
		"inventory": inventory,
		"equipped_weapon": equipped_weapon,
		"equipped_relic": equipped_relic,
	}


static func _owned_in_slot(value: Variant, inventory: Dictionary, expected_slot: String) -> bool:
	if not value is String or not inventory.has(value) or int(inventory[value]) <= 0:
		return false
	var item: Resource = get_item(value)
	return item != null and item.slot == expected_slot


static func bounded_count(value: Variant, maximum: int) -> int:
	if not (value is int or value is float):
		return 0
	var number: float = float(value)
	if not is_finite(number):
		return 0
	return int(clampf(number, 0.0, float(maximum)))
