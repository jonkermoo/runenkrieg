--!strict
-- Terrain from Rules/MapTerrain via WriteVoxels (4-stud voxels, fractional occupancy for smooth
-- surfaces). Water is written only inside the river channel.

local Ground = {}

local RES = 4
local CHUNK = 32 -- columns per chunk side

local MATERIAL_COLORS = {
	Grass = Color3.fromRGB(96, 142, 58),
	LeafyGrass = Color3.fromRGB(78, 122, 48),
	Ground = Color3.fromRGB(122, 100, 74),
	Mud = Color3.fromRGB(92, 76, 58),
	Rock = Color3.fromRGB(122, 120, 112),
}

function Ground.build(map: any, MT: any): number
	local terrain = workspace.Terrain
	terrain:Clear()
	task.wait()
	pcall(function()
		for name, color in MATERIAL_COLORS do
			terrain:SetMaterialColor((Enum.Material :: any)[name], color)
		end
		terrain.Decoration = true -- animated grass blades on Grass
	end)

	local b, m, tc = map.bounds, map.terrainMargin, map.terrain
	local vx0, vx1 = math.floor((b.minX - m) / RES), math.ceil((b.maxX + m) / RES) - 1
	local vz0, vz1 = math.floor((b.minZ - m) / RES), math.ceil((b.maxZ + m) / RES) - 1
	local vy0, vy1 = math.floor(tc.minY / RES), math.ceil(tc.maxY / RES) - 1
	local ny = vy1 - vy0 + 1
	local river = map.river
	local water, air, under = Enum.Material.Water, Enum.Material.Air, Enum.Material.Ground
	local chunks = 0

	for cx = vx0, vx1, CHUNK do
		for cz = vz0, vz1, CHUNK do
			local nx = math.min(CHUNK, vx1 - cx + 1)
			local nz = math.min(CHUNK, vz1 - cz + 1)
			local mats, occs = {}, {}
			for ix = 1, nx do
				local mx, ox = table.create(ny), table.create(ny)
				for iy = 1, ny do
					mx[iy], ox[iy] = table.create(nz), table.create(nz)
				end
				mats[ix], occs[ix] = mx, ox
				local x = (cx + ix - 0.5) * RES
				for iz = 1, nz do
					local z = (cz + iz - 0.5) * RES
					local h = MT.heightAt(map, x, z)
					local surface = (Enum.Material :: any)[MT.materialAt(map, x, z)]
					local inRiver = river ~= nil and MT.isRiver(map, x, z)
					for iy = 1, ny do
						local y0 = (vy0 + iy - 1) * RES
						local occ = math.clamp((h - y0) / RES, 0, 1)
						if occ > 0 then
							mx[iy][iz] = if h - (y0 + RES) > RES then under else surface
							ox[iy][iz] = occ
						elseif inRiver and y0 < river.waterY then
							mx[iy][iz] = water
							ox[iy][iz] = math.clamp((river.waterY - y0) / RES, 0, 1)
						else
							mx[iy][iz] = air
							ox[iy][iz] = 0
						end
					end
				end
			end
			local region = Region3.new(
				Vector3.new(cx * RES, vy0 * RES, cz * RES),
				Vector3.new((cx + nx) * RES, (vy1 + 1) * RES, (cz + nz) * RES)
			)
			terrain:WriteVoxels(region, RES, mats, occs)
			chunks += 1
			task.wait()
		end
	end
	return chunks
end

return Ground
