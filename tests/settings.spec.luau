--!strict
local Cfg = require("../src/shared/Config/Settings")
local Foliage = require("../src/shared/Config/Foliage")
local Camera = require("../src/shared/Config/Camera")
local R = require("../src/shared/Rules/Settings")
local Palette = require("../src/shared/Config/Palette")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local O = Cfg.Options :: any

local function getter(t: { [string]: any }): (string) -> any
	return function(k)
		return t[k]
	end
end

local function defaults(touch: boolean): { [string]: any }
	local t = {}
	for k, opt in O do
		t[k] = R.default(opt, touch)
	end
	return t
end

return {
	["every option's defaults are valid"] = function()
		for key, opt in O do
			assert(R.valid(opt, opt.default, Cfg.MaxKeyName), key)
			if opt.defaultTouch ~= nil then
				assert(R.valid(opt, opt.defaultTouch, Cfg.MaxKeyName), key .. " (touch)")
			end
			assert(type(opt.label) == "string", key .. " needs a label")
		end
	end,
	["every tab row is an option or the preset row, and every option is on a tab once"] = function()
		local seen = {}
		for _, tab in Cfg.Tabs do
			for _, row in tab.rows do
				assert(row == "Preset" or O[row], "unknown row " .. row)
				assert(not seen[row], row .. " is on two tabs")
				seen[row] = true
			end
		end
		for key in O do
			assert(seen[key], key .. " is on no tab")
		end
	end,
	["grass values are the foliage levels"] = function()
		for _, v in O.GrassQuality.values do
			assert(Foliage.Levels[v], v)
		end
	end,
	["sliders: snapped to the step, clamped, defaults on the grid"] = function()
		local s = O.HipSensitivity
		assert(R.snap(s, 1.02) == 1)
		assert(R.snap(s, 1.03) == 1.05)
		assert(R.snap(s, -5) == s.min and R.snap(s, 99) == s.max)
		assert(R.fromShare(s, 0) == s.min and R.fromShare(s, 1) == s.max and R.fromShare(s, 2) == s.max)
		assert(math.abs(R.share(s, R.fromShare(s, 0.5)) - 0.5) < 0.02)
		assert(R.valid(s, 1.05, Cfg.MaxKeyName) and not R.valid(s, 1.07, Cfg.MaxKeyName))
		assert(not R.valid(s, 0 / 0, Cfg.MaxKeyName), "NaN")
		assert(not R.valid(s, "1", Cfg.MaxKeyName))
		assert(O.FieldOfView.default == Camera.Fov, "the default field of view is the camera's")
		assert(R.format(O.FieldOfView, 70) == "70" and R.format(O.MasterVolume, 55) == "55%")
		assert(R.format(O.HipSensitivity, 1) == "1.00x")
	end,
	["choices and keys: only listed values, only plain key names"] = function()
		assert(R.valid(O.Shadows, "On", Cfg.MaxKeyName) and not R.valid(O.Shadows, "Maybe", Cfg.MaxKeyName))
		assert(R.valid(O.Key_Fire, "MouseButton1", Cfg.MaxKeyName) and R.valid(O.Key_Fire, "F", Cfg.MaxKeyName))
		assert(not R.valid(O.Key_Fire, "", Cfg.MaxKeyName) and not R.valid(O.Key_Fire, "a b", Cfg.MaxKeyName))
		assert(not R.valid(O.Key_Fire, string.rep("A", 33), Cfg.MaxKeyName))
		assert(not R.valid(nil, "On", Cfg.MaxKeyName), "unknown option")
	end,
	["clean keeps only valid entries and never errors"] = function()
		local c =
			R.clean(O, { Shadows = "Off", Debris = "Huge", FieldOfView = 85, Nope = 1, Key_Aim = 5 }, Cfg.MaxKeyName)
		assert(c.Shadows == "Off" and c.FieldOfView == 85)
		assert(O.FieldOfView.max == 90, "the field of view tops out at 90")
		assert(R.clean(O, { FieldOfView = 100 }, Cfg.MaxKeyName).FieldOfView == 90, "a saved wider view loads as 90")
		assert(R.clean(O, { FieldOfView = -3 }, Cfg.MaxKeyName).FieldOfView == O.FieldOfView.min)
		assert(R.clean(O, { FieldOfView = 0 / 0 }, Cfg.MaxKeyName).FieldOfView == nil, "NaN")
		assert(R.clean(O, { FieldOfView = math.huge }, Cfg.MaxKeyName).FieldOfView == nil)
		assert(c.Debris == nil and c.Nope == nil and c.Key_Aim == nil)
		assert(next(R.clean(O, "junk", Cfg.MaxKeyName)) == nil)
		local dup = R.clean(O, { Key_Fire = "F", Key_Reload = "F", Key_Aim = "J" }, Cfg.MaxKeyName)
		assert(dup.Key_Fire == nil and dup.Key_Reload == nil and dup.Key_Aim == "J", "a key bound twice is dropped")
		-- a save from before a keybind moved: its old key now another's default (user 2026-10-27: "Q is still exit")
		local old = R.clean(O, { Key_BuildExit = "Q", Key_Build = "B", Key_Aim = "J" }, Cfg.MaxKeyName)
		assert(old.Key_BuildExit == nil and old.Key_Build == "B" and old.Key_Aim == "J")
		assert(O.Key_BuildExit.default == "X" and O.Key_BuildPrev.default == "Q" and O.Key_BuildNext.default == "E")
		-- a key you chose that no other keybind takes by default stays
		assert(R.clean(O, { Key_BuildExit = "Z" }, Cfg.MaxKeyName).Key_BuildExit == "Z")
		assert(next(R.clean(O, nil, Cfg.MaxKeyName)) == nil)
	end,
	["presets: valid values, defaults are Normal, touch defaults are Low, a mix is Custom"] = function()
		for _, name in Cfg.PresetOrder do
			for key, v in Cfg.Presets[name] do
				assert(R.valid(O[key], v, Cfg.MaxKeyName), name .. "." .. key)
			end
		end
		assert(R.preset(Cfg.Presets, Cfg.PresetOrder, getter(defaults(false))) == "Normal")
		assert(R.preset(Cfg.Presets, Cfg.PresetOrder, getter(defaults(true))) == "Low")
		local mixed = defaults(false)
		mixed.Shadows = "Off"
		assert(R.preset(Cfg.Presets, Cfg.PresetOrder, getter(mixed)) == "Custom")
	end,
	["rebinding a key in use swaps; no key is bound twice"] = function()
		local t = defaults(false)
		local changes = R.rebind(O, getter(t), "Key_Reload", "C") -- C is crouch
		assert(changes.Key_Reload == "C" and changes.Key_Crouch == "R")
		for k, v in changes do
			t[k] = v
		end
		local used = {}
		for k, opt in O do
			if opt.kind == "key" then
				assert(not used[t[k]], t[k] .. " bound twice")
				used[t[k]] = true
			end
		end
		assert(next(R.rebind(O, getter(t), "Key_Reload", "C")) == nil, "the same key: no change")
		local free = R.rebind(O, getter(t), "Key_Reload", "F")
		assert(free.Key_Reload == "F" and free.Key_Crouch == nil)
	end,
	["default keybinds are all different"] = function()
		local used = {}
		for k, opt in O do
			if opt.kind == "key" then
				assert(not used[opt.default], k .. " shares its default key")
				used[opt.default] = true
			end
		end
	end,
	["aimed fov keeps the defaults' ratio; look and volume scale"] = function()
		assert(R.aimFov(Camera.Fov, Camera.Fov, Camera.AimFov) == Camera.AimFov)
		assert(R.aimFov(Camera.Fov * 1.2, Camera.Fov, Camera.AimFov) > Camera.AimFov)
		local x, y = R.look(0.4, 2, false)
		assert(x == 0.8 and y == 0.8)
		local _, yi = R.look(0.4, 1, true)
		assert(yi == -0.4)
		assert(R.volume(100, 100) == 1 and R.volume(50, 50) == 0.25 and R.volume(0, 100) == 0)
	end,
	["debris levels: Medium is the base, lower is less, the cap never 0"] = function()
		local L = Cfg.DebrisLevels
		for _, v in O.Debris.values do
			assert(L[v], v)
		end
		local live, life = R.debris(L.Medium, 600, 60)
		assert(live == 600 and life == 60)
		local lowLive, lowLife = R.debris(L.Low, 600, 60)
		assert(lowLive < live and lowLife < life)
		assert(R.debris(L.Low, 1, 60) == 1)
	end,
	["saving numbers are sane"] = function()
		assert(Cfg.SaveRate > 0 and Cfg.AutosaveEvery >= 6 and Cfg.SendDelay >= 1 / Cfg.SaveRate)
		assert(#Cfg.Store > 0 and #Cfg.Field > 0)
	end,
	["the menu spec has a row template for every kind in the tabs, and its colours exist"] = function()
		local spec = serde.decode("json", fs.readFile("src/shared/ui/SettingsMenu.json"))
		local ids, colors = {}, {}
		local function walk(n)
			ids[n.id] = n
			for _, key in { "color", "line", "textColor" } do
				if n[key] then
					table.insert(colors, n[key])
				end
			end
			for _, c in n.children or {} do
				walk(c)
			end
		end
		walk(spec.root)
		local KIND = { choice = "ChoiceRow", slider = "SliderRow", key = "KeyRow" }
		for _, tab in Cfg.Tabs do
			for _, key in tab.rows do
				local tpl = if key == "Preset" then "PresetRow" else KIND[O[key] and O[key].kind]
				assert(tpl and ids[tpl], `{tab.name}.{key}: no row template`)
			end
		end
		local own = spec.theme.palette
		local palette = (own and ((Palette.UI :: any).Grimoire[own] or (Palette.UI :: any)[own])) or Palette.UI.Settings
		for _, name in colors do
			assert(palette[name], `colour {name} not in the menu's palette`)
		end
		for name in spec.theme.fonts do
			assert(spec.theme.fonts[name].family, name)
		end
	end,
}
