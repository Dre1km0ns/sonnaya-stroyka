extends RefCounted
const PARTS := ["helmet","chest","legs","boots"]
const NAMES := ["Шлем","Нагрудник","Поножи","Ботинки"]
const COST := [7,15,11,5]
## v0.11: чешуя редкая (14–22 за Анаконду) — набор стоит 24 чешуи, а не 38.
const SCALE_COST := [5,8,7,4]
const WOOD_POINTS := [1,3,2,1] # leather
const SCALE_POINTS := [2,6,5,2] # iron
const WOOD_DURABILITY := [165,240,225,195] # chainmail
## v0.11: трофейная броня прочнее деревянной (было 77..112 — «золото», хуже дерева).
const SCALE_DURABILITY := [330,480,450,390]
## v0.24: металлическая броня — между деревом и чешуёй (рост дерево → металл → чешуя).
const METAL_COST := [4,7,6,3]
const METAL_POINTS := [2,5,4,2]
const METAL_DURABILITY := [250,360,340,290]
const TIERS := ["wood","metal","scale"]
static func slot(id: String) -> int:
	for i in range(4):
		if id in ["wood_"+PARTS[i],"metal_"+PARTS[i],"scale_"+PARTS[i]]: return i
	return -1
static func durability(id: String) -> int:
	var i := slot(id)
	return 0 if i<0 else (WOOD_DURABILITY[i] if id.begins_with("wood_") else (METAL_DURABILITY[i] if id.begins_with("metal_") else SCALE_DURABILITY[i]))
static func points(id: String) -> int:
	var i := slot(id)
	return 0 if i<0 else (WOOD_POINTS[i] if id.begins_with("wood_") else (METAL_POINTS[i] if id.begins_with("metal_") else SCALE_POINTS[i]))
static func reduce(damage: int,points_total: int) -> int:
	# Java armour, toughness=0; 100 HP здесь = 20 HP MC. HP округляем вверх, чтобы малый удар не исчезал.
	var effective := clampf(maxf(points_total/5.0,points_total-damage/10.0),0.0,20.0)
	return maxi(1,ceili(damage*(1.0-effective/25.0)))
