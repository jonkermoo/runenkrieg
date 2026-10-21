--!strict
-- Weapons in play (.claude/skills/roblox-weapons/SKILL.md, Config/Weapons). Builds a rigged weapon from its
-- library model (ReplicatedStorage.Assets.Weapons...): the export's Origin marker becomes the invisible "Gun" part at
-- the gun origin, static parts are welded to it, moving parts get Motor6Ds at their pivots, and the Muzzle / Aim /
-- Eject attachments sit on it (all looking down gun -Z, so sight and fire stay parallel). The whole weapon is
-- scaled by its Config `scale` (per gun axis) about the origin (gun-space numbers in Config are the modelled ones).
-- The parts are axis-aligned with gun space, so scaling their Size per axis can't shear them.
-- In the hands the Gun part is joined to the Torso by a Motor6D (no Tool grip): the hold animations
-- (tools/animation/rifle.luau, "Gun" pose) place the gun and point both arms at it.
-- Armory.give(player, name) hands it over as a Tool into its slot (one weapon per slot: a new primary replaces the
-- old); on each spawn the player's loadout is given (their pick via Armory.choose, else the kit's weapon). While
-- the Tool isn't equipped, a copy rides on the body where Config/Weapons `stow` puts it (slung on the back); it
-- hides while the weapon is in the hands. Both live on the server, so every player sees them. Put away with its
-- unequip animation (the client says so: Net "Stow"), a copy stays in the hands as "Stowing" (joined to the Torso
-- by its own "Hold" motor, which the animation moves) for Config/Locomotion.Stow.time before the slung copy shows.
-- No motion here: the moving parts only have their Motor6Ds; animation is a later, separate step.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Assets)
local G = require(Shared.Config.Grenades)
local L = require(Shared.Config.Locomotion)
local U = require(Shared.Config.Uniforms)
local W = require(Shared.Config.Weapons)
local Net = require(Shared.Net)
local Kits = require(script.Parent.Kits)

local Armory = {}

-- when each player last said they're putting their weapon away (Net "Stow")
local stowNote: { [Player]: number } = {}

local LOADOUT = "Loadout_" -- Player attribute per slot: the weapon the player spawns with

local function v3(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
end

local function libraryModel(name: string): Model
	local w = W[name]
	assert(w, "unknown weapon " .. name)
	local e = A.Entries[w.asset]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local f: Instance? = assets and assets:FindFirstChild(e.category)
	for _, sub in string.split(e.folder, "/") do -- "Olive/Rifles": weapons sit by team
		f = f and f:FindFirstChild(sub)
	end
	local m = f and f:FindFirstChild(w.asset)
	assert(m, `weapon model {w.asset} is not in ReplicatedStorage.Assets (run the Library sync in the dev place)`)
	return m :: Model
end

-- A rigged copy of the weapon as a Model (PrimaryPart = the Gun part at the gun origin). `kit`: whose colors
-- (Config/Weapons `kits`, a team's tint over `parts`; default: Config/Uniforms.Default).
function Armory.build(name: string, kit: string?): Model
	local w = W[name]
	local tint = w.kits and w.kits[kit or U.Default] or {}
	local model = libraryModel(name):Clone()
	model.Name = name
	local origin = model:FindFirstChild("Origin", true) :: BasePart
	assert(origin, name .. ": the model has no Origin marker")
	local frame = CFrame.new(origin.Position) -- gun space: origin position, the model's axes
	local s = v3(w.scale) -- per gun axis
	origin.Name = "Gun"
	origin:SetAttribute("Weapon", name) -- (src/client/GunFx: the weapon's own sounds, on every copy)
	origin.Transparency = 1
	origin.Size = Vector3.new(0.2, 0.2, 0.2)
	origin.CFrame = frame
	origin.PivotOffset = CFrame.new() -- the FBX import leaves a rotated pivot on the marker (KNOWN_TRAPS)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= origin then
			local rel = frame:ToObjectSpace(p.CFrame)
			p.Size *= s
			p.CFrame = frame * (rel.Rotation + rel.Position * s)
			local c = tint[p.Name] or w.parts[p.Name]
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

-- A grenade Tool's name: the hotbar shows how many are left.
function Armory.label(name: string, count: number): string
	return `{W[name].display} x{count}`
end

-- The "Hold" motor's C1: the item `held` away from the hold's Gun point (Config/Weapons; identity for most).
function Armory.heldOffset(name: string): CFrame
	local h = W[name].held
	return if h then CFrame.new(-h[1], -h[2], -h[3]) else CFrame.identity
end

-- The weapon as a Tool. No Handle, so Roblox adds no grip weld: the "Hold" Motor6D joins the Gun part to the
-- Torso while equipped (Part0 set by Armory.give, and by the owner's client at once, src/client/Locomotion). With
-- C0 = C1 = identity, the hold animation's "Gun" pose is the gun origin in the torso's space. `kit`: whose colors.
function Armory.tool(name: string, kit: string?): Tool
	local w = W[name]
	local model = Armory.build(name, kit)
	local tool = Instance.new("Tool")
	tool.Name = w.display
	tool.CanBeDropped = false
	tool.RequiresHandle = false
	local hold = Instance.new("Motor6D")
	hold.Name = "Hold"
	hold.C1 = Armory.heldOffset(name)
	hold.Part1 = model.PrimaryPart
	hold.Parent = model.PrimaryPart
	for _, c in model:GetChildren() do
		c.Parent = tool
	end
	model:Destroy()
	tool:SetAttribute("Weapon", name)
	if w.class == "Grenade" then
		tool:SetAttribute("Count", G.Carried) -- how many are left (src/server/Grenades)
		tool.Name = Armory.label(name, G.Carried)
	end
	return tool
end

-- The weapon's stowed copy on the character (not parented: Armory.give shows it while the Tool is put away); nil for
-- an item that shows nothing on the body (no `stow`: the grenades).
function Armory.stowed(character: Model, name: string): Model?
	local s = W[name].stow
	if not s then
		return nil
	end
	local part = character:FindFirstChild(s.part) :: BasePart?
	if not part then
		return nil
	end
	local kit = Kits.of(character)
	local model = Armory.build(name, kit)
	model.Name = "Stowed_" .. name
	-- over the worn pack (src/server/Packs; the kit's until it is on): further back by the pack's `sling`, unless
	-- strapped beside it (`beside`)
	local worn = character:FindFirstChild("Pack")
	local pack = worn and worn:GetAttribute("Entry") or (U.Kits[kit] :: any).pack
	local entry = type(pack) == "string" and A.Entries[pack]
	local at = v3(s.at) + Vector3.new(0, 0, if entry and not s.beside then entry.sling or 0 else 0)
	local muzzle, side = v3(s.muzzle).Unit, v3(s.side).Unit
	-- gun axes in the part's space: +X = side, -Z = muzzle, +Y completes the frame
	local z = -muzzle
	local weld = Instance.new("Weld")
	weld.Name = "Stow"
	weld.Part0 = part
	weld.Part1 = model.PrimaryPart
	weld.C0 = CFrame.fromMatrix(at, side, z:Cross(side), z)
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
	local tool = Armory.tool(name, character and Kits.of(character))
	tool.Parent = backpack

	local stowed = character and Armory.stowed(character, name)
	local hold = tool:FindFirstChild("Hold", true) :: Motor6D
	if character and not stowed then
		-- nothing on the body: only the hold motor follows the hands
		local function update()
			hold.Part0 = if tool.Parent == character then character:FindFirstChild("Torso") :: BasePart? else nil
		end
		tool:GetPropertyChangedSignal("Parent"):Connect(update)
		update()
	elseif character and stowed then
		local gone = false -- the tool is being destroyed: its stowed copy goes with it, never back on the body
		local wasHeld = false
		local stowing: Model? = nil -- the copy in the hands while it's being put away
		local token = 0 -- each change of hands; a put-away still under way checks it's still the latest
		local function clearStowing()
			if stowing then
				stowing:Destroy()
				stowing = nil
			end
		end
		-- put away: a copy in the hands for the unequip animation, the slung copy once it's over
		local function putAway(t: number)
			local torso = character:FindFirstChild("Torso") :: BasePart?
			if torso then
				local copy = Armory.build(name, Kits.of(character))
				copy.Name = "Stowing"
				local motor = Instance.new("Motor6D")
				motor.Name = "Hold"
				motor.Part0 = torso
				motor.Part1 = copy.PrimaryPart
				motor.Parent = copy.PrimaryPart
				copy.Parent = character
				stowing = copy
			end
			task.delay(L.Stow.time, function()
				if t == token and not gone then
					clearStowing()
					stowed.Parent = character
				end
			end)
		end
		local function update()
			if gone then
				return
			end
			local held = tool.Parent == character
			hold.Part0 = if held then character:FindFirstChild("Torso") :: BasePart? else nil
			token += 1
			clearStowing()
			if held then
				stowed.Parent = nil
			elseif wasHeld then
				-- just put away: with its animation if the client says so (the word may come a little before or after the
				-- Tool moves), else (a ragdoll knock) straight onto the back
				stowed.Parent = nil
				local t, t0 = token, os.clock()
				task.spawn(function()
					while t == token and not gone do
						if (stowNote[player] or -math.huge) >= t0 - L.Stow.wait then
							putAway(t)
							return
						end
						if os.clock() - t0 >= L.Stow.wait then
							stowed.Parent = character
							return
						end
						task.wait()
					end
				end)
			else
				stowed.Parent = character
			end
			wasHeld = held
		end
		tool:GetPropertyChangedSignal("Parent"):Connect(update)
		tool.Destroying:Connect(function()
			gone = true
			clearStowing()
			stowed:Destroy()
		end)
		update()
	end
	player:SetAttribute(LOADOUT .. slot, name)
	return tool
end

-- The player's weapon for a slot: their pick ("Loadout_<slot>" on the Player, set by Armory.choose), else the
-- weapon (the primary), grenade or shovel of their kit this life (src/server/Kits, Config/Uniforms; every soldier
-- carries a shovel, user 2026-10-20).
function Armory.loadout(player: Player, slot: string): string?
	local picked = player:GetAttribute(LOADOUT .. slot)
	if type(picked) == "string" and W[picked] and W[picked].slot == slot then
		return picked
	end
	local character = player.Character
	local kit = U.Kits[if character then Kits.of(character) else U.Default] :: any
	return if slot == "Primary"
		then kit.weapon
		elseif slot == "Grenade" then kit.grenade
		elseif slot == "Shovel" then kit.shovel
		else nil
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
		local seen: { [string]: boolean } = {}
		local slots: { string } = {}
		for _, w in W do
			if not seen[w.slot] then
				seen[w.slot] = true
				table.insert(slots, w.slot)
			end
		end
		-- the hotbar numbers follow the order given: the primary always on 1 (Shift+W+2 ghosts on some keyboards, so
		-- a sprinting draw on 2 never arrives), the rest after it by name
		table.sort(slots, function(a, b)
			if (a == "Primary") ~= (b == "Primary") then
				return a == "Primary"
			end
			return a < b
		end)
		for _, slot in slots do
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
	Net.event("Stow").OnServerEvent:Connect(function(player: Player)
		stowNote[player] = os.clock()
	end)
	Players.PlayerRemoving:Connect(function(player)
		stowNote[player] = nil
	end)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return Armory
