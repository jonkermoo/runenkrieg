--!strict
local Cfg = require("../src/shared/Config/TeamHealth")
local HealCfg = require("../src/shared/Config/Healing")
local Settings = require("../src/shared/Config/Settings")
local Palette = require("../src/shared/Config/Palette")
local R = require("../src/shared/Rules/TeamHealth")

return {
	["a bar only over a living teammate in range"] = function()
		assert(R.shown(true, 50, Cfg.Range, Cfg.Range), "at the range")
		assert(not R.shown(true, 50, Cfg.Range + 0.1, Cfg.Range), "past it")
		assert(not R.shown(false, 50, 5, Cfg.Range), "never an enemy")
		assert(not R.shown(true, 0, 5, Cfg.Range), "never the dead")
	end,
	["down stands out, then a bandage's worth of hurt, else ok"] = function()
		local share, look = R.look(80, 100, true, HealCfg)
		assert(share == 0.8 and look == "Down", look)
		assert(select(2, R.look(HealCfg.MedPackFrom, 100, false, HealCfg)) == "Ok", "a med pack's worth is ok")
		assert(select(2, R.look(HealCfg.MedPackFrom - 1, 100, false, HealCfg)) == "Low", "a bandage's worth is low")
		assert(select(2, R.look(100, 100, false, HealCfg)) == "Ok", "full")
		assert(R.look(150, 100, false, HealCfg) == 1 and R.look(5, 0, false, HealCfg) == 0, "the fill stays in 0..1")
	end,
	["held on the map key, its colours there"] = function()
		assert(Settings.Options.Key_Map.default == "M", "M, as the map")
		assert(table.find(Settings.Tabs[4].rows, "Key_Map"), "in the keybinds tab")
		local H = Palette.UI.Hud
		for _, k in { "healthTrack", "healthOk", "healthLow", "healthDown", "healthEdge" } do
			assert(type(H[k]) == "table" and #H[k] == 3, k)
		end
	end,
}
