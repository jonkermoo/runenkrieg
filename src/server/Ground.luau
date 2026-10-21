--!strict
-- Changes to the terrain on the server (src/server/Damage blasts, src/server/Trees falls). Terrain changes are voxels:
-- they stay and cost nothing after.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Blast = require(ReplicatedStorage:WaitForChild("Shared").Rules.Blast)

local Ground = {}

local VOXEL = 4 -- terrain voxel size (studs)

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

-- the terrain's height under (x, z) between `top` and `top - depth`, or nil
function Ground.heightAt(x: number, z: number, top: number, depth: number): number?
	local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.yAxis * -depth, terrainOnly)
	return if hit then hit.Position.Y else nil
end

-- A crater at `position` (Rules/Blast.craterPlan; `c` its config: churnFrom, churnTo, churnDepth): a low rim of earth
-- where there is ground near, the bowl, then the ground around churned to blasted earth (the grass on it goes:
-- src/client/GrassFoliage).
function Ground.crater(position: Vector3, plan: any, c: any)
	if not plan then
		return
	end
	local terrain = workspace.Terrain
	local churnTo = (Enum.Material :: any)[c.churnTo]
	for _, b in plan.rim do
		local over = position + Vector3.new(b.dx, plan.radius, b.dz)
		local hit = workspace:Raycast(over, Vector3.yAxis * -plan.radius * 3, terrainOnly)
		if hit then
			terrain:FillBall(hit.Position - Vector3.yAxis * b.sink, b.radius, churnTo)
		end
	end
	Ground.bowl(position, plan.mouth, plan.depth)
	Ground.churn(position, plan.churn, plan.radius * c.churnDepth, c)
end

-- The ground within `mouth` of `position` lowered by Blast.bowlDepth, column by column, following its shape (a level cut
-- left a cliff on the uphill side of a slope, Studio 2026-10-18). Only the ground near the blast's height: `depth` x 3
-- up or down. Columns with water are left alone.
function Ground.bowl(position: Vector3, mouth: number, depth: number)
	local terrain = workspace.Terrain
	local reach = Vector3.new(mouth, depth * 3, mouth)
	local region = Region3.new(position - reach, position + reach):ExpandToGrid(VOXEL)
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return
	end
	local size = mats.Size
	local corner = region.CFrame.Position - region.Size / 2
	for ix = 1, size.X do
		for iz = 1, size.Z do
			local x, z = corner.X + (ix - 0.5) * VOXEL, corner.Z + (iz - 0.5) * VOXEL
			local lower = Blast.bowlDepth(math.sqrt((x - position.X) ^ 2 + (z - position.Z) ^ 2), mouth, depth)
			local wet = false
			local column = table.create(size.Y, 0)
			for iy = 1, size.Y do
				column[iy] = occs[ix][iy][iz]
				wet = wet or mats[ix][iy][iz] == Enum.Material.Water
			end
			if lower > 0 and not wet then
				local out = Blast.lowerColumn(column, corner.Y, VOXEL, lower)
				for iy = 1, size.Y do
					occs[ix][iy][iz] = out[iy]
					if out[iy] <= 0 then
						mats[ix][iy][iz] = Enum.Material.Air
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, VOXEL, mats, occs)
end

-- the ground within `radius` across and `depth` up or down of `position` turns from c.churnFrom to c.churnTo
function Ground.churn(position: Vector3, radius: number, depth: number, c: any)
	local terrain = workspace.Terrain
	local churnTo = (Enum.Material :: any)[c.churnTo]
	local from: { [Enum.Material]: boolean } = {}
	for _, m in c.churnFrom do
		from[(Enum.Material :: any)[m]] = true
	end
	local reach = Vector3.new(radius, depth, radius)
	local region = Region3.new(position - reach, position + reach):ExpandToGrid(VOXEL)
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return
	end
	local size = mats.Size
	local corner = region.CFrame.Position - region.Size / 2
	local changed = false
	for ix = 1, size.X do
		for iz = 1, size.Z do
			local x, z = corner.X + (ix - 0.5) * VOXEL, corner.Z + (iz - 0.5) * VOXEL
			if (x - position.X) ^ 2 + (z - position.Z) ^ 2 <= radius * radius then
				for iy = 1, size.Y do
					if from[mats[ix][iy][iz]] then
						mats[ix][iy][iz] = churnTo
						changed = true
					end
				end
			end
		end
	end
	if changed then
		terrain:WriteVoxels(region, VOXEL, mats, occs)
	end
end

-- A gun's pit (src/server/Artillery `dig`): within `radius` of `position` the ground cut down to a level floor `depth`
-- under it (the top voxel left part full, so the floor sits at that height; mud), and a rim of earth `rimHeight` high
-- thrown up round it over the next `rim` studs, peaked in its middle, following the ground. Voxel by voxel with
-- fractional occupancy: a FillCylinder of Air that ends inside a 4-stud voxel cuts nothing (Studio 2026-10-21).
function Ground.pit(position: Vector3, radius: number, depth: number, rim: number, rimHeight: number)
	local terrain = workspace.Terrain
	local reach = Vector3.new(radius + rim, depth + rimHeight + VOXEL * 3, radius + rim)
	local region = Region3.new(position - reach, position + reach):ExpandToGrid(VOXEL)
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return
	end
	local size = mats.Size
	local corner = region.CFrame.Position - region.Size / 2
	local floor = position.Y - depth
	for ix = 1, size.X do
		for iz = 1, size.Z do
			local x, z = corner.X + (ix - 0.5) * VOXEL, corner.Z + (iz - 0.5) * VOXEL
			local d = math.sqrt((x - position.X) ^ 2 + (z - position.Z) ^ 2)
			if d <= radius then
				for iy = 1, size.Y do
					local y0 = corner.Y + (iy - 1) * VOXEL
					local keep = math.clamp((floor - y0) / VOXEL, 0, 1)
					if occs[ix][iy][iz] > keep then
						occs[ix][iy][iz] = keep
						mats[ix][iy][iz] = if keep <= 0 then Enum.Material.Air else Enum.Material.Mud
					end
				end
			elseif d <= radius + rim then
				-- the column's top now, then raised by the rim's height here
				local top: number? = nil
				for iy = size.Y, 1, -1 do
					if occs[ix][iy][iz] > 0 then
						top = corner.Y + (iy - 1) * VOXEL + occs[ix][iy][iz] * VOXEL
						break
					end
				end
				if top then
					local bump = rimHeight * (1 - math.abs(d - radius - rim / 2) / (rim / 2))
					for iy = 1, size.Y do
						local y0 = corner.Y + (iy - 1) * VOXEL
						local want = math.clamp((top + bump - y0) / VOXEL, 0, 1)
						if want > occs[ix][iy][iz] then
							occs[ix][iy][iz] = want
							if mats[ix][iy][iz] == Enum.Material.Air then
								mats[ix][iy][iz] = Enum.Material.Ground
							end
						end
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, VOXEL, mats, occs)
end

-- a ball of `material` (a tree's root ball of mud), or Air (its pit)
function Ground.ball(position: Vector3, radius: number, material: Enum.Material)
	workspace.Terrain:FillBall(position, radius, material)
end

return Ground
