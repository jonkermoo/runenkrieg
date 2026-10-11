--!strict
-- Uniform soldier bodies (docs/CHARACTERS.md): every character is the plain blocky R6 body with no
-- avatar packages, clothing or accessories, and the one soldier face, so hitboxes are fair and everyone reads as a
-- soldier. The rig type itself is a game setting (Game Settings -> Avatar -> R6); scripts can't set it.
-- Then it dresses the body in its uniform kit (Config/Uniforms): Shirt + Pants and skin color, and puts on the face
-- (on a "FaceCard" shell welded over the head).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local U = require(ReplicatedStorage:WaitForChild("Shared").Config.Uniforms)

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
	-- a fresh description is the default blocky body: no packages or accessories, just the kit
	local kit = U.Kits[U.Default]
	local skin = Color3.fromRGB(kit.skin[1], kit.skin[2], kit.skin[3])
	local desc = Instance.new("HumanoidDescription")
	desc.Face = 0
	desc.Shirt = 0
	desc.Pants = 0
	desc.HeadColor, desc.TorsoColor = skin, skin
	desc.LeftArmColor, desc.RightArmColor, desc.LeftLegColor, desc.RightLegColor = skin, skin, skin, skin
	pcall(function()
		humanoid:ApplyDescription(desc)
	end)
	local head = character:FindFirstChild("Head")
	if head then
		-- the avatar's own face goes; the soldier face goes on
		for _, d in head:GetChildren() do
			if d:IsA("Decal") then
				d:Destroy()
			end
		end
		-- the face goes on its own shell over the head, not on the Head: Roblox bakes decals on body parts into the
		-- character's lower-resolution texture (docs/KNOWN_TRAPS.md), a separate part keeps the full 1024 image
		local old = character:FindFirstChild("FaceCard")
		if old then
			old:Destroy()
		end
		local card = Instance.new("Part")
		card.Name = "FaceCard"
		card.Size = (head :: BasePart).Size
		card.Transparency = 1
		card.CanCollide, card.CanQuery, card.CanTouch, card.Massless = false, false, false, true
		card.CastShadow = false
		card.CFrame = (head :: BasePart).CFrame
		local shape = head:FindFirstChildWhichIsA("SpecialMesh")
		if shape then
			local mesh = shape:Clone()
			mesh.Scale *= 1.01 -- a hair outside the head, so the two surfaces never fight
			mesh.Parent = card
		end
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Face = Enum.NormalId.Front
		face.Texture = "rbxassetid://" .. U.Faces[1].open -- spawn at full health
		face.Parent = card
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = head :: BasePart, card
		weld.Parent = card
		card.Parent = character
	end
	for _, c in character:GetChildren() do
		if c:IsA("Clothing") then
			c:Destroy()
		end
	end
	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = "rbxassetid://" .. kit.shirt
	shirt.Parent = character
	local pants = Instance.new("Pants")
	pants.PantsTemplate = "rbxassetid://" .. kit.pants
	pants.Parent = character
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
