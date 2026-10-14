--!strict
local Cfg = require("../src/shared/Config/Showcase")
local Dev = require("../src/shared/Config/DevTools")
local Loco = require("../src/shared/Config/Locomotion")
local Map1 = require("../src/shared/Config/Maps/Map1")
local T = require("../src/shared/Rules/DevTeleports")
local W = require("../src/shared/Config/Weapons")

return {
	["the showcase has a teleport in front of its first row"] = function()
		local d = T.find(Map1, Dev, "Showcase")
		assert(d and d.offMap and d.y, "Showcase teleport missing")
		assert(d.z > Cfg.Origin[3], "the viewer stands in front of the first row")
	end,
	["every showcased hold rides on a real movement cycle"] = function()
		for _, h in Cfg.Holds do
			assert((Loco.Animations :: any)[h.base], `{h.hold}: no cycle {h.base}`)
		end
		for _, name in Cfg.Movement do
			assert((Loco.Animations :: any)[name], `movement {name} missing from Config/Locomotion`)
		end
	end,
	["every weapon's holds and the actions' holds exist"] = function()
		for name, w in W do
			for _, h in Cfg.Holds do
				if h.once then
					assert((w.holds :: any)[h.over], `{name}: {h.hold} replays over a missing hold {h.over}`)
				end
			end
			for _, a in if w.ammo then Cfg.Actions else {} do -- the actions are a gun's
				assert((w.holds :: any)[a.over], `{name}: {a.action} plays over a missing hold {a.over}`)
			end
		end
	end,
}
