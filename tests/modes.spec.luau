--!strict
local Cfg = require("../src/shared/Config/Modes")
local R = require("../src/shared/Rules/Modes")

return {
	["the user's three modes: admin (the default), FFA, normal"] = function()
		assert(Cfg.Default == "Admin" and Cfg.Defs.Admin.ready, "the admin server is the default")
		assert(Cfg.Defs.FFA.ready and Cfg.Defs.FFA.map == "Playtest", "FFA runs on the playtest map")
		assert(Cfg.Defs.Normal.ready and Cfg.Defs.Normal.map == "Map1", "normal is the frontline push on Map 1")
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
		local stub = { Default = "Admin", Legacy = Cfg.Legacy, Defs = { Admin = { ready = true }, Soon = {} } }
		assert(R.initial(stub, "Soon", nil) == "Admin", "a mode not built yet isn't started")
		assert(R.initial(Cfg, "Normal", nil) == "Normal")
		assert(R.initial(Cfg, "Nope", false) == Cfg.Default and R.initial(Cfg, 5, "yes") == Cfg.Default)
	end,
	["only a ready mode that isn't live can be switched to"] = function()
		assert(R.switchable(Cfg, "FFA", "Admin") and R.switchable(Cfg, "Admin", "FFA"))
		assert(not R.switchable(Cfg, "FFA", "FFA"), "already live")
		assert(R.switchable(Cfg, "Normal", "Admin"))
		assert(not R.switchable({ Defs = { Soon = { ready = false } } }, "Soon", "Admin"), "not built yet")
		assert(not R.switchable(Cfg, "Nope", "Admin") and not R.switchable(Cfg, nil, "Admin"))
	end,
	["only the admin mode opens the admin panel to everyone (user 2026-10-27)"] = function()
		assert(R.openAdmin(Cfg, "Admin"))
		assert(not R.openAdmin(Cfg, "FFA") and not R.openAdmin(Cfg, "Normal"))
		assert(not R.openAdmin(Cfg, nil) and not R.openAdmin(Cfg, "Nope"))
	end,
	["the match clock moves by the admin's seconds, never into the past"] = function()
		assert(R.extend(100, 60, 50) == 160)
		assert(R.extend(100, -60, 50) == 50, "clamped to now")
		assert(R.extend(100, -30, 50) == 70)
	end,
	["only normal keeps teams, or any mode with the admin's test switch (user 2026-10-27)"] = function()
		assert(R.keptTeams(Cfg, "Normal", nil), "normal keeps teams")
		assert(not R.keptTeams(Cfg, "Admin", nil) and not R.keptTeams(Cfg, "FFA", false), "rolled each life")
		assert(R.keptTeams(Cfg, "Admin", true) and R.keptTeams(Cfg, "FFA", true), "the test switch")
		assert(not R.keptTeams(Cfg, nil, nil) and not R.keptTeams(Cfg, "Nope", "yes"))
	end,
	["FFA pays battle points several times over (user 2026-10-29), the other modes once"] = function()
		assert(R.earnBoost(Cfg, "FFA") > 1)
		assert(R.earnBoost(Cfg, "Admin") == 1 and R.earnBoost(Cfg, "Normal") == 1)
		assert(R.earnBoost(Cfg, nil) == 1 and R.earnBoost(Cfg, "Nope") == 1)
	end,
}
