--!strict
-- Server-authoritative building destruction (docs/DESTRUCTION.md). The server owns section HP and
-- removes broken sections; clients get one SectionBroken event per break and spawn their own debris.
--   Destruction.damage(section, amount, origin?, cut?)
--   Destruction.explode(position, radius, damage) -- also kicks trees via Net "Explosion"
--   Destruction.shot(part, point) -- a bullet meeting `part`: glass breaks (Config/Firing.Shatter)
-- Stateless (all state lives in attributes), so it can be required from anywhere on the server.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local D = require(Shared.Config.Destruction)
local Shatter = require(Shared.Config.Firing).Shatter
local Shots = require(Shared.Rules.Firing)
local Rules = require(Shared.Rules.Destruction)
local Net = require(Shared.Net)

local Destruction = {}

local function isSection(i: Instance?): boolean
	return i ~= nil and i:IsA("Model") and CollectionService:HasTag(i, D.SectionTag)
end

local function sectionOf(part: Instance): Model?
	local m = part:FindFirstAncestorWhichIsA("Model")
	while m and not isSection(m) do
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return m
end

local function buildingOf(i: Instance): Model?
	local m = i:FindFirstAncestorWhichIsA("Model")
	while m and not CollectionService:HasTag(m, D.BuildingTag) do
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return m
end

-- How a piece goes (src/client/Debris): nil crumples (chunks that drop near where it was), "fall" lost its support (drops
-- where it was), "dust" was pulverised (a puff of dust and a few shards, gone in seconds). Config/Damage.Blast.Destroy.
type Piece = { cf: CFrame, size: Vector3, color: Color3, t: number, m: string? }

local function piece(p: BasePart, m: string?): Piece
	return { cf = p.CFrame, size = p.Size, color = p.Color, t = p.Transparency, m = m }
end

local function collect(model: Instance, out: { Piece }, m: string?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, piece(d, m))
		end
	end
end

-- Remove sections and tell clients to show debris (one event for the whole batch).
local function breakAll(sections: { Model }, origin: Vector3, m: string?)
	local pieces: { Piece } = {}
	for _, s in sections do
		if s.Parent then
			collect(s, pieces, m)
		end
	end
	if #pieces > 0 then
		Net.event("SectionBroken"):FireAllClients(pieces, origin)
	end
	for _, s in sections do
		s:Destroy()
	end
end

-- A section broken by a blast at `origin` whose hole reaches `hole` studs: a ragged hole (Config/Destruction.Jag). Each
-- box part is cut into cells; cells inside the hole (its edge jittered per cell) break off as debris, pulverised within
-- `dust` studs (Config/Damage.Blast.Destroy) and crumpled beyond, the rest become the section's "Remains" (a weaker
-- section, not a wall for collapse). Other parts go if their centre is in the hole.
local function breakRagged(section: Model, origin: Vector3, hole: number, dust: number)
	local J = D.Jag
	local seed = #section:GetFullName()
	local pieces: { Piece } = {}
	local keep: { BasePart } = {}
	for _, d in section:GetDescendants() do
		if d:IsA("Part") and d.Shape == Enum.PartType.Block then
			-- the face is its two biggest axes; cells across it
			local sz = d.Size
			local axes = { { "X", sz.X }, { "Y", sz.Y }, { "Z", sz.Z } }
			table.sort(axes, function(a, b)
				return a[2] > b[2]
			end)
			local ua, va = axes[1][1], axes[2][1]
			local function local3(u: number, v: number): Vector3
				local x = { X = 0, Y = 0, Z = 0 }
				x[ua], x[va] = u - (sz :: any)[ua] / 2, v - (sz :: any)[va] / 2
				return Vector3.new(x.X, x.Y, x.Z)
			end
			local bands = Rules.jagBands((sz :: any)[ua], (sz :: any)[va], J.cell, function(u, v)
				local at = d.CFrame * local3(u, v)
				local n = Rules.noise(math.floor(u / J.cell), math.floor(v / J.cell), seed)
				local r = (at - origin).Magnitude / (1 + J.jitter * (n * 2 - 1))
				return if r <= dust then 2 elseif r <= hole then 1 else 0
			end)
			local function part(r: Rules.Run): (CFrame, Vector3)
				local size = { X = sz.X, Y = sz.Y, Z = sz.Z }
				size[ua], size[va] = r.u1 - r.u0, r.v1 - r.v0
				return d.CFrame * CFrame.new(local3((r.u0 + r.u1) / 2, (r.v0 + r.v1) / 2)),
					Vector3.new(size.X, size.Y, size.Z)
			end
			for band, m in { [1] = "", [2] = "dust" } do
				for _, r in bands[band] or {} do
					local cf, size = part(r)
					table.insert(
						pieces,
						{ cf = cf, size = size, color = d.Color, t = d.Transparency, m = if m ~= "" then m else nil }
					)
				end
			end
			for _, r in bands[0] or {} do
				local cf, size = part(r)
				local c = d:Clone()
				c:ClearAllChildren()
				c.Size, c.CFrame = size, cf
				table.insert(keep, c)
			end
		elseif d:IsA("BasePart") then
			local r = (d.Position - origin).Magnitude
			if r <= hole then
				table.insert(pieces, piece(d, if r <= dust then "dust" else nil))
			else
				local c = d:Clone()
				c:ClearAllChildren()
				table.insert(keep, c)
			end
		end
	end
	if #pieces > 0 then
		Net.event("SectionBroken"):FireAllClients(pieces, origin)
	end
	if #keep > 0 then
		local remains = Instance.new("Model")
		remains.Name = "Remains"
		local maxHP = (section:GetAttribute("MaxHP") :: number? or 0) * J.remainsHP
		remains:SetAttribute("Kind", "Remains")
		remains:SetAttribute("Class", section:GetAttribute("Class"))
		remains:SetAttribute("Story", section:GetAttribute("Story"))
		remains:SetAttribute("MaxHP", maxHP)
		remains:SetAttribute("HP", maxHP)
		for _, c in keep do
			c.Parent = remains
		end
		remains.Parent = section.Parent
		CollectionService:AddTag(remains, D.SectionTag)
	end
	section:Destroy()
end

-- Sections that belong directly to this building (not to a nested building such as a tower).
local function ownSections(building: Model): { Model }
	local out = {}
	for _, d in building:GetDescendants() do
		if isSection(d) and buildingOf(d) == building then
			table.insert(out, d :: Model)
		end
	end
	return out
end

local function checkCollapse(building: Model, origin: Vector3)
	local counts = {}
	for name, value in building:GetAttributes() do
		local story = tonumber(string.match(name, "^WallCount_(%-?%d+)$"))
		if story then
			counts[story] = { initial = value, standing = 0 }
		end
	end
	local own = ownSections(building)
	for _, s in own do
		local story = s:GetAttribute("Story")
		if s:GetAttribute("Kind") == "Wall" and counts[story] then
			counts[story].standing += 1
		end
	end
	local from = Rules.collapseFrom(counts, D.CollapseSupportFraction)
	if from == nil then
		return
	end
	local doomed = {}
	for _, s in own do
		local story = s:GetAttribute("Story") :: number
		-- the ground slab (Story -1) never collapses; nested sections go with their parent section
		if story >= from and s.Parent and not isSection(s.Parent) then
			table.insert(doomed, s)
		end
	end
	building:SetAttribute("CollapsedFrom", from)
	breakAll(doomed, origin, "fall") -- (a story losing its walls comes down where it stood)
end

-- Support (user 2026-10-23: "anything not supported should fall"): every piece of a building must hang together with
-- the ground through the pieces it touches (Rules/Destruction.unsupported). Each section is one piece, its nested
-- sections with it; a section's Remains is one piece per part (a ragged hole can cut them apart); the building's parts
-- outside any section (foundation, plinth) and the ground slab (Story -1) are on the ground. What hangs on nothing
-- drops where it is as debris; a story losing its walls that way can still collapse.
local function unsupported(building: Model): ({ Model }, { BasePart })
	local nodes: { { BasePart } } = {}
	local owner: { [number]: Model } = {}
	local grounded: { [number]: boolean } = {}
	local nodeOf: { [BasePart]: number } = {}
	local function add(parts: { BasePart }, section: Model?, ground: boolean)
		table.insert(nodes, parts)
		local i = #nodes
		if section then
			owner[i] = section
		end
		grounded[i] = ground or nil
		for _, p in parts do
			nodeOf[p] = i
		end
	end
	for _, s in ownSections(building) do
		if not isSection(s.Parent) then
			local ground = s:GetAttribute("Story") == -1
			local parts = {}
			for _, d in s:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			if s:GetAttribute("Kind") == "Remains" and not ground then
				for _, p in parts do
					add({ p }, nil, false)
				end
			elseif #parts > 0 then
				add(parts, s, ground)
			end
		end
	end
	local base = {}
	for _, d in building:GetDescendants() do
		if d:IsA("BasePart") and not nodeOf[d] then
			table.insert(base, d)
		end
	end
	if #base > 0 then
		add(base, nil, true)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { building }
	local links: { { number } } = {}
	for i, parts in nodes do
		if not grounded[i] then
			local seen = {}
			links[i] = links[i] or {}
			for _, p in parts do
				for _, hit in workspace:GetPartBoundsInBox(p.CFrame, p.Size + Vector3.one * D.SupportTouch, params) do
					local j = nodeOf[hit :: BasePart]
					if j and j ~= i and not seen[j] then
						seen[j] = true
						table.insert(links[i], j)
						-- (links go both ways: a grounded piece isn't queried; repeats are harmless)
						links[j] = links[j] or {}
						table.insert(links[j], i)
					end
				end
			end
		end
	end
	local sections, parts = {}, {}
	for _, i in Rules.unsupported(#nodes, links, grounded) do
		if owner[i] then
			table.insert(sections, owner[i])
		else
			table.insert(parts, nodes[i][1])
		end
	end
	return sections, parts
end

local function dropUnsupported(building: Model, origin: Vector3)
	for _ = 1, 3 do
		if not building.Parent then
			return
		end
		local sections, parts = unsupported(building)
		if #sections == 0 and #parts == 0 then
			return
		end
		local pieces: { Piece } = {}
		for _, s in sections do
			collect(s, pieces, "fall")
		end
		local emptied: { [Instance]: boolean } = {}
		for _, p in parts do
			table.insert(pieces, piece(p, "fall"))
			if p.Parent then
				emptied[p.Parent] = true
			end
		end
		Net.event("SectionBroken"):FireAllClients(pieces, origin)
		for _, s in sections do
			s:Destroy()
		end
		for _, p in parts do
			p:Destroy()
		end
		for remains in emptied do
			if remains.Parent and not remains:FindFirstChildWhichIsA("BasePart", true) then
				remains:Destroy()
			end
		end
		checkCollapse(building, origin)
	end
end

-- buildings that lost something this frame: checked for unsupported pieces once, after the whole blast
local unsettled: { [Model]: Vector3 } = {}

local function settleLater(building: Model, origin: Vector3)
	if unsettled[building] then
		return
	end
	unsettled[building] = origin
	task.defer(function()
		unsettled[building] = nil
		dropUnsupported(building, origin)
	end)
end

-- How a blast breaks a section (Destruction.blast): `hole` its reach for this section's class (a ragged hole,
-- Config/Destruction.Jag), `dust` how far it pulverises it (Config/Damage.Blast.Destroy; 0: never), `distance` the
-- section's own distance from it. Without one the whole section crumples.
export type Cut = { hole: number, dust: number, distance: number }

function Destruction.damage(section: Model, amount: number, origin: Vector3?, cut: Cut?)
	if not section.Parent or amount <= 0 then
		return
	end
	local hp = (section:GetAttribute("HP") :: number) - amount
	section:SetAttribute("HP", hp)
	if hp > 0 then
		return
	end
	local building = buildingOf(section)
	local at = origin or section:GetPivot().Position
	local kind = section:GetAttribute("Kind")
	if origin and cut and type(kind) == "string" and (D.Jag.kinds :: any)[kind] then
		breakRagged(section, origin, cut.hole, cut.dust)
	else
		breakAll({ section }, at, if cut and cut.distance <= cut.dust then "dust" else nil)
	end
	if building then
		checkCollapse(building, at)
		settleLater(building, at)
	end
end

-- A bullet meeting `part` at `point`: a section of a Config/Firing.Shatter class (window glass) breaks at once (its
-- shards on every client) and true is returned, so the bullet carries on; anything else stops it (false).
function Destruction.shot(part: Instance, point: Vector3): boolean
	local s = sectionOf(part)
	local class = s and s:GetAttribute("Class")
	if not s or not Shots.shatters(if type(class) == "string" then class else nil, 0, Shatter) then
		return false
	end
	Destruction.damage(s, math.max(s:GetAttribute("HP") :: number? or 1, 1), point)
	return true
end

function Destruction.explode(position: Vector3, radius: number, damage: number): { broken: number, damaged: number }
	-- trees and other visual-only responders
	Net.event("Explosion"):FireAllClients(position, radius, 1)

	local nearest: { [Model]: number } = {}
	for _, part in workspace:GetPartBoundsInRadius(position, radius) do
		local s = sectionOf(part)
		if s then
			-- distance to the part's surface (approx: center distance minus half its smallest extent)
			local half = math.min(part.Size.X, part.Size.Y, part.Size.Z) / 2
			local d = math.max(0, (part.Position - position).Magnitude - half)
			if nearest[s] == nil or d < nearest[s] then
				nearest[s] = d
			end
		end
	end
	local before = 0
	for s in nearest do
		if s.Parent then
			before += 1
		end
	end
	local damaged = 0
	for s, d in nearest do
		if s.Parent then
			local dmg = Rules.blastDamage(d, radius, damage)
			if dmg > 0 then
				damaged += 1
				Destruction.damage(s, dmg, position)
			end
		end
	end
	local after = 0
	for s in nearest do
		if s.Parent then
			after += 1
		end
	end
	return { broken = before - after, damaged = damaged }
end

-- A blast like a real one (Rules/Blast, Config/Damage.Blast): each section within `reach` studs loses what the
-- overpressure at its nearest part does to it (`damageAt(distance, class, maxHP, kind, hp)`); trees and the like get
-- the visual kick through Net "Explosion". Returns the sections broken and damaged.
function Destruction.blast(
	position: Vector3,
	reach: number,
	damageAt: (distance: number, class: string?, maxHP: number, kind: string?, hp: number) -> number,
	holeAt: ((class: string?) -> number)?,
	dustAt: ((class: string?) -> number)?
): { broken: number, damaged: number }
	Net.event("Explosion"):FireAllClients(position, reach, 1)
	local nearest: { [Model]: number } = {}
	for _, part in workspace:GetPartBoundsInRadius(position, reach) do
		local s = sectionOf(part)
		if s then
			local half = math.min(part.Size.X, part.Size.Y, part.Size.Z) / 2
			local d = math.max(0, (part.Position - position).Magnitude - half)
			if nearest[s] == nil or d < nearest[s] then
				nearest[s] = d
			end
		end
	end
	local broken, damaged = 0, 0
	for s, d in nearest do
		if s.Parent then
			local class = s:GetAttribute("Class")
			local maxHP = s:GetAttribute("MaxHP")
			local kind = s:GetAttribute("Kind")
			local hp = s:GetAttribute("HP")
			local dmg = damageAt(
				d,
				if type(class) == "string" then class else nil,
				if type(maxHP) == "number" then maxHP else 0,
				if type(kind) == "string" then kind else nil,
				if type(hp) == "number" then hp else 0
			)
			if dmg > 0 then
				damaged += 1
				-- its ragged hole: as far as the blast breaks this class, at least a bite past this section's edge; its middle
				-- pulverised as far as the blast destroys this class
				local c = if type(class) == "string" then class else nil
				local cut: Cut? = if holeAt
					then {
						hole = math.max(holeAt(c), d + D.Jag.minBite),
						dust = if dustAt then dustAt(c) else 0,
						distance = d,
					}
					else nil
				Destruction.damage(s, dmg, position, cut)
				if not s.Parent then
					broken += 1
				end
			end
		end
	end
	return { broken = broken, damaged = damaged }
end

return Destruction
