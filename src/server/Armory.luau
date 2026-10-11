--!strict
-- Weapons in play (.claude/skills/roblox-weapons/SKILL.md, Config/Weapons). Builds a rigged weapon from its
-- library model (ReplicatedStorage.Assets.Weapons...): the export's Origin marker becomes the invisible Handle at
-- the gun origin, static parts are welded to it, moving parts get Motor6Ds at their pivots, and the Muzzle / Aim /
-- Eject attachments sit on it (all looking down gun -Z, so sight and fire stay parallel). The whole weapon is
-- scaled by its Config `scale` (per gun axis) about the origin (gun-space numbers in Config are the modelled ones).
-- The parts are axis-aligned with gun space, so scaling their Size per axis can't shear them.
-- Armory.give(player, name) hands it over as a Tool into its slot (one weapon per slot: a new primary replaces the
-- old); on each spawn the player's loadout is given (their pick via Armory.choose, else the kit's weapon). While
-- the Tool isn't equipped, a copy rides on the body where Config/Weapons `stow` puts it (slung on the back); it
-- hides while the weapon is in the hands. Both live on the server, so every player sees them.
-- No motion here: the moving parts only have their Motor6Ds; animation is a later, separate step.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Assets)
local U = require(Shared.Config.Uniforms)
local W = require(Shared.Config.Weapons)

local Armory = {}

local LOADOUT = "Loadout_" -- Player attribute per slot: the weapon the player spawns with

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
	local s = v3(w.scale) -- per gun axis
	origin.Name = "Handle"
	origin.Transparency = 1
	origin.Size = Vector3.new(0.2, 0.2, 0.2)
	origin.CFrame = frame
	origin.PivotOffset = CFrame.new() -- the FBX import leaves a rotated pivot on the marker (KNOWN_TRAPS)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= origin then
			local rel = frame:ToObjectSpace(p.CFrame)
			p.Size *= s
			p.CFrame = frame * (rel.Rotation + rel.Position * s)
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
				m.C0 = CFrame.new(v3(pivot) * s)
				m.C1 = p.CFrame:ToObjectSpace(frame * m.C0)
				m.Parent = origin
			else
				-- a Weld with the offset written down, not a WeldConstraint: those re-record their offset whenever
				-- they reactivate (reparenting the stowed copy), and a part that had drifted stays off (KNOWN_TRAPS)
				local weld = Instance.new("Weld")
				weld.Name = p.Name
				weld.Part0, weld.Part1 = origin, p
				weld.C0 = frame:ToObjectSpace(p.CFrame)
				weld.Parent = p
			end
		end
	end
	origin.Anchored = false
	origin.CanCollide, origin.CanQuery, origin.CanTouch = false, false, false
	for att, pos in w.attachments do
		local a = Instance.new("Attachment")
		a.Name = att
		a.Position = v3(pos) * s -- default orientation: looking down -Z, like the gun
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
	tool.Grip = CFrame.new(v3(w.grip) * v3(w.scale))
	for _, c in model:GetChildren() do
		c.Parent = tool
	end
	model:Destroy()
	tool:SetAttribute("Weapon", name)
	return tool
end

-- The weapon's stowed copy on the character (not parented: Armory.give shows it while the Tool is put away).
function Armory.stowed(character: Model, name: string): Model?
	local s = W[name].stow
	local part = character:FindFirstChild(s.part) :: BasePart?
	if not part then
		return nil
	end
	local model = Armory.build(name)
	model.Name = "Stowed_" .. name
	local muzzle, side = v3(s.muzzle).Unit, v3(s.side).Unit
	-- gun axes in the part's space: +X = side, -Z = muzzle, +Y completes the frame
	local z = -muzzle
	local weld = Instance.new("Weld")
	weld.Name = "Stow"
	weld.Part0 = part
	weld.Part1 = model.PrimaryPart
	weld.C0 = CFrame.fromMatrix(v3(s.at), side, z:Cross(side), z)
	weld.Parent = model.PrimaryPart
	return model
end

-- Gives the weapon into its slot as if the player had spawned with it: whatever weapon held that slot (in the
-- hands, in the backpack or slung) is removed first, so a player carries one weapon per slot (one primary).
-- Tools can't be dropped, so it stays for the rest of the life.
function Armory.give(player: Player, name: string): Tool
	local slot = W[name].slot
	local backpack = player:WaitForChild("Backpack")
	local character = player.Character
	for _, holder in { backpack, character } do
		for _, t in if holder then holder:GetChildren() else {} do
			local held = t:GetAttribute("Weapon")
			if t:IsA("Tool") and held and W[held] and W[held].slot == slot then
				t:Destroy() -- its stowed copy goes with it
			end
		end
	end
	local tool = Armory.tool(name)
	tool.Parent = backpack

	local stowed = character and Armory.stowed(character, name)
	if character and stowed then
		local function update()
			stowed.Parent = if tool.Parent == character then nil else character
		end
		tool:GetPropertyChangedSignal("Parent"):Connect(update)
		tool.Destroying:Connect(function()
			stowed:Destroy()
		end)
		update()
	end
	player:SetAttribute(LOADOUT .. slot, name)
	return tool
end

-- The player's weapon for a slot: their pick ("Loadout_<slot>" on the Player, set by Armory.choose), else the
-- kit's weapon (primary only; Config/Uniforms).
function Armory.loadout(player: Player, slot: string): string?
	local picked = player:GetAttribute(LOADOUT .. slot)
	if type(picked) == "string" and W[picked] and W[picked].slot == slot then
		return picked
	end
	local kit = U.Kits[U.Default] :: any
	return if slot == "Primary" then kit.weapon else nil
end

-- Makes the weapon the player's pick for its slot: given now (replacing the slot's weapon) and on every respawn.
function Armory.choose(player: Player, name: string)
	assert(W[name], "unknown weapon " .. name)
	player:SetAttribute(LOADOUT .. W[name].slot, name)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		Armory.give(player, name)
	end
end

-- Gives every slot of the loadout on each spawn.
function Armory.start()
	local function spawned(player: Player, character: Model)
		character:WaitForChild("Torso", 10)
		local slots: { [string]: boolean } = {}
		for _, w in W do
			slots[w.slot] = true
		end
		for slot in slots do
			local name = Armory.loadout(player, slot)
			if name then
				Armory.give(player, name)
			end
		end
	end
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			spawned(player, character)
		end)
		if player.Character then
			task.spawn(spawned, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return Armory
