--!strict
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
Net.init()

-- The soldiers' groups: a team's soldiers pass through each other (src/server/SoldierGroups, Config/Collision).
local SoldierGroups = require(script.SoldierGroups)
-- Client debris must never collide with characters.
PhysicsService:RegisterCollisionGroup("Debris")
-- The first-person viewmodel (src/client/Viewmodel) collides with nothing: its Humanoid forces the "Torso" part
-- collidable every frame, and that torso sits inside the player's own head (it shoved the character around).
PhysicsService:RegisterCollisionGroup("Viewmodel")
SoldierGroups.register() -- (after Debris and Viewmodel: the camera's sweep passes through them)
SoldierGroups.setWith("Debris", false)
for _, g in PhysicsService:GetRegisteredCollisionGroups() do
	PhysicsService:CollisionGroupSetCollidable("Viewmodel", g.name, false)
end
-- The out-of-bounds walls (Config/Boundary): they stop characters and nothing else, so shots and blasts reach beyond.
do
	local B = require(ReplicatedStorage.Shared.Config.Boundary)
	if not PhysicsService:IsCollisionGroupRegistered(B.CollisionGroup) then
		PhysicsService:RegisterCollisionGroup(B.CollisionGroup)
	end
	for _, g in PhysicsService:GetRegisteredCollisionGroups() do
		local blocks = table.find(B.Blocks, g.name) ~= nil
			or (table.find(B.Blocks, "Characters") ~= nil and SoldierGroups.isSoldier(g.name))
		PhysicsService:CollisionGroupSetCollidable(B.CollisionGroup, g.name, blocks)
	end
end
local assign = SoldierGroups.track
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(assign)
end)
for _, p in Players:GetPlayers() do
	if p.Character then
		assign(p.Character)
	end
	p.CharacterAdded:Connect(assign)
end

require(script.Profile).start() -- (the saved settings)
require(ReplicatedStorage:WaitForChild("Shared").Hitches).watch() -- (the hitch log's long frames)
require(script.Environment).start()
require(script.Loadouts).start() -- (the class each life spawns as, the match currency)
require(script.Bodies).start() -- (dresses the helmet and hair: script.Helmets)
require(script.Armory).start()
require(script.Deploy).start() -- (no auto respawn: the menus deploy; the loadout preview soldier)
require(script.Chat).start() -- (the game's own chat: team and whisper channels, Global between servers)
require(script.Doors).start()
require(script.Indoors).start() -- (pathfinding links through doorways and up stairs, for bots)
require(script.Sectors).start() -- (hides the sector dividers and point markers)
require(script.Flagpoles).start() -- (a pole on each sector point while the frontline match runs)
require(script.MapVote).start() -- (the next map, voted for between Normal matches)
require(script.MapFocus).start() -- (the live map kept streamed in for every player: Config/JoinLoading)
require(script.PoleWires).start() -- (the telegraph wires come down with their poles; before DevTools saves the map)
require(script.DevTools).start()
require(script.Firing).start()
require(script.Melee).start()
require(script.LookTilt).start()
require(script.StaffCast).start()
require(script.Ragdoll).start()
require(script.Damage).start()
require(script.Healing).start()
require(script.Dragging).start()
require(script.Grenades).start()
require(script.Artillery).start()
require(script.Build).start(require(script.Artillery)) -- (the guns players build)
-- (craters fill back in, trenches never; craters stop at trenches)
require(script.Ground).start(require(script.Build).dug, require(script.Build).nearTrench)
require(script.Wire).start()
require(script.Showcase).start()
require(script.TestShooter).start()
-- the zone match's captures pay match points and each match starts them over (src/server/Loadouts, when the game has
-- it; hooked before the first match starts)
local loadouts = script:FindFirstChild("Loadouts")
if loadouts then
	local L = require(loadouts) :: any
	require(script.ZoneMatch).onCapture(function(player)
		L.award(player, "Capture")
	end)
	require(script.ZoneMatch).onMatchStart(L.resetMatch)
	-- Normal mode's frontline: captures, neutralisations and Defends pay match points (Config/Classes.Earn)
	local Frontline = require(script.Frontline)
	Frontline.onAward(L.award)
	Frontline.onMatchStart(L.resetMatch)
	L.onKill(Frontline.killed)
	-- each match's results: kills, HP healed on others, HP built, points earned (src/server/MatchStats)
	local Stats = require(script.MatchStats)
	L.onKill(function(killer)
		Stats.add(killer, "Kills", 1)
	end)
	L.onEarn(function(player, n)
		Stats.add(player, "Earned", n)
	end)
	-- support pays (the marks rebalance, user 2026-11-05): health healed on others, a downed teammate dragged
	local ClassCfg = require(game:GetService("ReplicatedStorage").Shared.Config.Classes) :: any
	require(script.Healing).onHealed(function(player, n)
		Stats.add(player, "Healed", n)
		L.award(player, "Heal", n / ClassCfg.HealPer)
	end)
	require(script.Dragging).onDragged(function(player)
		L.award(player, "Drag")
	end)
	require(script.Build).onBuilt(function(player, n)
		Stats.add(player, "Built", n)
	end)
	Frontline.onMatchStart(Stats.reset)
	require(script.ZoneMatch).onMatchStart(Stats.reset)
end
require(script.Modes).start() -- (the server's game mode: the zone-capture match on the playtest map in FFA)
require(script.Bots).start() -- (bot soldiers filling the empty places: Config/Bots)

print("[runenkrieg] server started")
