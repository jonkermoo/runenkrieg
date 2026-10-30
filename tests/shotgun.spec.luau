--!strict
-- The M1897's reach (user 2026-10-30: "more reliable ... 1 shot kill potential at 70-100 studs if shot perfectly"):
-- its pattern (Rules/Firing.pellets) laid over a standing R6 soldier facing the shooter, each pellet's damage by the
-- zone it lands in and its falloff (Rules/Damage), as src/server/Damage sums one shot.
local D = require("../src/shared/Config/Damage")
local Damage = require("../src/shared/Rules/Damage")
local F = require("../src/shared/Rules/Firing")
local W = require("../src/shared/Config/Weapons")

local P = W.shotgun_m1897.pellets :: any
local TABLE = D.Weapons.Shotgun
local SEEDS = 500

-- the R6 parts' boxes as the shooter sees them (studs from the torso's centre: x right, y up)
local BOXES = {
	{ zone = "Torso", x = { -1, 1 }, y = { -1, 1 } },
	{ zone = "Limb", x = { 1, 2 }, y = { -1, 1 } },
	{ zone = "Limb", x = { -2, -1 }, y = { -1, 1 } },
	{ zone = "Limb", x = { -1, 1 }, y = { -3, -1 } },
	{ zone = "Head", x = { -1, 1 }, y = { 1, 2 } },
}

local function zoneAt(x: number, y: number): string?
	for _, b in BOXES do
		if x >= b.x[1] and x <= b.x[2] and y >= b.y[1] and y <= b.y[2] then
			return b.zone
		end
	end
	return nil
end

-- One shot's damage at `distance` studs, the barrel's line `off` studs to the side of the torso's centre.
local function shot(seed: number, distance: number, off: number): number
	local hits: { Damage.Hit } = {}
	for _, o in F.pellets(seed, P) do
		local x = off + distance * math.tan(math.rad(o[1]))
		local y = distance * math.tan(math.rad(o[2]))
		local zone = zoneAt(x, y)
		if zone then
			local share = Damage.falloff(distance, P.full, P.none)
			table.insert(hits, { zone = zone, amount = Damage.amount(TABLE, zone, share) })
		end
	end
	return (Damage.sum(hits))
end

-- The fewest and most damage over many shots.
local function range(distance: number, off: number): (number, number)
	local lo, hi = math.huge, 0
	for seed = 1, SEEDS do
		local t = shot(seed * 7919, distance, off)
		lo, hi = math.min(lo, t), math.max(hi, t)
	end
	return lo, hi
end

return {
	["a shot centred on the body kills at 70 and 100 studs, every time"] = function()
		for _, d in { 70, 85, 100 } do
			local lo = range(d, 0)
			assert(lo >= D.Health, `{d} studs: {lo}`)
		end
	end,
	["a shot 1.5 studs off the centre (on the arm), or past 100 studs, doesn't kill"] = function()
		for _, d in { 70, 100 } do
			local _, hi = range(d, 1.5)
			assert(hi < D.Health, `{d} studs, 1.5 off: {hi}`)
		end
		local _, far = range(110, 0)
		assert(far < D.Health, `110 studs centred: {far}`)
	end,
	["up close it's a shotgun: every pellet in the torso, a near miss still kills"] = function()
		local lo = range(10, 0)
		assert(lo == P.count * TABLE.Torso, `10 studs: {lo}`)
		local near = range(20, 1)
		assert(near >= D.Health, `20 studs, a stud off: {near}`)
	end,
}
