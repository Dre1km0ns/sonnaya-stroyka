extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var g=load("res://tools/_legacy_game_state_v091.gd").new();root.add_child(g)
 g.begin_world("fixture_v091","","12345",12345,false)
 g.add_item_count("pickaxe2",1);g.add_item_count("sword2",1);g.add_item_count("heal2",2)
 g.get_slot(0).durability=117;g.sword2_crafted=true;g.mother_defeated=true
 var armor=["wood_helmet","scale_chest","wood_legs","scale_boots"]
 for i in range(4): g.armor[i]={"id":armor[i],"count":1,"durability":37}
 g.place_wake_block(Vector3i(40,4,40),"door");g.wake_blocks[Vector3i(40,4,40)].facing=3;g.toggle_door(Vector3i(40,4,40));g.place_wake_block(Vector3i(42,4,40),"bed");g.place_wake_block(Vector3i(45,4,40),"chest")
 g.storage_slots(Vector3i(45,4,40))[0]={"id":"stone","count":23}
 g.enter_dream();g.place_dream_block(Vector3i(50,4,50),"door");g.dream_blocks[Vector3i(50,4,50)].facing=1
 g.reagent_counts=[7,8,9];g.nails=3;g.select_anchor(g.AnchorType.NAIL);g.try_place_anchor(Vector3i(50,4,50))
 var data:Dictionary=g.to_save_dict();data["_fixture_source"]="89cbb0d807041022accddd5a8837c3be90720359: actual v0.9.1 serializer"
 DirAccess.make_dir_recursive_absolute("res://tests/fixtures");var f=FileAccess.open("res://tests/fixtures/v091_save.json",FileAccess.WRITE);f.store_string(JSON.stringify(data,"\t"));f.close();print("LEGACY FIXTURE schema ",data.get("schema_version",data.get("version")))
 g.queue_free();await process_frame;quit()
