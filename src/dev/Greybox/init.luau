--!strict
-- Dev-only map builder: natural terrain, trees and out-of-bounds panels. Run in Studio edit mode
-- in the DEV place:
--   require(game.ServerStorage.Dev.Greybox:Clone()).build("Map1")
-- Cloning bypasses the require cache so Rojo edits take effect without restarting Studio.
-- Replaces Workspace.<map> and ALL terrain, generated from Config/Maps/<map> via Rules/MapTerrain.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parts = require(script.Parts)
local Ground = require(script.Ground)
local Trees = require(script.Trees)
local Features = require(script.Features)

local Greybox = {}

local DEV_PLACE_ID = 103459731368962

local function fresh(module: Instance): any
	return require(module:Clone() :: ModuleScript)
end

function Greybox.build(mapName: string): string
	assert(game.PlaceId == DEV_PLACE_ID, "Map builder only runs in the DEV place")
	local t0 = os.clock()
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local MT = fresh(Shared.Rules.MapTerrain)
	local boundaryCfg = fresh(Shared.Config.Boundary)
	local map = fresh(Shared.Config.Maps:FindFirstChild(mapName) :: Instance)
	Parts.reset()

	for _, name in { "Baseplate", "SpawnLocation", mapName } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local chunks = Ground.build(map, MT)
	local tTerrain = os.clock() - t0

	local root = Instance.new("Folder")
	root.Name = mapName
	root.Parent = workspace

	local trees = Trees.build(Parts.folder(root, "Trees"), map, MT)
	local panels = Features.bounds(root, map, boundaryCfg)
	Features.testSpawn(root, map, MT)
	Features.atmosphere()

	return string.format(
		"Built %s: terrain %d chunks (%.1fs), %d trees, %d boundary panels, %d parts, %.1fs total. h(300,20)=%.6f",
		mapName,
		chunks,
		tTerrain,
		trees,
		panels,
		Parts.count(),
		os.clock() - t0,
		MT.heightAt(map, 300, 20)
	)
end

return Greybox
