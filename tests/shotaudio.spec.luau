--!strict
local A = require("../src/shared/Config/Audio")
local Firing = require("../src/shared/Config/Firing")
local W = require("../src/shared/Config/Weapons")
local R = require("../src/shared/Rules/ShotAudio")

local H = A.Heard

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) < (eps or 1e-6)
end

return {
	["sound comes at 343 m/s: 960 studs take a second, nothing is early"] = function()
		assert(near(H.speed * 0.357, 343, 1), "343 m/s at 0.357 m per stud")
		assert(near(R.delay(960, H.speed), 1))
		assert(R.delay(0, H.speed) == 0 and R.delay(-5, H.speed) == 0)
	end,
	["close by only the shot, far off only the report, equal power between"] = function()
		local s, f = R.mix(0, H.near, H.far)
		assert(near(s, 1) and near(f, 0))
		s, f = R.mix(H.near, H.near, H.far)
		assert(near(s, 1) and near(f, 0))
		s, f = R.mix(H.far * 3, H.near, H.far)
		assert(near(s, 0) and near(f, 1))
		for d = H.near, H.far, 10 do
			s, f = R.mix(d, H.near, H.far)
			assert(near(s * s + f * f, 1), `power at {d}`)
		end
	end,
	["the highs go first with distance, never past the floor"] = function()
		local l0, m0, h0 = R.air(H.air.from, H.air)
		assert(l0 == 0 and m0 == 0 and h0 == 0, "nothing lost close by")
		local _, m1, h1 = R.air(400, H.air)
		assert(h1 < m1 and m1 <= 0, "highs drop faster than mids")
		local l2, m2, h2 = R.air(1e6, H.air)
		assert(l2 == H.air.floor[1] and m2 == H.air.floor[2] and h2 == H.air.floor[3], "stops at the floor")
		for _, g in H.air.floor do
			assert(g >= -80 and g <= 0, "an equalizer gain")
		end
	end,
	["a bullet passing beside the listener: where, how far off"] = function()
		local p = R.pass({ 0, 0, 0 }, { 0, 0, -500 }, { 6, 0, -300 }, 15, 40)
		assert(p and near(p.along, 300) and near(p.off, 6) and near(p.point[3], -300))
	end,
	["no pass: too far off, by the muzzle, behind the shooter, or past where it hit"] = function()
		assert(R.pass({ 0, 0, 0 }, { 0, 0, -500 }, { 20, 0, -300 }, 15, 40) == nil, "too far off")
		assert(R.pass({ 0, 0, 0 }, { 0, 0, -500 }, { 3, 0, -10 }, 15, 40) == nil, "next to the shooter")
		assert(R.pass({ 0, 0, 0 }, { 0, 0, -500 }, { 0, 0, 50 }, 15, 40) == nil, "behind the shooter")
		assert(R.pass({ 0, 0, 0 }, { 0, 0, -100 }, { 2, 0, -300 }, 15, 40) == nil, "it stopped before")
		assert(R.pass({ 0, 0, 0 }, { 0, 0, 0 }, { 2, 0, 0 }, 15, 40) == nil, "no path")
	end,
	["the crack comes before the report"] = function()
		for _, along in { H.pass.clear, 100, 300, 600 } do
			local crack = R.passTime(along, H.pass.radius, H.pass.bullet, H.speed)
			local report = R.delay(math.sqrt(along ^ 2 + H.pass.radius ^ 2), H.speed)
			assert(crack < report, `at {along} studs`)
		end
	end,
	["a pass is loudest on the path, fading to the edge"] = function()
		assert(near(R.passGain(0, 15, 0.3), 1) and near(R.passGain(15, 15, 0.3), 0.3))
		assert(near(R.passGain(99, 15, 0.3), 0.3) and R.passGain(5, 15, 0.3) > R.passGain(10, 15, 0.3))
	end,
	["echoes: longer paths only, quieter than the shot, strongest first, no more than asked"] = function()
		local paths = { { 300, 100 }, { 210, 5 }, { 250, 60 }, { 900, 400 } }
		local e = R.echoes(200, paths, H.speed, 2, 30, 0.5)
		assert(#e == 2, "two echoes")
		assert(e[1].index == 3 and e[2].index == 1, "nearest reflections first (the 15-stud detour is no echo)")
		for _, x in e do
			assert(x.gain < 0.5 and x.delay > R.delay(200, H.speed), "quieter and later than the shot")
		end
		assert(#R.echoes(200, {}, H.speed, 2, 30, 0.5) == 0)
	end,
	["echoes look about and around"] = function()
		assert(H.echo.rays >= 4 and H.echo.count >= 1 and H.echo.gain < 1 and H.echo.dull <= 0)
	end,
	["every gun is heard far off and going by"] = function()
		for name, w in W do
			if w.ammo then
				for _, s in { "Far", "Pass" } do
					local e = (w.sounds and (w.sounds :: any)[s]) or (Firing.Sounds :: any)[s]
					assert(e and (e.id or #e > 0), `{name}: no {s} sound`)
				end
			end
		end
		assert(A.Profiles.Report.max >= A.Profiles.Gunshot.max, "the report carries as far as the shot")
	end,
}
