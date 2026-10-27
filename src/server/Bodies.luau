--!strict
-- Uniform soldier bodies (docs/CHARACTERS.md): every character is the plain blocky R6 body with no
-- avatar packages, clothing or accessories, and the one soldier face, so hitboxes are fair and everyone reads as a
-- soldier. The rig type itself is a game setting (Game Settings -> Avatar -> R6); scripts can't set it.
-- Then it dresses the body in its uniform kit (Config/Uniforms): Shirt + Pants, rolls the life's skin and hair colors
-- (Config/Uniforms Skins / HairColors, Rules/Looks) and hairstyle, puts on the face (on a "FaceCard" shell welded
-- over the head), the kit's helmet over the hair (src/server/Helmets), the life's rig in the kit's colors
-- (src/server/Rigs), its pack on the back (src/server/Packs) and its species' ears and tail (src/server/Species).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local U = require(Shared.Config.Uniforms)
local SpeciesCfg = require(Shared.Config.Species)
local Faces = require(Shared.Rules.Faces)
local Looks = require(Shared.Rules.Looks)
local SpeciesRule = require(Shared.Rules.Species)
local Helmets = require(script.Parent.Helmets)
local Kits = require(script.Parent.Kits)
local Loadouts = require(script.Parent.Loadouts)
local Packs = require(script.Parent.Packs)
local Rigs = require(script.Parent.Rigs)
local Species = require(script.Parent.Species)

local Bodies = {}

local warned = false

-- each player's skin, hair color, hairstyle and rig (pool indexes) for their next life: rolled at the join and again on
-- each death (src/server/Deploy: the loadout menu's preview shows them), never the same as the life before
-- (Rules/Looks); and whether they are their nation's species that life (Config/Species.Chance, Rules/Species.roll)
type Look = { skin: number, hair: number, style: number, rig: number, species: boolean }
local planned: { [Player]: Look } = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function roll(last: Look?): Look
	return {
		skin = Looks.pick(U.Skins, math.random(), last and last.skin),
		hair = Looks.pick(U.HairColors, math.random(), last and last.hair),
		style = Looks.pick(U.Hairs, math.random(), last and last.style),
		rig = Looks.pick(U.Rigs, math.random(), last and last.rig),
		species = SpeciesRule.roll(math.random(), SpeciesCfg.Chance),
	}
end

local function nextLook(player: Player): Look
	local look = planned[player] or roll(nil)
	planned[player] = look
	return look
end

-- Rolls `player`'s next look afresh (on a death), never the same as the one they had.
function Bodies.reroll(player: Player)
	planned[player] = roll(planned[player])
end

-- This life's skin, hair color, hairstyle and rig (src/server/Rigs reads "Rig"): a player's planned look, anything else a roll; once per character
-- (applied again in the same life keeps them), written as the "Skin" / "Hair" / "HairStyle" attributes (pool names),
-- "SkinColor" / "HairColor" (Color3) and "SpeciesRoll" (the nation's species this life: src/server/Species).
-- `as`: dress it in that player's next look (the loadout preview).
local function rollLooks(character: Model, as: Player?): Color3
	local skin = character:GetAttribute("SkinColor")
	if typeof(skin) == "Color3" then
		return skin
	end
	local player = as or Players:GetPlayerFromCharacter(character)
	local look = if player then nextLook(player) else roll(nil)
	local s, h, st = look.skin, look.hair, look.style
	character:SetAttribute("HairStyle", U.Hairs[st].name)
	character:SetAttribute("SpeciesRoll", look.species)
	if character:GetAttribute("Rig") == nil then
		character:SetAttribute("Rig", U.Rigs[look.rig].name)
	end
	character:SetAttribute("Skin", U.Skins[s].name)
	character:SetAttribute("SkinColor", rgb(U.Skins[s].color))
	character:SetAttribute("Hair", U.HairColors[h].name)
	character:SetAttribute("HairColor", rgb(U.HairColors[h].color))
	return rgb(U.Skins[s].color)
end

-- Dresses `character` (a player's, a dummy, or with `as` the loadout preview rig in that player's next look).
function Bodies.apply(character: Model, as: Player?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 and not warned then
		warned = true
		warn("[Bodies] character is not R6: set Game Settings -> Avatar -> Avatar Type to R6")
	end
	-- a fresh description is the default blocky body: no packages or accessories, just the kit
	local kitName = Kits.of(character) -- (src/server/Kits: the player's kit this life)
	local kit = U.Kits[kitName]
	local skin = rollLooks(character, as)
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
		face.Parent = card
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = head :: BasePart, card
		weld.Parent = card
		card.Parent = character
		Bodies.followHealth(character, humanoid, face)
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
	-- the helmet stays off once it has been shot off this life
	Helmets.dress(
		character,
		-- (the class's helmet: src/server/Loadouts, Config/Classes)
		if character:GetAttribute("HelmetOn") == false then nil else Loadouts.gear(character).headwear,
		Species.of(character, kitName)
	)
	Rigs.dress(character, kitName)
	Packs.dress(character, kit.pack)
	-- the kit's species: ears and a tail (src/server/Species)
	Species.dress(character, kitName)
end

-- The face follows health (Rules/Faces): the tier's face while alive; on death the CLOSED face of the tier the
-- character was in LAST (one hit from full health = the healthy closed face; never picked from health 0).
-- Writes "FaceTier" (1..3) and "FaceClosed" (dead) on the character for the client blink (src/client/Blink).
local following: { [Humanoid]: boolean } = setmetatable({}, { __mode = "k" }) :: any

function Bodies.followHealth(character: Model, humanoid: Humanoid, face: Decal)
	local tier = Faces.tier(humanoid.Health / math.max(humanoid.MaxHealth, 1e-6), U.Faces)
	local closed = humanoid.Health <= 0
	local function show()
		local f = U.Faces[tier]
		face.Texture = "rbxassetid://" .. (if closed then f.closed else f.open)
		character:SetAttribute("FaceTier", tier)
		character:SetAttribute("FaceClosed", closed)
	end
	show()
	if following[humanoid] then
		return -- the appearance was applied again: the health hook is already there and now drives this new face
	end
	following[humanoid] = true
	humanoid.HealthChanged:Connect(function(health)
		if closed then
			return -- dead stays dead
		end
		tier, closed = Faces.after(tier, health, humanoid.MaxHealth, U.Faces)
		local card = character:FindFirstChild("FaceCard")
		face = (card and card:FindFirstChild("face") :: Decal?) or face
		show()
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
	Players.PlayerRemoving:Connect(function(p)
		planned[p] = nil
	end)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return Bodies
