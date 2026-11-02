--!strict
-- Dev-only map builder: flat-color terrain, roads, tree meshes, out-of-bounds panels, and the sector dividers and
-- capture point markers. Run in Studio edit mode in the DEV place:
--   require(game.ServerStorage.Dev.Greybox:Clone()).build("Map1")
-- or only the sector dividers and markers, over a map already built:
--   require(game.ServerStorage.Dev.Greybox:Clone()).sectors("Map1")
-- and check a built map against the map rules (docs/maps/MAP_RULES.md; read-only, any place):
--   require(game.ServerStorage.Dev.Greybox:Clone()).audit("Map1")
-- Cloning bypasses the require cache so Rojo edits take effect without restarting Studio.
-- Replaces Workspace.<map> and ALL terrain, generated from Config/Maps/<map> via Rules/MapTerrain; a map with `offMap`
-- (Config/Maps/Playtest) replaces only the terrain round itself and adds no spawn.

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

	-- a hand-placed layout (map.layout) keeps its natural trees off its buildings (Rules/Village.fixed); a village's
	-- landmarks out in the open clear theirs too (Rules/Village.naturalTrees)
	local P = fresh(Shared.Config.Props)
	local fixed = if map.layout then VillageRules.fixed(map, B, M, MT) else nil
	local layout = fixed or (if map.village then VillageRules.layout(map, B, M, MT, P) else nil)
	-- and the frontline's wave lines stand on open ground (Rules/Frontline.lineQuads)
	local lineCfg = fresh(Shared.Config.Frontline).Line
	local lines = if map.sectors and #map.sectors >= 3
		then fresh(Shared.Rules.Frontline).lineQuads(map.sectors, lineCfg, lineCfg.treeClear)
		else nil
	local natural = if fixed
		then fixed.trees
		elseif layout then VillageRules.naturalTrees(map, MT, layout.lots, map.village.trees.buildingClear, lines)
		else nil
	local trees = Trees.build(Parts.folder(root, "Trees"), map, MT, treeKit, assets, palette, natural)
	-- Village: roads are painted into the terrain by Rules/MapTerrain; buildings + props from the library.
	local villageStats = ""
	if layout then
		if not fixed then
			Trees.build(Parts.folder(root, "VillageTrees"), map, MT, treeKit, assets, palette, layout.trees)
		end
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
			VillageRules = VillageRules,
		})
		villageStats = string.format(
			" Village: %d buildings, %d boundary runs, %d poles, %d props, %d garden trees.",
			vstats.buildings,
			vstats.boundaries,
			vstats.poles,
			vstats.props,
			if fixed then 0 else #layout.trees
		)
	end
	local panels = Features.bounds(root, map, boundaryCfg)
	local dividers, points = 0, 0
	if map.dividers then
		dividers, points = Sectors.build(root, map, MT, fresh(Shared.Config.Sectors), fresh(Shared.Rules.Sectors))
	end
	if not map.offMap then
		Features.testSpawn(root, map, MT)
	end
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

-- The map rules' checks on a built map (src/dev/Greybox/Audit): a report, a FAIL line for each thing to fix.
function Greybox.audit(mapName: string): string
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	return require(script.Audit).run(mapName, {
		B = fresh(Shared.Config.Buildings),
		Front = fresh(Shared.Config.Frontline),
		M = fresh(Shared.Config.Metrics),
		FrontRules = fresh(Shared.Rules.Frontline),
		map = fresh(Shared.Config.Maps:FindFirstChild(mapName) :: Instance),
	})
end

return Greybox
