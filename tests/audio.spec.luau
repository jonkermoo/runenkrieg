--!strict
local A = require("../src/shared/Config/Audio")
local Cases = require("../src/shared/Config/Cases")
local Firing = require("../src/shared/Config/Firing")
local Weapons = require("../src/shared/Config/Weapons")

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
		local function check(name: string, s: any)
			if not s.id then -- variants
				for i, v in s do
					check(`{name}[{i}]`, v)
				end
				return
			end
			local a, b = s.start or 0, s.stop or math.huge
			assert(a >= 0 and b > a + 0.1, `{name}: plays {a}-{b} s`)
			if s.fade then
				assert(s.fade < b - a, `{name}: fades longer than it plays`)
			end
			if s.lead then
				assert(s.lead >= 0 and s.lead < b - a, `{name}: its peak is outside what plays`)
			end
		end
		for name, s in Firing.Sounds do
			check(name, s)
		end
		for weapon, w in Weapons do
			for name, s in (w.sounds or {}) :: any do
				check(`{weapon}.{name}`, s)
			end
		end
	end,
	["a spent case falls under real gravity"] = function()
		local c = Firing.Effects.Casing
		assert(math.abs(Cases.gravity - 9.8 / 0.357) < 0.5, "9.8 m/s^2 in studs (the case, flown by CaseDrop)")
		assert(math.abs(c.gravity - 9.8 / 0.357) < 0.5, "and anything else thrown off the gun")
		assert(c.up ^ 2 / (2 * Cases.gravity) > 0.5, "it rises visibly out of the port")
	end,
}
