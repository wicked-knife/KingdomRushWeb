-- Execute pinned Dove eb_veznan, mod_veznan_tower, veznan_portal, veznan_souls_aura, veznan_soul and level12.fn_can_power.
return function(root, result, read, V, json, bit)
  local input = json.decode(assert(io.open(os.getenv('DOVE_PROJECT') .. '/output/level12_reference_input.json', 'rb')):read('*a'))
  result.provenance = input.provenance

  local function vectors(t)
    if type(t) ~= 'table' then return t end
    if t.x and t.y then return V.v(t.x, t.y) end
    local out = {}
    for k, v in pairs(t) do out[tonumber(k) or k] = vectors(v) end
    return out
  end
  local function template(name) return vectors(table.deepclone(assert(input.templates[name], name))) end

  -- 1. Evaluate level12.lua fn_can_power directly
  local l12_src = read('kr1/data/levels/level12.lua')
  local l12_env = setmetatable({
    require = function(mod)
      if mod == 'lib.klua.vector' then return V end
      if mod == 'all.constants' then return true end
      return {}
    end,
  }, {__index = _G})
  local l12_chunk = assert(loadstring(l12_src))
  setfenv(l12_chunk, l12_env)
  local l12_mod = l12_chunk()
  result.power_points = {}
  for _, pt in ipairs({{95, 318}, {150, 345}, {211, 375}, {94, 318}, {213, 345}, {150, 377}, {518, 677}}) do
    result.power_points[#result.power_points + 1] = {
      x = pt[1], y = pt[2],
      allowed = l12_mod:fn_can_power({}, 1, V.v(pt[1], pt[2])) and true or false,
    }
  end

  -- 2. Resolve eb_veznan difficulty-2 HP via all/difficulty.lua PT logic
  result.veznan_stats = {
    hp_difficulty_2 = input.templates.eb_veznan.health.hp_max[2],
    demon_hp_difficulty_2 = input.templates.eb_veznan.health.hp_max[2] * 1.5,
    magic_armor = input.templates.eb_veznan.health.magic_armor,
    speed_human = input.templates.eb_veznan.motion.max_speed,
    speed_demon = input.templates.eb_veznan.demon.speed,
    demon_hit_times_ticks = {},
  }
  for _, ht in ipairs(input.templates.eb_veznan.melee.attacks[2].hit_times) do
    result.veznan_stats.demon_hit_times_ticks[#result.veznan_stats.demon_hit_times_ticks + 1] = math.floor(ht * 30 + 0.5)
  end

  -- 3. Common runtime harness for boss_scripts.lua coroutines
  local tick, store, events, inserted, removed, next_id = 0, nil, {}, {}, {}, 100
  local U, SU, LU, P, E = {}, {}, {}, {}, {}
  local scripts = {eb_veznan = {}, mod_veznan_tower = {}, veznan_souls_aura = {}, veznan_soul = {}}
  local S = {
    queue = function(_, id) if id then events[#events + 1] = {'sound', tick, id} end end,
    stop_all = function() events[#events + 1] = {'stop_all', tick} end,
  }
  local signal = {
    emit = function(name) events[#events + 1] = {'signal', tick, name} end,
  }
  local env = setmetatable({
    U = U, SU = SU, LU = LU, P = P, E = E, S = S, V = V, signal = signal, scripts = scripts,
    band = bit.band, bor = bit.bor, bnot = bit.bnot, fts = function(n) return n / 30 end,
    v = V.v,
    simulation = {
      queue_insert_entity = function(_, e)
        inserted[#inserted + 1] = {tick = tick, entity = e}
        store.entities[e.id] = e
      end,
      queue_remove_entity = function(_, e)
        removed[#removed + 1] = {tick, e.template_name or '', e.id}
        store.entities[e.id] = nil
      end,
    },
    queue_damage = function(_, d)
      events[#events + 1] = {'damage', tick, d.target_id, d.damage_type, d.value}
    end,
    _ = function(key) return input.ui.strings[key] or key end,
  }, {__index = _G})

  -- Deterministic math.random for reproducible oracle sampling
  local fixed_random_roll = 0.25
  env.math = setmetatable({
    random = function(lo, hi)
      if not lo then return fixed_random_roll end
      if not hi then return math.min(lo, math.max(1, math.floor(fixed_random_roll * lo) + 1)) end
      return lo
    end,
  }, {__index = math})

  local function load_fn(path, name)
    local body = assert(read(path):match('function ' .. name:gsub('%.', '%%.') .. '%((.-)\nend'), name)
    local chunk = assert(loadstring('function ' .. name .. '(' .. body .. '\nend'))
    setfenv(chunk, env)
    chunk()
  end

  function E:create_entity(name)
    local t = template(name)
    next_id = next_id + 1
    t.id = next_id
    t.pos = V.v(0, 0)
    if t.enemy then t.nav_path = {pi = 1, spi = 1, ni = 1} end
    if t.modifier then t.modifier.target_id = nil; t.modifier.source_id = nil end
    if t.tween then t.tween.ts = 0 end
    return t
  end
  function E.assign_damage(dtype, value, source_id, target_id)
    return {damage_type = dtype, value = value, source_id = source_id, target_id = target_id}
  end

  U.fts = function(n) return n / 30 end
  U.animation_start = function(this, name, flip, ts, loop, idx)
    local s = this.render.sprites[idx or 1]
    s.name = name; s.ts = ts; s.loop = loop
    if flip ~= nil then s.flip_x = flip end
    events[#events + 1] = {'anim', tick, this.template_name, s.prefix and (s.prefix .. '_' .. name) or name, loop and true or false}
  end
  U.animation_start_default = function(this, name, flip, ts, loop) U.animation_start(this, name, flip, ts, loop, 1) end
  U.animation_finished = function(this, idx)
    local s = this.render.sprites[idx or 1]
    local key = s.prefix and (s.prefix .. '_' .. s.name) or s.name
    local a = assert(input.animations[key], 'missing anim ' .. tostring(key))
    return math.floor((store.tick_ts - s.ts) * 30 + 0.5) >= #a.frames
  end
  U.animation_finished_default = function(this) return U.animation_finished(this, 1) end
  U.y_animation_wait_default = function(this) while not U.animation_finished_default(this) do coroutine.yield() end end
  U.y_animation_play = function(this, name, flip, ts, runs, idx)
    U.animation_start(this, name, flip, ts, false, idx or 1)
    while not U.animation_finished(this, idx or 1) do coroutine.yield() end
  end
  U.y_wait_unconditional = function(st, seconds)
    local start = st.tick_ts
    while st.tick_ts - start < seconds - 1e-6 do coroutine.yield() end
  end
  U.y_wait_conditional = function(st, seconds, cond)
    local start = st.tick_ts
    while st.tick_ts - start < seconds - 1e-6 do
      if cond and cond(st, st.tick_ts - start) then return true end
      coroutine.yield()
    end
    return false
  end
  U.enemy_ready_to_magic_attack = function(this, st, a)
    return not a.disabled and (st.tick_ts - (a.ts or 0) > a.cooldown) and (this.enemy.can_do_magic ~= false)
  end
  env.enemy_ready_to_magic_attack = U.enemy_ready_to_magic_attack
  U.has_modifiers = function(st, target, mod_name)
    for _, e in pairs(st.entities) do
      if e.modifier and e.template_name == mod_name and e.modifier.target_id == target.id then return true end
    end
    return false
  end
  U.is_inside_ellipse = function(a, b, r)
    local dx, dy = a.x - b.x, (a.y - b.y) / 0.7
    return dx * dx + dy * dy <= r * r
  end
  U.find_soldiers_in_range = function(soldiers, origin, min_r, max_r, flags, bans, filter_fn)
    local out = {}
    for _, s in ipairs(soldiers or {}) do
      if not s.pending_removal and s.health and not s.health.dead and U.is_inside_ellipse(s.pos, origin, max_r)
         and (not filter_fn or filter_fn(s)) then
        out[#out + 1] = s
      end
    end
    return #out > 0 and out or nil
  end
  U.heal = function(this, amount)
    local before = this.health.hp
    this.health.hp = math.min(this.health.hp_max, this.health.hp + amount)
    events[#events + 1] = {'heal', tick, this.health.hp - before, this.health.hp}
  end
  U.predict_damage = function(this, damage) return damage.value end
  U.bans_add = function(vis, mask) vis.bans = bit.bor(vis.bans or 0, mask) end
  U.bans_remove = function(vis, mask) vis.bans = bit.band(vis.bans or 0, bit.bnot(mask)) end
  U.update_max_speed = function(this, speed) this.motion.max_speed = speed end
  U.change_health_bar_offset_run_time = function(hb, y) hb.offset = V.v(hb.offset.x, y) end
  U.frandom = function(a, b) return a + (b - a) * fixed_random_roll end
  SU.delay_attack = function(st, a, d) a.ts = st.tick_ts - a.cooldown + d end
  SU.remove_modifiers = function() events[#events + 1] = {'remove_modifiers', tick} end
  SU.tower_block_inc = function(t) t.tower.block_count = (t.tower.block_count or 0) + 1; t.tower.blocked = true; events[#events + 1] = {'tower_block', tick, t.id, t.tower.block_count} end
  SU.tower_block_dec = function(t) t.tower.block_count = math.max(0, (t.tower.block_count or 1) - 1); t.tower.blocked = t.tower.block_count > 0; events[#events + 1] = {'tower_block', tick, t.id, t.tower.block_count} end
  SU.ui_click_proxy_add = function(t, m) events[#events + 1] = {'proxy_add', tick, t.id} end
  SU.ui_click_proxy_remove = function(t, m) events[#events + 1] = {'proxy_remove', tick, t.id} end
  SU.y_show_taunt_set = function(st, taunts, set_name, idx, pos, duration, wait)
    local set = taunts.sets[set_name]
    local chosen = idx or set.start_idx or 1
    local dur = duration or taunts.duration or 4
    events[#events + 1] = {'taunt', tick, set_name, chosen, string.format(set.format, chosen), dur}
    if wait then U.y_wait_unconditional(st, dur) end
  end
  SU.y_enemy_mixed_walk_melee_ranged = function(st, this, _, brk)
    if brk and brk() then return false end
    coroutine.yield()
    return true
  end
  LU.list_entities = function(entities, name)
    local out = {}
    for _, e in pairs(entities) do if e.template_name == name then out[#out + 1] = e end end
    return out
  end
  LU.kill_all_enemies = function() events[#events + 1] = {'kill_all_enemies', tick} end
  P.node_pos = function(_, pi, spi, ni)
    local pt = input.paths.paths[pi][spi][ni]
    return V.v(pt.x, pt.y)
  end

  load_fn('kr1/boss_scripts.lua', 'scripts.eb_veznan.on_damage')
  load_fn('kr1/boss_scripts.lua', 'scripts.eb_veznan.update')
  load_fn('kr1/boss_scripts.lua', 'scripts.mod_veznan_tower.update')
  load_fn('kr1/boss_scripts.lua', 'scripts.veznan_souls_aura.update')
  load_fn('kr1/boss_scripts.lua', 'scripts.veznan_soul.update')

  local function step_co(co, n)
    tick = n
    store.tick_ts = n / 30
    if coroutine.status(co) ~= 'dead' then
      local ok, err = coroutine.resume(co)
      assert(ok, err)
    end
  end

  -- 4. Scenario A & B: mod_veznan_tower (early release by 3 clicks vs timeout full trap)
  result.tower_locks = {}
  for _, mode in ipairs({'clicked_release', 'timeout_trap'}) do
    events, inserted, removed, next_id = {}, {}, {}, 100
    local tower = {id = 50, pos = V.v(400, 300), tower = {can_be_mod = true, block_count = 0, blocked = false}}
    local mod = E:create_entity('mod_veznan_tower')
    mod.modifier.target_id = 50
    store = {tick_ts = 0, tick_length = 1 / 30, entities = {[50] = tower, [mod.id] = mod}}
    local co = coroutine.create(function() scripts.mod_veznan_tower.update(mod, store) end)
    local done_tick = -1
    for n = 0, 500 do
      if mode == 'clicked_release' and (n == 40 or n == 55 or n == 70) then
        mod.ui.clicked = true
      end
      step_co(co, n)
      if coroutine.status(co) == 'dead' then done_tick = n; break end
    end
    result.tower_locks[mode] = {done_tick = done_tick, events = events, removed = removed}
  end

  -- 5. Scenario C: veznan_portal_update (portal 1, 2, 3)
  local raw_portals = {}
  local p_env = setmetatable({
    simulation = env.simulation,
    require = function(m)
      if m == 'entity_db' then
        return {
          register_t = function(_, name)
            local t = {template_name = name, render = {sprites = {{}}}, main_script = {}}
            raw_portals[name] = t
            return t
          end,
          add_comps = function() end,
          create_entity = function(_, name) return E:create_entity(name) end,
        }
      end
      if m == 'utils' then return U end
      if m == 'lib.klua.vector' then return V end
      if m == 'all.constants' then return true end
      if m == 'lib.klua.table' then return true end
      return {}
    end,
    vec_2 = V.v,
    Z_DECALS = 1400,
    math = env.math,
  }, {__index = _G})
  local p_chunk = assert(loadstring(read('kr1/template_groups/level12_templates.lua')))
  setfenv(p_chunk, p_env)
  p_chunk()
  local portal_fn = assert(raw_portals.veznan_portal.main_script.update)
  result.portals = {}
  for pidx, roll in ipairs({0.25, 0.70, 0.95}) do
    fixed_random_roll = roll
    events, inserted, removed, next_id = {}, {}, {}, 100
    local portal = template('veznan_portal')
    portal.id = 60 + pidx
    portal.portal_idx = pidx
    portal.out_nodes = {pidx == 1 and 101 or (pidx == 2 and 146 or 221)}
    portal.pos = V.v(520, pidx == 1 and 453 or (pidx == 2 and 300 or 137))
    store = {tick_ts = 0, tick_length = 1 / 30, entities = {[portal.id] = portal}}
    local co = coroutine.create(function() portal_fn(portal, store) end)
    local finished_tick = -1
    for n = 0, 350 do
      if n == 5 then portal.spawn_signal = true end
      step_co(co, n)
      if n > 5 and not portal.spawn_signal then finished_tick = n; break end
    end
    local births = {}
    for _, r in ipairs(inserted) do
      births[#births + 1] = {r.tick, r.entity.template_name, r.entity.nav_path.pi - 1, r.entity.nav_path.ni - 1, r.entity.pos.x, r.entity.pos.y}
    end
    result.portals['portal_' .. pidx] = {roll = roll, finished_tick = finished_tick, births = births, events = events}
  end
  fixed_random_roll = 0.25

  -- 6. Scenario D: veznan_souls_aura + veznan_soul
  events, inserted, removed, next_id = {}, {}, {}, 100
  local aura = E:create_entity('veznan_souls_aura')
  aura.pos = V.v(500, 314)
  store = {tick_ts = 0, tick_length = 1 / 30, entities = {[aura.id] = aura}}
  local aura_co = coroutine.create(function() scripts.veznan_souls_aura.update(aura, store) end)
  for n = 0, 120 do
    if n == 90 then aura.interrupt = true end
    step_co(aura_co, n)
  end
  local soul_ticks = {}
  for _, r in ipairs(inserted) do
    soul_ticks[#soul_ticks + 1] = {r.tick, r.entity.template_name, r.entity.soul_phase}
  end
  result.souls_aura = {count_before_interrupt = #soul_ticks, spawns = soul_ticks}

  -- 7. Scenario E: eb_veznan full lifecycle (welcome -> castle -> pre_battle -> battle + soul_drain -> demon -> death -> death-end)
  events, inserted, removed, next_id = {}, {}, {}, 100
  local v_ent = template('eb_veznan')
  v_ent.id = 1
  v_ent.pos = V.vclone(v_ent.pos_castle)
  v_ent.nav_path = {pi = 1, spi = 1, ni = 1}
  v_ent.health.hp_max = v_ent.health.hp_max[2]
  v_ent.health.hp = v_ent.health.hp_max
  v_ent.health.dead = false
  v_ent.health_bar.frames = {{bar_width = 30, scale = {x = 1, y = 1}}, {bar_width = 30, scale = {x = 1, y = 1}}}
  v_ent.unit.is_stunned = false
  v_ent.enemy.can_do_magic = true

  local s_militia = {id = 20, template_name = 'soldier_militia', pos = V.v(560, 400), health = {hp = 100, hp_max = 100, dead = false}, unit = {mod_offset = V.v(0, 10)}}
  local s_elem = {id = 21, template_name = 'soldier_elemental', pos = V.v(565, 400), health = {hp = 500, hp_max = 500, dead = false}, unit = {mod_offset = V.v(0, 10)}}
  local t1 = {id = 30, pos = V.v(436, 371), tower = {can_be_mod = true, block_count = 0, blocked = false}}
  local p1 = {id = 40, template_name = 'veznan_portal', portal_idx = 1, pos = V.v(520, 453), spawn_signal = false}

  store = {
    tick_ts = 0, tick_length = 1 / 30, wave_group_number = 0, lives = 20,
    entities = {[1] = v_ent, [20] = s_militia, [21] = s_elem, [30] = t1, [40] = p1},
    towers = {[30] = t1},
    soldiers = {s_militia, s_elem},
  }
  local co = coroutine.create(function() scripts.eb_veznan.update(v_ent, store) end)
  local phase_log = {}
  local last_phase = ''
  local battle_tick, demon_tick, death_tick, end_tick = -1, -1, -1, -1
  for n = 0, 2000 do
    if n == 30 then v_ent.phase_signal = 'welcome' end
    if n == 40 then store.wave_group_number = 1 end
    -- Trigger wave 9 in castle to verify block_towers & portal wave_data
    if n == 190 then store.wave_group_number = 9 end
    -- Trigger descend after castle checks
    if n == 650 then v_ent.phase_signal = 'descend' end
    -- Put militia & elemental in range during battle for soul_drain (after battle starts + >8s)
    if battle_tick >= 0 and n == battle_tick + 250 then
      s_militia.pos = V.v(v_ent.pos.x + 60, v_ent.pos.y)
      s_elem.pos = V.v(v_ent.pos.x + 70, v_ent.pos.y)
      v_ent.health.hp = v_ent.health.hp_max - 1000
    end
    -- Lethal hit in battle to trigger demon transform
    if battle_tick >= 0 and n == battle_tick + 310 then
      local allow = scripts.eb_veznan.on_damage(v_ent, store, {value = v_ent.health.hp + 100})
      events[#events + 1] = {'on_damage_battle', n, allow, v_ent.phase_signal and true or false}
    end
    -- Lethal hit in demon to trigger death
    if demon_tick >= 0 and n == demon_tick + 20 then
      local allow = scripts.eb_veznan.on_damage(v_ent, store, {value = v_ent.health.hp + 100})
      events[#events + 1] = {'on_damage_demon', n, allow, v_ent.phase_signal and true or false}
    end
    step_co(co, n)
    if (v_ent.phase or '') ~= last_phase then
      last_phase = v_ent.phase or ''
      phase_log[#phase_log + 1] = {
        tick = n, phase = last_phase, hp = v_ent.health.hp, hp_max = v_ent.health.hp_max,
        prefix = v_ent.render.sprites[1].prefix, speed = v_ent.motion.max_speed,
        bans = v_ent.vis.bans, ignore_damage = v_ent.health.ignore_damage and true or false,
      }
      if last_phase == 'battle' then battle_tick = n end
      if last_phase == 'demon' then demon_tick = n end
      if last_phase == 'death' then death_tick = n end
      if last_phase == 'death-end' then end_tick = n end
    end
    if coroutine.status(co) == 'dead' then break end
  end
  result.veznan_lifecycle = {
    phases = phase_log,
    battle_tick = battle_tick,
    demon_tick = demon_tick,
    death_tick = death_tick,
    end_tick = end_tick,
    events = events,
    removed = removed,
  }
end
