--!strict
-- The map checker on Map 1 (roadmap 2.1): reach, falls, sight lines, travel times. Report: `lune run tests/mapreport`.
local Check = require("../src/shared/Rules/MapCheck")
local S = require("./mapgrid")

local g, map, cfg, M = S.grid, S.map, S.cfg, S.metrics
local L = cfg.Limits

local function sprint(studs: number): number
	return studs / M.Movement.SprintSpeed
end

-- the sprint time from `team`'s spawn to a sector's capture zone
local function toSector(team: string, s: any): number?
	local _, d = Check.nearest(g, S.walks[team], s.x, s.z, s.radius)
	return d and sprint(d)
end

return {
	["both spawns stand on open ground"] = function()
		for team, cells in S.spawns do
			assert(#cells > 10, `{team} spawn has {#cells} open cells`)
		end
	end,
	["reach: every sector and every ford can be walked to from both spawns"] = function()
		for team in S.spawns do
			for _, s in map.sectors do
				assert(toSector(team, s), `{team} can't walk to {s.id}`)
			end
			for _, f in map.river.fords do
				local x = map.river.x
				local i = Check.nearest(g, S.walks[team], x, f.z, map.river.width + map.river.bankWidth)
				assert(i, `{team} can't reach the ford at z={f.z}`)
			end
		end
	end,
	["falls: nowhere you can get to that you can't walk back from"] = function()
		for team, cells in S.spawns do
			local pits = Check.pits(g, cells)
			assert(#pits == 0, `{team}: {#pits} cells you can't climb out of`)
		end
	end,
	["reach: no big walkable area cut off from the spawns"] = function()
		local pockets = Check.pockets(g, S.walks.West)
		for _, p in pockets do
			assert(#p <= cfg.PocketCells, `a cut-off area of {#p} cells`)
		end
	end,
	["sight: no spawn sees the other, or the centre sector, through the fog"] = function()
		local W, E = map.spawnZones.West, map.spawnZones.East
		assert(E.minX - W.maxX > map.fogEnd, "spawn to spawn inside the fog")
		local centre
		for _, s in map.sectors do
			if s.startOwner == "Neutral" then
				centre = s
			end
		end
		assert(centre.x - W.maxX > map.fogEnd and E.minX - centre.x > map.fogEnd, "a spawn sees the centre")
	end,
	["sight: a soldier on open level ground sees to the fog; a hill hides him"] = function()
		-- a made-up flat map, then a hill between
		local flat = {
			bounds = { minX = 0, maxX = 600, minZ = -30, maxZ = 30 },
			fogEnd = 500,
		}
		local MT = {
			heightAt = function(_, x: number, _z: number): number
				return if x > 200 and x < 220 then 12 else 0
			end,
			isRiver = function()
				return false
			end,
		}
		local fg = Check.grid(flat, MT, cfg, {}, {}, {}, 50)
		local open = Check.sight(fg, 300, 0, 1, 0, 290)
		assert(open >= 290 - cfg.Step, `open ground: {open}`)
		local blocked = Check.sight(fg, 100, 0, 1, 0, 400)
		assert(blocked < 230, `past the hill: {blocked}`)
		-- from a rise, a canopy between hides the ground behind it (on the level the leaves are over the line)
		local rise = {
			heightAt = function(_, x: number, _z: number): number
				return if x <= 300 then 18 else 0
			end,
			isRiver = MT.isRiver,
		}
		local bare = Check.grid(flat, rise, cfg, {}, {}, {}, 50)
		local tree = { { x = 330, z = 0, kind = "T", scale = 1 } }
		local wooded = Check.grid(flat, rise, cfg, tree, {}, { T = 30 }, 50)
		local all = Check.sight(bare, 300, 0, 1, 0, 290)
		local some = Check.sight(wooded, 300, 0, 1, 0, 290)
		assert(all >= 290 - cfg.Step, `from the rise: {all}`)
		local hidden = 0
		for d = 40, 290, cfg.Step do
			-- (a target is hidden if the farthest seen is short of it or it falls in the shade: count with a short look)
			if Check.sight(wooded, 300, 0, 1, 0, d) < d then
				hidden += 1
			end
		end
		assert(hidden > 0 and some > 0, `a canopy hides some of the ground behind it ({hidden})`)
	end,
	["travel: each spawn reaches its first sector and the centre in time, and fairly"] = function()
		local centre, times = nil, {}
		for _, s in map.sectors do
			if s.startOwner == "Neutral" then
				centre = s
			end
		end
		for team in S.spawns do
			local first = math.huge
			for _, s in map.sectors do
				if s.startOwner == team and not s.isHQ then
					first = math.min(first, toSector(team, s) or math.huge)
				end
			end
			assert(first <= L.ownFirst, `{team}: {first} s to its first sector`)
			local c = toSector(team, centre) :: number
			assert(c <= L.centre, `{team}: {c} s to the centre`)
			times[team] = c
		end
		local a, b = times.West, times.East
		assert(math.abs(a - b) / math.min(a, b) <= L.fairness, `centre runs {a} vs {b} s`)
	end,
}
