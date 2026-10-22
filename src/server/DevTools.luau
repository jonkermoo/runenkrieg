--!strict
-- Dev teleports: allowed players (Config/DevTools) get the DevTools attribute; the client menu sends a
-- destination id over Net "DevTeleport" and the server moves the character, standing on the ground.
-- Dev weapons: the weapon menu sends a weapon name over Net "DevGiveWeapon"; it becomes the player's loadout pick
-- for its slot (Armory.choose: given now as if spawned with it, and on every respawn).
-- Test actions: the target, blast and admin panels send Net "DevAction" (action, value, aim point); each is checked here
-- (the DevTools attribute, Rules/DevActions: the action, its value from the Config lists, the aim point's reach) and
-- done: target dummies (src/server/DevDummies), blasts at the aim point (src/server/Damage.blast; Net "DevBlast" shows
-- the explosion to everyone), your health / death / respawn / god mode / knock / helmet, the range's test shooters
-- (src/server/TestShooter) and undo destruction (src/server/DevWorld).
-- DevTools.teleport(player, id) is also used directly by tests/demos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Armory = require(script.Parent.Armory)
local Artillery = require(script.Parent.Artillery)
local Damage = require(script.Parent.Damage)
local DevDummies = require(script.Parent.DevDummies)
local DevWorld = require(script.Parent.DevWorld)
local Helmets = require(script.Parent.Helmets)
local Ragdoll = require(script.Parent.Ragdoll)
local Cfg = require(Shared.Config.DevTools)
local W = require(Shared.Config.Weapons)
local Map1 = require(Shared.Config.Maps.Map1)
local Rules = require(Shared.Rules.DevTeleports)
local Actions = require(Shared.Rules.DevActions)
local Net = require(Shared.Net)

local DevTools = {}

local last: { [Player]: number } = {}
local lastAction: { [Player]: number } = {} -- (test actions keep their own cooldown)

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
	for _, name in { "ClientGrass", "ClientGrassBlades", "ClientDebris" } do
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

-- Does one checked test action for `player` (aim: the aim point, for the aimed actions).
local function act(player: Player, action: string, value: any, aim: Vector3?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if action == "Dummy" and aim and root then
		local at = aim + Vector3.new(0, Cfg.Dummies.RootHeight, 0)
		local face = Vector3.new(root.Position.X, at.Y, root.Position.Z)
		if (face - at).Magnitude < 1e-3 then
			face = at + Vector3.new(0, 0, 1)
		end
		DevDummies.spawn({ kit = value.kit, helmet = value.helmet, move = value.move, at = CFrame.lookAt(at, face) })
	elseif action == "PlaceGun" and aim and root then
		Artillery.place(value, aim, aim - root.Position)
	elseif action == "ClearGuns" then
		Artillery.clear()
	elseif action == "HealDummies" then
		DevDummies.heal()
	elseif action == "ClearDummies" then
		DevDummies.clear()
	elseif (action == "BlastStage" or action == "BlastKg") and aim then
		local by = if player:GetAttribute(Cfg.Blasts.HurtAttribute) == true then nil else character
		Net.event("DevBlast")
			:FireAllClients(
				aim,
				if action == "BlastStage" then value else nil,
				if action == "BlastKg" then value else nil
			)
		if action == "BlastKg" then
			Damage.blast(aim, value, by)
		else
			Damage.staffBlast(aim, value, by)
		end
	elseif action == "BlastHurts" then
		player:SetAttribute(Cfg.Blasts.HurtAttribute, if value then true else nil)
	elseif action == "God" then
		player:SetAttribute(Cfg.Admin.GodAttribute, if value then true else nil)
	elseif action == "Shooters" then
		workspace:SetAttribute(Cfg.TestShooter.Attribute, if value then true else nil)
	elseif action == "UndoDestruction" then
		DevWorld.undo()
	elseif action == "Respawn" then
		player:LoadCharacter()
	elseif humanoid and character and root and humanoid.Health > 0 then
		if action == "Health" then
			humanoid.Health = math.min(value, humanoid.MaxHealth)
		elseif action == "Kill" then
			humanoid.Health = 0
		elseif action == "KnockMe" then
			Ragdoll.knock(character, Cfg.Admin.SelfKnock, -root.CFrame.LookVector)
		elseif action == "HelmetOff" then
			Helmets.knockOff(character, -root.CFrame.LookVector)
		elseif action == "Grenade" then
			Armory.give(player, value) -- a full count, in place of the grenade carried
		end
	end
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
		lastAction[p] = nil
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
	Net.event("DevAction").OnServerEvent:Connect(function(player: Player, action: any, value: any, aim: any)
		if player:GetAttribute(Cfg.Attribute) ~= true or not Actions.valid(Cfg, action, value) then
			return
		end
		local point: Vector3? = nil
		if Actions.Aimed[action] then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if typeof(aim) ~= "Vector3" or not root then
				return
			end
			local d = (aim :: Vector3) - root.Position
			if not Actions.inReach(Cfg, d.X, d.Y, d.Z) then
				return
			end
			point = aim
		end
		local now = os.clock()
		if lastAction[player] and now - lastAction[player] < Cfg.CooldownSeconds then
			return
		end
		lastAction[player] = now
		act(player, action, value, point)
	end)
	DevDummies.start()
	DevWorld.start()
end

return DevTools
