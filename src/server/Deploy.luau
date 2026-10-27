--!strict
-- Spawning from the menus (user 2026-10-27): no character until the player deploys. A player who joins gets the title
-- screen, then the loadout menu (src/client/Menus); on every death the loadout menu opens again. The "Deploy" action
-- (Net "Loadout", src/server/Loadouts) spawns them once Config/Metrics.Combat.RespawnDelay has passed since their last
-- death (at once after the join). Each player's next life is settled ahead: the kit and looks are rolled at the join
-- and on each death (src/server/Kits, src/server/Bodies), and the menu shows that soldier in the picked class: a
-- dressed, anchored rig kept in the player's PlayerGui (only they get it) as "LoadoutPreview", rebuilt on every pick
-- and death, its primary in the hands (the client plays the hold).
-- Kept teams (Config/Teams, Rules/Teams; user 2026-10-27): where the mode keeps them (Rules/Modes.keptTeams) a newcomer
-- joins the smallest team and keeps it every life (elsewhere the kit is rolled again on each death), and the state
-- carries `teams` for the menu's team cards: every team's count and room, the player's own, and why each is closed. A
-- team change ("Team", kit) is checked here again: in the menu only (not alive) and only if it keeps the teams even.
-- Every head count change (a join, a leave, a change) sends the new counts to everyone in the menus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Classes)
local Metrics = require(Shared.Config.Metrics)
local ModeCfg = require(Shared.Config.Modes)
local TeamCfg = require(Shared.Config.Teams)
local U = require(Shared.Config.Uniforms)
local Rules = require(Shared.Rules.Classes)
local ModeRules = require(Shared.Rules.Modes)
local Teams = require(Shared.Rules.Teams)
local Armory = require(script.Parent.Armory)
local Bodies = require(script.Parent.Bodies)
local Kits = require(script.Parent.Kits)
local Loadouts = require(script.Parent.Loadouts)

local Deploy = {}

local PREVIEW = "LoadoutPreview"

-- when each player last died (os.clock); none: never spawned or alive
local diedAt: { [Player]: number } = {}

local function alive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function kept(): boolean
	return ModeRules.keptTeams(
		ModeCfg,
		workspace:GetAttribute(ModeCfg.Attribute),
		workspace:GetAttribute(TeamCfg.DevAttribute)
	)
end

-- Every team's head count, leaving out `except`.
local function counts(except: Player?): { [string]: number }
	local of: { unknown } = {}
	for _, p in Players:GetPlayers() do
		if p ~= except then
			table.insert(of, Kits.next(p))
		end
	end
	return Teams.counts(of, U.Teams)
end

local ROOM = Teams.room(TeamCfg.MaxPlayers, #U.Teams)

-- The menu's team cards for `player` (nil where teams aren't kept): each team's count, the room, their own team, and
-- why each is closed to them ("" when open).
local function teamsOf(player: Player): { [string]: any }?
	if not kept() then
		return nil
	end
	local c = counts()
	local own = Kits.next(player)
	local closed: { [string]: string } = {}
	for _, t in U.Teams do
		closed[t] = Teams.blocked(c, own, t, TeamCfg.Gap, ROOM) or ""
	end
	return { list = U.Teams, counts = c, room = ROOM, own = own, closed = closed }
end

-- The new head counts to everyone in the menus.
local function recount()
	if not kept() then
		return
	end
	for _, p in Players:GetPlayers() do
		if not alive(p) then
			Loadouts.send(p)
		end
	end
end

-- Seconds until `player` may deploy (0: now).
function Deploy.wait(player: Player): number
	local at = diedAt[player]
	if not at then
		return 0
	end
	return math.max(Metrics.Combat.RespawnDelay - (os.clock() - at), 0)
end

-- The soldier `player` spawns as next, as class `key`: their next kit and looks, the class's helmet and primary.
local function preview(player: Player, key: string)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return
	end
	local old = gui:FindFirstChild(PREVIEW)
	if old then
		old:Destroy()
	end
	local kit = Kits.next(player)
	local desc = Instance.new("HumanoidDescription")
	local rig = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	rig.Name = PREVIEW
	for _, d in rig:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	rig.PrimaryPart = root
	rig:SetAttribute("Kit", kit) -- (src/server/Kits)
	rig:SetAttribute("Class", key) -- (src/server/Loadouts: the class's helmet)
	rig:SetAttribute("Muted", true)
	rig:PivotTo(CFrame.new())
	rig.Parent = gui
	Bodies.apply(rig, player) -- in this player's next look
	local primary = Rules.gear(key, kit, C.Defs, U.Kits, C.Gear).Primary
	if primary then
		local tool = Armory.tool(primary, kit)
		local hold = tool:FindFirstChild("Hold", true) :: Motor6D
		hold.Part0 = rig:FindFirstChild("Torso") :: BasePart
		tool.Parent = rig
		rig:SetAttribute("Primary", primary) -- (src/client/Menus plays its ready hold)
	end
end

local function spawned(player: Player, character: Model)
	diedAt[player] = nil
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		diedAt[player] = os.clock()
	end)
end

function Deploy.start()
	Players.CharacterAutoLoads = false
	Loadouts.bind({
		changed = function(player: Player, why: string)
			if why == "Died" then
				diedAt[player] = os.clock()
				if not kept() then
					Kits.reroll(player)
				end
				Bodies.reroll(player)
			end
			preview(player, Loadouts.picked(player))
		end,
		deploy = function(player: Player)
			if alive(player) or Deploy.wait(player) > 0 then
				return
			end
			diedAt[player] = nil
			player:LoadCharacter()
		end,
		team = function(player: Player, kit: any): boolean
			if not kept() or alive(player) then
				return false
			end
			if Teams.blocked(counts(), Kits.next(player), kit, TeamCfg.Gap, ROOM) then
				return false
			end
			Kits.place(player, kit)
			task.defer(recount)
			return true
		end,
		fields = function(player: Player)
			if not player:FindFirstChildOfClass("PlayerGui") or not player.PlayerGui:FindFirstChild(PREVIEW) then
				preview(player, Loadouts.picked(player))
			end
			return {
				wait = Deploy.wait(player),
				alive = alive(player),
				kit = Kits.next(player),
				teams = teamsOf(player),
			}
		end,
	})
	local function hook(player: Player)
		if kept() then
			Kits.place(player, Teams.smallest(counts(player), U.Teams, math.random()))
			recount()
		end
		player.CharacterAdded:Connect(function(character)
			spawned(player, character)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		diedAt[p] = nil
		task.defer(recount) -- (once they're gone from the list)
	end)
	-- the admin's test switch, or a mode change: the cards show or go
	local function resend()
		for _, p in Players:GetPlayers() do
			if not alive(p) then
				Loadouts.send(p)
			end
		end
	end
	workspace:GetAttributeChangedSignal(TeamCfg.DevAttribute):Connect(resend)
	workspace:GetAttributeChangedSignal(ModeCfg.Attribute):Connect(resend)
end

return Deploy
