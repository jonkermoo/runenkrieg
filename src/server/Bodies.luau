--!strict
-- Uniform soldier bodies (docs/CHARACTERS.md): every character is the plain blocky R6 body with no
-- avatar packages, clothing, accessories or face, so hitboxes are fair and everyone reads as a
-- soldier. The rig type itself is a game setting (Game Settings -> Avatar -> R6); scripts can't set it.
-- Uniform colors and gear are added on top of this body later (nation kits).

local Players = game:GetService("Players")

local Bodies = {}

local warned = false

function Bodies.apply(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 and not warned then
		warned = true
		warn("[Bodies] character is not R6: set Game Settings -> Avatar -> Avatar Type to R6")
	end
	-- a fresh description is the default blocky body: no packages, clothing or accessories
	local desc = Instance.new("HumanoidDescription")
	desc.Face = 0
	pcall(function()
		humanoid:ApplyDescription(desc)
	end)
	local head = character:FindFirstChild("Head")
	local face = head and head:FindFirstChildOfClass("Decal")
	if face then
		face:Destroy() -- faceless (docs/CHARACTERS.md)
	end
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
