--!strict
-- Changes to the terrain on the server (src/server/Damage blasts, src/server/Trees falls). Terrain changes are voxels:
-- they stay and cost nothing after, except craters, which fill back in over a few minutes (Rules/Refill,
-- Config/Damage.Blast.Crater.Refill); dug ground (gun pits here, trenches: src/server/Build) never does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DamageCfg = require(Shared.Config.Damage)
local Blast = require(Shared.Rules.Blast)
local Refill = require(Shared.Rules.Refill)
local Rules = require(Shared.Rules.Artillery)

local Ground = {}

local VOXEL = 4 -- terrain voxel size (studs)

-- Craters filling back in. Per voxel ("x,y,z" in voxel units) a blast changed: what it was before the first blast there
-- (`bo`, `bm`), what the latest one left (`fo`, `fm`) and that crater's id. Per crater: when it was made (os.clock, moved
-- back when the cap starts it early), its voxels' box (`lo`, `hi`, voxel units) and keys, and the share filled so far.
type Voxel = { bo: number, bm: Enum.Material, fo: number, fm: Enum.Material, id: number }
type Crater = { id: number, born: number, lo: Vector3, hi: Vector3, keys: { string }, share: number }
local voxels: { [string]: Voxel } = {}
local craters: { Crater } = {} -- oldest first
local nextCrater = 0
-- gun pits' voxels (Ground.pit), never refilled; trenches' come from src/server/Build (Ground.start)
local pitted: { [string]: boolean } = {}
local trenched: (string) -> boolean = function(_key: string)
	return false
end
-- whether a point is within some studs of a trench's ground (src/server/Build.nearTrench): craters stop short of it
local nearTrench: (Vector3, number) -> boolean = function(_p: Vector3, _extra: number)
	return false
end

local function dug(key: string): boolean
	return pitted[key] == true or trenched(key)
end

-- a region's corner voxel in voxel units (the region is on the grid), and the corner
local function gridOf(region: Region3): (number, number, number, Vector3)
	local corner = region.CFrame.Position - region.Size / 2
	return math.round(corner.X / VOXEL), math.round(corner.Y / VOXEL), math.round(corner.Z / VOXEL), corner
end

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
-- Every voxel it changes is kept to fill back in (Ground.record); first, `c.Refill.rimFill` of what older craters under
-- its thrown earth still lack is put back.
function Ground.crater(position: Vector3, plan: any, c: any)
	if not plan then
		return
	end
	local terrain = workspace.Terrain
	local churnTo = (Enum.Material :: any)[c.churnTo]
	local first = plan.rim[1]
	local outer = if first then first.radius + Vector3.new(first.dx, 0, first.dz).Magnitude else plan.mouth
	local across = math.max(plan.churn, plan.mouth, outer)
	local up = math.max(plan.depth * 3, plan.radius * c.churnDepth, plan.radius * 2 + outer)
	local reach = Vector3.new(across, up, across)
	local region = Region3.new(position - reach, position + reach):ExpandToGrid(VOXEL)
	local ok, mats0, occs0 = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if c.Refill and ok then
		Ground.rimFill(position, region, plan.mouth, outer, c.Refill.rimFill)
	end
	for _, b in plan.rim do
		local over = position + Vector3.new(b.dx, plan.radius, b.dz)
		local hit = workspace:Raycast(over, Vector3.yAxis * -plan.radius * 3, terrainOnly)
		if hit and not nearTrench(hit.Position, b.radius) then
			terrain:FillBall(hit.Position - Vector3.yAxis * b.sink, b.radius, churnTo)
		end
	end
	Ground.bowl(position, plan.mouth, plan.depth)
	Ground.churn(position, plan.churn, plan.radius * c.churnDepth, c)
	if c.Refill and ok then
		Ground.record(region, mats0, occs0, c.Refill)
	end
end

-- Older craters' voxels in `region` under a new blast's thrown earth (past its `mouth`, out to `outer`, flat, round
-- `position`) get `share` of what they lack put back, as mud.
function Ground.rimFill(position: Vector3, region: Region3, mouth: number, outer: number, share: number)
	local terrain = workspace.Terrain
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return
	end
	local gx, gy, gz, corner = gridOf(region)
	local size = mats.Size
	local changed = false
	for ix = 1, size.X do
		for iz = 1, size.Z do
			local x, z = corner.X + (ix - 0.5) * VOXEL, corner.Z + (iz - 0.5) * VOXEL
			if Refill.underRim(math.sqrt((x - position.X) ^ 2 + (z - position.Z) ^ 2), mouth, outer) then
				for iy = 1, size.Y do
					local key = `{gx + ix - 1},{gy + iy - 1},{gz + iz - 1}`
					local v = voxels[key]
					if v and not dug(key) then
						local o = Refill.rimFilled(occs[ix][iy][iz], v.bo, share)
						if o > occs[ix][iy][iz] then
							occs[ix][iy][iz] = o
							if mats[ix][iy][iz] == Enum.Material.Air then
								mats[ix][iy][iz] = Enum.Material.Mud
							end
							changed = true
						end
					end
				end
			end
		end
	end
	if changed then
		terrain:WriteVoxels(region, VOXEL, mats, occs)
	end
end

-- A new crater: every voxel of `region` that differs from before the blast (`mats0`, `occs0`) fills back in from how it
-- is now. A voxel an older crater had keeps the ground from before that one and is this crater's now. Past
-- `r.maxCraters` still waiting, the oldest start filling now.
function Ground.record(region: Region3, mats0: any, occs0: any, r: any)
	local terrain = workspace.Terrain
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return
	end
	nextCrater += 1
	local crater: Crater =
		{ id = nextCrater, born = os.clock(), lo = Vector3.zero, hi = Vector3.zero, keys = {}, share = 0 }
	local gx, gy, gz = gridOf(region)
	local size = mats.Size
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for ix = 1, size.X do
		for iy = 1, size.Y do
			for iz = 1, size.Z do
				local o, m = occs[ix][iy][iz], mats[ix][iy][iz]
				local o0, m0 = occs0[ix][iy][iz], mats0[ix][iy][iz]
				if math.abs(o - o0) > 1e-3 or m ~= m0 then
					local at = Vector3.new(gx + ix - 1, gy + iy - 1, gz + iz - 1)
					local key = `{at.X},{at.Y},{at.Z}`
					if not dug(key) then
						local v = voxels[key]
						if v then
							v.fo, v.fm, v.id = o, m, crater.id
						else
							voxels[key] = { bo = o0, bm = m0, fo = o, fm = m, id = crater.id }
						end
						table.insert(crater.keys, key)
						lo, hi = lo:Min(at), hi:Max(at)
					end
				end
			end
		end
	end
	if #crater.keys == 0 then
		return
	end
	crater.lo, crater.hi = lo, hi
	table.insert(craters, crater)
	local now = os.clock()
	local waiting = {}
	for _, k in craters do
		if now - k.born < r.delay then
			table.insert(waiting, k)
		end
	end
	for i = 1, Refill.overCap(#waiting, r.maxCraters) do
		local k = waiting[i]
		k.born = now - Refill.startNow(now - k.born, r)
	end
end

-- Writes crater `k`'s voxels `share` filled back (its mud gone when `done`); returns how many voxels its box holds.
-- Voxels a later crater took are left to that one, dug ones as they are (and forgotten).
local function refillCrater(k: Crater, share: number, done: boolean): number
	local terrain = workspace.Terrain
	local region = Region3.new(k.lo * VOXEL, (k.hi + Vector3.one) * VOXEL)
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return 0
	end
	local size = mats.Size
	for _, key in k.keys do
		local v = voxels[key]
		if v and v.id == k.id then
			if dug(key) then
				voxels[key] = nil
			else
				local at = string.split(key, ",")
				local ix = (tonumber(at[1]) :: number) - k.lo.X + 1
				local iy = (tonumber(at[2]) :: number) - k.lo.Y + 1
				local iz = (tonumber(at[3]) :: number) - k.lo.Z + 1
				local o = Refill.occupancy(v.fo, v.bo, share)
				occs[ix][iy][iz] = o
				mats[ix][iy][iz] = Refill.material(o, v.bm, v.fm, done, Enum.Material.Air, Enum.Material.Mud)
				if done then
					voxels[key] = nil
				end
			end
		end
	end
	terrain:WriteVoxels(region, VOXEL, mats, occs)
	return size.X * size.Y * size.Z
end

-- Starts the craters filling back in: every `tick` s each crater due a step is written, oldest first, at most `budget`
-- voxels a tick (the rest next tick). `isTrench`: whether a trench touched a voxel (src/server/Build.dug); `near`:
-- whether a point is within some studs of a trench's ground (src/server/Build.nearTrench), where craters stop.
function Ground.start(isTrench: (string) -> boolean, near: ((Vector3, number) -> boolean)?)
	trenched = isTrench
	if near then
		nearTrench = near
	end
	task.spawn(function()
		while true do
			local r = DamageCfg.Blast.Crater.Refill
			task.wait(r.tick)
			local now = os.clock()
			local left = r.budget
			local i = 1
			while i <= #craters and left > 0 do
				local k = craters[i]
				local age = now - k.born
				if Refill.done(age, r) then
					left -= refillCrater(k, 1, true)
					table.remove(craters, i)
				else
					local share = Refill.share(age, r)
					if share > k.share then
						left -= refillCrater(k, share, false)
						k.share = share
					end
					i += 1
				end
			end
		end
	end)
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
			if lower > 0 and not wet and not nearTrench(Vector3.new(x, position.Y, z), VOXEL / 2) then
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
			local inside = (x - position.X) ^ 2 + (z - position.Z) ^ 2 <= radius * radius
			if inside and not nearTrench(Vector3.new(x, position.Y, z), VOXEL / 2) then
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

-- the ground under a pit to come (Ground.pit's `base`): its region read once, at the pit's full size
export type PitBase = { region: Region3, mats: any, occs: any }

local function copy(grid: any): any
	local out = table.create(#grid)
	for x = 1, #grid do
		local plane = grid[x]
		local p = table.create(#plane)
		for y = 1, #plane do
			p[y] = table.clone(plane[y])
		end
		out[x] = p
	end
	out.Size = grid.Size -- (ReadVoxels' grids carry their size)
	return out
end

-- Reads the ground a pit (Ground.pit's arguments, at its full depth) will reach, to dig it in stages; nil when it
-- can't be read.
function Ground.pitBase(
	position: Vector3,
	radius: number,
	depth: number,
	rim: number,
	rimHeight: number,
	ramp: { length: number }?,
	wall: number?
): PitBase?
	local terrain = workspace.Terrain
	local lean = if wall then 1 / math.tan(math.rad(wall)) else 0
	local out = radius + depth * lean + rim + (if ramp then ramp.length else 0)
	local reach = Vector3.new(out, depth + rimHeight + VOXEL * 3, out)
	local region = Region3.new(position - reach, position + reach):ExpandToGrid(VOXEL)
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return nil
	end
	return { region = region, mats = mats, occs = occs }
end

-- Puts the ground back as `base` read it (a built gun's pit filled in)
function Ground.restore(base: PitBase)
	workspace.Terrain:WriteVoxels(base.region, VOXEL, base.mats, base.occs)
end

-- A gun's pit (src/server/Artillery `dig`): within `radius` of `position` the ground cut down to a level floor `depth`
-- under it (the top voxel left part full, so the floor sits at that height; mud; filled up to it where the ground falls
-- away, on a slope), and a rim of earth `rimHeight` high thrown up round it over the next `rim` studs, peaked in its
-- middle, following the ground (the rim at least two voxels wide, or no voxel centre falls in it: Studio round 13c). Voxel by voxel with
-- fractional occupancy: a FillCylinder of Air that ends inside a 4-stud voxel cuts nothing (Studio 2026-10-21). A
-- smooth surface stands at its top voxel's CENTRE + 4 x occupancy (measured in Studio), not its bottom.
-- `ramp` (optional): a way in, a lane `width` wide running out along `dir` (flat, unit) from the floor's edge, its floor
-- rising from the pit's floor to the ground over `length` studs, cut through the rim.
-- `wall` (optional, degrees): the pit's wall (and the ramp's sides) lean back at this angle from the floor's edge up to
-- the ground, where the rim starts (a trench's wall: Config/Build.Trench.wallAngle); nil: cut straight down.
-- `base` (optional, Ground.pitBase): the ground as it was before any of this pit, which it is dug into afresh (a
-- player-built gun's pit deepening stage by stage, src/server/Build).
-- Returns how far out from `position` it reached.
function Ground.pit(
	position: Vector3,
	radius: number,
	depth: number,
	rim: number,
	rimHeight: number,
	ramp: { dir: Vector3, width: number, length: number }?,
	wall: number?,
	base: PitBase?
): number
	local terrain = workspace.Terrain
	local lean = if wall then 1 / math.tan(math.rad(wall)) else 0 -- studs out per stud up
	local top = radius + depth * lean -- the wall's top edge, on the ground
	local out = top + rim + (if ramp then ramp.length else 0)
	local region, mats, occs
	if base then
		region, mats, occs = base.region, copy(base.mats), copy(base.occs)
	else
		local reach = Vector3.new(out, depth + rimHeight + VOXEL * 3, out)
		region = Region3.new(position - reach, position + reach):ExpandToGrid(VOXEL)
		local ok
		ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
		if not ok then
			return out
		end
	end
	local size = mats.Size
	local corner = region.CFrame.Position - region.Size / 2
	local floor = position.Y - depth
	local gx, gy, gz = gridOf(region)
	for ix = 1, size.X do
		for iz = 1, size.Z do
			local x, z = corner.X + (ix - 0.5) * VOXEL, corner.Z + (iz - 0.5) * VOXEL
			local d = math.sqrt((x - position.X) ^ 2 + (z - position.Z) ^ 2)
			-- how low this column is cut (nil: not), and whether it is the floor (filled up to it as well)
			local cut: number? = nil
			local level = d <= radius
			if level then
				cut = floor
			elseif d <= top then
				cut = floor + (d - radius) / lean
			end
			local inRamp = false
			if ramp then
				local along = (x - position.X) * ramp.dir.X + (z - position.Z) * ramp.dir.Z
				local across = math.abs((x - position.X) * ramp.dir.Z - (z - position.Z) * ramp.dir.X)
				local side = across - ramp.width / 2
				if along > 0 and along <= radius + ramp.length and (side <= 0 or (wall and side <= depth * lean)) then
					local slope = floor + depth * math.clamp((along - radius) / ramp.length, 0, 1)
					local lane = slope + (if side > 0 then side / lean else 0)
					inRamp = side <= 0
					cut = if cut then math.min(cut, lane) else lane
				end
			end
			local raise = not level and not inRamp and d > top and d <= top + rim
			if cut or raise then
				-- dug: no crater here fills back in, now or later
				for iy = 1, size.Y do
					pitted[`{gx + ix - 1},{gy + iy - 1},{gz + iz - 1}`] = true
				end
			end
			if raise then
				-- the column's top now, then raised by the rim's height here
				local ground: number? = nil
				for iy = size.Y, 1, -1 do
					if occs[ix][iy][iz] > 0 then
						ground = corner.Y + (iy - 0.5) * VOXEL + occs[ix][iy][iz] * VOXEL
						break
					end
				end
				if ground then
					local bump = rimHeight * (1 - math.abs(d - top - rim / 2) / (rim / 2))
					for iy = 1, size.Y do
						local mid = corner.Y + (iy - 0.5) * VOXEL
						local want = math.clamp((ground + bump - mid) / VOXEL, 0, 1)
						if want > occs[ix][iy][iz] then
							occs[ix][iy][iz] = want
							if mats[ix][iy][iz] == Enum.Material.Air then
								mats[ix][iy][iz] = Enum.Material.Ground
							end
						end
					end
				end
			end
			if cut then
				for iy = 1, size.Y do
					local mid = corner.Y + (iy - 0.5) * VOXEL
					local keep = math.clamp((cut - mid) / VOXEL, 0, 1)
					-- cut down to it; the floor also filled up to it where the ground fell away (downhill on a slope)
					if occs[ix][iy][iz] > keep or (level and occs[ix][iy][iz] ~= keep) then
						occs[ix][iy][iz] = keep
						mats[ix][iy][iz] = if keep <= 0 then Enum.Material.Air else Enum.Material.Mud
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, VOXEL, mats, occs)
	return out
end

-- The ground under a gun standing on the terrain (src/server/Artillery, Config/Artillery `level`): within the box
-- `lo`..`hi` (x, z in the space of `pivot`, whose height is the gun's foot) cut down or filled up to a level floor at
-- the foot, easing back to the ground as it was over the next `blend` studs (Rules/Artillery.levelAt); its top
-- `material` (no grass). Voxel by voxel with fractional occupancy, as Ground.pit. Columns with water, or no ground
-- within reach, are left alone. Returns how far out from the pivot it reached.
function Ground.level(pivot: CFrame, lo: { number }, hi: { number }, blend: number, material: Enum.Material): number
	local terrain = workspace.Terrain
	local foot = pivot.Position
	local out = 0
	for _, c in { { lo[1], lo[2] }, { lo[1], hi[2] }, { hi[1], lo[2] }, { hi[1], hi[2] } } do
		out = math.max(out, Vector2.new(c[1], c[2]).Magnitude + blend)
	end
	local reach = Vector3.new(out, blend + VOXEL * 4, out)
	local region = Region3.new(foot - reach, foot + reach):ExpandToGrid(VOXEL)
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return out
	end
	local size = mats.Size
	local corner = region.CFrame.Position - region.Size / 2
	for ix = 1, size.X do
		for iz = 1, size.Z do
			local x, z = corner.X + (ix - 0.5) * VOXEL, corner.Z + (iz - 0.5) * VOXEL
			local l = pivot:PointToObjectSpace(Vector3.new(x, foot.Y, z))
			-- the column's top as it is (nil: none in reach, or water in it)
			local ground: number? = nil
			for iy = size.Y, 1, -1 do
				if mats[ix][iy][iz] == Enum.Material.Water then
					ground = nil
					break
				end
				if ground == nil and occs[ix][iy][iz] > 0 then
					ground = corner.Y + (iy - 0.5) * VOXEL + occs[ix][iy][iz] * VOXEL
				end
			end
			local want = if ground then Rules.levelAt(l.X, l.Z, lo, hi, blend, foot.Y, ground) else nil
			if want then
				for iy = 1, size.Y do
					local mid = corner.Y + (iy - 0.5) * VOXEL
					local keep = math.clamp((want - mid) / VOXEL, 0, 1)
					occs[ix][iy][iz] = keep
					if keep <= 0 then
						mats[ix][iy][iz] = Enum.Material.Air
					elseif mats[ix][iy][iz] == Enum.Material.Air or mid > want - VOXEL * 2 then
						mats[ix][iy][iz] = material -- the top two voxels (and what it is filled up with)
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, VOXEL, mats, occs)
	return out
end

-- a ball of `material` (a tree's root ball of mud), or Air (its pit)
function Ground.ball(position: Vector3, radius: number, material: Enum.Material)
	workspace.Terrain:FillBall(position, radius, material)
end

return Ground
