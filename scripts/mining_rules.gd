extends RefCounted
## Minecraft Java: hardness; инструмент: дерево ×2, камень ×4.
## Время = hardness ×1.5 / speed (правильный инструмент), иначе ×5 для камня.
const HARDNESS := {"ground": 0.6, "hill": 0.6, "dirt": 0.5, "sand": 0.5, "leaves": 0.2,
	"log": 2.0, "planks": 2.0, "stone": 1.5, "deep_stone": 3.0, "ruin": 2.0, "mossy_ruin": 2.0,
	"workbench": 2.5, "bed": 0.2, "door": 3.0, "chest": 2.5, "torch": 0.0, "beacon": 3.0,
	"lathe": 2.5, "sawmill": 2.5, "alchemy": 2.5, "idea_catcher": 2.0, "nest": 0.5, "egg": 0.2,
	"drift": 0.5, "mouth": 0.5, "bedrock": -1.0}
static func hardness(kind: String) -> float:
	return float(HARDNESS.get(kind, 1.0))
static func seconds(kind: String, tool: String = "") -> float:
	var h := hardness(kind)
	if h < 0:
		return INF
	var rock := kind in ["stone", "deep_stone", "ruin", "mossy_ruin", "lathe", "alchemy"]
	var pick := tool in ["pickaxe", "pickaxe2"]
	var speed := (4.0 if tool == "pickaxe2" else 2.0) if rock and pick else 1.0
	return maxf(0.05, h * (1.5 if not rock or pick else 5.0) / speed)
static func idea_seconds(kind: String) -> int:
	if kind in ["hill", "ground", "dirt", "leaves", "sand"]:
		return 1
	if kind == "stone":
		return 5
	return maxi(1, roundi(hardness(kind) * 3.0))

static func material(kind: String) -> String:
	if kind in ["stone", "deep_stone", "ruin", "mossy_ruin", "bedrock", "lathe", "alchemy"]:
		return "stone"
	if kind in ["log", "planks", "workbench", "door", "chest", "sawmill", "bed"]:
		return "wood"
	if kind == "leaves":
		return "leaves"
	return "dirt"
