--!strict
-- "Undo destruction" for manual tests (Config/DevTools.World; DEV place only): at the start of a play test every
-- building, loose map section (src/server/Destruction's tags) and tree (Config/TreeSway.Tag) is copied, and the terrain
-- inside Config/DevTools.World.Terrain; DevWorld.undo() puts the copies back in place of whatever is left of them (broken
-- sections, snapped trees) and pastes the terrain over the craters.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools).World
local DestructionCfg = require(Shared.Config.Destruction)
local ShowcaseCfg = require(Shared.Config.Showcase)
local TreeCfg = require(Shared.Config.TreeSway)

local DevWorld = {}

type Saved = { live: Instance?, copy: Instance, parent: Instance }
local saved: { Saved } = {}
local terrain: TerrainRegion? = nil
local corner: Vector3int16? = nil

local function region(): Region3int16
	local lo, hi = Cfg.Terrain.min, Cfg.Terrain.max
	local function v(t: { number }, f: (number) -> number): Vector3int16
		return Vector3int16.new(f(t[1] / 4), f(t[2] / 4), f(t[3] / 4)) -- (4-stud voxels)
	end
	return Region3int16.new(v(lo, math.floor), v(hi, math.ceil))
end

-- what to copy: the buildings, the sections and doors outside them, the trees (each once, outermost first)
local function roots(): { Instance }
	local out: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	local function add(i: Instance)
		if seen[i] or not i:IsDescendantOf(workspace) then
			return
		end
		local a = i.Parent
		while a and a ~= workspace do
			if seen[a] then
				return -- inside a building already copied
			end
			a = a.Parent
		end
		seen[i] = true
		table.insert(out, i)
	end
	for _, tag in { DestructionCfg.BuildingTag, DestructionCfg.SectionTag, DestructionCfg.DoorTag, TreeCfg.Tag } do
		for _, i in CollectionService:GetTagged(tag) do
			local b = i:FindFirstAncestorWhichIsA("Model")
			while b and not CollectionService:HasTag(b, DestructionCfg.BuildingTag) do
				b = b:FindFirstAncestorWhichIsA("Model")
			end
			add(b or i)
		end
	end
	return out
end

function DevWorld.save()
	table.clear(saved)
	for _, i in roots() do
		local was = i.Archivable
		i.Archivable = true
		local copy = i:Clone()
		i.Archivable = was
		if copy and i.Parent then
			table.insert(saved, { live = i, copy = copy, parent = i.Parent })
		end
	end
	local r = region()
	local ok, got = pcall(function()
		return workspace.Terrain:CopyRegion(r)
	end)
	terrain, corner = if ok then got else nil, r.Min
	print(`[DevWorld] saved {#saved} buildings, sections and trees; terrain {if ok then "saved" else "not saved"}`)
end

function DevWorld.undo()
	for _, s in saved do
		if s.live then
			s.live:Destroy()
		end
		local fresh = s.copy:Clone()
		fresh.Parent = s.parent
		s.live = fresh
	end
	if terrain and corner then
		workspace.Terrain:PasteRegion(terrain, corner, true)
	end
	print(`[DevWorld] put back {#saved} buildings, sections and trees`)
end

function DevWorld.start()
	if game.PlaceId ~= ShowcaseCfg.PlaceId then
		return
	end
	task.defer(DevWorld.save)
end

return DevWorld
