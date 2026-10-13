--!strict
local Cfg = require("../src/shared/Config/Spells")
local Spells = require("../src/shared/Rules/Spells")

return {
	["stages: a tap is stage 1, longer holds reach later stages"] = function()
		assert(Spells.stage(Cfg.Stages, 0) == 1)
		assert(Spells.stage(Cfg.Stages, 0.1) == 1)
		assert(Spells.stage(Cfg.Stages, Cfg.Stages[2].hold) == 2)
		assert(Spells.stage(Cfg.Stages, Cfg.Stages[3].hold + 5) == 3)
	end,
	["stage holds rise and start at zero"] = function()
		assert(Cfg.Stages[1].hold == 0)
		for i = 2, #Cfg.Stages do
			assert(Cfg.Stages[i].hold > Cfg.Stages[i - 1].hold, `stage {i} holds no longer than {i - 1}`)
		end
	end,
	["an unbuilt stage fires the highest built one below it"] = function()
		local built = { Quick = true }
		assert(Spells.firing(Cfg.Stages, built, 0) == 1)
		assert(Spells.firing(Cfg.Stages, built, 99) == 1)
		assert(Spells.firing(Cfg.Stages, { Quick = true, Full = true }, 99) == 3)
		assert(Spells.firing(Cfg.Stages, {}, 0) == nil)
	end,
}
