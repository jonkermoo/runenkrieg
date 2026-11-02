--!strict
local Cfg = require("../src/shared/Config/Bots")
local Damage = require("../src/shared/Config/Damage")
local R = require("../src/shared/Rules/BotStaff")

local S = Cfg.Staff
local ranges = Damage.Staff.Range

local function shot(over: { [string]: any }): R.Shot
	local s: R.Shot = {
		distance = 60,
		visible = true,
		affordable = 3,
		group = 1,
		strong = false,
		mateOnLine = false,
		mateNearBlast = false,
	}
	for k, v in over do
		(s :: any)[k] = v
	end
	return s
end

return {
	["stage: a lone soldier in the open near gets a quick shot"] = function()
		assert(R.stage(shot({}), ranges, S) == 1)
	end,
	["stage: past the quick shot's range, or at cover, a medium shot"] = function()
		assert(R.stage(shot({ distance = ranges[1] + 10 }), ranges, S) == 2)
		assert(R.stage(shot({ visible = false }), ranges, S) == 2, "at cover")
		assert(R.stage(shot({ visible = false, affordable = 1 }), ranges, S) == 0, "no quick shot at cover")
		assert(R.stage(shot({ distance = ranges[2] + 10 }), ranges, S) == 0, "out of every range but the mega's")
	end,
	["stage: a mega shot only at groups and strongpoints, never near a teammate"] = function()
		assert(R.stage(shot({ group = S.megaGroup }), ranges, S) == 3)
		assert(R.stage(shot({ strong = true }), ranges, S) == 3)
		assert(R.stage(shot({ strong = true, mateNearBlast = true }), ranges, S) == 2, "a teammate near: medium")
		assert(R.stage(shot({ group = S.megaGroup, affordable = 2 }), ranges, S) == 2, "the mana pays for medium")
		assert(R.stage(shot({ strong = true, distance = ranges[2] + 10 }), ranges, S) == 3, "the mega reaches further")
	end,
	["stage: nothing with a teammate on the beam's line or no mana"] = function()
		assert(R.stage(shot({ mateOnLine = true }), ranges, S) == 0)
		assert(R.stage(shot({ affordable = 0 }), ranges, S) == 0)
	end,
	["mates: on the line, near the blast"] = function()
		local onLine, near = R.mates({ { x = 50, z = 2 } }, 0, 0, 100, 0, S.line, S.blast)
		assert(onLine and not near)
		onLine, near = R.mates({ { x = 110, z = 15 } }, 0, 0, 100, 0, S.line, S.blast)
		assert(not onLine and near)
		onLine, near = R.mates({ { x = -20, z = 0 } }, 0, 0, 100, 0, S.line, S.blast)
		assert(not onLine and not near, "behind the caster")
	end,
	["release: held long enough and the cooldown over"] = function()
		assert(R.release(1.1, 1.0, 0))
		assert(not R.release(0.9, 1.0, 0))
		assert(not R.release(3.1, 3.0, 0.2))
	end,
}
