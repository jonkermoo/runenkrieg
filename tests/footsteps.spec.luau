--!strict
local F = require("../src/shared/Config/Footsteps")

return {
	["footsteps have sounds"] = function()
		assert(#F.Sounds > 0, "no footstep sounds")
	end,
	["footsteps are subtle and low"] = function()
		assert(F.Volume <= 0.3 and F.SprintVolume >= F.Volume and F.SprintVolume <= 0.4, "footsteps should stay quiet")
		assert(F.Pitch < 1, "footsteps are pitched down (deeper)")
		assert(F.RollOffMax > F.RollOffMin, "roll-off range is inverted")
	end,
}
