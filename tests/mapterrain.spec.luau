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
	["terrain stays inside the voxel slab, including the margin"] = function()
		local m = Map1.terrainMargin
		for x = b.minX - m, b.maxX + m, 16 do
			for z = b.minZ - m, b.maxZ + m, 16 do
				local h = T.heightAt(Map1, x, z)
				assert(h > Map1.terrain.minY + 4 and h < Map1.terrain.maxY - 4, `height {h} at {x},{z}`)
			end
		end
	end,
	["hills outside the bounds are dramatic, and flat again at the margin edge"] = function()
		local m = Map1.terrainMargin
		local peak = 0
		for x = b.minX, b.maxX, 20 do
			for _, z in { b.minZ - 200, b.maxZ + 200, b.minZ - 250, b.maxZ + 250 } do
				peak = math.max(peak, T.heightAt(Map1, x, z))
			end
		end
		assert(peak > 30, `outer hills only reach {peak}`)
		for x = b.minX, b.maxX, 50 do
			local z = b.maxZ + m - 1
			if not T.isRiver(Map1, x, z) then
				local h = T.heightAt(Map1, x, z)
				assert(math.abs(h) < 1.5, `margin edge not flat at x={x}: {h}`)
			end
		end
	end,
	["ground inside the bounds is uneven, not flat"] = function()
		-- mean absolute height change over 6 studs, away from reserved flats
		local sum, n = 0, 0
		forGrid(23, function(x, z)
			if x < 1050 and not T.isRiver(Map1, x, z) then
				sum += math.abs(T.heightAt(Map1, x + 6, z) - T.heightAt(Map1, x, z))
				n += 1
			end
		end)
		assert(sum / n > 0.25, `ground too flat: {sum / n}`)
	end,
	["no flattened areas: the village is as uneven as open ground"] = function()
		local function roughness(x0: number, x1: number): number
			local sum, n = 0, 0
			for x = x0, x1, 23 do
				for z = b.minZ, b.maxZ, 23 do
					if not T.isRiver(Map1, x, z) then
						sum += math.abs(T.heightAt(Map1, x + 6, z) - T.heightAt(Map1, x, z))
						n += 1
					end
				end
			end
			return sum / n
		end
		local village = roughness(1150, 1900)
		assert(village > 0.3, `village terrain too flat: {village}`)
		local open = roughness(-150, 480)
		assert(open > 0.3, `open ground too flat: {open}`)
		for _, r in Map1.reserved do
			assert(r.baseY == nil, `{r.id} is still flattened`)
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
	["trees never float and never stand on rock faces"] = function()
		local r = Map1.trees.footprint
		for i = 1, #trees, 7 do
			local t = trees[i]
			local base = T.treeBaseY(Map1, t.x, t.z)
			for k = 0, 5 do
				local a = k * math.pi / 3
				assert(base < T.heightAt(Map1, t.x + r * math.cos(a), t.z + r * math.sin(a)), "trunk floats")
			end
			assert(T.slopeAt(Map1, t.x, t.z) <= Map1.trees.maxSlope, "tree on a rock face")
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
