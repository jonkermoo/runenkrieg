--!strict
local Vfx = require("../src/shared/Config/Vfx")
local Runes = require("../src/shared/Config/Runes")
local Palette = require("../src/shared/Config/Palette")
local DevTools = require("../src/shared/Config/DevTools")

local EFFECTS = {
	Circle = true,
	Charge = true,
	Ray = true,
	Burst = true,
	Blast1 = true,
	Blast3 = true,
	Grenade = true,
	Shell = true,
	Shockwave = true,
	Star = true,
	Spikes = true,
	Lightning = true,
	Aura = true,
	Zoltraak = true,
	Cast1 = true,
	Cast2 = true,
	Cast3 = true,
}

-- every string field named color / Color / core / Core / Accent names a Palette.Magic color
local function colors(t: any, path: string)
	for k, v in t do
		if type(v) == "table" then
			colors(v, `{path}.{k}`)
		elseif
			type(v) == "string" and (k == "color" or k == "Color" or k == "core" or k == "Core" or k == "Accent")
		then
			assert(Palette.Magic[v], `{path}.{k}: {v} is not a Palette.Magic color`)
		end
	end
end

return {
	["effect colors are magic palette names"] = function()
		for name, e in Vfx do
			if name ~= "Showcase" then
				colors(e, name)
			end
		end
	end,
	["runes: strokes inside the unit box"] = function()
		local n = 0
		for name, strokes in Runes do
			n += 1
			assert(#strokes > 0, name)
			for _, s in strokes do
				assert(#s == 4, name)
				for _, v in s do
					assert(v >= 0 and v <= 1, `{name}: {v} outside 0..1`)
				end
			end
		end
		assert(n >= 12, "too few runes")
	end,
	["explosions grow with the stage; stage 3 about the real fireball"] = function()
		local S = Vfx.Blast.Stages
		local Damage = require("../src/shared/Config/Damage")
		assert(#S == #Damage.Staff.Range, "one explosion per stage")
		for i = 2, #S do
			assert(S[i].fireball > S[i - 1].fireball and S[i].rings >= S[i - 1].rings, `stage {i} bigger`)
		end
		-- a 10 kg TNT fireball is roughly 8 m across: within a few studs
		local real = 8 / Damage.Blast.MetresPerStud
		assert(math.abs(S[#S].fireball - real) < 4, `stage 3 fireball {S[#S].fireball} vs ~{real}`)
		local K = Vfx.Blast.Charge
		local d10 = K.a * 10 ^ K.b / K.metresPerStud
		assert(math.abs(d10 * K.metresPerStud - 8) < 0.5, `10 kg fireball {d10 * K.metresPerStud} m`)
	end,
	["stronger blasts: taller, longer clouds and longer leftover runes"] = function()
		-- user 2026-10-25: "taller longer lasting clouds the stronger they are", runes and static "longer the stronger"
		local B = Vfx.Blast
		for _, pair in { B.Cluster.tall, B.Cluster.life, B.Smoke.life, B.Runes.life, B.Runes.count, B.Static.arcs } do
			assert(pair[2] > pair[1] and pair[1] > 0, "grows with strength")
		end
		assert(B.Scale.big > B.Scale.small and B.Scale.small > 0)
		local C = B.Cluster
		assert(0 < C.hot and C.hot < C.burn and C.burn < C.crumble and C.crumble < 1, "hot, burning, dark, crumbling")
		assert(C.inner < 1 and C.inner + C.toward > 1, "the dark body shows in front with the rim round it")
		assert(C.min >= 1 and C.max >= C.min)
		assert(B.Colors.dark > B.Colors.darkMagic, "magic keeps more of its colour")
		for _, g in B.Glyphs do
			for _, st in g do
				assert(#st == 4, "a stroke is x0, y0, x1, y1")
				for _, v in st do
					assert(math.abs(v) <= 0.5, "strokes stay in the unit box")
				end
			end
		end
		assert(Palette.Terrain[B.Clods.dirt], "the clods' fallback colour is a terrain colour")
		-- round 2 (user: "the cloud is too high", "i liked the inital blast orb", "more variety of gray smoke")
		assert(B.Cluster.tall[2] <= 1.5, "a low dome, not a column into the sky")
		assert(B.Orb.size > 0 and B.Orb.core < 1 and B.Orb.hold > 0, "the orb stays a moment on the hit")
		assert(#B.Smoke.shades >= 3, "several greys")
		for _, g in B.Smoke.shades do
			assert(Palette.Magic[g], `smoke shade {g} is a Palette.Magic colour`)
		end
		assert(B.Smoke.life[1] > B.Cluster.life[1], "the grey smoke outlives the coloured balls")
		assert(B.Runes.float[2] > 0 and B.Runes.each[1] > B.Runes.appear, "runes float up and fade")
		assert(B.Pop.flash > 0 and B.Pop.orbLife > B.Pop.time, "the grenade's orb outlasts its flash")
		local G = require("../src/shared/Config/Grenades")
		assert(G.Vfx.pop == true, "grenades pop (user 2026-10-25: no cloud, quick, less fiery)")
		assert(G.Types[Vfx.Showcase.Grenade], "the showcase's grenade exists")
	end,
	["timings and sizes are positive"] = function()
		assert(Vfx.Circle.Appear > 0 and Vfx.Circle.Close.time > 0 and Vfx.Circle.Diameter > 0)
		assert(Vfx.Ray.Extend > 0 and Vfx.Ray.Hold > 0 and Vfx.Ray.Fade > 0)
		for _, l in Vfx.Ray.Layers do
			assert(l.width1 >= l.width0 and l.width0 > 0, "beam layers widen away from the caster")
		end
		assert(Vfx.Zoltraak.Range > Vfx.Zoltraak.CircleAhead)
	end,
	["beam profiles only override Ray's keys, with as many layers"] = function()
		for name, prof in Vfx.Beams do
			for k in prof do
				assert((Vfx.Ray :: any)[k] ~= nil or k == "Impact", `{name}.{k} is not a Ray key`)
			end
			if prof.Layers then
				assert(#prof.Layers == #Vfx.Ray.Layers, `{name}: layer count`)
			end
		end
	end,
	["staff cast: a stage per built spell stage, circles growing outward, known beam profiles"] = function()
		local stages = Vfx.Cast.Stages
		for i, s in stages do
			assert((Vfx.Beams :: any)[s.beam], `cast stage {i}: unknown beam {s.beam}`)
			if i > 1 then
				assert(s.diameter > stages[i - 1].diameter, `cast stage {i} circle not larger`)
				assert(s.ahead > stages[i - 1].ahead, `cast stage {i} circle not further out`)
			end
		end
		local Spells = require("../src/shared/Config/Spells")
		for i, s in stages do
			local lead = (s :: any).lead
			if lead then -- an assembling circle starts after the stage before it is reached
				assert(
					i > 1 and Spells.Stages[i].hold - lead > Spells.Stages[i - 1].hold,
					`cast stage {i} lead too long`
				)
			end
		end
		for i, s in Spells.Stages do
			if Spells.Built[s.name] then
				assert(stages[i] and stages[i].beam == s.name, `built spell stage {s.name} has no cast stage {i}`)
			end
		end
	end,
	["showcase: every entry is a known effect, with a teleport and hideable labels"] = function()
		for _, e in Vfx.Showcase.Entries do
			assert(EFFECTS[e.effect], `unknown effect {e.effect}`)
			if e.effect == "Shell" then
				assert(require("../src/shared/Config/Artillery").Guns[e.gun], `unknown gun {e.gun}`)
			end
			assert(e.every > 0)
		end
		local found = false
		for _, d in DevTools.Extra do
			found = found or d.id == "Effects"
		end
		assert(found, "no Effects teleport")
		assert(table.find(DevTools.Admin.LabelFolders, "DevVfx"), "DevVfx labels not hideable")
	end,
	["every magic scheme colors every effect, from the palette"] = function()
		local FIELDS = {
			"arc",
			"arcCore",
			"mist",
			"flash",
			"glow",
			"circle",
			"accent",
			"haze",
			"charge",
			"core",
			"orbit",
			"pointer",
		}
		local n = 0
		for name, sc in Vfx.Schemes do
			n += 1
			assert(#sc.layers == 4, `{name}: a beam has 4 layers`)
			for _, c in sc.layers do
				assert(Palette.Magic[c], `{name}: layer {c} is not a Palette.Magic color`)
			end
			for _, f in FIELDS do
				assert(Palette.Magic[sc[f]], `{name}.{f}: {sc[f]} is not a Palette.Magic color`)
			end
		end
		assert(n >= 6, "the six looks of the magic")
	end,
}
