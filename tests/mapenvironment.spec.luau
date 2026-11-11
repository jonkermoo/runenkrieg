--!strict
-- The environment pass on the frontline maps (user 2026-11-10: "make it just a overall uneven terrain", "it can be open,
-- it just cant look empty", "not every sector visible"): the fields, the clumps and the hidden points, each fair
-- between the two sides (Rules/MapTerrain.twinOf: through the middle point, or across its x).
local Maps = require("./frontlinemaps")
local MT = require("../src/shared/Rules/MapTerrain")
local M = require("../src/shared/Config/Metrics")
local Moods = require("../src/shared/Config/Moods")

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return Maps.each(function(map: any, name: string)
	return {
		["the fields mirror: every edge run and haystack has its twin, the kind at a spot is its twin's"] = function()
			if not map.fields then
				return
			end
			local F = MT.fieldLayout(map)
			assert(#F.runs > 50 and #F.stacks > 5, `{name}: {#F.runs} runs, {#F.stacks} stacks`)
			local function hasRun(kind: string, a: { number }, b: { number }): boolean
				for _, r in F.runs do
					if r.kind == kind then
						local same = near(r.a[1], a[1])
							and near(r.a[2], a[2])
							and near(r.b[1], b[1])
							and near(r.b[2], b[2])
						local flip = near(r.a[1], b[1])
							and near(r.a[2], b[2])
							and near(r.b[1], a[1])
							and near(r.b[2], a[2])
						if same or flip then
							return true
						end
					end
				end
				return false
			end
			for _, r in F.runs do
				local ax, az = MT.twinOf(map, r.a[1], r.a[2])
				local bx, bz = MT.twinOf(map, r.b[1], r.b[2])
				assert(hasRun(r.kind, { ax, az }, { bx, bz }), `{name}: a {r.kind} at {r.a[1]}, {r.a[2]} has no twin`)
			end
			for _, st in F.stacks do
				local tx, tz = MT.twinOf(map, st.x, st.z)
				local found = false
				for _, o in F.stacks do
					found = found or (near(o.x, tx) and near(o.z, tz))
				end
				assert(found, `{name}: a haystack at {st.x}, {st.z} has no twin`)
			end
			local b = map.bounds
			for x = b.minX, b.maxX, 37 do
				for z = b.minZ, b.maxZ, 29 do
					local tx, tz = MT.twinOf(map, x, z)
					local k1 = MT.fieldAt(map, x, z)
					local k2 = MT.fieldAt(map, tx, tz)
					assert(k1 == k2, `{name}: field {k1} at {x}, {z}, its twin {k2}`)
				end
			end
		end,
		["its look is a preset, every preset whole and listed (Config/Moods)"] = function()
			assert(Moods.Presets[map.mood], `{name}'s mood {map.mood} isn't a preset`)
			local n = 0
			for key, m in Moods.Presets do
				n += 1
				assert(table.find(Moods.Order, key), `{key} isn't in the Look row`)
				for _, f in { "saturation", "contrast", "brightness", "light", "cloudCover" } do
					assert(type((m :: any)[f]) == "number", `{key} has no {f}`)
				end
				assert(#m.tint == 3 and #m.cloudColor == 3 and m.haze.density > 0 and #m.haze.color == 3, `{key}`)
				assert(m.saturation <= 0, `{key} adds colour (user 2026-11-11: "remove this highly saturated look")`)
			end
			assert(n == #Moods.Order, "every look in the row is a preset")
		end,
		["the farmland is cleared: no tree on a field"] = function()
			if not map.fields then
				return
			end
			for _, t in MT.trees(map) do
				assert(not MT.fieldAt(map, t.x, t.z), `{name}: a tree on a field at {t.x}, {t.z}`)
			end
		end,
		["out of sight: no crest sees the points two away (terrain only)"] = function()
			local L = MT.legPieces(map)
			local eye, head = M.Character.EyeHeight, M.Character.Height
			local function clear(ax: number, az: number, bx: number, bz: number): boolean
				local ya, yb = MT.heightAt(map, ax, az) + eye, MT.heightAt(map, bx, bz) + head
				local d = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
				for t = 3, d - 3, 3 do
					local k = t / d
					if MT.heightAt(map, ax + (bx - ax) * k, az + (bz - az) * k) > ya + (yb - ya) * k then
						return false
					end
				end
				return true
			end
			local seen, all = 0, 0
			for _, c in L.crests do
				for j, s in map.sectors do
					if math.abs(j - c.sector) >= 2 then
						for n = -80, 80, 40 do
							all += 1
							if clear(c.cx - c.dz * n, c.cz + c.dx * n, s.x, s.z) then
								seen += 1
							end
						end
					end
				end
			end
			-- (Map 1's Ashby stands on no crest and the river takes its swell: its own houses and the haze cover it)
			assert(seen / all < 0.15, `{name}: {seen} of {all} lines from a crest reach a point two away`)
		end,
	}
end)
