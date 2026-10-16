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

require(script.Bodies).start() -- (dresses the helmet and hair: script.Helmets)
require(script.Armory).start()
require(script.Doors).start()
require(script.DevTools).start()
require(script.Firing).start()
require(script.Showcase).start()
require(script.TestShooter).start()

print("[runenkrieg] server started")
