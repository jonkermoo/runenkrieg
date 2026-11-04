--!strict
-- The spots inside buildings a soldier who isn't a player could use (firing spots at windows and doorways, cover
-- behind solid wall), read off each built building (src/dev/Buildings: a Kind "Wall" section with a Lintel is an
-- opening, a Doorstep makes it a door, a Sill a window) and worked out by Rules/Indoors. Only spots with standing room
-- and a floor under them are kept. Cached per building until a piece of it goes (src/server/Destruction); a new match
-- puts fresh copies of the buildings back (src/server/DevWorld), which start with no cache.
--   Indoors.spots(building) -> { Spot }    every spot of one building (a Model tagged Config/Destruction.BuildingTag)
--   Indoors.near(at, within, kind?) -> { Spot }    across all buildings, nearest first
-- A Spot is { kind = "Window" | "Doorway" | "Cover", at: Vector3 (floor level), face: Vector3 (flat unit, out of the
-- building), story: number, building: Model }.
-- Pathfinding: every doorway and flight of stairs gets a PathfindingLink (Config/Indoors.Links: the navmesh doesn't fit
-- the bots' agent through a 4.6-wide doorway, nor up every flight), labelled for Config/Indoors.PathCosts. Made once
-- per section at start and as sections arrive; DevWorld's copies carry theirs.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local D = require(Shared.Config.Destruction)
local Cfg = require(Shared.Config.Indoors)
local Rules = require(Shared.Rules.Indoors)

local S = Cfg.Spots
local L = Cfg.Links

local Indoors = {}

Indoors.behind = 0 -- spots left out, behind an open door (Rules/Indoors.behindDoor; the bots' log)

export type Spot = { kind: Rules.Kind, at: Vector3, face: Vector3, story: number, building: Model }

local cache: { [Model]: { Spot } } = setmetatable({}, { __mode = "k" }) :: any
local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function p(v: Vector3): Rules.P
	return { x = v.X, y = v.Y, z = v.Z }
end

local function v3(q: Rules.P): Vector3
	return Vector3.new(q.x, q.y, q.z)
end

-- One wall section as a Rules piece, or nil if it isn't a whole wall section.
function Indoors.piece(section: Instance): Rules.Piece?
	if not section:IsA("Model") or section:GetAttribute("Kind") ~= "Wall" then
		return nil
	end
	local floor, wall = math.huge, nil :: BasePart?
	for _, c in section:GetChildren() do
		if c:IsA("BasePart") and c.Name == "Wall" then
			floor = math.min(floor, c.Position.Y - c.Size.Y / 2)
			wall = wall or c
		end
	end
	if not wall then
		return nil
	end
	local out = wall.CFrame.LookVector -- a wall's local -Z points outside
	out = Vector3.new(out.X, 0, out.Z).Unit
	local thick = wall.Size.Z
	local story = section:GetAttribute("Story") :: number? or 0
	local lintel = section:FindFirstChild("Lintel")
	if lintel and lintel:IsA("BasePart") then
		-- the lintel sits on the outside face, 0.15 proud, 1.3 wider than the opening
		local c = lintel.Position - out * (thick / 2 + 0.15)
		local kind = if section:FindFirstChild("Doorstep") then "door" else "window"
		return {
			kind = kind,
			at = p(Vector3.new(c.X, floor, c.Z)),
			out = p(out),
			width = lintel.Size.X - 1.3,
			thick = thick,
			story = story,
		}
	end
	local c = wall.Position
	return {
		kind = "solid",
		at = p(Vector3.new(c.X, floor, c.Z)),
		out = p(out),
		width = wall.Size.X,
		thick = thick,
		story = story,
	}
end

local function building(i: Instance): Model?
	local m = i:FindFirstAncestorWhichIsA("Model")
	while m and not CollectionService:HasTag(m, D.BuildingTag) do
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return m
end

-- room to stand at a spot: nothing of the building in a soldier-sized box over it (a door, which swings, aside), and a
-- floor under it
local function standable(b: Model, at: Vector3): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { b }
	local size = Vector3.new(2 * S.clearance, S.height, 2 * S.clearance)
	for _, hit in workspace:GetPartBoundsInBox(CFrame.new(at + Vector3.new(0, S.lift + S.height / 2, 0)), size, params) do
		local section = hit:FindFirstAncestorWhichIsA("Model")
		if hit.CanCollide and not (section and CollectionService:HasTag(section, D.DoorTag)) then
			return false
		end
	end
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = { b }
	return workspace:Raycast(at + Vector3.new(0, 1, 0), Vector3.new(0, -1 - S.floorProbe, 0), ray) ~= nil
end

-- a doorway's door hinge (the Hinge attribute, in its shut panel's space: src/server/Doors), or nil
local function hingeOf(section: Instance): Vector3?
	for _, c in section:GetChildren() do
		if c:IsA("Model") and CollectionService:HasTag(c, D.DoorTag) and c.PrimaryPart then
			local shut = c:GetAttribute("ClosedPanel")
			local panel = if typeof(shut) == "CFrame" then shut else (c.PrimaryPart :: BasePart).CFrame
			local h = c:GetAttribute("Hinge")
			return (panel * CFrame.new(if typeof(h) == "Vector3" then h else Vector3.zero)).Position
		end
	end
	return nil
end

-- a doorway's side spot past its door's hinge isn't kept: the door, open, shuts it in against the wall
function Indoors.spots(b: Model): { Spot }
	local got = cache[b]
	if got then
		return got
	end
	if not watched[b] then
		watched[b] = true
		-- a piece broken or knocked down: work the spots out again next time
		b.DescendantRemoving:Connect(function()
			cache[b] = nil
		end)
	end
	local pieces: { Rules.Piece } = {}
	local hinges: { { piece: Rules.Piece, hinge: Rules.P } } = {}
	for _, d in b:GetDescendants() do
		if CollectionService:HasTag(d, D.SectionTag) and building(d) == b then
			local w = Indoors.piece(d)
			if w then
				table.insert(pieces, w)
				local h = if w.kind == "door" then hingeOf(d) else nil
				if h then
					table.insert(hinges, { piece = w, hinge = p(h) })
				end
			end
		end
	end
	local out: { Spot } = {}
	for _, s in Rules.spots(pieces, S) do
		local at = v3(s.at)
		local behind = false
		for _, h in hinges do
			-- (the doorway's own side spot: wedged between the open door and the wall; others are walked round to)
			if
				s.kind == "Doorway"
				and h.piece.story == s.story
				and Rules.distance(h.piece.at, s.at) < h.piece.width + S.side + S.stand
			then
				behind = behind or Rules.behindDoor(h.piece, h.hinge, s.at)
			end
		end
		if behind then
			Indoors.behind += 1
		elseif standable(b, at) then
			table.insert(out, { kind = s.kind, at = at, face = v3(s.face), story = s.story, building = b })
		end
	end
	cache[b] = out
	return out
end

function Indoors.near(at: Vector3, within: number, kind: Rules.Kind?): { Spot }
	local found: { { spot: Spot, d: number } } = {}
	for _, b in CollectionService:GetTagged(D.BuildingTag) do
		if b:IsA("Model") and b:IsDescendantOf(workspace) then
			-- skip buildings too far to have a spot in range (the bounding box's half diagonal)
			local cf, size = b:GetBoundingBox()
			if (cf.Position - at).Magnitude <= within + size.Magnitude / 2 then
				for _, s in Indoors.spots(b) do
					local d = (s.at - at).Magnitude
					if d <= within and (kind == nil or s.kind == kind) then
						table.insert(found, { spot = s, d = d })
					end
				end
			end
		end
	end
	table.sort(found, function(x, y)
		return x.d < y.d
	end)
	local out = {}
	for i, f in found do
		out[i] = f.spot
	end
	return out
end

-- the ground under a point within Links.drop (a floor inside, the terrain or a doorstep outside), or nil
local function ground(at: Vector3, skip: Instance): Vector3?
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = { skip }
	local hit = workspace:Raycast(at + Vector3.new(0, 3, 0), Vector3.new(0, -3 - L.drop, 0), ray)
	return if hit then hit.Position else nil
end

local function link(
	section: Instance,
	name: string,
	label: string,
	a: BasePart,
	at0: Vector3,
	b: BasePart,
	at1: Vector3
)
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "0"
	a0.Parent = a
	a0.WorldPosition = at0
	local a1 = Instance.new("Attachment")
	a1.Name = name .. "1"
	a1.Parent = b
	a1.WorldPosition = at1
	local l = Instance.new("PathfindingLink")
	l.Name = name
	l.Label = label
	l.IsBidirectional = true
	l.Attachment0 = a0
	l.Attachment1 = a1
	l.Parent = section
end

-- a doorway's link, outside to inside (none if the ground outside is out of reach: a door up a bank, or blocked)
local function doorway(section: Instance)
	local piece = Indoors.piece(section)
	if not piece or piece.kind ~= "door" or section:FindFirstChild("DoorwayLink") then
		return
	end
	local wall = section:FindFirstChild("Wall") :: BasePart
	local door: Instance = section
	for _, c in section:GetChildren() do
		if CollectionService:HasTag(c, D.DoorTag) then
			door = c
		end
	end
	local o, i = Rules.passage(piece, L)
	local gi = ground(v3(i), door)
	-- outside: the first clear ground going out a stud at a time (a pole or a fence in front of the door)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { building(section) or section, workspace.Terrain }
	local size = Vector3.new(2 * S.clearance, S.height, 2 * S.clearance)
	local out = Vector3.new(piece.out.x, 0, piece.out.z)
	local go: Vector3? = nil
	for k = 0, L.further do
		local at = ground(v3(o) + out * k, door)
		local clear = at ~= nil
		if at then
			for _, hit in
				workspace:GetPartBoundsInBox(CFrame.new(at + Vector3.new(0, S.lift + S.height / 2, 0)), size, params)
			do
				clear = clear and not hit.CanCollide
			end
		end
		if clear then
			go = at
			break
		end
	end
	if go and gi then
		link(section, "DoorwayLink", L.door, wall, go, wall, gi)
	end
end

-- a flight's link, from the floor beside its foot to past its top (or onto its top step when there's no room past it)
local function flight(section: Instance)
	if section:FindFirstChild("StairLink") then
		return
	end
	local steps: { BasePart } = {}
	for _, c in section:GetChildren() do
		if c:IsA("BasePart") and c.Name == "Step" then
			table.insert(steps, c)
		end
	end
	if #steps < 2 then
		return
	end
	-- each step is a column from the flight's base: the higher the middle, the higher the step
	table.sort(steps, function(x, y)
		return x.Position.Y < y.Position.Y
	end)
	local lo, hi = steps[1], steps[#steps]
	local up = ((hi.Position - lo.Position) * Vector3.new(1, 0, 1)).Unit
	local room = Vector3.new(-up.Z, 0, up.X)
	local block = section:FindFirstAncestorWhichIsA("Model")
	if block and (block:GetBoundingBox().Position - lo.Position):Dot(room) < 0 then
		room = -room
	end
	local foot = Vector3.new(lo.Position.X, lo.Position.Y - lo.Size.Y / 2, lo.Position.Z)
	local top = Vector3.new(hi.Position.X, hi.Position.Y + hi.Size.Y / 2, hi.Position.Z)
	local low, beyond, onTop = Rules.flight(p(foot), p(top), p(up), p(room), lo.Size.Z, lo.Size.X, L)
	local b = building(section)
	local head = if b and standable(b, v3(beyond)) then v3(beyond) else v3(onTop)
	link(section, "StairLink", L.stairs, lo, v3(low), hi, head)
end

local function hook(section: Instance)
	if not section:IsDescendantOf(workspace) then
		return
	end
	local kind = section:GetAttribute("Kind")
	if kind == "Wall" then
		doorway(section)
	elseif kind == "Stairs" then
		flight(section)
	end
end

function Indoors.start()
	for _, s in CollectionService:GetTagged(D.SectionTag) do
		hook(s)
	end
	CollectionService:GetInstanceAddedSignal(D.SectionTag):Connect(function(s)
		task.defer(hook, s) -- once its pieces are in too
	end)
end

return Indoors
