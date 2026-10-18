--!strict
local C = require("../src/shared/Config/Grenades")
local G = require("../src/shared/Rules/Grenade")
local W = require("../src/shared/Config/Weapons")

local GRAVITY = 196.2 -- Roblox's default workspace.Gravity
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

return {
	["a level look is lifted by the loft, at the grenade's speed"] = function()
		local vx, vy, vz = G.launch(0, 0, -1, 10, 100)
		assert(near(vx, 0) and vz < 0)
		assert(near(math.sqrt(vx * vx + vy * vy + vz * vz), 100))
		assert(near(math.deg(math.atan2(vy, -vz)), 10))
	end,
	["looking straight up never throws it backwards"] = function()
		local vx, vy, vz = G.launch(0, 1, 0, 10, 100)
		assert(vy > 99 and near(vx, 0) and near(vz, 0))
	end,
	["the hand is right of, above and in front of the head, whichever way it looks"] = function()
		-- looking down -Z: right is +X, forward -Z
		local x, y, z = G.hand(0, 10, 0, 0, 0, -1, { 0.8, 0.6, -0.8 })
		assert(near(x, 0.8) and near(y, 10.6) and near(z, -0.8))
		-- looking down +X: right is +Z
		x, y, z = G.hand(0, 0, 0, 1, 0, 0, { 0.8, 0.6, -0.8 })
		assert(near(x, 0.8) and near(y, 0.6) and near(z, 0.8))
		-- looking up 45 degrees: "up" leans back, "forward" leans up
		x, y, z = G.hand(0, 0, 0, 0, 1, -1, { 0, 1, 0 })
		assert(near(x, 0) and near(y, math.sqrt(0.5)) and near(z, math.sqrt(0.5)))
		-- straight up still gives a frame
		x, y, z = G.hand(0, 0, 0, 0, 1, 0, { 0.8, 0, 0 })
		assert(near(math.sqrt(x * x + y * y + z * z), 0.8))
	end,
	["a wall between head and hand: the throw starts short of it"] = function()
		assert(G.clearShare(1.3, nil, 0.3) == 1)
		assert(G.clearShare(1.3, 2, 0.3) == 1)
		assert(near(G.clearShare(1.3, 0.65, 0.3), 0.35 / 1.3))
		assert(G.clearShare(1.3, 0.1, 0.3) == 0) -- pressed against it: from the head
	end,
	["the path starts at the hand and falls under gravity"] = function()
		local x, y, z = G.at(0, 1, 2, 3, 4, 5, 6, GRAVITY)
		assert(x == 1 and y == 2 and z == 3)
		local _, y1 = G.at(1, 0, 0, 0, 0, 0, 0, GRAVITY)
		assert(near(y1, -GRAVITY / 2))
	end,
	["a well thrown Mills lands about 30 m (84 studs) away, the stick about 35 m"] = function()
		local mills = G.range(C.Types.grenade_mills.speed, 45, GRAVITY)
		local stick = G.range(C.Types.grenade_stick.speed, 45, GRAVITY)
		assert(mills > 80 and mills < 88, mills)
		assert(stick > mills and stick < 105, stick)
	end,
	["fragments: lethal close, falling off to the wound range, nothing beyond"] = function()
		local f = C.Types.grenade_mills.fragments
		assert(G.fragments(0, f) == f.max and G.fragments(f.lethal, f) == f.max)
		assert(near(G.fragments(f.wound, f), f.far))
		assert(G.fragments(f.wound + 0.01, f) == 0)
		local mid = G.fragments((f.lethal + f.wound) / 2, f)
		assert(mid < f.near and mid > f.far)
	end,
	["the user's ranges: lethal within about 8 studs, wounding to about 28 (Mills)"] = function()
		local f = C.Types.grenade_mills.fragments
		assert(f.lethal >= 7 and f.lethal <= 9 and f.wound >= 25 and f.wound <= 30)
	end,
	["the server refuses a throw from far off or with no direction"] = function()
		assert(G.throwOk(0, 0, -1, 1, C.Throw.reach))
		assert(not G.throwOk(0, 0, -1, C.Throw.reach + 1, C.Throw.reach))
		assert(not G.throwOk(0, 0, 0, 1, C.Throw.reach))
		assert(not G.throwOk(0 / 0, 0, 1, 1, C.Throw.reach))
	end,
	["every grenade type is a Grenade-class weapon in the Grenade slot, and back"] = function()
		for name in C.Types do
			local w = W[name]
			assert(w, name)
			assert(w.class == "Grenade" and w.slot == "Grenade", name)
		end
		for name, w in W do
			if w.class == "Grenade" then
				assert(C.Types[name], name .. " has no Config/Grenades.Types entry")
			end
		end
	end,
	["fuse and count as the user picked"] = function()
		assert(C.Fuse == 3 and C.Carried == 2)
	end,
}
