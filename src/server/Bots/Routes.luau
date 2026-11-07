--!strict
-- Spots round Normal's sectors for the bots' squads (Config/Bots.Routes, Rules/BotSquads; user 2026-11-01: "make them
-- take advantage of the size of the map ... logical choices of where they decide to go"). For each sector and side:
-- approach spots on rings outside the zone toward that side's home (where an attacking squad gathers before it
-- pushes in) and hold spots inside the zone (where defenders stand), each on dry open ground with room to stand,
-- scored by whether the other side's view can't see it (a ray), how much stands close by (walls, trees, houses,
-- built pieces), a hold spot by how much of the other side's way in it sees (rays from its eye), and its lane (north, centre or south of the straight line home). Worked out a few spots a frame in
-- the background, again every Routes.refresh seconds (building changes the ground); until the first list is ready a
-- sector has none (the squads walk to the zone straight).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local FrontCfg = require(Shared.Config.Frontline)
local Map = require(Shared.LiveMap).map -- (the match's map)
local BotBuild = require(Shared.Rules.BotBuild)
local Squads = require(Shared.Rules.BotSquads)
local Rules = require(Shared.Rules.Bots)
local MapTerrain = require(Shared.Rules.MapTerrain)

local Routes = {}

local RT = Cfg.Routes

export type Spot = { pos: Vector3, hidden: boolean, near: number, distance: number, lane: number, sees: number? }
type Entry = { spots: { Spot }?, at: number, building: boolean }

local cache: { [string]: Entry } = {}
local generation = 0 -- bumped by Routes.clear: a build under way for an old map is dropped

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = false

-- soldiers never count as cover or as in the way
local function soldiers(): { Instance }
	local out: { Instance } = CollectionService:GetTagged(Cfg.Tag)
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(out, p.Character)
		end
	end
	return out
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- the point of sector `i` on the ground
local function point(i: number): Vector3
	local s = Map.sectors[i]
	local g = FrontCfg.GroundRay
	local hit = workspace:Raycast(Vector3.new(s.x, g.top, s.z), Vector3.new(0, -g.depth, 0), terrainOnly)
	return Vector3.new(s.x, if hit then hit.Position.Y else 0, s.z)
end

-- the way from sector `i` toward `side`'s home end (flat, unit)
local function homeward(i: number, side: string): Vector3
	local back = Map.sectors[if side == "West" then i - 1 else i + 1]
	local s = Map.sectors[i]
	local d = if back then Vector3.new(back.x - s.x, 0, back.z - s.z) else Vector3.zero
	if d.Magnitude < 1 then
		-- (its home end: away from the enemy's way, from the live map's sector chain)
		local tx, tz = BotBuild.toward(Map.sectors, i, side)
		d = Vector3.new(-tx, 0, -tz)
	end
	return d.Unit
end

-- dry ground with room to stand at (x, z) inside the map's walls, or nil
local function standable(x: number, z: number, skip: { Instance }): Vector3?
	local ix, iz = Rules.inside(x, z, Map.bounds, Cfg.Move.Edge)
	if ix ~= x or iz ~= z then
		return nil -- (beyond the walls, or too close to them)
	end
	local g = FrontCfg.GroundRay
	local hit = workspace:Raycast(Vector3.new(x, g.top, z), Vector3.new(0, -g.depth, 0), terrainOnly)
	if not hit or hit.Material == Enum.Material.Water then
		return nil
	end
	local box = OverlapParams.new()
	box.FilterType = Enum.RaycastFilterType.Exclude
	box.FilterDescendantsInstances = skip
	box.RespectCanCollide = true
	if
		#workspace:GetPartBoundsInBox(CFrame.new(hit.Position + Vector3.new(0, 3, 0)), Vector3.new(3, 5, 3), box) > 0
	then
		return nil -- (inside a house, a wall, a tree)
	end
	return hit.Position
end

-- one sector's spots for `side`: `hold` inside its zone, else approach spots outside it toward the side's home
local function build(i: number, side: string, hold: boolean, gen: number): { Spot }?
	local s = Map.sectors[i]
	local c = point(i)
	local home = homeward(i, side)
	local skip = soldiers()
	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Exclude
	rays.FilterDescendantsInstances = skip
	local near = OverlapParams.new()
	near.FilterType = Enum.RaycastFilterType.Exclude
	near.FilterDescendantsInstances = skip
	-- the far side's view: from the zone's middle (attackers' approach), or from out on the enemy's side (holding)
	local view = if hold then c - home * (s.radius + RT.view) else c
	view += Vector3.yAxis * RT.eye
	-- (holding: the far side's view points across its way in, each a spot's eye looks at)
	local views: { Vector3 } = {}
	if hold then
		for _, deg in RT.holdViews do
			local dir = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(deg)) * -home
			table.insert(views, c + dir * (s.radius + RT.view) + Vector3.yAxis * RT.eye)
		end
	end
	local homeX, homeZ = c.X + home.X * 100, c.Z + home.Z * 100
	local out: { Spot } = {}
	local radii = {}
	if hold then
		for _, share in RT.holdRings do
			table.insert(radii, s.radius * share)
		end
	else
		for _, r in RT.rings do
			table.insert(radii, s.radius + r)
		end
	end
	-- (approaching: the side's own sector behind, the way back to it; a spot across the river from it slides back to the
	-- side's own bank, Config/Bots.Routes.wet)
	local back = Map.sectors[if side == "West" then i - 1 else i + 1]
	local perRing = if hold then RT.holdPerRing else RT.perRing
	local done = 0
	for _, r in radii do
		for k = 0, perRing - 1 do
			-- across the arc each side of the way home (holding: all round)
			local a = if hold
				then k / perRing * 2 * math.pi
				else math.rad(-RT.arc + 2 * RT.arc * k / math.max(perRing - 1, 1))
			local dir = if hold
				then Vector3.new(math.cos(a), 0, math.sin(a))
				else (CFrame.fromAxisAngle(Vector3.yAxis, a) * home)
			local at = c + dir * r
			if not hold and back then
				local W = RT.wet
				local _, last = MapTerrain.wetSpan(Map, at.X, at.Z, back.x, back.z, W.step, W.pad)
				if last then
					local way = Vector3.new(back.x - at.X, 0, back.z - at.Z)
					at += way * last + way.Unit * W.bank
				end
			end
			local pos = standable(at.X, at.Z, skip)
			if pos then
				local chest = (pos :: Vector3) + Vector3.yAxis * RT.chest
				local hit = workspace:Raycast(view, chest - view, rays)
				local hidden = hit ~= nil and hit.Distance < (chest - view).Magnitude - 1
				local around =
					workspace:GetPartBoundsInRadius((pos :: Vector3) + Vector3.yAxis * 3, RT.nearRadius, near)
				local sees: number? = nil
				if hold then
					local eyeAt = (pos :: Vector3) + Vector3.yAxis * RT.eye
					sees = 0
					for _, v in views do
						local look = workspace:Raycast(eyeAt, v - eyeAt, rays)
						if not look or look.Distance >= (v - eyeAt).Magnitude - 1 then
							sees = (sees :: number) + 1
						end
					end
				end
				table.insert(out, {
					pos = pos :: Vector3,
					hidden = hidden,
					near = #around,
					distance = if hold
						then flat((pos :: Vector3) - c).Magnitude
						else math.max(flat((pos :: Vector3) - c).Magnitude - s.radius, 0),
					lane = Squads.lane(homeX, homeZ, c.X, c.Z, pos.X, pos.Z, RT.laneWithin),
					sees = sees,
				})
			end
			done += 1
			if done % RT.perFrame == 0 then
				task.wait()
				if gen ~= generation then
					return nil
				end
			end
		end
	end
	return out
end

-- The spots of sector `i` for `side` (`hold`: inside the zone, else approach spots); nil until the first are worked out.
function Routes.spots(i: number, side: string, hold: boolean): { Spot }?
	local key = `{i}{side}{if hold then "H" else "A"}`
	local e = cache[key]
	local now = os.clock()
	if not e then
		e = { spots = nil, at = -math.huge, building = false }
		cache[key] = e
	end
	local entry = e :: Entry
	if not entry.building and now - entry.at >= RT.refresh then
		entry.building = true
		local gen = generation
		task.spawn(function()
			local ok, spots = pcall(build, i, side, hold, gen)
			entry.building = false
			if gen ~= generation then
				return
			end
			entry.at = os.clock()
			if ok and spots then
				entry.spots = spots
			elseif not ok then
				warn(`[Bots] routes {key}: {spots}`)
			end
		end)
	end
	return entry.spots
end

-- The ground under (x, z) (a terrain ray), for a waypoint off the spots; kept inside the map's walls.
function Routes.ground(x: number, z: number): Vector3
	x, z = Rules.inside(x, z, Map.bounds, Cfg.Move.Edge)
	local g = FrontCfg.GroundRay
	local hit = workspace:Raycast(Vector3.new(x, g.top, z), Vector3.new(0, -g.depth, 0), terrainOnly)
	return Vector3.new(x, if hit then hit.Position.Y else 0, z)
end

-- Forgets every spot (a new match: the map put back).
function Routes.clear()
	generation += 1
	table.clear(cache)
end

return Routes
