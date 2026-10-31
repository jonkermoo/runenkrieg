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
-- Every head count change (a join, a leave, a change) sends the new counts to everyone in the menus. In Normal mode
-- only the match's two teams are in play (src/server/Kits.playing): the cards show those, and each new pair (a new
-- match, Workspace's MatchTeams) splits everyone evenly over them again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Classes)
local Front = require(Shared.Config.Frontline)
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
	return Teams.counts(of, Kits.playing())
end

-- how many each team in play has room for
local function room(): number
	return Teams.room(TeamCfg.MaxPlayers, #Kits.playing())
end

-- The menu's team cards for `player` (nil where teams aren't kept): each team's count, the room, their own team, and
-- why each is closed to them ("" when open).
local function teamsOf(player: Player): { [string]: any }?
	if not kept() then
		return nil
	end
	local c = counts()
	local own = Kits.next(player)
	local list, r = Kits.playing(), room()
	local closed: { [string]: string } = {}
	for _, t in list do
		closed[t] = Teams.blocked(c, own, t, TeamCfg.Gap, r) or ""
	end
	return { list = list, counts = c, room = r, own = own, closed = closed }
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

-- each player's latest preview build: a build that finds a newer one started meanwhile drops its own rig (the user's
-- play test 2026-10-30: "players sometimes dont load their preview character"; a pick and a death close together ran
-- two builds at once, each yielding, and one destroyed or doubled the other)
local previewSeq: { [Player]: number } = {}

-- one build of the preview; false if a newer build took over (its rig gone)
local function buildPreview(player: Player, key: string, seq: number, made: { rig: Model? }): boolean
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return true
	end
	local kit = Kits.next(player)
	local desc = Instance.new("HumanoidDescription")
	local rig = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	made.rig = rig
	if previewSeq[player] ~= seq then
		rig:Destroy()
		return false
	end
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
	-- dressed whole out of the player's sight first, then handed over at once: src/client/Menus copies the rig the moment
	-- it arrives, so one dressed in their PlayerGui was copied bare (user 2026-10-31: "avatar still naked or not
	-- assessorized in loadout menu": the uniform but no hair, face, helmet or pack)
	rig.Parent = ServerStorage
	Bodies.apply(rig, player) -- in this player's next look
	if previewSeq[player] ~= seq then
		rig:Destroy()
		return false
	end
	local primary = Rules.gear(key, kit, C.Defs, U.Kits, C.Gear).Primary
	if primary then
		local tool = Armory.tool(primary, kit)
		local hold = tool:FindFirstChild("Hold", true) :: Motor6D
		hold.Part0 = rig:FindFirstChild("Torso") :: BasePart
		tool.Parent = rig
		rig:SetAttribute("Primary", primary) -- (src/client/Menus plays its ready hold)
	end
	-- the old preview (every one: an older build may have left one) goes as this one comes
	for _, old in gui:GetChildren() do
		if old.Name == PREVIEW then
			old:Destroy()
		end
	end
	rig.Parent = gui
	return true
end

-- The soldier `player` spawns as next, as class `key`: their next kit and looks, the class's helmet and primary. Only
-- the latest call's rig stays; a build that fails (the avatar service) is tried once more.
local function preview(player: Player, key: string)
	local seq = (previewSeq[player] or 0) + 1
	previewSeq[player] = seq
	for attempt = 1, 2 do
		local made: { rig: Model? } = { rig = nil }
		local ok, err = pcall(buildPreview, player, key, seq, made)
		if ok then
			return
		end
		if made.rig then
			(made.rig :: Model):Destroy() -- (half built, out of sight in ServerStorage)
		end
		if previewSeq[player] ~= seq then
			return
		end
		warn(`[Deploy] {player.Name}'s loadout preview failed (try {attempt} of 2): {err}`)
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
			if Teams.blocked(counts(), Kits.next(player), kit, TeamCfg.Gap, room()) then
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
			Kits.place(player, Teams.smallest(counts(player), Kits.playing(), math.random()))
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
		previewSeq[p] = nil
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
	-- a new pair of teams in play (Normal mode's next match, or switching into Normal): everyone split evenly over
	-- them, in a random order
	local function split()
		if kept() and workspace:GetAttribute(Front.TeamsAttribute) ~= nil then
			local list = Kits.playing()
			local c = Teams.counts({}, list)
			local order = Players:GetPlayers()
			for i = #order, 2, -1 do
				local j = math.random(i)
				order[i], order[j] = order[j], order[i]
			end
			for _, p in order do
				local t = Teams.smallest(c, list, math.random())
				Kits.place(p, t)
				c[t] += 1
			end
		end
		resend()
	end
	workspace:GetAttributeChangedSignal(TeamCfg.DevAttribute):Connect(resend)
	workspace:GetAttributeChangedSignal(ModeCfg.Attribute):Connect(split)
	workspace:GetAttributeChangedSignal(Front.TeamsAttribute):Connect(split)
end

return Deploy
