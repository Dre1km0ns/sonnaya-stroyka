extends StaticBody3D
## Кровать / ритуальная точка входа в сон.


func _ready() -> void:
	add_to_group("bed")
	collision_layer = 8 # interactable
	collision_mask = 0
