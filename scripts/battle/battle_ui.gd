extends RefCounted
## Campaign battle compositions transcribed from Dove game_gui.lua. Shared layout
## mechanics (image, text fitting, transforms and hit regions) live in one place.
const Layout = preload("res://scripts/battle/dove_ui_layout.gd")
const WaveFlags = preload("res://scripts/battle/battle_wave_flags.gd")
var view: Control
var paint: RefCounted
var data: Dictionary
var strings: Dictionary
var selection_id := ""
var selection_at := 0.0
var selection_type := ""
var selection_template := ""
var closing_id := ""
var closing_type := ""
var closing_template := ""
var closing_at := 0.0
var panel_id := ""
var panel_at := 0.0
var power_mode := {}
var power_at := {}
var power_animation := {}
var power_hint := ""
var power_hint_hidden := false
var wave_flags: RefCounted
var reward_fx: Array[Dictionary] = []

func _init(battle: Control) -> void:
	view = battle; paint = Layout.new(view, view.fonts)
	data = view.sim.data.ui; strings = data.strings
	wave_flags = WaveFlags.new(view, paint)

func clock() -> float: return Time.get_ticks_msec() / 1000.0
func begin() -> void: paint.begin()
func text(key: String) -> String: return strings.get(key, key)
func _number(value: float) -> String: return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")
func _size(id: String) -> Vector2: return paint.image_size(id)

func power_frame(power: String, now: float) -> String:
	var sim: RefCounted = view.sim
	var mode := "locked" if not sim.unlocked[power] else ("cooldown" if sim.cooldowns[power] > 0 else ("selected" if view.targeting == power else "ready"))
	var previous: String = power_mode.get(power, "")
	if previous != mode:
		power_mode[power] = mode; power_at[power] = now; power_animation[power] = ""
		if mode == "ready" and previous == "cooldown":
			power_animation[power] = "ready"; view._sound("GUISpellRefresh")
		elif mode == "ready" and previous == "locked": power_animation[power] = "unlocked"
	var prefix := "fire" if power == "fire" else "reinforcements"
	var ready_prefix := "fire_ready" if power == "fire" else "reinforcement_ready"
	var elapsed := maxi(0, int((now - float(power_at[power])) * 30))
	if mode == "locked": return ready_prefix + "_0030"
	if mode == "selected": return ready_prefix + "_0029"
	# Dove reserves 30–44 for first unlock; cooldown refresh uses 1–28.
	if mode == "ready":
		if power_animation.get(power, "") == "ready" and elapsed < 28: return "%s_%04d" % [ready_prefix, 1 + elapsed]
		if power_animation.get(power, "") == "unlocked" and elapsed < 15: return "%s_%04d" % [ready_prefix, 30 + elapsed]
		if view.hovered == "target" + str({"power": power}): return prefix + "_0002"
	return prefix + "_0001"

func show_wave_reward(reward: Dictionary) -> void:
	# Dove WaveRewardFx / TimeRewardFx use sprite digits with 0.7 letter spacing.
	if int(reward.gold) > 0:
		_add_reward("+%d" % int(reward.gold), "")
		view._sound("GUICoins")
	if int(reward.seconds) > 1:
		for power: String in reward.powers: _add_reward("-%ds" % int(reward.seconds), power)

func _add_reward(value: String, power: String) -> void:
	var glyphs: Array[Dictionary] = []
	var offset := 0.0
	var height := 0.0
	for c in value:
		var index := 11 if c in ["+", "-"] else (12 if c == "s" else int(c))
		var frame := ("waveReward_" if power == "" else "waveRewardTimer_") + "%04d" % index
		var dimensions := _size(frame)
		glyphs.append({"frame": frame, "x": offset})
		offset += roundf(0.7 * dimensions.x); height = maxf(height, dimensions.y)
	var coin_width := _size("nextwave_coin_0001").x if power == "" else 0.0
	if power == "": height = maxf(height, _size("nextwave_coin_0001").y)
	var width := coin_width + offset if power == "" else offset + offset * 0.3 / value.length()
	reward_fx.append({"text": value, "power": power, "age": 0.0, "duration": 1.5 if power == "" else 1.0,
		"glyphs": glyphs, "coin_width": coin_width, "size": Vector2(width, height)})

func advance_rewards(delta: float) -> void:
	# HUD animation time, like Dove's UI tweens, is independent of simulation speed.
	for fx: Dictionary in reward_fx: fx.age += delta
	reward_fx = reward_fx.filter(func(fx): return fx.age < fx.duration)

func reward_bounds(fx: Dictionary) -> Rect2:
	if fx.power == "":
		# Anchor the source coin/digits below the gold counter as requested.
		return Rect2(Vector2(164 * 0.9 - fx.size.x / 2, 46), fx.size)
	var button_size := _size("fire_0001" if fx.power == "fire" else "reinforcements_0001")
	var center := Vector2(164 + (66 if fx.power == "reinforcements" else 0) + button_size.x / 2, 763 - button_size.y)
	var ease := 1 - pow(1 - clampf(fx.age, 0, 1), 2)
	return Rect2(center - Vector2(fx.size.x / 2, fx.size.y * (2 + ease) / 3), fx.size)

func _draw_wave_rewards() -> void:
	for fx: Dictionary in reward_fx:
		var alpha := pow(1 - clampf(fx.age / fx.duration, 0, 1), 2)
		paint.push(reward_bounds(fx).position, 1, alpha)
		if fx.power == "": paint.image("nextwave_coin_%04d" % mini(14, 1 + int(fx.age * 30)))
		for glyph: Dictionary in fx.glyphs: paint.image(glyph.frame, Vector2(fx.coin_width + glyph.x, 0))
		paint.pop()

func selection() -> void:
	if selection_id != view.selected:
		closing_id = selection_id; closing_type = selection_type; closing_at = clock()
		closing_template = selection_template
		selection_id = view.selected; selection_at = clock()
		var tower: Dictionary = view.sim.tower_by_id(selection_id)
		selection_type = tower.get("type", "")
		selection_template = tower.get("template", "")
	if selection_id != "": _selection(selection_id, false)
	elif closing_id != "" and clock() - closing_at < 0.12: _selection(closing_id, true)

func _selection(id: String, closing: bool) -> void:
	var sim: RefCounted = view.sim
	var tower: Dictionary = sim.tower_by_id(id)
	if tower.is_empty() or (tower.ready > sim.tick and not closing): return
	if closing: tower = tower.duplicate(); tower.type = closing_type; tower.template = closing_template
	var t: Dictionary = sim.tower_template(tower)
	var range_pos: Vector2 = view.world(tower.pos + Vector2(0, 12))
	if tower.type not in ["","holder_elf"] and not closing:
		var radius: float = t.barrack.rally_range if tower.type == "barrack" else t.attacks.range
		var ellipse := PackedVector2Array()
		for i in range(65): ellipse.append(range_pos + Vector2(cos(i * TAU / 64), sin(i * TAU / 64) * 0.7) * radius)
		view.draw_colored_polygon(ellipse, Color(0.4, 0.85, 1, 0.10)); view.draw_polyline(ellipse, Color(0.7, 0.9, 1, 0.5), 1)
		if tower.type == "barrack": view._art("pointer_set_rally_0001", view.world(tower.rally))
	elif not closing:
		for type: String in view.Simulation.TYPES:
			if view.hovered != "build" + str({"id": id, "type": type}): continue
			var preview: Dictionary = sim.templates["tower_" + type + "_1"]
			var radius: float = preview.barrack.rally_range if type == "barrack" else preview.attacks.range
			var ellipse := PackedVector2Array()
			for i in range(65): ellipse.append(range_pos + Vector2(cos(i * TAU / 64), sin(i * TAU / 64) * 0.7) * radius)
			view.draw_colored_polygon(ellipse, Color(0.4, 0.85, 1, 0.10)); view.draw_polyline(ellipse, Color(0.7, 0.9, 1, 0.5), 1)
	if view.targeting != "": return
	var center: Vector2 = view.world(tower.pos + view.Simulation.vec(t.tower.range_offset) + view.Simulation.vec(t.tower.menu_offset))
	center.x = clampf(center.x, 110, view.view_width - 110)
	center.y = clampf(center.y, 135, 650)
	var elapsed := clock() - (closing_at if closing else selection_at)
	var ease := 1 - pow(1 - clampf(elapsed / 0.12, 0, 1), 2)
	var fraction := 1 - ease if closing else ease
	paint.push(center, lerpf(0.6, 1.0, fraction), fraction)
	paint.push(-_size("gui_ring") / 2)
	paint.image("gui_ring")
	var enabled := not closing and elapsed >= 0.12
	if tower.type == "":
		for item: Dictionary in data.tower_menus.holder:
			var type: String = str(item.action_arg).trim_prefix("tower_build_")
			var price: int = sim.templates["tower_" + type + "_1"].tower.price
			var pos := Vector2(data.tower_menu_button_places[int(item.place) - 1].x, data.tower_menu_button_places[int(item.place) - 1].y)
			_menu_icon(item.image, pos, "build", {"id": id, "type": type}, price, sim.gold >= price and enabled)
	else:
		var target: String = sim.upgrade_target(tower)
		if target != "" and not sim.tower_locked(target):
			var item: Dictionary = data.get("upgrade_menus", {}).get(target, {})
			var price: int = sim.templates[target].tower.price
			var pos: Vector2 = view.Simulation.vec(data.tower_menu_button_places[int(item.place) - 1])
			_menu_icon(item.image, pos, "upgrade", {"id": id, "upgrade_to": target}, price, enabled and sim.gold >= price)
		elif target != "" or sim.tower_locked(view.Simulation.UPGRADES.get(tower.template, "")):
			_menu_icon("main_icons_0014", Vector2(74, 6), "locked", {}, -1, false)
		if tower.has("powers"):
			for item: Dictionary in data.tower_menus.get(str(t.tower.type), []):
				var power: String = item.get("action_arg", "")
				if not tower.powers.has(power): continue
				var pos: Vector2 = view.Simulation.vec(data.tower_menu_button_places[int(item.place) - 1])
				var price: int = sim.power_price(tower, power)
				_menu_icon(item.image, pos, "upgrade_power", {"id":id,"power":power}, price, enabled and price >= 0 and sim.gold >= price)
				for rank in range(3):
					paint.image("power_rank_0001" if rank < int(tower.powers[power]) else "power_rank_0002", pos + Vector2((rank - 1) * 9, 17), Vector2(0.5,0.5))
		if tower.type == "barrack": _menu_icon("sub_icons_0001", Vector2(128, 118), "target", {"power": "rally"}, -1, enabled)
		if t.get("mercenary",false):
			var price: int = sim.Elf.price(sim,tower,"soldier_elf")
			_menu_icon("main_icons_0016",Vector2(74,6),"buy_soldier",{"id":id,"type":"soldier_elf"},int(sim.templates.soldier_elf.unit.price),enabled and price >= 0 and sim.gold >= price)
		_menu_icon("ico_sell_0001", Vector2(74, 140), "sell", {"id": id}, -1, enabled)
	paint.pop(); paint.pop()
	if not closing and enabled: _tower_tooltip(tower)

func _menu_icon(image: String, center: Vector2, action: String, args: Dictionary, price: int, enabled: bool) -> void:
	var dimensions := _size("main_icons_0000") if image.begins_with("main_icons") else _size(image)
	var pos := center - dimensions / 2
	var over: bool = view.hovered == action + str(args)
	if over and enabled:
		var glow := "glow_ico_sell" if action == "sell" else ("glow_ico_sub" if action == "target" else "glow_ico_main")
		paint.image(glow, center, Vector2(0.5, 0.5))
	paint.image(image, center, Vector2(0.5, 0.5), Color.WHITE if enabled or action == "locked" else Color(0.5, 0.5, 0.5))
	if image.begins_with("main_icons"): paint.image("main_icons_0000", pos)
	if price >= 0:
		var tag := _size("price_tag")
		var at := pos + Vector2((dimensions.x - tag.x) / 2, dimensions.y - 11)
		paint.image("price_tag", at)
		paint.label(str(price), Rect2(at + Vector2(2, 2), tag - Vector2(4, 4)), 11, Color("ffe000"), "center", "middle", 1, 1, "", "numbers")
	paint.hit(Rect2(pos, dimensions), action, args, enabled)

func _tower_tooltip(tower: Dictionary) -> void:
	var title := ""
	var description := ""
	for item: Dictionary in data.tower_menus.holder:
		var type: String = str(item.action_arg).trim_prefix("tower_build_")
		if view.hovered == "build" + str({"id": tower.id, "type": type}):
			title = text(item.tt_title); description = text(item.tt_desc)
	if view.hovered == "locked" + str({}):
		title = "升级尚未解锁"
		description = "本关只能建造一级防御塔。" if int(view.sim.tower_template(tower).tower.level) == 1 else "本关防御塔最高可升至二级。"
	var target: String = view.sim.upgrade_target(tower)
	if target != "" and view.hovered == "upgrade" + str({"id": tower.id, "upgrade_to": target}):
		var item: Dictionary = data.get("upgrade_menus", {}).get(target, {})
		title = text(item.tt_title); description = text(item.tt_desc)
	if view.hovered == "sell" + str({"id": tower.id}):
		title = "出售防御塔"; description = "返还 %d 金币" % view.sim.sell_refund(tower)
	if view.hovered == "buy_soldier" + str({"id":tower.id,"type":"soldier_elf"}):
		title = text("TOWER_ELF_NAME"); description = text("TOWER_ELF_DESCRIPTION") + "\n已招募 %d/4 个兵位；阵亡后自动补员。" % int(tower.get("hired",0))
	for item: Dictionary in data.tower_menus.get(str(view.sim.tower_template(tower).tower.type), []):
		var power: String = item.get("action_arg", "")
		if not tower.get("powers",{}).has(power) or view.hovered != "upgrade_power" + str({"id":tower.id,"power":power}): continue
		var level := mini(3, int(tower.powers[power]) + 1)
		title = text(item.tt_list[level - 1].tt_title)
		description = data.power_descriptions[power][level - 1]
	if title == "": return
	var dimensions := _size("tooltip_bg_standard")
	var point: Vector2 = view.world(tower.pos) + Vector2(115, -125)
	if point.x + dimensions.x > view.view_width - 16: point.x -= dimensions.x + 230
	point.y = clampf(point.y, 90, 660 - dimensions.y)
	paint.push(point)
	paint.image("tooltip_bg_standard")
	paint.label(title, Rect2(12, 8, dimensions.x - 24, 25), 17, Color("ffe9b0"), "left", "middle", 1, 1, "", "body_bold")
	paint.label(description, Rect2(12, 39, dimensions.x - 24, dimensions.y - 53), 13, Color("f1e6c4"), "left", "top", 0, 1)
	paint.pop()

func hud() -> void:
	var sim: RefCounted = view.sim
	paint.push(Vector2(0, -22), 0.9)
	paint.image("top_left")
	paint.label(str(sim.lives), Rect2(78, 33, 31, 35), 18, Color.WHITE, "center", "middle", 1, 1, "hud:lives", "numbers_bold")
	paint.label(str(sim.gold), Rect2(135, 33, 58, 35), 18, Color.WHITE, "center", "middle", 1, 1, "hud:gold", "numbers_bold")
	paint.label("专项测试" if sim.data.get("arena",false) else "%d/%d 波" % [sim.wave, sim.data.waves.groups.size()], Rect2(234, 31, 82, 35), 16, Color.WHITE, "center", "middle", 1, 1, "hud:wave", "numbers_bold")
	paint.pop()
	paint.push(Vector2(view.view_width - 37, -21), 0.9)
	var base := _size("pause_base")
	paint.image("pause_base", Vector2(-base.x, 0))
	var button := _size("pause_btn_0001")
	var button_pos := Vector2(-base.x / 2 - button.x / 2, 25)
	paint.image("pause_btn_0002" if view.hovered == "pause{}" else "pause_btn_0001", button_pos)
	paint.hit(Rect2(button_pos, button), "pause")
	paint.pop()
	paint.push(Vector2(view.view_width - 190, 2), 0.60)
	paint.button("options_button_bg_0001", Vector2.ZERO, "%d×" % sim.speed, "speed", {}, true, "options", "numbers_bold")
	paint.pop()
	paint.image("bg_bottom_bar", Vector2(0, 769), Vector2(0, 1))
	paint.push(Vector2(105, 733))
	paint.image("base_powers_bg", Vector2(20.5, 36), Vector2(0, 1))
	for i in range(2):
		var power := "fire" if i == 0 else "reinforcements"
		var frame := power_frame(power, clock())
		var mode: String = power_mode[power]
		var pos := Vector2(59 + i * 66, 30)
		var dimensions := _size(frame)
		paint.image(frame, pos, Vector2(0, 1))
		var rect := Rect2(pos - Vector2(0, dimensions.y), dimensions)
		if mode == "cooldown":
			var duration: float = sim.templates.power_fireball_control.cooldown if i == 0 else sim.templates.power_reinforcements_control.cooldown
			var fraction: float = sim.cooldowns[power] / (duration * 30)
			paint._apply()
			view.draw_rect(Rect2(rect.position + Vector2(9, 10 + (dimensions.y - 19) * (1 - fraction)), Vector2(dimensions.x - 18, (dimensions.y - 19) * fraction)), Color(0, 0, 0, 0.59))
		paint.image("power_nbrs_000%d" % (i + 1), Vector2(pos.x + dimensions.x / 2, 36), Vector2(0.5, 1))
		paint.hit(rect, "target", {"power": power}, mode not in ["locked", "cooldown"])
	paint.pop()
	wave_flags.draw()
	_unit_info()
	for i in range(sim.alerts.size()):
		var id: String = sim.alerts[i]
		var icon: String = data.notifications[id].icon
		paint.push(Vector2(14, 135 + i * 49), 0.7)
		paint.image(icon)
		paint.hit(Rect2(Vector2.ZERO, _size(icon)), "enemy_notice", {"id": id})
		paint.pop()
	if view.tip != "":
		paint.push(Vector2(12, 79), 0.75)
		paint.button("options_button_bg_0001", Vector2.ZERO, "战斗提示", "tip")
		paint.pop()
	if sim.notices.is_empty() and not sim.paused and sim.result == "": _balloons()
	wave_flags.draw_tooltip()
	_draw_wave_rewards()

func _unit_info() -> void:
	var info: Dictionary = view.unit_info()
	if info.is_empty(): return
	# InfoBar source coordinates: portrait (56,32), name (97,8),
	# stats (100,33) at 0.8 scale. Fit the whole composition between powers/waves.
	var dimensions := _size("base")
	var left := 352.0
	var right: float = view.view_width - 178
	var factor := minf(1, (right - left) / dimensions.x)
	var position := Vector2((left + right - dimensions.x * factor) / 2, 769 - dimensions.y * factor)
	paint.push(position, factor)
	paint.image("base")
	if info.portrait != "":
		paint.push(Vector2(56, 32), 0.8)
		paint.image(info.portrait, Vector2.ZERO, Vector2(0.5, 0.5))
		paint.image("info_portraits_0000", Vector2.ZERO, Vector2(0.5, 0.5))
		paint.pop()
	paint.label(info.name, Rect2(97, 5, 320, 21), 12, Color.WHITE, "left", "bottom", 1, 1, "unit:name", "infobar_name")
	paint.push(Vector2(100, 33), 0.8)
	var health_size := _size("base_info_bar_bg")
	paint.image("base_info_bar_bg")
	var foreground := _size("base_info_bar")
	paint.image("base_info_bar", (health_size - foreground) / 2, Vector2.ZERO, Color.WHITE, Vector2(clampf(info.hp / info.hp_max, 0, 1), 1))
	paint.label("%d / %d" % [int(info.hp), int(info.hp_max)], Rect2(0, 0, health_size.x, 17), 11, Color.WHITE, "center", "middle", 1, 1, "unit:hp", "infobar_stats")
	var columns := [
		["base_info_icons_sword", "%d–%d / %s秒" % [int(info.damage_min), int(info.damage_max), _number(info.cooldown)], 112.0],
		["base_info_icons_armor", "%d%%" % roundi(info.armor * 100), 60.0],
		["base_info_icons_magic_armor", "%d%%" % roundi(info.magic_armor * 100), 60.0],
		["base_info_icons_cost" if info.enemy else "base_info_icons_lifetime", str(info.lives) if info.enemy else "%s秒" % _number(info.respawn), 60.0]]
	var x := 145.0
	for column: Array in columns:
		paint.image(column[0], Vector2(x, 0))
		paint.label(column[1], Rect2(x + 19, -2, float(column[2]) - 20, 20), 12, Color.WHITE, "left", "middle", 1, 1, "unit:" + column[0], "infobar_stats")
		x += float(column[2])
	paint.pop()
	# Consume clicks on the entire bar, including empty space around its labels.
	paint.hit(Rect2(Vector2.ZERO, dimensions), "unit_info")
	paint.pop()

func _balloons() -> void:
	var sim: RefCounted = view.sim
	if int(sim.data.get("level", {}).get("id", 1)) != 1: return
	if view.targeting == "" and view.selected != "": return
	var built := false
	for t: Dictionary in sim.towers:
		if t.type != "": built = true
	var id := "TB_BUILD" if not built and sim.wave == 0 else ("TB_START" if sim.wave == 0 else "")
	if power_hint != "" and not power_hint_hidden: id = power_hint
	if id == "": return
	if id == "TB_START" and not wave_flags.hovered_flag().is_empty(): return
	var d: Dictionary = data.tutorial_balloons[id]
	var pos := Vector2(d.offset.x, d.offset.y)
	if d.origin == "world": pos = view.world(pos)
	elif d.origin == "bottom-right": pos += Vector2(view.view_width, 768)
	else: pos += Vector2(0, 768)
	if id == "TB_START" and not wave_flags.active.is_empty():
		pos = wave_flags.position(wave_flags.active[0]) + Vector2(-24, 58)
	paint.push(pos - _size(d.image) / 2)
	if id == "TB_START": paint.image(d.image, Vector2(0, _size(d.image).y), Vector2.ZERO, Color.WHITE, Vector2(1, -1))
	else: paint.image(d.image)
	for definition: Dictionary in data.slides.get(id, []):
		if id == "TB_START":
			definition = definition.duplicate(true); definition.pos.y += 20
		paint.source_label(definition, strings)
	paint.pop()

func _panel(id: String, dimensions: Vector2, preferred: float = 1.3, duration: float = 0.4) -> void:
	if panel_id != id: panel_id = id; panel_at = clock()
	var elapsed := clampf((clock() - panel_at) / duration, 0, 1)
	var ease := 1 + 2.70158 * pow(elapsed - 1, 3) + 1.70158 * pow(elapsed - 1, 2)
	var scale_value := minf(preferred, minf((view.view_width - 64) / dimensions.x, 650 / dimensions.y))
	paint.push(Vector2(view.view_width / 2, 384), scale_value * lerpf(0.5, 1, ease), elapsed)
	paint.push(-dimensions / 2)

func _end_panel() -> void: paint.pop(); paint.pop()

func _title(image: String, caption: String, at: Vector2, center: bool = true) -> void:
	var dimensions := _size(image)
	var pos := at - Vector2(dimensions.x / 2 if center else 0, dimensions.y)
	paint.image(image, pos)
	paint.label(caption, Rect2(pos + Vector2((dimensions.x - 208) / 2, 16), Vector2(208, 38)), 24, Color("f7f4b9"), "center", "middle", 1, 1, "", "h_noti")

func notice(id: String) -> void:
	view._dim()
	var notification: Dictionary = data.notifications[id]
	var power := id.begins_with("POWER_")
	var enemy := id.begins_with("enemy_")
	var paper: String = "notifications_newenemy" if power or enemy else notification.get("paper","notifications_newenemy")
	var dimensions := _size(paper)
	var dual_tower: bool = notification.get("layout", "") == "N_TOWER_2"
	_panel(id, Vector2(dimensions.x, dimensions.y * 2 + 34) if dual_tower else dimensions + Vector2(0, 48))
	if notification.get("layout", "") == "N_TOWER_2":
		# Include the title above the source cards in the viewport fitting bounds.
		paint.push(Vector2(0,64))
		for i in range(2):
			var y := i * (dimensions.y - 30)
			paint.image(paper,Vector2(0,y))
			paint.push(Vector2(134,160 + y),1,1,PI / 24)
			paint.image(notification.images[i],Vector2.ZERO,Vector2(0.5,0.5))
			paint.image("notifications_polaroid_overlay",Vector2.ZERO,Vector2(0.5,0.5))
			paint.pop()
			paint.label(text(notification.subs[i]),Rect2(257,70 + y,320,20),15,Color("181a0f"),"left","top")
			paint.label(text(notification.prefixes[i] + "_NAME"),Rect2(255,90 + y,320,40),28,Color("181a0f"),"left","top",1,0,"","body_slides")
			paint.label(text(notification.prefixes[i] + "_EXTRA"),Rect2(255,130 + y,320,100),17,Color("181a0f"),"left","top")
		_title("notifications_tit_towers_bg","新防御塔",Vector2.ZERO,false)
		paint.button("notifications_but_dark_bg_0001",Vector2(450,dimensions.y * 2 - 70),"知道了","confirm",{},true,"notice")
		paint.pop()
	elif notification.get("layout", "") == "upgrade":
		var tier: String = "三级" if int(notification.get("tier", 2)) == 3 else "二级"
		_title("notifications_tit_towers_bg", tier + "防御塔", Vector2(80, 40), false)
		paint.image(paper)
		paint.label("现在可以升级防御塔！", Rect2(70, 45, 480, 40), 27, Color("181a0f"), "center", "middle")
		paint.label("选中已建造的防御塔，点击升级图标。升级会增强防御塔；金币不足时按钮不可用。", Rect2(65, 100, 500, 85), 20, Color("181a0f"), "left", "top")
		paint.label("本关四类防御塔均可升至" + tier + "。", Rect2(65, 195, 500, 40), 19, Color("181a0f"), "center", "middle")
		paint.button("notifications_but_dark_bg_0001", Vector2(400, 254), "知道了", "confirm", {}, true, "notice")
	elif enemy:
		_title("notifications_tit_newenemy_bg", "新敌人", Vector2(80, 40), false)
		paint.image(paper)
		var prefix := id.to_upper()
		paint.push(Vector2(134, 160), 1, 1, PI / 24)
		paint.image("encyclopedia_creeps_%04d" % int(view.sim.templates[id].info.enc_icon), Vector2.ZERO, Vector2(0.5, 0.5))
		paint.image("notifications_polaroid_overlay", Vector2.ZERO, Vector2(0.5, 0.5))
		paint.pop()
		paint.label(text(prefix + "_NAME"), Rect2(255, 50, 320, 36), 28, Color("181a0f"), "left", "top", 1, 0, "", "body_slides")
		paint.label(text(prefix + "_DESCRIPTION"), Rect2(255, 86, 320, 100), 19, Color("181a0f"), "left", "top")
		paint.label(text(prefix + "_EXTRA").replace("- ", "* "), Rect2(255, 187, 320, 90), 13, Color("921900"), "left", "top")
		paint.button("notifications_but_dark_bg_0001", Vector2(400, 254), "知道了", "confirm", {}, true, "notice")
	elif power:
		_title("notifications_tit_newpower_bg", text("NEW SPECIAL POWER!"), Vector2(80, 40), false)
		paint.image(paper)
		var image: String = notification.image
		paint.push(Vector2(134, 160), 1, 1, PI / 24)
		paint.image(image, Vector2.ZERO, Vector2(0.5, 0.5))
		paint.image("notifications_polaroid_overlay", Vector2.ZERO, Vector2(0.5, 0.5))
		paint.pop()
		paint.label(text(notification.prefix + "_NAME"), Rect2(255, 50, 320, 35), 28, Color("181a0f"), "left", "middle", 1, 0, "", "h_noti")
		var copy := text(notification.prefix + "_LARGE_DESCRIPTION")
		copy = copy.replace("%$T('power_reinforcements_control').cooldown%$", str(int(view.sim.templates.power_reinforcements_control.cooldown)))
		paint.label(copy, Rect2(255, 85, 320, 130), 17, Color("181a0f"), "left", "top")
		paint.button("notifications_but_dark_bg_0001", Vector2(475, 254) - Vector2(_size("notifications_but_dark_bg_0001").x / 2, 0), "知道了", "confirm", {}, true, "notice")
	else:
		var tutorial := id.begins_with("TUTORIAL_")
		_title("tutorial_tit_instructions_bg" if tutorial else "notifications_tit_generics_bg_0001", text("INSTRUCTIONS" if tutorial else "HINT"), Vector2(dimensions.x / 2, 32))
		paint.image(paper)
		for definition: Dictionary in data.slides[id]: paint.source_label(definition, strings)
		if tutorial and notification.has("next"):
			var button_size := _size("notifications_but_lightblue_bg_0001")
			paint.button("notifications_but_lightblue_bg_0001", Vector2(dimensions.x / 2 - 20 - button_size.x, dimensions.y - 30), "跳过说明", "skip_tutorial", {}, true, "notice")
			paint.button("notifications_but_lightblue_bg_0001", Vector2(dimensions.x / 2 + 20, dimensions.y - 30), "下一页", "confirm", {}, true, "notice")
		elif tutorial:
			var button_size := _size("tutorial_but_gotcha_bg_long_0001")
			var pos := Vector2((dimensions.x - button_size.x) / 2, dimensions.y - 24)
			paint.button("tutorial_but_gotcha_bg_long_0001", pos, "知道了！", "confirm", {}, true, "gotcha")
			paint.label(text("I'm ready. Now bring it on!"), Rect2(pos + Vector2(15, 26), Vector2(button_size.x - 30, 20)), 12, Color("fffec8"), "center", "middle", 1, 1)
		else: paint.button("notifications_but_lightblue_bg_0001", Vector2(300, 360), "知道了", "confirm", {}, true, "notice")
	_end_panel()

func pause() -> void:
	view._dim()
	var dimensions := _size("options_bg_notxt")
	_panel("pause", dimensions, 1.15, 0.25)
	paint.image("options_bg_notxt")
	paint.label("游戏暂停", Rect2(172, 28, 170, 32), 24, Color("fafafa"), "center", "middle", 1, 2, "", "h_popup")
	var settings: Node = view.get_parent().settings
	_volume("音效", 100, "sfx", settings.sfx_volume, 4)
	_volume("音乐", 184, "music", settings.music_volume, 1)
	var button_size := _size("options_button_bg_0001")
	for item in [[view.return_label, "map", 45 + button_size.x / 2], ["重新开始", "restart", ceil(dimensions.x / 2)], ["继续战斗", "pause", dimensions.x - 45 - button_size.x / 2]]:
		paint.button("options_button_bg_0001", Vector2(item[2] - button_size.x / 2, 338 - button_size.y / 2), item[0], item[1])
	_end_panel()

func _volume(caption: String, y: float, bus: String, value: float, index: int) -> void:
	paint.label(caption, Rect2(0, y, _size("options_bg_notxt").x, 28), 20, Color("e9e9b2"), "center", "middle", 1, 1, "", "h_noti")
	var at := Vector2(100, y + 34)
	var track := _size("options_barBg")
	var fill := _size("options_bar")
	var offset := Vector2(track.x * 0.0266666667, track.y / 3)
	paint.image("options_barBg", at)
	paint.image("options_bar", at + offset, Vector2.ZERO, Color.WHITE, Vector2(value, 1))
	paint.image("options_sounds_%04d" % index, at + Vector2(offset.x + fill.x * value, track.y / 2), Vector2(0.5, 0.5))
	paint.hit(Rect2(at, track).grow(12), "volume", {"bus": bus, "track": paint.region(Rect2(at + offset, fill))})

func result() -> void:
	view._dim()
	if view.sim.result == "victory":
		var dimensions := _size("victoryBadges_notxt_0002")
		_panel("victory", Vector2(dimensions.x, 480), 1.15)
		paint.image("victoryBadges_notxt_0002")
		paint.label("胜 利", Rect2(dimensions.x / 2 - 160, 165, 320, 78), 64, Color("4c3817"), "center", "middle", 1, 0, "", "h_popup")
		var stars: int = view.outcome.get("stars", 1)
		var end_frame: int = [19, 38, 54][stars - 1]
		var elapsed: float = clock() - panel_at - view.VICTORY_STAR_DELAY
		var frame := mini(int(maxf(0, elapsed) * 30), end_frame)
		if elapsed >= 0:
			paint.image("victoryStars_%04d" % maxi(1, frame), Vector2(dimensions.x / 2, 230), Vector2(0.5, 0))
		paint.label(("调试局 · " if view.sim.developer_used else "") + "生命 %d · 击杀 %d · %d/%d 波" % [view.sim.lives, view.sim.kills, view.sim.wave, view.sim.data.waves.groups.size()], Rect2(60, 347, dimensions.x - 120, 28), 17, Color("ffe9b0"), "center", "middle", 1, 1)
		var button := _size("button_border_large_0001")
		paint.button("button_border_large_0001", Vector2((dimensions.x - button.x) / 2, 389), view.return_label, "map")
		paint.push(Vector2(dimensions.x / 2, 448), 0.85)
		paint.button("button_border_0001", Vector2(-_size("button_border_0001").x / 2, 0), "重新开始", "restart")
		paint.pop()
	else:
		_panel("defeat", Vector2(455, 384), 1.25)
		paint.image("defeat_bg_notxt")
		paint.label("防线失守", Rect2(160, 81, 140, 32), 24, Color.WHITE, "center", "middle", 1, 2, "", "h_popup")
		paint.label("生命已经耗尽\n调整防御塔搭配，再试一次。", Rect2(104, 155, 246, 90), 15, Color.WHITE, "center", "middle", 3, 1)
		var dimensions := _size("options_button_bg_0001")
		paint.button("options_button_bg_0001", Vector2(84, 266), "重新开始", "restart")
		paint.button("options_button_bg_0001", Vector2(455 - 84 - dimensions.x, 266), view.return_label, "map")
	_end_panel()

func confirmed(id: String) -> void:
	panel_id = ""
	if id == "POWER_REINFORCEMENT" or id == "POWER_FIREBALL":
		power_hint = "TB_POWER2" if id == "POWER_REINFORCEMENT" else "TB_POWER1"; power_hint_hidden = false

func reset() -> void:
	selection_id = ""; closing_id = ""; panel_id = ""; power_mode.clear(); power_at.clear(); power_animation.clear(); power_hint = ""
	wave_flags.reset()
	reward_fx.clear()
