--!strict
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
Net.init()

-- Client debris must never collide with characters.
PhysicsService:RegisterCollisionGroup("Debris")
PhysicsService:RegisterCollisionGroup("Characters")
PhysicsService:CollisionGroupSetCollidable("Debris", "Characters", false)
-- The first-person viewmodel (src/client/Viewmodel) collides with nothing: its Humanoid forces the "Torso" part
-- collidable every frame, and that torso sits inside the player's own head (it shoved the character around).
PhysicsService:RegisterCollisionGroup("Viewmodel")
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
		PhysicsService:CollisionGroupSetCollidable(B.CollisionGroup, g.name, table.find(B.Blocks, g.name) ~= nil)
	end
end
local function assign(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Characters"
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Characters"
		end
	end)
end
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
require(script.Environment).start()
require(script.Loadouts).start() -- (the class each life spawns as, the match currency)
require(script.Bodies).start() -- (dresses the helmet and hair: script.Helmets)
require(script.Armory).start()
require(script.Deploy).start() -- (no auto respawn: the menus deploy; the loadout preview soldier)
require(script.Chat).start() -- (the game's own chat: team and whisper channels, Global between servers)
require(script.Doors).start()
require(script.Sectors).start() -- (hides the sector dividers and point markers)
require(script.Flagpoles).start() -- (a pole on each sector point while the frontline match runs)
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
	-- Normal mode's frontline: captures, neutralisations, Defends and the win pay match points (Config/Classes.Earn)
	local Frontline = require(script.Frontline)
	Frontline.onAward(L.award)
	Frontline.onMatchStart(L.resetMatch)
	L.onKill(Frontline.killed)
end
require(script.Modes).start() -- (the server's game mode: the zone-capture match on the playtest map in FFA)
require(script.Bots).start() -- (bot soldiers filling the empty places: Config/Bots)

print("[runenkrieg] server started")
