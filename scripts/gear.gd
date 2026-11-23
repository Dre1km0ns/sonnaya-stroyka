extends RefCounted
## v0.24: единая таблица снаряжения — тиры кирок, мечи (урон/дальность), луки, стрелы, прочность, броня.
## Рост дерево → камень → металл → чешуя (меч) ощущается по урону, дальности, скорости и прочности.

## Тир кирки: 0 — рука/не кирка, 1 — деревянная, 2 — каменная, 3 — металлическая.
const PICK_TIER := {"pickaxe": 1, "pickaxe2": 2, "pickaxe3": 3}
## Время добычи камня (с) по тиру кирки. Рука — x5 и без дропа (mining_rules).
const PICK_STONE_TIME := {1: 3.0, 2: 1.5, 3: 0.9}
## Урон кирки по мобу.
const PICK_DAMAGE := {"pickaxe": 2, "pickaxe2": 6, "pickaxe3": 9}

## Мечи (pt128u): дальность деревянного 3.5 м, дальше по нарастающей до 4.5 м у лучшего.
const SWORDS := {
	"sword": {"dmg": 8, "reach": 3.5},
	"sword2": {"dmg": 14, "reach": 3.8},
	"metal_sword": {"dmg": 19, "reach": 4.15},
	"sword3": {"dmg": 24, "reach": 4.5},
}
## Луки: натяжение (с до полной силы), множитель урона и скорость стрелы (м/с).
const BOWS := {
	# v0.25 (t143u): без натяжения — клик стреляет, между выстрелами перезарядка cd (как в Террарии);
	# range — дальность: первые 75 % стрела летит ровно по прицелу со 100 % урона, дальше падает, урон до 80 %.
	"bow": {"draw": 0.9, "cd": 0.75, "mult": 1.0, "speed": 30.0, "range": 36.0},
	"bow2": {"draw": 0.7, "cd": 0.55, "mult": 1.5, "speed": 40.0, "range": 50.0},
}
## Стрелы: урон при полном натяжении деревянным луком. Порядок — сначала лучшие.
const ARROWS := ["arrow2", "arrow"]
const ARROW_DAMAGE := {"arrow": 9, "arrow2": 16}

## Прочность. Дерево короткое, камень заметно дольше, металл — ещё в 2 раза, чешуя — лучшая.
const DURABILITY := {
	"pickaxe": 130, "sword": 130, "bow": 150,
	"pickaxe2": 420, "sword2": 420,
	"pickaxe3": 900, "metal_sword": 900, "bow2": 700,
	"sword3": 1200,
	"grill_saucer": 400,
}

static func pick_tier(id: String) -> int:
	return int(PICK_TIER.get(id, 0))

static func is_pickaxe(id: String) -> bool:
	return PICK_TIER.has(id)

static func is_sword(id: String) -> bool:
	return SWORDS.has(id)

static func is_bow(id: String) -> bool:
	return BOWS.has(id)

static func is_arrow(id: String) -> bool:
	return ARROW_DAMAGE.has(id)

static func sword_damage(id: String) -> int:
	return int(SWORDS.get(id, {}).get("dmg", 0))

static func sword_reach(id: String) -> float:
	return float(SWORDS.get(id, {}).get("reach", 0.0))

static func pick_damage(id: String) -> int:
	return int(PICK_DAMAGE.get(id, 1))

static func durability(id: String) -> int:
	return int(DURABILITY.get(id, 0))

static func wears(id: String) -> bool:
	return DURABILITY.has(id)
