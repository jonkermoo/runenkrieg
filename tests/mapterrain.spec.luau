--!strict
local M = require("../src/shared/Config/Metrics")
local Map1 = require("../src/shared/Config/Maps/Map1")
local T = require("../src/shared/Rules/MapTerrain")

local b = Map1.bounds

-- Sample the playable area on a grid.
local function forGrid(step: number, fn: (x: number, z: number) -> ())
	for x = b.minX, b.maxX, step do
		for z = b.minZ, b.maxZ, step do
			fn(x, z)
		end
	end
end

local trees = T.trees(Map1)

return {
	["deterministic: same input, same terrain and trees"] = function()
		assert(T.heightAt(Map1, 123.4, -56.7) == T.heightAt(Map1, 123.4, -56.7))
		local again = T.trees(Map1)
		assert(#again == #trees and again[1].x == trees[1].x and again[#again].z == trees[#trees].z)
	end,
	["hash is well distributed"] = function()
		local sum, n = 0, 0
		for i = -50, 50 do
			for j = -50, 50 do
				sum += T.hash01(i, j, 3)
				n += 1
			end
		end
		local mean = sum / n
		assert(mean > 0.47 and mean < 0.53, `hash mean {mean}`)
	end,
	["land is walkable everywhere outside the river"] = function()
		local worst, wx, wz = 0, 0, 0
		forGrid(8, function(x, z)
			if not T.isRiver(Map1, x, z) then
				local s = T.slopeAt(Map1, x, z)
				if s > worst then
					worst, wx, wz = s, x, z
				end
			end
		end)
		assert(worst < M.Movement.MaxSlopeAngle, `slope {worst} at {wx},{wz}`)
	end,
	["terrain stays inside the voxel slab"] = function()
		forGrid(16, function(x, z)
			local h = T.heightAt(Map1, x, z)
			assert(h > Map1.terrain.minY + 4 and h < Map1.terrain.maxY - 4, `height {h} at {x},{z}`)
		end)
	end,
	["reserved areas are flat"] = function()
		for _, r in Map1.reserved do
			if r.baseY ~= nil then
				for x = r.minX, r.maxX, 10 do
					for z = r.minZ, r.maxZ, 10 do
						if not T.isRiver(Map1, x, z) then
							assert(math.abs(T.heightAt(Map1, x, z) - r.baseY) < 0.01, `{r.id} not flat at {x},{z}`)
						end
					end
				end
			end
		end
	end,
	["river is water-deep except at fords, which are wadeable"] = function()
		local r = Map1.river
		local midZ = 140 -- between fords
		local cx = T.riverCenterX(Map1, midZ)
		assert(r.waterY - T.heightAt(Map1, cx, midZ) > 4, "river too shallow between fords")
		for _, f in r.fords do
			local depth = r.waterY - T.heightAt(Map1, T.riverCenterX(Map1, f.z), f.z)
			assert(depth > 0 and depth < 2, `ford at z={f.z} depth {depth}`)
		end
	end,
	["river banks rise above the water"] = function()
		local r = Map1.river
		for z = b.minZ, b.maxZ, 20 do
			local edge = T.riverCenterX(Map1, z) + r.width / 2 + r.bankWidth + 1
			assert(T.heightAt(Map1, edge, z) > r.waterY + 1, `bank under water at z={z}`)
		end
	end,
	["no trees in reserved areas, spawns, river or sector cores"] = function()
		local T2 = Map1.trees
		for _, t in trees do
			for _, r in Map1.reserved do
				assert(T.outside(r, t.x, t.z) > 0, `tree in {r.id}`)
			end
			assert(not T.isRiver(Map1, t.x, t.z), "tree in river")
			for _, s in Map1.sectors do
				local d = math.sqrt((t.x - s.x) ^ 2 + (t.z - s.z) ^ 2)
				assert(d >= s.radius * T2.sectorClearFrac, `tree in {s.id} core`)
			end
		end
	end,
	["tree count within budget, with forest beyond the bounds"] = function()
		local inside, outsideN = 0, 0
		for _, t in trees do
			if T.outside(b, t.x, t.z) > 0 then
				outsideN += 1
			else
				inside += 1
			end
		end
		assert(#trees <= Map1.trees.maxCount, `{#trees} trees over budget`)
		assert(inside > 200 and outsideN > inside, `inside {inside}, outside {outsideN}`)
	end,
	["trees keep a minimum spacing"] = function()
		local min = Map1.trees.cell * 0.5 - 0.01
		local grid: { [string]: { any } } = {}
		local function key(cx: number, cz: number): string
			return cx .. ":" .. cz
		end
		for _, t in trees do
			local cx, cz = math.floor(t.x / min), math.floor(t.z / min)
			for ox = -1, 1 do
				for oz = -1, 1 do
					for _, o in grid[key(cx + ox, cz + oz)] or {} do
						local d = math.sqrt((t.x - o.x) ^ 2 + (t.z - o.z) ^ 2)
						assert(d >= min, `trees {d} studs apart at {t.x},{t.z}`)
					end
				end
			end
			local k = key(cx, cz)
			grid[k] = grid[k] or {}
			table.insert(grid[k], t)
		end
	end,
}
