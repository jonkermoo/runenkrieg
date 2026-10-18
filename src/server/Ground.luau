--!strict
-- Changes to the terrain on the server (src/server/Damage blasts, src/server/Trees falls). Terrain changes are voxels:
-- they stay and cost nothing after.

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

-- A crater at `position` (Rules/Blast.craterPlan / craterPlanFor; `c` its config: churnFrom, churnTo, churnDepth): a
-- low rim of earth where there is ground near, the hole, then the ground around churned to blasted earth (the grass on
-- it goes: src/client/GrassFoliage).
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
	terrain:FillBall(position - Vector3.yAxis * plan.sink, plan.radius, Enum.Material.Air)
	Ground.churn(position, plan.churn, plan.radius * c.churnDepth, c)
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

-- a ball of `material` (a tree's root ball of mud), or Air (its pit)
function Ground.ball(position: Vector3, radius: number, material: Enum.Material)
	workspace.Terrain:FillBall(position, radius, material)
end

return Ground
