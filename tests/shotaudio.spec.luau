--!strict
local A = require("../src/shared/Config/Audio")
local Artillery = require("../src/shared/Config/Artillery")
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
	["echoes: longer paths only, strongest first, no more than asked"] = function()
		local paths = { { 300, 100 }, { 210, 5 }, { 250, 60 }, { 900, 400 } }
		local e = R.echoes(200, paths, H.speed, 2, 30, 0.5, 80)
		assert(#e == 2, "two echoes")
		assert(e[1].index == 3 and e[2].index == 1, "nearest reflections first (the 15-stud detour is no echo)")
		for _, x in e do
			assert(x.gain < 0.5 and x.delay > R.delay(200, H.speed), "quieter and later than the shot")
		end
		assert(#R.echoes(200, {}, H.speed, 2, 30, 0.5, 80) == 0)
	end,
	["an echo off a wall beside the listener is no louder than the whole path allows"] = function()
		-- a wall 10 studs away, the shot 440 off: the wall's own falloff would play it at full; the path's is 80 / 450
		local e = R.echoes(440, { { 445, 10 } }, H.speed, 1, 0, 1, 80)
		assert(near(e[1].gain, 80 / 455, 1e-9), "scaled to the path's falloff")
		local far = R.echoes(440, { { 300, 300 } }, H.speed, 1, 0, 1, 80)
		assert(near(far[1].gain, 300 / 600, 1e-9), "a far wall: the rest of the path")
	end,
	["an echo comes clearly after the shot"] = function()
		assert(R.delay(H.echo.extra, H.speed) >= 0.1, "a tenth of a second at least, or it only thickens the shot")
	end,
	["echoes look about and around"] = function()
		assert(H.echo.rays >= 4 and H.echo.count >= 1 and H.echo.gain < 1 and H.echo.dull <= 0)
	end,
	["no echo beside the gun: it grows in with the far report"] = function()
		assert(R.grow(0, H.echo.from, H.echo.full) == 0 and R.grow(H.echo.from, H.echo.from, H.echo.full) == 0)
		assert(near(R.grow(H.echo.full, H.echo.from, H.echo.full), 1) and R.grow(1e6, H.echo.from, H.echo.full) == 1)
		assert(R.grow(150, H.echo.from, H.echo.full) < R.grow(250, H.echo.from, H.echo.full), "louder farther off")
		assert(H.echo.from >= H.near and H.echo.full <= H.far * 1.5, "with the far report, not before it")
	end,
	["the rifle shot's reflection dies away under its fade, its own decay before it plays whole"] = function()
		-- (the file swells again from 1.3 s, peaking at 1.45: a reflection, measured 2026-10-28)
		local s = Firing.Sounds.Shot
		local from = s.stop - s.fade
		assert(from >= 1.1 and from <= 1.25, "the fade starts as the decay ends, before the swell")
		assert(s.curve == "Exponential" and s.fade >= 1, "a natural die-away, not a cut")
	end,
	["a field gun's report: dry beside it, the distant boom growing in"] = function()
		local r = Artillery.Report
		assert(r.near > 0 and r.far > r.near)
		local s, f = R.mix(r.near * 0.5, r.near, r.far)
		assert(near(s, 1) and near(f, 0), "beside it only the gun")
		s, f = R.mix(r.far, r.near, r.far)
		assert(near(s, 0, 1e-9) and near(f, 1), "far off only the boom")
	end,
	["each gun's report: a believable pitch and tone"] = function()
		for name, w in W do
			local r = w.report
			if r then
				assert(r.pitch >= 0.7 and r.pitch <= 1.4, `{name}: pitch {r.pitch}`)
				assert(#r.eq == 3, `{name}: low, mid, high`)
				for _, g in r.eq do
					assert(math.abs(g) <= 12, `{name}: {g} dB`)
				end
			elseif w.ammo then
				error(`{name}: a gun with no report`)
			end
		end
		local mg = Artillery.Guns.mg08.mg
		assert(mg and mg.report.pitch >= 0.7 and mg.report.pitch <= 1.4 and #mg.report.eq == 3, "the MG's report")
		-- a smaller powder charge booms higher (blast scaling)
		assert(W.rifle_winchester1907.report.pitch > W.rifle_m91.report.pitch, ".351 WSL over 6.5 Carcano")
		assert(W.rifle_m91.report.pitch > W.rifle_g98.report.pitch, "6.5 Carcano over 7.92 Mauser")
		assert(W.pistol_nagant.report.pitch > W.pistol_webley.report.pitch, "7.62 Nagant over .455 Webley")
		assert(W.pistol_c96.sounds and W.pistol_c96.sounds.Shot, "the C96 fires a pistol's shot, not a rifle's")
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
