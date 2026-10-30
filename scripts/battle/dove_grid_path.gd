extends RefCounted
## Dove grid_a_star + grid_db.find_waypoints, including heap tie order, edge
## exclusions, 1000-iteration cap, and the source's skipped first path cell.
var heap: Array = []

static func heuristic(a: Vector2i,b: Vector2i) -> float:
	var d := (a-b).abs()
	return d.x+d.y-0.586*mini(d.x,d.y)

func up(index: int) -> void:
	while index>0:
		var parent := (index-1)/2 as int
		if float(heap[parent].cost)<=float(heap[index].cost): break
		var old: Dictionary=heap[index];heap[index]=heap[parent];heap[parent]=old;index=parent

func down(index: int) -> void:
	while index*2+1<heap.size():
		var child := index*2+1
		if child+1<heap.size() and float(heap[child+1].cost)<float(heap[child].cost): child+=1
		if float(heap[index].cost)<=float(heap[child].cost): break
		var old: Dictionary=heap[index];heap[index]=heap[child];heap[child]=old;index=child

func push(node: Vector2i,cost: float) -> void:
	heap.append({"node":node,"cost":cost});up(heap.size()-1)

func pop() -> Vector2i:
	var result: Vector2i=heap[0].node
	var last: Dictionary=heap.pop_back()
	if not heap.is_empty(): heap[0]=last;down(0)
	return result

func update_cost(node: Vector2i,cost: float) -> void:
	for index in heap.size():
		if heap[index].node==node:
			heap[index].cost=cost
			# Reproduce both adjustment directions of the source heap update.
			var position := index
			while position>0:
				var parent := (position-1)/2 as int
				if float(heap[parent].cost)<=float(heap[position].cost): break
				var old: Dictionary=heap[position];heap[position]=heap[parent];heap[parent]=old;position=parent
			down(position);return

static func valid(grid: Array,cell: Vector2i,mask: int) -> bool:
	return cell.x>0 and cell.x<grid.size()-1 and cell.y>0 and cell.y<grid[cell.x].size()-1 and (int(grid[cell.x][cell.y]) & ~mask)==0

static func coordinates(terrain: Dictionary,point: Vector2) -> Vector2i:
	var x := clampi(ceili((point.x-float(terrain.ox))/16.0)-1,0,terrain.grid.size()-1)
	return Vector2i(x,clampi(ceili((point.y-float(terrain.oy))/16.0)-1,0,terrain.grid[x].size()-1))

func waypoints(terrain: Dictionary,from: Vector2,fallback: Vector2,to: Vector2,mask: int) -> Variant:
	heap.clear()
	var grid: Array=terrain.grid
	var start := coordinates(terrain,from)
	var goal := coordinates(terrain,to)
	if (int(grid[start.x][start.y]) & ~mask)!=0: start=coordinates(terrain,fallback)
	if (int(grid[start.x][start.y]) & ~mask)!=0:
		var found := false
		for distance in range(6):
			for dx in range(-distance,distance+1):
				for dy in range(-distance,distance+1):
					var candidate := start+Vector2i(dx,dy)
					if valid(grid,candidate,mask): start=candidate;found=true;break
				if found: break
			if found: break
		if not found: return null
	var costs := {start:0.0}
	var previous := {}
	var closed := {}
	var opened := {start:true}
	push(start,heuristic(start,goal))
	var current := start
	var iterations := 0
	while not heap.is_empty() and iterations<1000:
		iterations+=1;current=pop();opened.erase(current);closed[current]=true
		if current==goal: break
		for offset in [Vector2i(-1,-1),Vector2i(-1,0),Vector2i(-1,1),Vector2i(0,-1),Vector2i(0,1),Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1)]:
			var neighbor: Vector2i=current+offset
			if not valid(grid,neighbor,mask) or closed.has(neighbor): continue
			var cost: float=float(costs[current])+(1.0 if offset.x==0 or offset.y==0 else 1.4142)
			if not costs.has(neighbor) or cost<float(costs[neighbor]):
				previous[neighbor]=current;costs[neighbor]=cost
				var total: float=cost+heuristic(neighbor,goal)
				if opened.has(neighbor): update_cost(neighbor,total)
				else: push(neighbor,total);opened[neighbor]=true
	if iterations>=1000 or current!=goal: return null
	var cells: Array[Vector2i]=[]
	while current!=start: cells.push_front(current);current=previous[current]
	var result: Array[Vector2]=[]
	for index in cells.size():
		if index==0: continue
		result.append(to if index==cells.size()-1 else Vector2((cells[index].x+0.5)*16+float(terrain.ox),(cells[index].y+0.5)*16+float(terrain.oy)))
	return result
