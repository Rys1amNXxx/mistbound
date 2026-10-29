extends Resource
class_name ItemDefinition

## Immutable design data shared by inventory, combat, and presentation.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var color: Color = Color.WHITE
@export_enum("weapon", "relic") var slot: String = "weapon"
@export_enum("melee", "projectile") var weapon_kind: String = "melee"
@export var base_damage: float = 0.0
@export var attack_interval: float = 0.38
@export var attack_range: float = 85.0
@export var projectile_speed: float = 0.0
@export var effect_id: String = ""
## Retained for old callers; phase-one relics use effects, not flat bonuses.
@export var damage_bonus: float = 0.0
