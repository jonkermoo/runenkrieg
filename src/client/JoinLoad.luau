--!strict
-- The match's map loaded on joining a server (Config/JoinLoading, Rules/JoinLoading; src/client/Menus holds its loading
-- screen meanwhile): the map's model waited for, every spot of a grid over its bounds and each capture point streamed
-- in (StreamingEnabled), then the meshes, textures and decals of everything streamed in preloaded, so the title
-- screen's live match shows no ground or house popping in. Never longer than Config/JoinLoading.Max.
--   JoinLoad.run(report: (progress 0..1) -> ()): yields until loaded (or out of time).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.JoinLoading)
local Rules = require(Shared.Rules.JoinLoading)
local LiveMap = require(Shared.LiveMap)

local JoinLoad = {}

function JoinLoad.run(report: (number) -> ())
	local start = os.clock()
	local function late(): boolean
		return os.clock() - start > Cfg.Max
	end
	local key = LiveMap.key()
	local ok, map = pcall(LiveMap.get, key)
	if not ok or not map or not map.bounds then
		report(1)
		return
	end
	while not LiveMap.built(key) and os.clock() - start < Cfg.BuiltWait do
		task.wait(0.2)
	end
	local points = {}
	for _, s in map.sectors or {} do
		table.insert(points, { s.x, s.z })
	end
	local spots = Rules.spots(map.bounds, points, Cfg.Spacing)
	local done, total = 0, #spots + 1
	report(Rules.progress(done, total))
	local player = Players.LocalPlayer
	for _, p in spots do -- (one after another: the server streams each before the next)
		if late() then
			return
		end
		pcall(function()
			player:RequestStreamAroundAsync(Vector3.new(p[1], 0, p[2]))
		end)
		done += 1
		report(Rules.progress(done, total))
	end
	-- one instance for each mesh, texture and decal asset of what streamed in
	local root = workspace:FindFirstChild(key)
	local list: { Instance } = {}
	local seen: { [string]: boolean } = {}
	local function add(d: Instance, ...: string)
		local new = false
		for _, id in { ... } do
			if id ~= "" and not seen[id] then
				seen[id], new = true, true
			end
		end
		if new then
			table.insert(list, d)
		end
	end
	for _, d in (if root then root:GetDescendants() else {}) do
		if d:IsA("MeshPart") then
			add(d, d.MeshId, d.TextureID)
		elseif d:IsA("SpecialMesh") then
			add(d, d.MeshId, d.TextureId)
		elseif d:IsA("Decal") then -- (Textures too)
			add(d, d.Texture)
		elseif d:IsA("SurfaceAppearance") then
			table.insert(list, d)
		end
	end
	total = #spots + math.max(#list, 1)
	for k = 1, #list, Cfg.Batch do
		if late() then
			return
		end
		pcall(
			ContentProvider.PreloadAsync,
			ContentProvider,
			table.move(list, k, math.min(k + Cfg.Batch - 1, #list), 1, {})
		)
		done += math.min(Cfg.Batch, #list - k + 1)
		report(Rules.progress(done, total))
	end
	report(1)
end

return JoinLoad
