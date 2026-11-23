extends RefCounted
## MC hardness; v0.9 pacing: wooden pick stone 3s, stone pick 1.5s; dirt ×1.25.
## Hand: harvestable hardness ×1.5; wrong-tool rock ×5 and no drop.
const HARDNESS := {"dirt": 0.6, "sand": 0.5, "leaves": 0.2,
	"log": 2.0, "planks": 2.0, "stone": 1.5, "deep_stone": 3.0, "ruin": 2.0, "mossy_ruin": 2.0,
	"workbench": 2.5, "bed": 0.2, "door": 3.0, "chest": 2.5, "torch": 0.0, "beacon": 3.0,
	"lathe": 2.5, "sawmill": 2.5, "alchemy": 2.5, "idea_catcher": 2.0, "nest": 0.5, "egg": 0.2,
	"drift": 0.5, "mouth": 0.5, "bedrock": -1.0, "metal_ore": 3.0}
const Gear := preload("res://scripts/gear.gd")
## v0.24: металлическая руда — только каменной киркой или лучше (pt126u).
const ORE_MIN_TIER := 2
const ROCK := ["stone","deep_stone","ruin","mossy_ruin","lathe","alchemy","beacon","metal_ore"]
static func hardness(kind: String) -> float:
	return float(HARDNESS.get(kind, 1.0))
static func seconds(kind: String,tool: String = "") -> float:
	var h := hardness(kind)
	if h<0: return INF
	var tier := Gear.pick_tier(tool)
	if kind == "metal_ore" and tier < ORE_MIN_TIER: return INF
	var rock := kind in ROCK
	if tier > 0:
		var stone_time: float = Gear.PICK_STONE_TIME[tier]
		if kind in ["dirt","sand"]: return stone_time*1.25
		if rock: return stone_time*h/1.5
	# MC harvestable-by-hand blocks: h*1.5; wrong-tool stone h*5 and no drop.
	return maxf(0.05,h*(5.0 if rock else 1.5))
static func can_mine(kind: String, tool: String) -> bool:
	return is_finite(seconds(kind, tool))
static func drops(kind: String,tool: String) -> bool:
	if kind == "bedrock": return false
	if kind == "metal_ore": return Gear.pick_tier(tool) >= ORE_MIN_TIER
	return Gear.pick_tier(tool) > 0 or kind not in ROCK
static func idea_seconds(kind: String) -> int:
	if kind in ["dirt", "leaves", "sand"]:
		return 1
	if kind == "stone":
		return 5
	return maxi(1, roundi(hardness(kind) * 3.0))

static func material(kind: String) -> String:
	if kind in ["stone", "deep_stone", "ruin", "mossy_ruin", "bedrock", "lathe", "alchemy", "metal_ore", "beacon"]:
		return "stone"
	if kind in ["log", "planks", "workbench", "door", "chest", "sawmill", "bed"]:
		return "wood"
	if kind == "leaves":
		return "leaves"
	return "dirt"
