extends SceneTree
var scene: Node
var G: Node
func _initialize(): call_deferred("run")
func shot(name: String) -> void:
 await process_frame
 await RenderingServer.frame_post_draw
 var path="/workspace/shots/v010_"+name+".png"
 root.get_texture().get_image().save_png(path);print("SHOT "+path)
func run():
 G=root.get_node("GameState");G.begin_world("v0.10 preview","","6767676767",G.DEV_SEED,true)
 scene=load("res://scenes/main.tscn").instantiate();scene.set_meta("smoke",true);root.add_child(scene);current_scene=scene
 await create_timer(2).timeout
 var console=get_first_node_in_group("dev_console");console.execute("time day")
 scene.player.set_physics_process(false);scene.player.global_position=Vector3(3.5,0.1,5.5);scene.player.camera.look_at(Vector3(3.5,1,1.7))
 G.set_slot(0,{});G.select_item_slot(0);G.place_wake_block(Vector3i(3,0,1),"door",0)
 await create_timer(0.3).timeout
 var hud=scene.get_node("HUD");hud.set_debug("on");await shot("f3")
 hud.set_debug("off");await shot("door_closed");G.toggle_door(Vector3i(3,0,1));await create_timer(0.2).timeout;await shot("door_open")
 G.set_slot(0,{"id":"sword3","count":1,"durability":700});G.select_item_slot(0);scene.build._update_hand_tools();await shot("scale_sword")
 var inv=get_first_node_in_group("inventory_ui");inv.open();await create_timer(0.2).timeout;await shot("inventory");inv.close()
 console.open();console.execute("help sword3");console.execute("help potion");console.execute("help anchor");console.execute("help chunks");await create_timer(0.2).timeout;await shot("console_help");console.close()
 scene.queue_free();await process_frame;paused=true
 for audio in root.find_children("*","AudioStreamPlayer",true,false)+root.find_children("*","AudioStreamPlayer3D",true,false):audio.stop();audio.queue_free()
 await create_timer(0.3).timeout;quit()
