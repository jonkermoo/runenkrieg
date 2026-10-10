--!strict
local Cfg = require("../src/shared/Config/TreeSway")
local S = require("../src/shared/Rules/TreeSway")

local function mag(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

local function maxIdle(part: any): number
	local strength, dx, dz = S.wind(Cfg.DefaultWind.x, Cfg.DefaultWind.z, Cfg)
	local m = 0
	for i = 0, 2000 do
		local x, z = S.idleTilt(i * 0.01, 123, -45, strength, dx, dz, part, Cfg.Gust)
		m = math.max(m, mag(x, z))
	end
	return math.deg(m)
end

return {
	["leaves sway more than wood, wood barely moves"] = function()
		local trunk, canopy = maxIdle(Cfg.Trunk), maxIdle(Cfg.Canopy)
		assert(canopy > trunk * 3, `canopy {canopy} vs trunk {trunk}`)
		assert(trunk < 0.6, `trunk sways {trunk} deg`)
		assert(canopy < 3, `canopy sways {canopy} deg: distracting`)
	end,
	["sway leans downwind on average"] = function()
		local strength, dx, dz = S.wind(10, 0, Cfg)
		local sum = 0
		for i = 0, 3000 do
			local x = S.idleTilt(i * 0.01, 0, 0, strength, dx, dz, Cfg.Canopy, Cfg.Gust)
			sum += x
		end
		assert(sum > 0, "mean tilt should point downwind (+x)")
	end,
	["neighbouring trees are not in lockstep"] = function()
		local strength, dx, dz = S.wind(10, 4, Cfg)
		local a = S.idleTilt(3.3, 100, 100, strength, dx, dz, Cfg.Canopy, Cfg.Gust)
		local b = S.idleTilt(3.3, 160, 90, strength, dx, dz, Cfg.Canopy, Cfg.Gust)
		assert(math.abs(a - b) > 1e-4, "two trees 60 studs apart move identically")
	end,
	["zero wind falls back to the default wind"] = function()
		local strength = S.wind(0, 0, Cfg)
		assert(strength > 0, "no sway with zero GlobalWind")
	end,
	["explosion pushes away from the blast and the spring settles"] = function()
		for _, part in { Cfg.Trunk, Cfg.Canopy } do
			local s = S.newSpring()
			S.kick(s, 10, 0, 0, 0, 40, math.rad(Cfg.Explosion.maxKick) * part.impulseScale)
			assert(s.vx > 0, "kick should push away from the blast (+x)")
			local peak = 0
			for _ = 1, 6 * 60 do
				S.step(s, part.stiffness, part.damping, 1 / 60)
				S.clamp(s, math.rad(part.maxLean))
				peak = math.max(peak, mag(s.x, s.z))
			end
			assert(math.deg(peak) > 1, "explosion barely moved the tree")
			assert(math.deg(peak) <= part.maxLean + 1e-6, "lean exceeded maxLean")
			assert(S.asleep(s, math.rad(Cfg.SleepAngle)), "spring did not settle within 6 s")
		end
	end,
	["spring is stable at the worst frame rate"] = function()
		local s = S.newSpring()
		s.vx = 5
		for _ = 1, 400 do
			S.step(s, Cfg.Trunk.stiffness, Cfg.Trunk.damping, 1 / 10) -- clamped to 1/20 internally
		end
		assert(math.abs(s.x) < 1e-3 and s.x == s.x, "spring diverged")
	end,
	["falloff is 1 at the center, 0 at the radius, monotonic"] = function()
		assert(S.falloff(0, 30) == 1 and S.falloff(30, 30) == 0 and S.falloff(40, 30) == 0)
		assert(S.falloff(10, 30) > S.falloff(20, 30))
	end,
}
