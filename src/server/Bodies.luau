--!strict
-- Uniform soldier bodies (docs/CHARACTERS.md): every character gets the same body scales
-- (Config/Metrics.Character.Scales) when it spawns, so hitboxes are fair and buildings fit. The
-- avatar's clothing and accessories are kept for now; uniforms replace them later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = require(ReplicatedStorage:WaitForChild("Shared").Config.Metrics)

local Bodies = {}

function Bodies.apply(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local s = M.Character.Scales
	local ok, desc = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not desc then
		return
	end
	desc.HeightScale = s.Height
	desc.WidthScale = s.Width
	desc.DepthScale = s.Depth
	desc.HeadScale = s.Head
	desc.BodyTypeScale = s.BodyType
	desc.ProportionScale = s.Proportion
	pcall(function()
		humanoid:ApplyDescription(desc)
	end)
end

function Bodies.start()
	local function hook(player: Player)
		player.CharacterAppearanceLoaded:Connect(Bodies.apply)
		if player.Character and player:HasAppearanceLoaded() then
			Bodies.apply(player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return Bodies
