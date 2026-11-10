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
 console.open();console.execute("help sword3");console.execute("help potion");console.execute("help anchor");console.execute("help chunks");console.execute("help transfer");await create_timer(0.2).timeout;await shot("console_help");console.close()
 scene.switcher.enter_dream();scene.player.set_physics_process(false)
 G.set_slot(0,{});G.select_item_slot(0)
 for x in range(7):
  for z in range(5):G.place_dream_block(Vector3i(8+x,9,8+z),"planks")
 for x in range(7):
  for y in range(3):
   if x==3 and y<2:continue
   G.place_dream_block(Vector3i(8+x,10+y,8),"planks")
 G.place_dream_block(Vector3i(11,10,8),"door",0)
 scene.player.global_position=Vector3(11.5,10.5,13);scene.player.camera.look_at(Vector3(11.5,11.1,8.5));G.select_anchor(G.AnchorType.ANCHOR3)
 scene.dream_voxels.flush_dirty() if "dream_voxels" in scene else scene.anchors.dream_voxels.flush_dirty()
 await physics_frame;await physics_frame;await create_timer(0.3).timeout
 scene.anchors._dirty=true;scene.anchors._update_preview();await shot("transfer_preview")
 var target=scene.anchors._target_cell();var plan=G.anchor_preview(target)
 for i in range(100):
  if plan.ready:break
  await create_timer(0.05).timeout;plan=G.anchor_preview(target)
 assert(G.try_place_anchor(target));scene.anchors._dirty=true;scene.anchors._update_preview();await shot("anchored_cells")
 var result=scene.switcher.wake_up();assert(result.ok);await shot("wake_result")
 var ui=get_first_node_in_group("transfer_result_ui");var key=InputEventKey.new();key.keycode=KEY_Y;key.pressed=true;ui._input(key)
 assert(not G.transfer_ui_open and not paused and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED);print("GUI mouse capture and modal close OK")
 scene.queue_free();await process_frame;paused=true
 for audio in root.find_children("*","AudioStreamPlayer",true,false)+root.find_children("*","AudioStreamPlayer3D",true,false):audio.stop();audio.queue_free()
 await create_timer(0.3).timeout;quit()
