extends Control
## Source comic keyframes; no campaign state is mutated here.
signal completed
const Catalog=preload("res://scripts/dove_asset_catalog.gd")
var definition:Dictionary
var catalog:RefCounted
var fonts:RefCounted
var audio:Node
var phase:="comic1"
var page_index:=0
var elapsed:=0.0
var phase_elapsed:=0.0
var fade_elapsed:=-1.0
var playing:=true
var finishing:=false
var frames:Dictionary={}
var sound_player:AudioStreamPlayer
var zoom:=1.0
var view_width:=1024.0
var margin:=0.0

func initialize(boot:Node,sound:Node) -> bool:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/kr1_end/definition.json"))
	if not parsed is Dictionary or not parsed.get("comics") is Array or parsed.comics.size()!=2:return false
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/kr1_end/manifest.json"))
	if not manifest is Dictionary:return false
	for path:String in manifest.get("resources",[]):
		if not ResourceLoader.exists(path):return false
	definition=parsed
	catalog=Catalog.new("res://data/kr1_end/catalog.json");fonts=boot.fonts;audio=sound
	sound_player=AudioStreamPlayer.new();sound_player.bus="SFX";add_child(sound_player)
	_music("MusicEndCredits")
	return true

func _music(id:String) -> void:
	var sound:Dictionary=catalog.get_sound(id)
	audio.play_music(load(sound.paths[0]),float(sound.get("gain",1)))

func _paper() -> void:
	sound_player.stream=load(catalog.get_sound("GUINotificationPaperOver").paths[0])
	if DisplayServer.get_name()!="headless":sound_player.play()

func pages() -> Array:return definition.comics[0 if phase=="comic1" else 1]

func page() -> Dictionary:return pages()[page_index]

func skip() -> void:
	if finishing or fade_elapsed>=0:return
	if playing:elapsed=float(page().end_frame)/30;playing=false
	else:_paper();fade_elapsed=0

func _next_page() -> void:
	fade_elapsed=-1
	if page_index+1<pages().size():page_index+=1;playing=true;return
	if phase=="comic1":phase="comic2";page_index=0;elapsed=0;phase_elapsed=0;playing=true;_music("MusicSuspense");return
	finishing=true;audio.stop_music();completed.emit()

func _process(delta:float) -> void:
	if definition.is_empty() or finishing:return
	phase_elapsed+=delta
	if phase=="comic1" and phase_elapsed<1:pass
	elif playing:
		elapsed=minf(elapsed+delta,float(page().end_frame)/30)
		if elapsed>=float(page().end_frame)/30:playing=false
	if fade_elapsed>=0:
		fade_elapsed+=delta
		if fade_elapsed>=0.25:_next_page()
	queue_redraw()

static func sample(keys:Array,frame:float) -> Array:
	var first:Array=keys[0]
	if frame<float(first[0]):return [first[1],first[2],first[3],first[4],0.0]
	for i in range(1,keys.size()):
		var target:Array=keys[i];var prev:Array=keys[i-1]
		if frame>float(target[0]):continue
		var f:float=clampf((frame-float(prev[0]))/(float(target[0])-float(prev[0])),0,1)
		if int(target[6])>0:f=1-pow(2,-10*f) if f<1 else 1.0
		else:f=pow(2,10*(f-1)) if f>0 else 0.0
		return [lerpf(prev[1],target[1],f),lerpf(prev[2],target[2],f),lerpf(prev[3],target[3],f),lerpf(prev[4],target[4],f),lerpf(prev[5],target[5],f)]
	var last:Array=keys[-1];return [last[1],last[2],last[3],last[4],last[5]]

func _frame(name_value:String) -> Dictionary:
	if not frames.has(name_value):frames[name_value]=catalog.get_frame("kr1_end",name_value)
	return frames[name_value]

func _image(name_value:String,point:Vector2,anchor:Vector2,scale_value:Vector2,alpha:float) -> void:
	var f:Dictionary=_frame(name_value)
	var factor:float=float(f.ref_scale)*768.0/1080.0
	var origin:Vector2=anchor*f.original_size-f.trim
	draw_set_transform((point+Vector2(margin,0))*zoom,0,scale_value*zoom)
	draw_texture_rect(f.texture,Rect2(-origin*factor,f.logical_size*factor),false,Color(1,1,1,alpha))
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*zoom)

func _draw() -> void:
	if definition.is_empty():return
	zoom=size.y/768;view_width=size.x/zoom;margin=(view_width-1024)/2
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*zoom)
	draw_rect(Rect2(0,0,view_width,768),Color.BLACK)
	var p:Dictionary=page();var alpha:float=1-clampf(fade_elapsed/0.25,0,1) if fade_elapsed>=0 else 1.0
	for id:String in p.order:
		if not p.sprites.has(id):continue
		var sprite:Dictionary=p.sprites[id];var value:Array=sample(sprite.keys,elapsed*30)
		var point:=Vector2(value[0],value[1]);var scale_value:=Vector2(value[2],value[3]);var opacity:float=float(value[4])*alpha
		_image(sprite.image,point,Vector2(sprite.anchor[0],sprite.anchor[1]),scale_value,opacity)
		for label:Dictionary in p.labels:
			if label.sprite!=id:continue
			var f:Dictionary=_frame(sprite.image)
			var frame_size:Vector2=f.original_size*float(f.ref_scale)*768.0/1080
			var origin:Vector2=Vector2(sprite.anchor[0],sprite.anchor[1])*frame_size
			var text_point:Vector2=point-origin+Vector2(label.pos[0],label.pos[1])+origin
			var font:Font=fonts.font_for("body")
			var font_size:=22;var w:float=label.size[0]
			var paragraph:=TextParagraph.new()
			while true:
				paragraph.clear();paragraph.width=w;paragraph.alignment=HORIZONTAL_ALIGNMENT_CENTER
				paragraph.break_flags=TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE
				paragraph.add_string(label.text,font,font_size)
				if font_size<=9 or (paragraph.get_size().y<=float(label.size[1]) and (int(label.fit_lines)<=0 or paragraph.get_line_count()<=int(label.fit_lines))):break
				font_size-=1
			draw_set_transform((text_point+Vector2(margin,0))*zoom,float(label.rotation),scale_value*zoom)
			paragraph.draw(get_canvas_item(),Vector2(-w/2,-paragraph.get_size().y/2),Color(label.color[0]/255.0,label.color[1]/255.0,label.color[2]/255.0,opacity))
			draw_set_transform(Vector2.ZERO,0,Vector2.ONE*zoom)
	if phase=="comic1" and phase_elapsed<1:draw_rect(Rect2(0,0,view_width,768),Color(1,1,1,1-phase_elapsed))

func _gui_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:skip();accept_event()

func _unhandled_key_input(event:InputEvent) -> void:
	if event.is_pressed():skip();get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if catalog!=null:catalog.clear_cache()
