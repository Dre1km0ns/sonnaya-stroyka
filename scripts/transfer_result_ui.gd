extends CanvasLayer
const ThemeMaker:=preload("res://scripts/ui_theme.gd")
var panel:Control
var title:Label
var details:Label
var buttons:HBoxContainer
var last_result:Dictionary={}
var _switcher:Node
var _retry_clock:=0.0
func _ready()->void:
	layer=35;process_mode=Node.PROCESS_MODE_ALWAYS;add_to_group("transfer_result_ui")
	panel=Control.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.theme=ThemeMaker.make();add_child(panel)
	var dim:=ColorRect.new();dim.color=Color(0.015,0.025,0.06,0.8);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_child(dim)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_child(center)
	var frame:=PanelContainer.new();frame.custom_minimum_size=Vector2(650,340);center.add_child(frame)
	var margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	frame.add_child(margin);var box:=VBoxContainer.new();box.add_theme_constant_override("separation",16);margin.add_child(box)
	title=Label.new();title.add_theme_font_size_override("font_size",26);box.add_child(title)
	details=Label.new();details.custom_minimum_size=Vector2(600,190);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.add_theme_font_size_override("font_size",16);box.add_child(details)
	buttons=HBoxContainer.new();buttons.add_theme_constant_override("separation",10);box.add_child(buttons);panel.hide()
func show_result(result:Dictionary,switcher:Node)->void:
	last_result=result;_switcher=switcher;_retry_clock=0;GameState.transfer_ui_open=true
	for console in get_tree().get_nodes_in_group("dev_console"):
		if GameState.console_open: console.close()
	for child in buttons.get_children(): child.free()
	panel.show();get_tree().paused=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if result.ok:
		title.text="Черновик сна сохранён" if result.get("aborted",false) else "Пробуждение · результат переноса"
		var spent:Dictionary=result.get("spent",{})
		details.text="Перенесено: %d объектов\nЗаблокировано: %d · Мутаций: %d / максимум %d\nБез якоря: %d · Получено осыпи: +%d\nПотрачено: %d якорей · %d реагентов · %.0f ясности\n"%[result.transferred,result.blocked,result.mutations,result.get("cap",0),result.get("unanchored",0),result.dust,spent.get("anchors",0),spent.get("reagents",0),spent.get("clarity",0)]
		if result.get("aborted",false): details.text+="%d объектов осталось во Сне. Якоря отменены, резерв возвращён.\n"%result.get("draft_saved",0)
		else: details.text+="Бросок мутации 7% на блок; общий предел — 3% структуры.\nМаяки защитили: %d (+5 осыпи за каждый предотвращённый бросок)."%result.get("protected",0)
		_button("Продолжить · Esc / Y",close)
	else:
		title.text="Перенос остановлен — ничего не потеряно" if result.get("ready",true) else "Проверяем рельеф Яви…"
		var conflicts:Array=result.get("conflicts",[]);details.text="Ничего не перенесено и дополнительно не списано.\nБлоки сна и резерв сохранены.\n"
		for i in range(mini(3,conflicts.size())): details.text+=str(conflicts[i])+"\n"
		if not result.get("ready",true): details.text+="Проверка в worker; мир на паузе. Повторяем автоматически.\n"
		details.text+="Можно исправить конфликт во Сне или вернуться без потери черновика."
		_button("Проверить снова",_retry)
		var stay:=_button("Остаться во Сне",close);stay.disabled=GameState.clarity<=0
		_button("В Явь, сохранить черновик",func():_switcher.wake_up(true))
func _button(text:String,callback:Callable)->Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size=Vector2(0,40);button.pressed.connect(callback);buttons.add_child(button);return button
func _retry()->void:
	if is_instance_valid(_switcher): _switcher.wake_up()
func _process(delta:float)->void:
	if not panel.visible or last_result.get("ok",true) or last_result.get("ready",true): return
	_retry_clock+=delta
	if _retry_clock>=0.3: _retry_clock=0;_retry()
func close()->void:
	if not last_result.get("ok",true) and GameState.clarity<=0:
		if is_instance_valid(_switcher): _switcher.wake_up(true)
		return
	panel.hide();GameState.transfer_ui_open=false;GameState.modal_closed_frame=Engine.get_process_frames();get_tree().paused=false;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func _input(event:InputEvent)->void:
	if panel.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE,KEY_Y]:
		get_viewport().set_input_as_handled();close()
func _exit_tree()->void:
	if GameState.transfer_ui_open: GameState.transfer_ui_open=false;get_tree().paused=false
