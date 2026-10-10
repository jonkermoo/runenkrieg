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

require(script.Bodies).start()
require(script.Doors).start()
require(script.DevTools).start()

print("[runenkrieg] server started")
