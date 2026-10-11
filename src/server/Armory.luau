--!strict
-- Weapons in play (.claude/skills/roblox-weapons/SKILL.md, Config/Weapons). Builds a rigged weapon from its
-- library model (ReplicatedStorage.Assets.Weapons...): the export's Origin marker becomes the invisible Handle at
-- the gun origin, static parts are welded to it, moving parts get Motor6Ds at their pivots, and the Muzzle / Aim /
-- Eject attachments sit on it (all looking down gun -Z, so sight and fire stay parallel).
-- Armory.give(player, name) hands it over as a Tool; the kit's weapon (Config/Uniforms) is given on spawn.
-- No motion here: the moving parts only have their Motor6Ds; animation is a later, separate step.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Assets)
local U = require(Shared.Config.Uniforms)
local W = require(Shared.Config.Weapons)

local Armory = {}

local function v3(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
end

local function libraryModel(name: string): Model
	local w = W[name]
	assert(w, "unknown weapon " .. name)
	local e = A.Entries[w.asset]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local f = assets and assets:FindFirstChild(e.category)
	f = f and f:FindFirstChild(e.folder)
	local m = f and f:FindFirstChild(w.asset)
	assert(m, `weapon model {w.asset} is not in ReplicatedStorage.Assets (run the Library sync in the dev place)`)
	return m :: Model
end

-- A rigged copy of the weapon as a Model (PrimaryPart = Handle).
function Armory.build(name: string): Model
	local w = W[name]
	local model = libraryModel(name):Clone()
	model.Name = name
	local origin = model:FindFirstChild("Origin", true) :: BasePart
	assert(origin, name .. ": the model has no Origin marker")
	local frame = CFrame.new(origin.Position) -- gun space: origin position, the model's axes
	origin.Name = "Handle"
	origin.Transparency = 1
	origin.Size = Vector3.new(0.2, 0.2, 0.2)
	origin.CFrame = frame
	origin.PivotOffset = CFrame.new() -- the FBX import leaves a rotated pivot on the marker (KNOWN_TRAPS)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= origin then
			local c = w.parts[p.Name]
			if c then
				p.Color = Color3.fromRGB(c[1], c[2], c[3])
			end
			p.Material = Enum.Material.SmoothPlastic
			p.Anchored = false
			p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
			p.Massless = true
			if table.find(w.hidden, p.Name) then
				p.Transparency = 1
			end
			local pivot = w.moving[p.Name]
			if pivot then
				local m = Instance.new("Motor6D")
				m.Name = p.Name
				m.Part0, m.Part1 = origin, p
				m.C0 = CFrame.new(v3(pivot))
				m.C1 = p.CFrame:ToObjectSpace(frame * m.C0)
				m.Parent = origin
			else
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = origin, p
				weld.Parent = p
			end
		end
	end
	origin.Anchored = false
	origin.CanCollide, origin.CanQuery, origin.CanTouch = false, false, false
	for att, pos in w.attachments do
		local a = Instance.new("Attachment")
		a.Name = att
		a.Position = v3(pos) -- default orientation: looking down -Z, like the gun
		a.Parent = origin
	end
	model.PrimaryPart = origin
	model:SetAttribute("Weapon", name)
	return model
end

-- The weapon as a Tool (Handle = the gun origin; Grip puts the right hand on the wrist).
function Armory.tool(name: string): Tool
	local w = W[name]
	local model = Armory.build(name)
	local tool = Instance.new("Tool")
	tool.Name = w.display
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(v3(w.grip))
	for _, c in model:GetChildren() do
		c.Parent = tool
	end
	model:Destroy()
	tool:SetAttribute("Weapon", name)
	return tool
end

function Armory.give(player: Player, name: string): Tool
	local backpack = player:WaitForChild("Backpack")
	for _, t in backpack:GetChildren() do
		if t:GetAttribute("Weapon") == name then
			t:Destroy()
		end
	end
	local tool = Armory.tool(name)
	tool.Parent = backpack
	return tool
end

function Armory.start()
	local kit = U.Kits[U.Default] :: any
	if not kit.weapon then
		return -- the default kit carries no weapon yet (teams/nations not decided)
	end
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			Armory.give(player, kit.weapon)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return Armory
