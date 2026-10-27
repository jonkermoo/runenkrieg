--!strict
-- Terrain from Rules/MapTerrain via WriteVoxels (4-stud voxels, fractional occupancy for smooth
-- surfaces). Water is written only inside the river channel.

local Ground = {}

local RES = 4
local CHUNK = 32 -- columns per chunk side

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Flat-color terrain: override each terrain material with an untextured MaterialVariant (no maps),
-- then color it from the palette. The override also removes grass-blade decoration.
function Ground.applyPalette(palette: any)
	local terrain = workspace.Terrain
	local MaterialService = game:GetService("MaterialService")
	for name, color in palette.Terrain do
		local base = (Enum.Material :: any)[name]
		local variantName = "Flat" .. name
		local v = MaterialService:FindFirstChild(variantName) or Instance.new("MaterialVariant")
		v.Name = variantName;
		(v :: MaterialVariant).BaseMaterial = base
		v.Parent = MaterialService
		MaterialService:SetBaseMaterialOverride(base, variantName)
		terrain:SetMaterialColor(base, rgb(color))
	end
	local w = palette.Water
	terrain.WaterColor = rgb(w.color)
	terrain.WaterTransparency = w.transparency
	terrain.WaterReflectance = w.reflectance
	terrain.WaterWaveSize = w.waveSize
end

-- Air over everything a map's terrain and skirt cover (a map built beside another clears only its own ground).
local function clearOwn(map: any)
	local b, reach, tc = map.bounds, map.terrainMargin + (if map.skirt then map.skirt.width else 0), map.terrain
	local x = b.minX - reach
	while x < b.maxX + reach do
		local w = math.min(512, b.maxX + reach - x)
		local z = b.minZ - reach
		while z < b.maxZ + reach do
			local d = math.min(512, b.maxZ + reach - z)
			local low = math.min(tc.minY, -16)
			workspace.Terrain:FillBlock(
				CFrame.new(x + w / 2, (low + tc.maxY) / 2, z + d / 2),
				Vector3.new(w, tc.maxY - low + 8, d),
				Enum.Material.Air
			)
			z += d
		end
		x += w
		task.wait()
	end
end

function Ground.build(map: any, MT: any, palette: any): number
	local terrain = workspace.Terrain
	if map.offMap then
		clearOwn(map)
	else
		terrain:Clear()
	end
	task.wait()
	Ground.applyPalette(palette)

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
							mx[iy][iz] = if h - (y0 + RES) > tc.surfaceDepth then under else surface
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
	Ground.skirt(map, MT)
	return chunks
end

-- Flat low-detail ground around the detailed area, plus distant hills for the horizon.
function Ground.skirt(map: any, MT: any)
	local terrain = workspace.Terrain
	local b, m, sk = map.bounds, map.terrainMargin, map.skirt
	if not sk then
		return
	end
	local ix0, ix1 = b.minX - m, b.maxX + m
	local iz0, iz1 = b.minZ - m, b.maxZ + m
	local ox0, ox1 = ix0 - sk.width, ix1 + sk.width
	local oz0, oz1 = iz0 - sk.width, iz1 + sk.width
	local depth = 16
	local rects = {
		{ ox0, ox1, oz0, iz0 }, -- north band
		{ ox0, ox1, iz1, oz1 }, -- south band
		{ ox0, ix0, iz0, iz1 }, -- west band
		{ ix1, ox1, iz0, iz1 }, -- east band
	}
	for _, r in rects do
		local x = r[1]
		while x < r[2] do
			local w = math.min(512, r[2] - x)
			local z = r[3]
			while z < r[4] do
				local d = math.min(512, r[4] - z)
				terrain:FillBlock(
					CFrame.new(x + w / 2, -depth / 2, z + d / 2),
					Vector3.new(w, depth, d),
					Enum.Material.Grass
				)
				z += d
			end
			x += w
		end
		task.wait()
	end
	for _, h in sk.hills do
		-- A ball sunk so only a cap of `peak` height shows.
		terrain:FillBall(Vector3.new(h[1], h[4] - h[3], h[2]), h[3], Enum.Material.Grass)
		task.wait()
	end
	-- Carry the river through the skirt so it flows out into the fog instead of ending at a wall.
	local r = map.river
	if r then
		local seg = 16
		for _, span in { { oz0, iz0 }, { iz1, oz1 } } do
			local z = span[1]
			while z < span[2] do
				local zc = z + seg / 2
				local x = MT.riverCenterX(map, zc)
				local cf = CFrame.new(x, (r.bedY + 4) / 2, zc)
				terrain:FillBlock(cf, Vector3.new(r.width + 8, 4 - r.bedY, seg + 2), Enum.Material.Air)
				terrain:FillBlock(
					CFrame.new(x, (r.bedY - 4 + r.waterY) / 2, zc),
					Vector3.new(r.width, r.waterY - r.bedY + 4, seg + 2),
					Enum.Material.Water
				)
				z += seg
			end
		end
		task.wait()
	end
end

return Ground
