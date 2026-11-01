--!strict
local Cfg = require("../src/shared/Config/Indoors")
local Bots = require("../src/shared/Config/Bots")
local Metrics = require("../src/shared/Config/Metrics")
local R = require("../src/shared/Rules/Indoors")

local S = Cfg.Spots
local L = Cfg.Links

local function p(x: number, y: number, z: number): R.P
	return { x = x, y = y, z = z }
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

-- a front wall at z = -7 facing -Z (out of the building), floor at y = 1
local function piece(kind: any, x: number, width: number, story: number?): R.Piece
	return { kind = kind, at = p(x, 1, -7), out = p(0, 0, -1), width = width, thick = 1.4, story = story or 0 }
end

local function count(spots: { R.Spot }, kind: string): number
	local n = 0
	for _, s in spots do
		if s.kind == kind then
			n += 1
		end
	end
	return n
end

return {
	["a window spot stands inside, back from the wall, facing out"] = function()
		local spots = R.spots({ piece("window", 3, 3.4) }, S)
		assert(#spots == 1 and spots[1].kind == "Window")
		local s = spots[1]
		assert(near(s.at.x, 3) and near(s.at.y, 1))
		assert(near(s.at.z, -7 + 0.7 + S.stand), "half the wall plus `stand` in")
		assert(s.face.z == -1, "faces out")
	end,
	["a doorway has a spot in it and one either side inside"] = function()
		local spots = R.spots({ piece("door", 0, 4.6) }, S)
		assert(#spots == 3 and count(spots, "Doorway") == 3)
		local xs = {}
		for _, s in spots do
			table.insert(xs, s.at.x)
			assert(s.at.z > -7, "inside")
		end
		table.sort(xs)
		local side = 4.6 / 2 + S.side
		assert(near(xs[1], -side) and near(xs[2], 0) and near(xs[3], side))
	end,
	["cover behind solid wall, not too short and not crowding other spots"] = function()
		local spots = R.spots({
			piece("solid", -8, 4),
			piece("solid", -5, S.coverWidth - 0.5), -- too short
			piece("window", 3, 3.4),
			piece("solid", 3 + S.spacing - 0.5, 4), -- next to the window spot
		}, S)
		assert(count(spots, "Window") == 1)
		assert(count(spots, "Cover") == 1)
		for _, s in spots do
			if s.kind == "Cover" then
				assert(near(s.at.x, -8))
			end
		end
	end,
	["the same pieces always give the same spots, windows and doorways first"] = function()
		local pieces = { piece("solid", -8, 4), piece("door", 0, 4.6), piece("window", 6, 3.4, 1) }
		local a, b = R.spots(pieces, S), R.spots(pieces, S)
		assert(#a == #b and #a == 5)
		for i = 1, #a do
			assert(a[i].kind == b[i].kind and a[i].at.x == b[i].at.x)
		end
		assert(a[#a].kind == "Cover")
		assert(a[4].story == 1, "the window upstairs keeps its story")
	end,
	["walls facing other ways turn the spots with them"] = function()
		local w: R.Piece = { kind = "door", at = p(10, 0, 0), out = p(1, 0, 0), width = 4.6, thick = 1, story = 0 }
		local spots = R.spots({ w }, S)
		for _, s in spots do
			assert(near(s.at.x, 10 - 0.5 - S.stand), "in from an east wall")
			assert(s.face.x == 1)
		end
		local side = 4.6 / 2 + S.side
		assert(near(math.abs(spots[2].at.z), side) and near(spots[2].at.z, -spots[3].at.z))
	end,
	["a doorway's passage is outside then inside"] = function()
		local o, i = R.passage(piece("door", 2, 4.6), L)
		assert(near(o.z, -7 - 0.7 - L.approach) and near(i.z, -7 + 0.7 + L.approach))
		assert(near(o.x, 2) and near(i.y, 1))
	end,
	["a flight's link runs from the floor beside its foot to just past its top"] = function()
		-- climbing +X along a back wall at z = 5, the room toward -Z; steps 1.2 deep, 5 wide, top at 12.6
		local low, beyond, top = R.flight(p(-9, 0.6, 5), p(7.8, 12.6, 5), p(1, 0, 0), p(0, 0, -1), 5, 1.2, L)
		assert(
			near(low.x, -9 + L.up) and near(low.y, 0.6) and near(low.z, 5 - 2.5 - L.out),
			"beside the foot, on the floor"
		)
		assert(near(beyond.x, 7.8 + 0.6 + L.past) and near(beyond.y, 12.6) and near(beyond.z, 5), "past the top step")
		assert(top.x == 7.8 and top.y == 12.6, "the top step itself")
	end,
	["door reach is the prompt's distance, nearest picks within range"] = function()
		assert(R.reaches(p(0, 0, 0), p(0, 3, 8), 9))
		assert(not R.reaches(p(0, 0, 0), p(0, 3, 9), 9))
		local pts = { p(20, 0, 0), p(5, 0, 0), p(-6, 0, 0) }
		assert(R.nearest(pts, p(0, 0, 0), 30) == 2)
		assert(R.nearest(pts, p(0, 0, 0), 4) == nil)
		assert(R.nearest({}, p(0, 0, 0), 100) == nil)
	end,
	["near lists spots in range, nearest first, by kind"] = function()
		local spots = R.spots({ piece("solid", -8, 4), piece("door", 0, 4.6), piece("window", 6, 3.4) }, S)
		local at = p(6, 1, -4)
		local all = R.near(spots, at, 100)
		assert(#all == #spots and all[1].kind == "Window")
		for i = 2, #all do
			assert(R.distance(all[i - 1].at, at) <= R.distance(all[i].at, at))
		end
		assert(#R.near(spots, at, 100, "Cover") == 1)
		assert(#R.near(spots, at, 0.5) == 1 and #R.near(spots, at, 0.2) == 0)
	end,
	["a soldier fits: standing room inside the bot body, stand-off clears it, doorways wider than it"] = function()
		local r = Bots.Move.AgentRadius
		assert(S.stand >= S.clearance, "the standing box doesn't reach into the wall")
		assert(S.clearance <= r, "no wider than the bots' path agent")
		assert(Metrics.Building.DoorWidth > 2 * r, "a bot fits through a door")
		assert(S.height + S.lift <= Metrics.Building.DoorHeight)
		assert(Cfg.PathCosts[L.door] ~= nil and Cfg.PathCosts[L.stairs] ~= nil, "the link labels have path costs")
		assert(Cfg.PathCosts[Cfg.Door.label] ~= nil, "the door label has a path cost")
		assert(L.approach > r and L.approach >= S.stand, "a doorway's link ends clear of the wall")
	end,
}
