--!strict
-- Dev-only map builder: flat-color terrain, roads, tree meshes, out-of-bounds panels, and the sector dividers and
-- capture point markers. Run in Studio edit mode in the DEV place:
--   require(game.ServerStorage.Dev.Greybox:Clone()).build("Map1")
-- or only the sector dividers and markers, over a map already built:
--   require(game.ServerStorage.Dev.Greybox:Clone()).sectors("Map1")
-- Cloning bypasses the require cache so Rojo edits take effect without restarting Studio.
-- Replaces Workspace.<map> and ALL terrain, generated from Config/Maps/<map> via Rules/MapTerrain.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parts = require(script.Parts)
local Ground = require(script.Ground)
local Trees = require(script.Trees)
local Features = require(script.Features)
local VillageBuild = require(script.VillageBuild)
local Sectors = require(script.Sectors)

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
	local assets = fresh(Shared.Config.Assets)
	local M = fresh(Shared.Config.Metrics)
	local B = fresh(Shared.Config.Buildings)
	local palette = fresh(Shared.Config.Palette)
	local VillageRules = fresh(Shared.Rules.Village)
	local Library = fresh(game:GetService("ServerStorage").Dev.Library)
	local treeKit = Library.ensure("TreeKit")
	local map = fresh(Shared.Config.Maps:FindFirstChild(mapName) :: Instance)
	Parts.reset()

	for _, name in { "Baseplate", "SpawnLocation", mapName } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local chunks = Ground.build(map, MT, palette)
	local tTerrain = os.clock() - t0

	local root = Instance.new("Folder")
	root.Name = mapName
	root.Parent = workspace

	local trees = Trees.build(Parts.folder(root, "Trees"), map, MT, treeKit, assets, palette)
	-- Village: roads are painted into the terrain by Rules/MapTerrain; buildings + props from the library.
	local villageStats = ""
	if map.village then
		local P = fresh(Shared.Config.Props)
		local layout = VillageRules.layout(map, B, M, MT, P)
		Trees.build(Parts.folder(root, "VillageTrees"), map, MT, treeKit, assets, palette, layout.trees)
		local vstats = VillageBuild.build(Parts.folder(root, "Village"), map, layout, {
			MT = MT,
			B = B,
			P = P,
			D = fresh(Shared.Config.Destruction),
			palette = palette,
			RulesD = fresh(Shared.Rules.Destruction),
			Props = fresh(game:GetService("ServerStorage").Dev.Props),
			Buildings = fresh(game:GetService("ServerStorage").Dev.Buildings),
			Library = Library,
		})
		villageStats = string.format(
			" Village: %d buildings, %d boundary runs, %d poles, %d props, %d garden trees.",
			vstats.buildings,
			vstats.boundaries,
			vstats.poles,
			vstats.props,
			#layout.trees
		)
	end
	local panels = Features.bounds(root, map, boundaryCfg)
	local dividers, points = 0, 0
	if map.dividers then
		dividers, points = Sectors.build(root, map, MT, fresh(Shared.Config.Sectors), fresh(Shared.Rules.Sectors))
	end
	Features.testSpawn(root, map, MT)
	Features.atmosphere(palette)
	Features.wind(fresh(Shared.Config.TreeSway))

	return string.format(
		"Built %s: terrain %d chunks (%.1fs), %d trees, %d boundary panels, %d divider blocks, %d points, %d parts, %.1fs total.%s",
		mapName,
		chunks,
		tTerrain,
		trees,
		panels,
		dividers,
		points,
		Parts.count(),
		os.clock() - t0,
		villageStats
	)
end

-- Rebuilds only Workspace.<map>.Sectors (dividers and point markers) from the map's config.
function Greybox.sectors(mapName: string): string
	assert(game.PlaceId == DEV_PLACE_ID, "Map builder only runs in the DEV place")
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local root = workspace:FindFirstChild(mapName)
	assert(root, `{mapName} isn't built: run build("{mapName}") first`)
	local old = root:FindFirstChild("Sectors")
	if old then
		old:Destroy()
	end
	local map = fresh(Shared.Config.Maps:FindFirstChild(mapName) :: Instance)
	local dividers, points = Sectors.build(
		root,
		map,
		fresh(Shared.Rules.MapTerrain),
		fresh(Shared.Config.Sectors),
		fresh(Shared.Rules.Sectors)
	)
	return string.format("Built %s sectors: %d divider blocks, %d points.", mapName, dividers, points)
end

return Greybox
