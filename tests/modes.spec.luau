--!strict
local Cfg = require("../src/shared/Config/Modes")
local R = require("../src/shared/Rules/Modes")

return {
	["the user's three modes: admin (the default), FFA, normal not built yet"] = function()
		assert(Cfg.Default == "Admin" and Cfg.Defs.Admin.ready, "the admin server is the default")
		assert(Cfg.Defs.FFA.ready and Cfg.Defs.FFA.map == "Playtest", "FFA runs on the playtest map")
		assert(Cfg.Defs.Normal and not Cfg.Defs.Normal.ready, "normal is a stub")
		for _, key in Cfg.List do
			assert(Cfg.Defs[key], `listed mode {key} exists`)
		end
		assert(Cfg.Defs[Cfg.Legacy.mode].ready, "the legacy switch starts a ready mode")
	end,
	["a server starts in its saved mode, else FFA from the old switch, else the default"] = function()
		assert(R.initial(Cfg, "FFA", nil) == "FFA")
		assert(R.initial(Cfg, "Admin", true) == "Admin", "a saved mode wins over the old switch")
		assert(R.initial(Cfg, nil, true) == "FFA")
		assert(R.initial(Cfg, nil, nil) == Cfg.Default)
		assert(R.initial(Cfg, "Normal", nil) == Cfg.Default, "a mode not built yet isn't started")
		assert(R.initial(Cfg, "Nope", false) == Cfg.Default and R.initial(Cfg, 5, "yes") == Cfg.Default)
	end,
	["only a ready mode that isn't live can be switched to"] = function()
		assert(R.switchable(Cfg, "FFA", "Admin") and R.switchable(Cfg, "Admin", "FFA"))
		assert(not R.switchable(Cfg, "FFA", "FFA"), "already live")
		assert(not R.switchable(Cfg, "Normal", "Admin"), "not built yet")
		assert(not R.switchable(Cfg, "Nope", "Admin") and not R.switchable(Cfg, nil, "Admin"))
	end,
	["the match clock moves by the admin's seconds, never into the past"] = function()
		assert(R.extend(100, 60, 50) == 160)
		assert(R.extend(100, -60, 50) == 50, "clamped to now")
		assert(R.extend(100, -30, 50) == 70)
	end,
}
