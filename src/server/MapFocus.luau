--!strict
-- The live map kept streamed in for every player (Config/JoinLoading, Rules/JoinLoading.foci; user 2026-11-04: "how do
-- we fix some minor stuff not rendering?"). Under StreamingEnabled a client holds only what is near its soldier, and
-- what it streamed in elsewhere may stream out again: small props across the map went missing. Here a few unseen
-- anchors spread over the live map's bounds are each player's replication foci (Player:AddReplicationFocus), so what
-- lies within Workspace.StreamingMinRadius of them is sent to every client and never streams out, with or without a
-- soldier (no avatar walks the map). They move to the next map as soon as it's picked (Workspace's map attribute, set
-- by src/server/Frontline), so it streams in while the armory plays. The map's part count goes on its model
-- (Config/JoinLoading.PartsAttribute) for the clients' loaders to check against.
--   MapFocus.start()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.JoinLoading)
local FrontCfg = require(Shared.Config.Frontline)
local Rules = require(Shared.Rules.JoinLoading)
local LiveMap = require(Shared.LiveMap)

local MapFocus = {}

local folder: Folder
local anchors: { BasePart } = {}
local focusKey: string? = nil

local function apply(player: Player)
	for _, a in anchors do
		pcall(function()
			(player :: any):AddReplicationFocus(a)
		end)
	end
end

local function drop(player: Player)
	for _, a in anchors do
		pcall(function()
			(player :: any):RemoveReplicationFocus(a)
		end)
	end
end

local function countParts(key: string)
	local model = workspace:FindFirstChild(key)
	if not model then
		return
	end
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	model:SetAttribute(Cfg.PartsAttribute, n)
end

local function refocus()
	local key = LiveMap.key()
	if key == focusKey then
		return
	end
	local ok, map = pcall(LiveMap.get, key)
	if not ok or not map or not map.bounds then
		return
	end
	focusKey = key
	for _, p in Players:GetPlayers() do
		drop(p)
	end
	for _, a in anchors do
		a:Destroy()
	end
	table.clear(anchors)
	for i, f in Rules.foci(map.bounds, Cfg.FocusMargin, Cfg.MinRadius) do
		local a = Instance.new("Part")
		a.Name = `Focus{i}`
		a.Size = Vector3.one
		a.Transparency = 1
		a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch, a.CastShadow = true, false, false, false, false
		a.Position = Vector3.new(f[1], 0, f[2])
		a.Parent = folder
		table.insert(anchors, a)
	end
	for _, p in Players:GetPlayers() do
		apply(p)
	end
	countParts(key)
end

function MapFocus.start()
	folder = Instance.new("Folder")
	folder.Name = Cfg.FocusFolder
	folder.Parent = workspace
	Players.PlayerAdded:Connect(apply)
	Players.PlayerRemoving:Connect(drop)
	workspace:GetAttributeChangedSignal(FrontCfg.MapAttribute):Connect(refocus)
	-- (the map's model may stand only after the server starts: Greybox, a rebuild)
	workspace.ChildAdded:Connect(function(child)
		if child.Name == LiveMap.key() then
			countParts(child.Name)
		end
	end)
	refocus()
end

return MapFocus
