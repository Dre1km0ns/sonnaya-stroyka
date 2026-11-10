extends RefCounted
## MC hardness; v0.9 pacing: wooden pick stone 3s, stone pick 1.5s; dirt ×1.25.
## Hand: harvestable hardness ×1.5; wrong-tool rock ×5 and no drop.
const HARDNESS := {"ground": 0.6, "hill": 0.6, "dirt": 0.5, "sand": 0.5, "leaves": 0.2,
	"log": 2.0, "planks": 2.0, "stone": 1.5, "deep_stone": 3.0, "ruin": 2.0, "mossy_ruin": 2.0,
	"workbench": 2.5, "bed": 0.2, "door": 3.0, "chest": 2.5, "torch": 0.0, "beacon": 3.0,
	"lathe": 2.5, "sawmill": 2.5, "alchemy": 2.5, "idea_catcher": 2.0, "nest": 0.5, "egg": 0.2,
	"drift": 0.5, "mouth": 0.5, "bedrock": -1.0}
static func hardness(kind: String) -> float:
	return float(HARDNESS.get(kind, 1.0))
static func seconds(kind: String,tool: String = "") -> float:
	var h := hardness(kind)
	if h<0: return INF
	var pick := tool in ["pickaxe","pickaxe2"]
	var rock := kind in ["stone","deep_stone","ruin","mossy_ruin","lathe","alchemy","beacon"]
	if pick:
		var stone_time := 1.5 if tool=="pickaxe2" else 3.0
		if kind in ["dirt","ground","hill","sand"]: return stone_time*1.25
		if rock: return stone_time*h/1.5
	# MC harvestable-by-hand blocks: h*1.5; wrong-tool stone h*5 and no drop.
	return maxf(0.05,h*(5.0 if rock else 1.5))
static func drops(kind: String,tool: String) -> bool:
	return kind!="bedrock" and (tool in ["pickaxe","pickaxe2"] or kind not in ["stone","deep_stone","ruin","mossy_ruin","lathe","alchemy","beacon","bedrock"])
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
