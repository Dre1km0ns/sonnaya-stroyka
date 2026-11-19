extends Node
## One batched wireframe mesh, throttled pure-data preflight, no per-cell nodes.
var player:CharacterBody3D
var dream_voxels:Node3D
var preview:MeshInstance3D
var info:Label
var _timer:=0.0
var _dirty:=true
var _last_cell:=Vector3i(2147483647,0,0)
var _last_anchor:=-1
var last_preview:Dictionary={}
const EDGES:=[Vector2i(0,1),Vector2i(0,2),Vector2i(0,4),Vector2i(1,3),Vector2i(1,5),Vector2i(2,3),Vector2i(2,6),Vector2i(3,7),Vector2i(4,5),Vector2i(4,6),Vector2i(5,7),Vector2i(6,7)]
func setup(p:CharacterBody3D,dream_layer:Node3D)->void:
	add_to_group("anchor_preview");player=p;dream_voxels=dream_layer;preview=MeshInstance3D.new();preview.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(preview)
	var layer:=CanvasLayer.new();layer.layer=9;add_child(layer);info=Label.new();info.anchor_left=1.0;info.anchor_right=1.0;info.offset_left=-462.0;info.offset_right=-92.0;info.offset_top=250.0;info.custom_minimum_size=Vector2(370,0);  # v0.11: справа, не перекрывает панель целей
	info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.add_theme_font_size_override("font_size",14)
	var bg:=StyleBoxFlat.new();bg.bg_color=Color(0.02,0.035,0.05,0.78);bg.content_margin_left=10;bg.content_margin_right=10;bg.content_margin_top=7;bg.content_margin_bottom=7;info.add_theme_stylebox_override("normal",bg);layer.add_child(info)
	GameState.placed_cells_changed.connect(func(_dream,_cells):_dirty=true)
	GameState.anchor_selected.connect(func(_type):_dirty=true)
func _process(delta:float)->void:
	var active:=is_instance_valid(player) and GameState.is_dream() and not GameState.ui_blocked()
	# v0.21: во время обучения рамка и справка якоря появляются только на шаге «якорь».
	if active and GameState.tutorial_focus() and GameState.tutorial_step_id()!="anchor": active=false
	var tut_anchor:=active and GameState.tutorial_focus() and GameState.tutorial_step_id()=="anchor"
	var has_target:=int(last_preview.get("local_count",0))>0
	preview.visible=active;info.visible=active and (has_target or tut_anchor)
	# v0.21 c2: на шаге обучения «якорь» справка видна сразу — с подсказкой, куда навестись.
	if tut_anchor and not has_target:info.text="ЯКОРЬ · наведись прицелом на верстак\nРамка покажет, что закрепится. Потом Q."
	if not active:return
	_timer-=delta
	if _timer<=0:
		_timer=0.15;_update_preview()
		if tut_anchor and int(last_preview.get("local_count",0))==0:info.text="ЯКОРЬ · наведись прицелом на верстак\nРамка покажет, что закрепится. Потом Q."
	if Input.is_action_just_pressed("anchor_place"): _try_anchor()
func _target_cell()->Vector3i:
	var aim:Dictionary=player.get_look_ray()
	if aim.get("hit",false):return GameState.ray_cell(aim)
	var camera:Camera3D=player.get_node("CameraPivot/Camera3D")
	return dream_voxels.world_to_cell(camera.global_position-camera.global_transform.basis.z*4)
func _lines(mesh:ImmediateMesh,low:Vector3,size:Vector3,color:Color)->void:
	var points:Array[Vector3]=[]
	for i in range(8):points.append(low+Vector3(size.x if i&1 else 0,size.y if i&2 else 0,size.z if i&4 else 0))
	for edge in EDGES:mesh.surface_set_color(color);mesh.surface_add_vertex(points[edge.x]);mesh.surface_add_vertex(points[edge.y])
func _update_preview()->void:
	var cell:=_target_cell();var t:=int(GameState.selected_anchor)
	if cell==_last_cell and t==_last_anchor and not _dirty and last_preview.get("ready",true):return
	_last_cell=cell;_last_anchor=t;_dirty=false;last_preview=GameState.anchor_preview(cell)
	var p:=last_preview;var cost:Dictionary=p.cost
	var status:="Q — закрепить" if p.ok and p.affordable else ("Проверка рельефа Яви…" if not p.ready else ("Недостаточно реагентов/осознанности" if not p.affordable else ("Не хватает в Яви: "+GameState.materials_text(p.missing) if not p.missing.is_empty() else ("Всё уже стоит в Яви" if p.same>0 and p.new_roots.is_empty() else "Нет новых блоков"))))
	if not p.conflicts.is_empty():status="Конфликт: "+str(p.conflicts[0])
	var mats:String=GameState.materials_text(p.materials) if not p.materials.is_empty() else "—"
	# v0.21: компактная справка — 3–4 строки вместо шести.
	var drift_line:="" if int(p.get("drift",0))==0 else "\nДрейф: %d бл. — может мутировать, до %d"%[int(p.get("drift",0)),mini(p.cap,int(p.get("drift",0)))]
	info.text="ЯКОРЬ · %s · новых %d · закреплено %d\nЦена: %d реаг. + %.0f осознанности · Явь: %s%s\n%s"%[GameState.ItemDB.display_name(cost.special),p.new_roots.size(),p.already,cost.reagents,cost.clarity,mats,drift_line,status]
	var mesh:=ImmediateMesh.new();var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.vertex_color_use_as_albedo=true;mat.no_depth_test=true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,mat)
	var size:=1 if t==0 else (GameState.WEDGE_SIZE if t==1 else GameState.ANCHOR3_SIZE);var half:=int(size/2)
	var color:=Color(1,0.8,0.2) if p.ok else Color(1,0.35,0.25)
	_lines(mesh,Vector3(cell-Vector3i.ONE*half),Vector3.ONE*size,color)
	for c in p.cells:
		var root:Vector3i=p.cells[c];_lines(mesh,Vector3(c)-Vector3.ONE*0.006,Vector3.ONE*1.012,Color(0.3,1,0.6) if GameState.dream_blocks[root].get("anchored",false) else color)
	mesh.surface_end();preview.mesh=mesh
func _try_anchor()->void:
	GameState.try_place_anchor(_target_cell());_dirty=true;_update_preview()

func set_overlay_visible(value:bool)->void:
	preview.visible=value;info.visible=value
