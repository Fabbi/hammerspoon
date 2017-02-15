local eventtap = require "hs.eventtap"
local event = eventtap.event
local etype = event.types
local keycodes = require "hs.keycodes".map

local filter = require "hs.fnutils".filter
local concat = require "hs.fnutils".concat
local contains = require "hs.fnutils".contains

-- import this and call `init()` on it
local function diffTbl(t1, t2)
  -- returns t1 without elements of t2
  local function nc(e)
    return not contains(t2, e)
  end
  return filter(t1, nc)
end
local function mergeTbl(t1, t2)
  -- returns t1 with t2, no duplicates
  return concat(t1, diffTbl(t2, t1))
end

hr = {}
-- Keycodes not present in `keycodes` table:

-- application key = 110
-- r_cmd           = 54
-- l_cmd           = 55
-- l_shift         = 56
-- l_alt           = 58
-- l_ctrl          = 59
-- r_shift         = 60
-- r_alt           = 61
-- fn              = 63

hr.config = {
  activator = keycodes["space"],

  -- held keybindings can not have a key
  rebinds = {
    h = {only={modifier={}, key="left"}},
    j = {only={modifier={}, key="down"}},
    k = {only={modifier={}, key="up"}},
    l = {only={modifier={}, key="right"}},
    i = {only={modifier={}, key="f"}},

    a = {held={modifier={"shift"}},
         only={modifier={"ctrl"}, key="s"}}
  }
}

hr.state = {
  other_key_pressed = false,
  space_down = false,
  modifiers = {},
  down = {},
  key_pressed_since = {}
}

-- a shorter keystroke action then the predefined one
local function shortKeyStroke(k)
  -- do we need this?
  local mods = eventtap.checkKeyboardModifiers()
  hs.eventtap.event.newKeyEvent(mods, k, true):post()
  hs.timer.usleep(50000)
  hs.eventtap.event.newKeyEvent(mods, k, false):post()
end

local function handle_new_event(key, is_down_event)
  local function set_mods(from)
    if is_down_event then
      hr.state.modifiers = mergeTbl(hr.state.modifiers, from)
    else
      hr.state.modifiers = diffTbl(hr.state.modifiers, from)
    end
  end

  -- we already handled this one
  if is_down_event and hr.state.down[key] then return end

  local tbl = hr.config.rebinds[key]

  -- handle bindings with a "hold down action"
  if tbl.held then
    if is_down_event then hr.state.down[key]=true end

    set_mods(tbl.held.modifier)

    -- if it is an up event
    --   and no other key got pressed
    --     activate `only` binding`
    if (not is_down_event and
      not hr.state.key_pressed_since[key] and
      tbl.only) then
        local mods = tbl.only.modifier
        for _,k in ipairs(hr.state.modifiers) do
          mods[k] = true
        end
          hs.eventtap.keyStroke(mods, tbl.only.key)
    end
    return
  end

  -- only activate `down event` if there is no `held` binding
  if tbl.only then
    set_mods(tbl.only.modifier)
    return {hs.eventtap.event.newKeyEvent(hr.state.modifiers, tbl.only.key, is_down_event)}
  end
end


-- this function takes an Event
-- and returns: <discard original event?>, <Events to post>
hr.process_key_event = function (evt)
  local is_down_event = evt:getType() == etype.keyDown
  local kc = evt:getKeyCode()

  -- handle the modifier
  if kc == hr.config.activator then
    -- down event
    if is_down_event then
      hr.state.other_key_pressed = false
      hr.state.space_down = true
      return true,{}

    -- up event
    else
      hr.state.space_down=false
      hr.state.modifiers={}
      hr.state.down={}
      -- we did not press any other key, so send `space`
      if not hr.state.other_key_pressed then
        hr.eventtap:stop() -- else we start a loop
        shortKeyStroke("space")
        hr.eventtap:start()
      end
      return true,{}
    end -- is_down_event

  -- handle other keys
  else
    -- if we are not in `home-row-mode` keep the events
    if not hr.state.space_down then
      return false, evt
    end

    -- set key pressed since down-events for every handled key
    if is_down_event then
      -- only set other_key_pressed if it is a down event
      -- (to prevent <keydown> <space down> <keyup> <space up> to result in errors)
      hr.state.other_key_pressed = true
      for tk, tv in pairs(hr.state.down) do
        if tk ~= keycodes[kc] and tv then
          hr.state.key_pressed_since[tk] = true
        end
      end
    end

    -- now handle home row rebinds
    if hr.config.rebinds[keycodes[kc]] then
      local new_evt = handle_new_event(keycodes[kc], is_down_event)
      if not is_down_event then
        hr.state.down[keycodes[kc]] = false
        hr.state.key_pressed_since[keycodes[kc]] = false
      end
      if new_evt then
        return true, new_evt
      end
      return true, {}
    end

    -- should the default event have homerow modifiers?
    -- evt:setFlags(...)
    return false, evt
  end
end

function init_module()
  hr.eventtap = eventtap.new({etype.keyUp, etype.keyDown}, hr.process_key_event)
  -- hr.eventtap:start()
end

hr.init = init_module()

return home_row
