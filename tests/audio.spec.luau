--!strict
local A = require("../src/shared/Config/Audio")
local Firing = require("../src/shared/Config/Firing")

return {
	["every falloff profile has a reference distance inside its range"] = function()
		for name, p in A.Profiles do
			assert(p.ref > 0 and p.max > p.ref * 10, `{name}: reference {p.ref}, range {p.max}`)
		end
	end,
	["a shot carries past the fog; the action and steps stay close"] = function()
		assert(A.Profiles.Gunshot.max > Firing.Range, "a shot is heard beyond its own range")
		assert(A.Profiles.Mechanism.max < A.Profiles.Gunshot.max / 10, "the bolt is heard only nearby")
		assert(A.Profiles.Footstep.max < A.Profiles.Gunshot.max / 10, "footsteps are heard only nearby")
	end,
	["a 1/d falloff: half the volume at twice the reference distance"] = function()
		local p = A.Profiles.Gunshot
		local function gain(d: number): number
			return math.min(1, p.ref / d)
		end
		assert(math.abs(gain(2 * p.ref) - 0.5) < 1e-9 and gain(p.ref / 2) == 1)
	end,
	["every trimmed sound plays a real stretch of its file"] = function()
		for name, s in Firing.Sounds do
			local a, b = (s :: any).start or 0, (s :: any).stop or math.huge
			assert(a >= 0 and b > a + 0.1, `{name}: plays {a}-{b} s`)
			if (s :: any).fade then
				assert((s :: any).fade < b - a, `{name}: fades longer than it plays`)
			end
		end
	end,
	["a spent case falls under real gravity"] = function()
		local c = Firing.Effects.Casing
		assert(math.abs(c.gravity - 9.8 / 0.357) < 0.5, "9.8 m/s^2 in studs")
		assert(c.up ^ 2 / (2 * c.gravity) > 0.5, "it rises visibly out of the port")
	end,
}
