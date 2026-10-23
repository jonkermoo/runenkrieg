--!strict
local R = require("../src/shared/Rules/Dragging")
local Cfg = require("../src/shared/Config/Dragging")

local function state(over: { [string]: any }?): R.State
	local s: { [string]: any } = {
		same = false,
		team = true,
		draggerHealth = 100,
		draggerDown = false,
		draggerBusy = false,
		bodyHealth = 40,
		bodyDown = true,
		distance = 3,
	}
	for k, v in over or {} do
		s[k] = v
	end
	return s :: any
end

return {
	["a downed living teammate in reach can be dragged"] = function()
		assert(R.canStart(state(), Cfg))
		assert(R.keep(state(), Cfg))
	end,
	["never yourself, never an enemy"] = function()
		assert(not R.canStart(state({ same = true }), Cfg), "yourself")
		assert(not R.canStart(state({ team = false }), Cfg), "an enemy")
		assert(not R.keep(state({ team = false }), Cfg), "an enemy, going on")
	end,
	["only a body that is down and alive"] = function()
		assert(not R.canStart(state({ bodyDown = false }), Cfg), "standing")
		assert(not R.canStart(state({ bodyHealth = 0 }), Cfg), "dead")
		assert(not R.keep(state({ bodyHealth = 0 }), Cfg), "died while dragged: let go")
		assert(not R.keep(state({ bodyDown = false }), Cfg), "got up")
	end,
	["the dragger on their feet, alive, hands free"] = function()
		assert(not R.canStart(state({ draggerHealth = 0 }), Cfg), "dead")
		assert(not R.canStart(state({ draggerDown = true }), Cfg), "knocked down")
		assert(not R.canStart(state({ draggerBusy = true }), Cfg), "busy")
		assert(not R.keep(state({ draggerDown = true }), Cfg), "knocked down mid-drag: let go")
		assert(not R.keep(state({ draggerBusy = true }), Cfg), "weapon drawn or heal started: let go")
	end,
	["reach: Range to start (slack for lag), Break to go on"] = function()
		assert(R.canStart(state({ distance = Cfg.Range }), Cfg))
		assert(not R.canStart(state({ distance = Cfg.Range + 0.1 }), Cfg))
		assert(R.canStart(state({ distance = Cfg.Range + Cfg.StartSlack }), Cfg, true))
		assert(not R.canStart(state({ distance = Cfg.Range + Cfg.StartSlack + 0.1 }), Cfg, true))
		assert(R.keep(state({ distance = Cfg.Break }), Cfg))
		assert(not R.keep(state({ distance = Cfg.Break + 0.1 }), Cfg), "caught on something")
		assert(not R.canStart(state({ distance = 0 / 0 }), Cfg), "NaN")
		assert(Cfg.Break > Cfg.Range + Cfg.StartSlack, "a fresh drag doesn't let go at once")
	end,
}
