--!strict
-- Dev teleports: allowed players (Config/DevTools) get the DevTools attribute; the client menu sends a
-- destination id over Net "DevTeleport" and the server moves the character, standing on the ground.
-- Dev weapons: the weapon menu sends a weapon name over Net "DevGiveWeapon"; it becomes the player's loadout pick
-- for its slot (Armory.choose: given now as if spawned with it, and on every respawn).
-- DevTools.teleport(player, id) is also used directly by tests/demos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Armory = require(script.Parent.Armory)
local Cfg = require(Shared.Config.DevTools)
local W = require(Shared.Config.Weapons)
local Map1 = require(Shared.Config.Maps.Map1)
local Rules = require(Shared.Rules.DevTeleports)
local Net = require(Shared.Net)

local DevTools = {}

local last: { [Player]: number } = {}

local function groundY(x: number, z: number, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = false
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), params)
	return if hit then hit.Position.Y else 0
end

function DevTools.teleport(player: Player, id: string): boolean
	local dest = Rules.find(Map1, Cfg, id)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not dest or not character or not root then
		return false
	end
	local ignore: { Instance } = { character }
	for _, name in { "ClientGrass", "ClientDebris" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	local y = dest.y or groundY(dest.x, dest.z, ignore)
	local pos = Vector3.new(dest.x, y + 3.2, dest.z)
	local look = if dest.look then Vector3.new(dest.look[1], pos.Y, dest.look[2]) else pos + Vector3.new(0, 0, -1)
	character:PivotTo(CFrame.lookAt(pos, look))
	root.AssemblyLinearVelocity = Vector3.zero
	-- streaming: make sure the destination is loaded for this player
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(pos)
		end)
	end)
	return true
end

function DevTools.start()
	local function setup(player: Player)
		local allowed = Rules.allowed(Cfg, player.UserId, RunService:IsStudio())
		player:SetAttribute(Cfg.Attribute, allowed)
	end
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do
		setup(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
	Net.event("DevTeleport").OnServerEvent:Connect(function(player: Player, id: any)
		if player:GetAttribute(Cfg.Attribute) ~= true or type(id) ~= "string" then
			return
		end
		local now = os.clock()
		if last[player] and now - last[player] < Cfg.CooldownSeconds then
			return
		end
		last[player] = now
		DevTools.teleport(player, id)
	end)
	Net.event("DevGiveWeapon").OnServerEvent:Connect(function(player: Player, name: any)
		if player:GetAttribute(Cfg.Attribute) ~= true or type(name) ~= "string" or not W[name] then
			return
		end
		local now = os.clock()
		if last[player] and now - last[player] < Cfg.CooldownSeconds then
			return
		end
		last[player] = now
		Armory.choose(player, name)
	end)
end

return DevTools
