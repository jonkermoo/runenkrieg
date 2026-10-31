--!strict
-- Dev teleports: allowed players (Config/DevTools) get the DevTools attribute; the client menu sends a
-- destination id over Net "DevTeleport" and the server moves the character, standing on the ground.
-- Dev weapons: the weapon menu sends a weapon name over Net "DevGiveWeapon"; it becomes the player's loadout pick
-- for its slot (Armory.choose: given now as if spawned with it, and on every respawn).
-- Test actions: the target, blast and admin panels send Net "DevAction" (action, value, aim point); each is checked here
-- (the DevTools attribute, Rules/DevActions: the action, its value from the Config lists, the aim point's reach) and
-- done: target dummies (src/server/DevDummies), blasts at the aim point (src/server/Damage.blast; Net "DevBlast" shows
-- the explosion to everyone), your health / death / respawn / team (respawn as it) / god mode / knock / helmet, the range's test shooters
-- (src/server/TestShooter), undo destruction (src/server/DevWorld) and the clock (src/server/Environment: set the time,
-- pause the day cycle; start fog / rain / clear sky now, the random weather off / on), the server's game mode
-- (src/server/Modes), the FFA match (src/server/ZoneMatch: end, restart, skip the zone, more time, score), match points
-- and a class pinned every life (src/server/Loadouts), building anything, unlimited ammo, everyone respawned.
-- DevTools.teleport(player, id) is also used directly by tests/demos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Armory = require(script.Parent.Armory)
local Artillery = require(script.Parent.Artillery)
local Damage = require(script.Parent.Damage)
local DevDummies = require(script.Parent.DevDummies)
local Build = require(script.Parent.Build)
local DevWorld = require(script.Parent.DevWorld)
local Environment = require(script.Parent.Environment)
local Helmets = require(script.Parent.Helmets)
local Loadouts = require(script.Parent.Loadouts)
local Frontline = require(script.Parent.Frontline)
local Modes = require(script.Parent.Modes)
local ZoneMatch = require(script.Parent.ZoneMatch)
local SectorCfg = require(Shared.Config.Sectors)
local Ragdoll = require(script.Parent.Ragdoll)
local Cfg = require(Shared.Config.DevTools)
local BotsCfg = require(Shared.Config.Bots)
local ClassCfg = require(Shared.Config.Classes)
local ModeCfg = require(Shared.Config.Modes)
local TeamCfg = require(Shared.Config.Teams)
local ModeRules = require(Shared.Rules.Modes)
local W = require(Shared.Config.Weapons)
local Map1 = require(Shared.Config.Maps.Map1)
local Rules = require(Shared.Rules.DevTeleports)
local Actions = require(Shared.Rules.DevActions)
local Net = require(Shared.Net)

local DevTools = {}

local DEFS = { modes = ModeCfg.Defs, classes = ClassCfg.Defs } -- (the "Mode" and "Class" values, Rules/DevActions)
-- the admin settings a player loses with the tools (the server's mode closing them)
local REVOKED = {
	Cfg.Admin.GodAttribute,
	Cfg.Blasts.HurtAttribute,
	Cfg.Admin.Dig.attribute,
	Cfg.Admin.BuildAllAttribute,
	Cfg.Admin.AmmoAttribute,
	Cfg.Admin.ClassAttribute,
}

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
	elseif action == "PlacePiece" and aim and root and table.find(Cfg.Blasts.Pieces, value) then
		-- (facing away from you, like the guns)
		local away = (aim - root.Position) * Vector3.new(1, 0, 1)
		if away.Magnitude < 1e-3 then
			away = Vector3.new(0, 0, -1)
		end
		Build.devPlace(player, value, CFrame.lookAt(aim, aim + away))
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
	elseif action == "DigStep" then
		player:SetAttribute(Cfg.Admin.Dig.attribute, if value > 0 then value else nil)
	elseif action == "God" then
		player:SetAttribute(Cfg.Admin.GodAttribute, if value then true else nil)
	elseif action == "Shooters" then
		workspace:SetAttribute(Cfg.TestShooter.Attribute, if value then true else nil)
	elseif action == "UndoDestruction" then
		DevWorld.undo()
	elseif action == "Clock" then
		Environment.setClock(value)
	elseif action == "ClockPaused" then
		Environment.pause(value)
	elseif action == "Weather" then
		Environment.forceNow(value, Cfg.Admin.WeatherSeconds)
	elseif action == "WeatherCalm" then
		Environment.calm(value)
	elseif action == "Respawn" then
		player:LoadCharacter()
	elseif action == "Mode" then
		Modes.switch(value)
	elseif action == "MatchEnd" then
		-- the live mode's match: Normal's frontline or the FFA's zone match
		if Frontline.running() then
			Frontline.finish()
		else
			ZoneMatch.finish()
		end
	elseif action == "MatchRestart" then
		if Frontline.running() then
			Frontline.restart()
		else
			ZoneMatch.restart()
		end
	elseif action == "FrontStart" then
		Frontline.begin()
	elseif action == "FrontTake" then
		Frontline.take(player)
	elseif action == "Sectors" then
		-- the sector dividers and point markers shown in play (src/server/Sectors)
		workspace:SetAttribute(SectorCfg.ShowAttribute, value)
	elseif action == "ZoneSkip" then
		ZoneMatch.skip()
	elseif action == "MatchTime" then
		ZoneMatch.extend(value)
	elseif action == "ZoneScore" then
		ZoneMatch.addScore(player, value)
	elseif action == "Bots" then
		workspace:SetAttribute(BotsCfg.Attribute, value) -- (src/server/Bots: the count pinned)
	elseif action == "BotsAuto" then
		workspace:SetAttribute(BotsCfg.Attribute, nil)
	elseif action == "BotDifficulty" then
		workspace:SetAttribute(BotsCfg.DifficultyAttribute, value)
	elseif action == "Points" then
		Loadouts.grant(player, value)
	elseif action == "Class" then
		-- pinned (Rules/Classes.resolve reads it on every spawn), then a new body as it now
		player:SetAttribute(Cfg.Admin.ClassAttribute, if value == Cfg.Admin.Normal then nil else value)
		player:LoadCharacter()
	elseif action == "BuildAll" then
		player:SetAttribute(Cfg.Admin.BuildAllAttribute, if value then true else nil)
	elseif action == "Ammo" then
		player:SetAttribute(Cfg.Admin.AmmoAttribute, if value then true else nil)
	elseif action == "KeptTeams" then
		-- test the kept teams and the loadout menu's team cards outside Normal (Config/Teams; src/server/Deploy)
		workspace:SetAttribute(TeamCfg.DevAttribute, if value then true else nil)
	elseif action == "RespawnAll" then
		for _, p in Players:GetPlayers() do
			task.spawn(function()
				p:LoadCharacter()
			end)
		end
	elseif action == "Team" then
		-- the pinned kit (src/server/Kits reads it on every spawn), then a new body in it now
		player:SetAttribute("Kit", if value == Cfg.Admin.Random then nil else value)
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
	-- (everyone again each time the server's mode changes: only the admin mode opens the tools to all)
	local function setup(player: Player)
		local open = ModeRules.openAdmin(ModeCfg, workspace:GetAttribute(ModeCfg.Attribute))
		local allowed = Rules.allowed(Cfg, player.UserId, RunService:IsStudio(), game.PlaceId, open)
		player:SetAttribute(Cfg.Attribute, allowed)
		if not allowed then
			for _, name in REVOKED do
				player:SetAttribute(name, nil)
			end
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do
		setup(p)
	end
	workspace:GetAttributeChangedSignal(ModeCfg.Attribute):Connect(function()
		for _, p in Players:GetPlayers() do
			setup(p)
		end
	end)
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
		if player:GetAttribute(Cfg.Attribute) ~= true or not Actions.valid(Cfg, action, value, DEFS) then
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
