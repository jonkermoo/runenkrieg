--!strict
local A = require("../src/shared/Config/Assets")
local Cfg = require("../src/shared/Config/Species")
local Palette = require("../src/shared/Config/Palette")
local U = require("../src/shared/Config/Uniforms")
local Species = require("../src/shared/Rules/Species")

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

return {
	["every species' models are registered and every kit names a real species"] = function()
		for name, kind in Cfg.Kinds do
			assert(A.Entries[kind.ears], `{name}: ears {kind.ears} not in Config/Assets`)
			assert(kind.earPivots.EarL and kind.earPivots.EarR, `{name}: needs both ear pivots`)
			assert(#kind.earPivots.EarL == 3 and #kind.earPivots.EarR == 3, `{name}: ear pivots need 3 numbers`)
			assert(kind.earMotion >= 0 and kind.earMotion <= 1, `{name}: earMotion out of 0..1`)
			if kind.tail then
				assert(A.Entries[kind.tail], `{name}: tail {kind.tail} not in Config/Assets`)
				assert(kind.tailPivots and #kind.tailPivots >= 2, `{name}: a tail needs its segment pivots`)
			else
				assert(kind.tailPivots == nil, `{name}: tail pivots without a tail`)
			end
		end
		for kit, name in Cfg.Kits do
			assert(U.Kits[kit], `Kits: unknown uniform kit {kit}`)
			assert(Cfg.Kinds[name], `Kits: {kit} names unknown species {name}`)
		end
	end,
	["ear pivots mirror left to right"] = function()
		for name, kind in Cfg.Kinds do
			local l, r = kind.earPivots.EarL, kind.earPivots.EarR
			assert(near(l[1], -r[1]) and near(l[2], r[2]) and near(l[3], r[3]), `{name}: ear pivots not mirrored`)
		end
	end,
	["a kit's species, the player's override winning"] = function()
		assert(Species.of("uniform1", nil, Cfg) == "katzling", "grey kit: Katzling")
		assert(Species.of("uniform2", nil, Cfg) == "alb", "olive kit: Alb")
		assert(Species.of("nokit", nil, Cfg) == nil, "an unlisted kit: human")
		assert(Species.of("uniform1", "fennek", Cfg) == "fennek", "override to a species")
		assert(Species.of("uniform1", "human", Cfg) == nil, "override to human")
		assert(Species.of("uniform1", "dragon", Cfg) == "katzling", "an unknown override is ignored")
	end,
	["piece names split into piece, role, ear and segment"] = function()
		local piece, role = Species.split("EarRTufts_Fluff")
		assert(piece == "EarRTufts" and role == "Fluff", "split")
		local tag, shell, ruff = Species.ear("EarL")
		assert(tag == "EarL" and shell and not ruff, "the ear itself")
		tag, shell, ruff = Species.ear("EarRRuff")
		assert(tag == "EarR" and not shell and ruff, "the ruff")
		tag, shell, ruff = Species.ear("EarLInner")
		assert(tag == "EarL" and not shell and not ruff, "the inner")
		assert(Species.ear("Tail1") == nil, "a tail piece is no ear")
		assert(Species.segment("Tail3") == 3 and Species.segment("EarL") == nil, "segments")
	end,
	["colours by role: fur the hair, skin the skin, fluff between hair and cream"] = function()
		local hair, skin = { 100, 60, 40 }, { 200, 150, 100 }
		assert(Species.color("Fur", hair, skin, Palette.Species) == hair, "fur")
		assert(Species.color(nil, hair, skin, Palette.Species) == hair, "no role: fur")
		assert(Species.color("Skin", hair, skin, Palette.Species) == skin, "skin")
		assert(Species.color("Inner", hair, skin, Palette.Species) == Palette.Species.Inner, "inner")
		local f = Species.color("Fluff", hair, skin, Palette.Species)
		for i = 1, 3 do
			local lo, hi = math.min(hair[i], Palette.Species.Cream[i]), math.max(hair[i], Palette.Species.Cream[i])
			assert(f[i] >= lo and f[i] <= hi and f[i] == math.floor(f[i]), "fluff between hair and cream")
		end
	end,
	["ears: still at rest, back when sprinting, flat and out when hurt, a twitch swivels"] = function()
		local E = Cfg.Motion.Ear
		local quiet = table.clone(E)
		quiet.swayDeg = 0
		local x, y, z = Species.earAngles(0, 1, 0, 1, 0, 0, 0, quiet)
		assert(x == 0 and y == 0 and z == 0, "rest")
		x = Species.earAngles(0, 1, 0, 1, 0, 1, 0, quiet)
		assert(near(x, E.sprintBackDeg), "sprinting lies back")
		local xr, _, zr = Species.earAngles(0, 1, 0, 1, 0, 0, 1, quiet)
		local _, _, zl = Species.earAngles(0, -1, 0, 1, 0, 0, 1, quiet)
		assert(xr > 0 and zr < 0 and zl > 0, "flat: back, and each ear rolls out to its own side")
		local _, yr = Species.earAngles(0, 1, 0, 1, 1, 0, 0, quiet)
		local _, yl = Species.earAngles(0, -1, 0, 1, 1, 0, 0, quiet)
		assert(near(yr, E.twitchDeg) and near(yl, -E.twitchDeg), "a twitch swivels each ear its own way")
		local xs = Species.earAngles(0, 1, 0, 0.5, 0, 1, 0, quiet)
		assert(near(xs, E.sprintBackDeg * 0.5), "the species' share scales it")
	end,
	["twitch and hurt curves"] = function()
		assert(Species.twitch(-0.1, 0.2) == 0 and Species.twitch(0.3, 0.2) == 0, "outside a twitch")
		assert(near(Species.twitch(0.1, 0.2), 1), "the twitch peaks halfway")
		assert(Species.hurt(0, 0.8) == 1 and Species.hurt(0.8, 0.8) == 0, "hurt eases from 1 to 0")
		assert(Species.hurt(-math.huge, 0.8) == 0, "never hit")
	end,
	["tail: lifts running forward, swings against sideways motion, droops dead, stays within limits"] = function()
		local T = table.clone(Cfg.Motion.Tail)
		T.swayDeg = 0
		local n = 4
		local x = Species.tailAngles(1, n, 0, 100, 0, 0, T)
		assert(near(x, -T.liftMax / n), "forward lifts, capped")
		local _, y = Species.tailAngles(1, n, 0, 0, 5, 0, T)
		assert(y < 0, "moving right swings it left")
		local _, ymax = Species.tailAngles(1, n, 0, 0, -1000, 0, T)
		assert(near(ymax, T.lagMax / n), "the swing is capped")
		local xd, yd = Species.tailAngles(2, n, 1.3, 10, 3, 1, Cfg.Motion.Tail)
		assert(near(xd, T.deadDroopDeg) and yd == 0, "dead: droops, no sway")
	end,
	["easing heads to the target and is frame-rate independent"] = function()
		local once = Species.ease(0, 10, 5, 0.2)
		local twice = Species.ease(Species.ease(0, 10, 5, 0.1), 10, 5, 0.1)
		assert(near(once, twice, 1e-9), "two half steps = one step")
		assert(once > 0 and once < 10, "partway")
		assert(near(Species.ease(3, 10, 5, 100), 10, 1e-6), "gets there")
	end,
}
