extends RefCounted
## Pure-data preflight. No scene access, mutation, resource spending or partial writes.
const BLOCKS := ["bedrock","drift","mouth","workbench","hill","ruin","ground","log","leaves","planks","stone","deep_stone","dirt","sand","nest","bed","lathe","sawmill","alchemy","idea_catcher","chest","door","mossy_ruin","torch","beacon"]
static func root_at(source:Dictionary,c:Vector3i)->Vector3i:
	if not source.get(c,{}).has("root"): return c
	var a:PackedStringArray=str(source[c].root).split(",")
	return Vector3i(int(a[0]),int(a[1]),int(a[2])) if a.size()==3 else c
static func footprint(c:Vector3i,data:Dictionary)->Array[Vector3i]:
	var cells:Array[Vector3i]=[c];var kind:String=data.get("kind","")
	if kind in ["bed","door","idea_catcher"] and not data.get("legacy_compact",false): cells.append(c+(Vector3i.BACK if kind=="bed" else Vector3i.UP))
	return cells
static func roots_for(source:Dictionary,cells:Array,anchored_only:bool=false)->Array[Vector3i]:
	var seen:Dictionary={};var out:Array[Vector3i]=[]
	for c in cells:
		if not source.has(c): continue
		var root:=root_at(source,c)
		if not source.has(root) or (anchored_only and not source[root].get("anchored",false)): continue
		if not seen.has(root): seen[root]=true;out.append(root)
	out.sort_custom(func(a:Vector3i,b:Vector3i)->bool:return a.x<b.x if a.x!=b.x else (a.y<b.y if a.y!=b.y else a.z<b.z))
	return out
static func build(source:Dictionary,target:Dictionary,roots:Array,natural:Dictionary,protected_areas:Array,ready:bool=true)->Dictionary:
	var cells:Dictionary={};var conflicts:Array=[];var blocked:Dictionary={}
	for c in roots:
		var data:Dictionary=source.get(c,{});var kind:String=data.get("kind","")
		if kind not in BLOCKS: conflicts.append("Неизвестный блок %s в %s"%[kind,c]);blocked[c]=true;continue
		for cell in footprint(c,data):
			cells[cell]=c
			var reason:=""
			if absi(cell.x)>100000 or absi(cell.z)>100000 or cell.y<=-31 or cell.y>128: reason="недопустимые координаты"
			elif not source.has(cell) or root_at(source,cell)!=c: reason="неполный многоблочный объект"
			elif cell!=c and source[cell].get("kind","")!={"bed":"bed_foot","door":"door_top","idea_catcher":"catcher_top"}.get(kind,""): reason="неверная часть объекта"
			elif target.has(cell): reason="уже занят постройкой Яви"
			elif str(natural.get(cell,""))!="": reason="занят рельефом Яви: "+str(natural[cell])
			else:
				for area in protected_areas:
					if area.intersects(AABB(Vector3(cell),Vector3.ONE)): reason="зона появления игрока";break
			if reason!="": conflicts.append("%s: %s"%[cell,reason]);blocked[c]=true
	return {"ok":ready and conflicts.is_empty(),"ready":ready,"roots":roots,"cells":cells,"count":roots.size(),"blocked":blocked.size(),"conflicts":conflicts,"cap":floori(roots.size()*0.03)}
static func mutations(source:Dictionary,roots:Array,beacons:Array,seed:int,immune:Array)->Dictionary:
	var rng:=RandomNumberGenerator.new();rng.seed=seed
	var candidates:Array[Vector3i]=[];var protected_count:=0;var eligible:=0
	for c in roots:
		if source[c].get("kind","") in immune: continue
		eligible+=1
		if rng.randf()>=0.07: continue
		var safe:=false
		for beacon in beacons:
			var d:Vector3i=(c-beacon).abs()
			if d.x<=10 and d.y<=10 and d.z<=10: safe=true;break
		if safe: protected_count+=1
		else: candidates.append(c)
	for i in range(candidates.size()-1,0,-1):
		var j:=rng.randi_range(0,i);var tmp:=candidates[i];candidates[i]=candidates[j];candidates[j]=tmp
	var rolled:=candidates.size()+protected_count
	var cap:=floori(roots.size()*0.03)
	if candidates.size()>cap: candidates.resize(cap)
	return {"cells":candidates,"protected":protected_count,"eligible":eligible,"cap":cap,"rolled":rolled}
