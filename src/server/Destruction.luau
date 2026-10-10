--!strict
-- Server-authoritative building destruction (docs/DESTRUCTION.md). The server owns section HP and
-- removes broken sections; clients get one SectionBroken event per break and spawn their own debris.
--   Destruction.damage(section, amount, origin?)
--   Destruction.explode(position, radius, damage) -- also kicks trees via Net "Explosion"
-- Stateless (all state lives in attributes), so it can be required from anywhere on the server.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local D = require(Shared.Config.Destruction)
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

type Piece = { cf: CFrame, size: Vector3, color: Color3, t: number }

local function collect(model: Instance, out: { Piece })
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, { cf = d.CFrame, size = d.Size, color = d.Color, t = d.Transparency })
		end
	end
end

-- Remove sections and tell clients to show debris (one event for the whole batch).
local function breakAll(sections: { Model }, origin: Vector3)
	local pieces: { Piece } = {}
	for _, s in sections do
		if s.Parent then
			collect(s, pieces)
		end
	end
	if #pieces > 0 then
		Net.event("SectionBroken"):FireAllClients(pieces, origin)
	end
	for _, s in sections do
		s:Destroy()
	end
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
	breakAll(doomed, origin)
end

function Destruction.damage(section: Model, amount: number, origin: Vector3?)
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
	breakAll({ section }, at)
	if building then
		checkCollapse(building, at)
	end
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

return Destruction
