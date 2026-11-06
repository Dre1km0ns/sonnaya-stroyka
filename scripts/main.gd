extends Node3D
## Главная сцена v0.4: реагенты, инвентарь, призраки, руины/озёра.

@onready var player: CharacterBody3D = $Player
@onready var wake_world: Node3D = $WakeWorld
@onready var dream_world: Node3D = $DreamWorld
@onready var wake_voxels: Node3D = $WakeWorld/WakeVoxels
@onready var dream_voxels: Node3D = $DreamWorld/DreamVoxels
@onready var bed: StaticBody3D = $WakeWorld/Bed
@onready var build: Node = $Systems/BuildController
@onready var anchors: Node = $Systems/AnchorSystem
@onready var switcher: Node = $Systems/WorldSwitcher
@onready var wake_chunks: Node3D = $WakeWorld/WakeChunks
@onready var dream_chunks: Node3D = $DreamWorld/DreamChunks
@onready var threat: Node = $Systems/ThreatDirector
@onready var saver: Node = $Systems/SaveSystem


func _ready() -> void:
	build.setup(player, dream_voxels)
	anchors.setup(player, dream_voxels)
	switcher.setup(player, wake_world, dream_world, bed, wake_voxels, dream_voxels)
	threat.setup(player, wake_world, bed)
	saver.setup(self, player, wake_voxels, dream_voxels, threat)
	if wake_chunks and wake_chunks.has_method("setup"):
		wake_chunks.setup(player, GameState.world_seed_wake)
	if dream_chunks and dream_chunks.has_method("setup"):
		dream_chunks.setup(player, GameState.world_seed_dream)
	# Автозагрузка при старте, если есть сейв
	if saver.has_save():
		saver.load_game()
		GameState.set_hint("Продолжение с диска (F5 сейв / F9 лоад).")
	print("Сонная стройка v0.4 ready (reagents+ghosts+inventory). Path OK.")


func apply_world_visibility(is_dream: bool) -> void:
	if switcher and switcher.has_method("_apply_visibility"):
		switcher.call("_apply_visibility", is_dream)
	if switcher and switcher.has_method("_tint_dream"):
		switcher.call("_tint_dream", is_dream)
	if "flying" in player:
		player.set("flying", is_dream)
