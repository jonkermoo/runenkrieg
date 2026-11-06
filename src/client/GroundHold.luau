--!strict
-- This client's soldier never falls through ground that hasn't loaded here yet (user 2026-11-05: "i fell out of the map
-- after the map cutscene"; Config/JoinLoading.Ground). A soldier is moved by its own player's client, so where the
-- client lacks the terrain or floor under it (still streaming in after a spawn, a release from the wave line, a
-- teleport) it dropped through into the sky below. Each check: over the live map's ground (its bounds and terrain
-- margin), free to move, and nothing under the root within `depth` studs: the root is held still here (anchored on
-- this client only) and the ground asked for (Player:RequestStreamAroundAsync) until something is under it, `maxHold`
-- seconds at the most. The admin's Loading section shows how often it held (the HeldAttribute count).
--   GroundHold.start()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.JoinLoading).Ground
local LiveMap = require(Shared.LiveMap)
local Rules = require(Shared.Rules.JoinLoading)

local GroundHold = {}

local player = Players.LocalPlayer
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = false

local held: BasePart? = nil

local function groundUnder(character: Model, root: BasePart): boolean
	params.FilterDescendantsInstances = { character }
	return workspace:Raycast(root.Position, Vector3.new(0, -Cfg.depth, 0), params) ~= nil
end

local function onMap(pos: Vector3): boolean
	local ok, map = pcall(LiveMap.get)
	if not ok or not map or not map.bounds then
		return false
	end
	return Rules.within(map.bounds, map.terrainMargin or 0, pos.X, pos.Z)
end

local function hold(character: Model, root: BasePart)
	held = root
	root.Anchored = true -- (this client only: the server's copy is unchanged)
	root.AssemblyLinearVelocity = Vector3.zero
	player:SetAttribute(Cfg.HeldAttribute, (player:GetAttribute(Cfg.HeldAttribute) or 0) + 1)
	local at = root.Position
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(at, Cfg.maxHold)
		end)
	end)
	local from = os.clock()
	while root.Parent and character.Parent and not groundUnder(character, root) do
		if os.clock() - from > Cfg.maxHold then
			break
		end
		task.wait(Cfg.check)
	end
	if root.Parent and held == root then
		root.Anchored = false
	end
	held = nil
end

function GroundHold.start()
	local last = 0
	RunService.Heartbeat:Connect(function()
		if held or os.clock() - last < Cfg.check then
			return
		end
		last = os.clock()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root or root.Anchored then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		if onMap(root.Position) and not groundUnder(character, root) then
			task.spawn(hold, character, root)
		end
	end)
end

return GroundHold
