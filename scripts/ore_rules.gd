extends RefCounted
## v0.24: металлическая руда в шахтах — гнёзда 2×2×2 (≈75 % заполнения) в камне на глубине −7…−26.
## Чистая функция от сида и клетки — одинаково в потоке генерации (chunk_job) и в chunk_manager.
const ORE_TOP := -7
const ORE_BOTTOM := -26
const CLUSTER_CHANCE := 26   # из 1024 гнёзд 2×2×2

static func is_ore(c: Vector3i, world_seed: int) -> bool:
	if c.y > ORE_TOP or c.y < ORE_BOTTOM:
		return false
	var h := hash([world_seed, c.x >> 1, c.y >> 1, c.z >> 1, 911])
	if (h & 1023) >= CLUSTER_CHANCE:
		return false
	return (hash([world_seed, c.x, c.y, c.z, 37]) & 3) != 0

static func kind_at(c: Vector3i, world_seed: int, depth_kind: String) -> String:
	if depth_kind in ["stone", "deep_stone"] and is_ore(c, world_seed):
		return "metal_ore"
	return depth_kind
