--!strict
-- "Undo destruction" for manual tests (Config/DevTools.World; DEV place only): at the start of a play test every
-- building, loose map section (src/server/Destruction's tags) and tree (Config/TreeSway.Tag) is copied, and the terrain
-- inside each box of Config/DevTools.World.Terrain; DevWorld.undo() puts the copies back in place of whatever is left of them (broken
-- sections, snapped trees) and pastes the terrain over the craters. Normal mode uses it too, in every place: each new
-- match puts the map back (src/server/Frontline). Only what changed goes back (user 2026-11-02: "occasionally the
-- entire map refreshes"; it replaced all ~4,600 buildings and trees and pasted the whole map's terrain, so every client
-- saw the map vanish and stream in again): a thing whose fingerprint still matches stays, and only the terrain chunks
-- a write touched (DevWorld.touch, from src/server/Ground and Trenches) are pasted (Rules/MapReset).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools).World
local DestructionCfg = require(Shared.Config.Destruction)
local ShowcaseCfg = require(Shared.Config.Showcase)
local TreeCfg = require(Shared.Config.TreeSway)
local Reset = require(Shared.Rules.MapReset)

local DevWorld = {}

type Saved = { live: Instance?, copy: Instance, parent: Instance, print: string }
local saved: { Saved } = {}
-- the terrain by chunk key (Rules/MapReset), and the chunks written since the save
local terrains: { [string]: { region: TerrainRegion, corner: Vector3int16 } } = {}
local touched: { [string]: boolean } = {}

-- a thing's fingerprint: its pieces, their hit points, the doors open, where it stands
local function fingerprint(i: Instance): string
	local count, hp, open = 0, 0, 0
	for _, d in i:GetDescendants() do
		count += 1
		local h = d:GetAttribute("HP")
		if type(h) == "number" then
			hp += h
		end
		if d:GetAttribute("Open") == true then
			open += 1
		end
	end
	local at = if i:IsA("PVInstance") then (i :: PVInstance):GetPivot().Position else Vector3.zero
	return Reset.fingerprint(count, hp, open, at.X, at.Y, at.Z)
end

-- the voxels (4-stud) of columns x0..x1, z0..z1 between y0 and y1
local function region(x0: number, z0: number, x1: number, z1: number, y0: number, y1: number): Region3int16
	return Region3int16.new(
		Vector3int16.new(math.floor(x0 / 4), math.floor(y0 / 4), math.floor(z0 / 4)),
		Vector3int16.new(math.ceil(x1 / 4) - 1, math.ceil(y1 / 4), math.ceil(z1 / 4) - 1)
	)
end

-- A terrain write in this box (src/server/Ground, Trenches): its chunks are pasted back at the next undo.
function DevWorld.touch(min: Vector3, max: Vector3)
	for _, k in Reset.chunksIn(min.X, min.Z, max.X, max.Z, Cfg.Chunk) do
		touched[k] = true
	end
end
-- the same for a Region3 (what WriteVoxels was given)
function DevWorld.touchRegion(r: Region3)
	local half = r.Size / 2
	DevWorld.touch(r.CFrame.Position - half, r.CFrame.Position + half)
end

-- what to copy: the buildings, the sections and doors outside them, the trees, the telegraph wires' spans
-- (src/server/PoleWires; each once, outermost first)
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
	for _, tag in
		{
			DestructionCfg.BuildingTag,
			DestructionCfg.SectionTag,
			DestructionCfg.DoorTag,
			TreeCfg.Tag,
			DestructionCfg.Wires.Tag,
		}
	do
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
			table.insert(saved, { live = i, copy = copy, parent = i.Parent, print = fingerprint(i) })
		end
	end
	table.clear(terrains)
	table.clear(touched)
	local chunks = 0
	for _, box in Cfg.Terrain do
		local rect = { box.min[1], box.min[3], box.max[1], box.max[3] }
		local ax, az = Reset.chunkOf(rect[1], rect[2], Cfg.Chunk)
		local bx, bz = Reset.chunkOf(rect[3] - 0.01, rect[4] - 0.01, Cfg.Chunk)
		for ix = ax, bx do
			for iz = az, bz do
				local c = Reset.chunkRect(ix, iz, Cfg.Chunk, rect)
				local r = region(c[1], c[2], c[3], c[4], box.min[2], box.max[2])
				local ok, got = pcall(function()
					return workspace.Terrain:CopyRegion(r)
				end)
				if ok then
					terrains[Reset.key(ix, iz)] = { region = got, corner = r.Min }
					chunks += 1
				end
			end
		end
	end
	print(`[DevWorld] saved {#saved} buildings, sections and trees; terrain {chunks} chunks`)
end

function DevWorld.undo()
	local back = 0
	for _, s in saved do
		local live = s.live
		if live and live.Parent == s.parent and fingerprint(live) == s.print then
			continue -- (untouched: left as it is, so no client sees it go and come back)
		end
		if live then
			live:Destroy()
		end
		local fresh = s.copy:Clone()
		fresh.Parent = s.parent
		s.live = fresh
		back += 1
	end
	local pasted = 0
	for k in touched do
		local t = terrains[k]
		if t then
			workspace.Terrain:PasteRegion(t.region, t.corner, true)
			pasted += 1
		end
	end
	table.clear(touched)
	print(`[DevWorld] put back {back} of {#saved} buildings, sections and trees; terrain {pasted} chunks`)
end

-- Saves the world now unless it already is (src/server/Frontline: a Normal match puts the map back between matches,
-- in any place).
function DevWorld.ensure()
	if #saved == 0 and next(terrains) == nil then
		DevWorld.save()
	end
end

function DevWorld.start()
	if game.PlaceId ~= ShowcaseCfg.PlaceId then
		return
	end
	task.defer(DevWorld.save)
end

return DevWorld
