--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/BotBuildings")

local I = Cfg.Indoors

local function spot(x: number, z: number, fx: number, fz: number, story: number?, taken: number?): R.Spot
	return { x = x, z = z, fx = fx, fz = fz, story = story or 0, taken = taken or 0 }
end

return {
	["pickHold: a free spot in the zone facing the enemy, upstairs first"] = function()
		local spots = {
			spot(0, 10, -1, 0), -- faces away from the enemy (east, +x)
			spot(5, 0, 1, 0), -- ground floor, facing east
			spot(6, 2, 1, 0, 1), -- upstairs, facing east
			spot(8, 0, 1, 0, 2, 1), -- taken
			spot(200, 0, 1, 0, 2), -- out of the zone
		}
		assert(R.pickHold(spots, 0, 0, 60, 1, 0, {}, I) == 3, "upstairs facing east")
		spots[3].taken = 1
		assert(R.pickHold(spots, 0, 0, 60, 1, 0, {}, I) == 2)
		spots[2].taken = 1
		assert(R.pickHold(spots, 0, 0, 60, 1, 0, {}, I) == nil, "none left facing the right way")
	end,
	["coverCandidates: nearest first, within reach, never toward the threat"] = function()
		-- the bot at the origin, the threat 50 east
		local spots = { spot(-10, 0, 0, 0), spot(5, 0, 0, 0), spot(30, 0, 0, 0), spot(-3, 2, 0, 0), spot(0, 40, 0, 0) }
		local got = R.coverCandidates(spots, 0, 0, 50, 0, 20, 2, 4)
		-- (5, 0) is 5 studs toward the threat (more than the 2 allowed), (30, 0) and (0, 40) out of reach
		assert(#got == 2 and got[1] == 4 and got[2] == 1, table.concat(got, ","))
		assert(#R.coverCandidates(spots, 0, 0, 50, 0, 20, 2, 1) == 1, "at most `count`")
	end,
	["inside: the spot by an enemy in a building"] = function()
		local spots = { spot(0, 0, 1, 0), spot(10, 0, 1, 0) }
		assert(R.inside(spots, 9, 1, I.clearWithin) == 2)
		assert(R.inside(spots, 40, 0, I.clearWithin) == nil, "out in the street")
	end,
	["waitForDoor: only at a shut door's link, and while it swings"] = function()
		assert(R.waitForDoor(true, 3, true, 99, I))
		assert(R.waitForDoor(true, 3, false, 0.2, I), "swinging")
		assert(not R.waitForDoor(true, 3, false, I.doorWait + 0.1, I), "open")
		assert(not R.waitForDoor(true, I.doorReach + 1, true, 99, I), "not there yet")
		assert(not R.waitForDoor(false, 1, true, 99, I), "an ordinary waypoint")
	end,
}
