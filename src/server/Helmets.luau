--!strict
-- Helmets and hair (docs/HATS.md "Always a head piece; helmets can be shot off", docs/HAIRS.md; user 2026-10-14).
-- Every soldier spawns with its kit's helmet (Config/Uniforms Kits `headwear`) over the helmet-on version of its
-- rolled hairstyle (Config/Assets `hair_<style>_<shell>`). A shot in the top half of the head's hitbox (Rules/Looks
-- onHelmet; src/server/Firing) knocks the helmet off: the helmet-on hair is swapped for the original and a loose copy of
-- the helmet flies off along the shot and despawns (Config/Uniforms HelmetOff).
-- Helmet and hair are welded to the Head and never take hits themselves (CanQuery off): the hit zones are the Head
-- part's own box, plus the worn helmet's shape where it stands out of it (Helmets.crown: the crown and the brim; user
-- 2026-10-22). The character's "HelmetOn" attribute says whether the helmet is still on.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Assets)
local HairCfg = require(Shared.Config.HairMotion)
local HairSway = require(Shared.Rules.HairMotion)
local U = require(Shared.Config.Uniforms)
local Looks = require(Shared.Rules.Looks)

local Helmets = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The library model of a Config/Assets entry (ReplicatedStorage.Assets.<category>.<folder>.<name>, kept by
-- src/dev/Library sync), or nil with a warning.
local function library(name: string): Model?
	local e = A.Entries[name]
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and f:FindFirstChild(e.category)
	for _, part in string.split(e.folder, "/") do
		f = f and f:FindFirstChild(part)
	end
	local m = f and f:FindFirstChild(name)
	if not m then
		warn(`[Helmets] {name} is not in the asset library: run the Library sync (CLAUDE.md)`)
		return nil
	end
	return m :: Model
end

-- A worn copy: every part unanchored, welded to the head, weightless, no collisions, no hits.
local function wear(model: Model, head: BasePart, name: string): Model
	model.Name = name
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			p.CastShadow = false
			p.Material = Enum.Material.SmoothPlastic
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = head, p
			w.Parent = p
		end
	end
	return model
end

-- The hair entry's mesh in its color at its place on the head, or nil (bald, or not in the library).
local function hair(character: Model, head: BasePart, shell: string?): Model?
	local style = character:GetAttribute("HairStyle")
	local entry = type(style) == "string" and Looks.hairEntry(style, shell)
	local src = entry and library(entry)
	if not entry or not src then
		return nil
	end
	local model = src:Clone()
	local color = character:GetAttribute("HairColor")
	-- a rigged hair (tools/hair/rig_hair.py) carries an Origin marker at the head's centre: every part keeps its place
	-- relative to it, so its bones stay where the rig put them; an older hair sits by its bounding-box `center`
	local origin: BasePart? = nil
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "Origin" then
			origin = p
		end
	end
	local frame = origin and CFrame.new(origin.Position)
	local fit = A.Entries[entry].hair :: any
	local c = fit and fit.center or { 0, 0, 0 }
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CFrame = if frame
				then head.CFrame * frame:ToObjectSpace(p.CFrame)
				else head.CFrame * CFrame.new(c[1], c[2], c[3]) * p.CFrame.Rotation
			if p.Name == "Origin" or p.Name == "RootPart" then
				p.Transparency = 1
			elseif typeof(color) == "Color3" then
				p.Color = color
			end
		elseif p:IsA("JointInstance") then
			p:Destroy() -- the importer's joints: wear() welds every part to the head instead
		end
	end
	local bones = 0
	for _, b in model:GetDescendants() do
		if b:IsA("Bone") and HairSway.bone(b.Name) then
			bones += 1
		end
	end
	if bones > 0 then
		-- moved on every client by src/client/HairMotion, which waits until all `Bones` have replicated
		model:SetAttribute("Bones", bones)
		CollectionService:AddTag(model, HairCfg.Tag)
	end
	return wear(model, head, "Hair")
end

-- The helmet's library copy in its fit colors, at its brim height on the head (as src/dev/HairPreview.helmet).
local function helmet(entry: string, head: BasePart): Model?
	local src = library(entry)
	if not src then
		return nil
	end
	local fit = A.Entries[entry].fit :: any
	local model = src:Clone()
	local shell: BasePart? = nil
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			if string.find(string.lower(p.Name), "^helmet") then
				shell = p
				p.Color = rgb(fit.color)
			elseif fit.parts and fit.parts[p.Name] then
				p.Color = rgb(fit.parts[p.Name])
			end
		end
	end
	if not shell then
		warn(`[Helmets] {entry}: no helmet shell part`)
		return nil
	end
	local c = fit.center or { 0, 0, 0 }
	local want = head.CFrame * CFrame.new(c[1], fit.brim + c[2], c[3]) * shell.CFrame.Rotation
	model:PivotTo(want * shell.CFrame:Inverse() * model:GetPivot())
	return wear(model, head, "Helmet")
end

-- The shell whose helmet-on hairs fit a soldier with no helmet on (the head wrap, Config/Healing.Wraps): the one they
-- last wore ("HairShell", set by dress), else the default kit's.
local function shortShell(character: Model): string?
	local shell = character:GetAttribute("HairShell")
	if type(shell) == "string" then
		return shell
	end
	local kit = U.Kits[U.Default]
	local headwear = kit and kit.headwear
	local fit = headwear and A.Entries[headwear] and A.Entries[headwear].fit
	return if fit then (fit :: any).shell else nil
end

local function clear(character: Model)
	for _, name in { "Helmet", "Hair" } do
		local old = character:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

-- Spawn: the kit's helmet (if any) over the helmet-on hair, or the original hair bareheaded. Reads the character's
-- "HairStyle" and "HairColor" attributes (src/server/Bodies rolls them).
function Helmets.dress(character: Model, headwear: string?)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	clear(character)
	local on = headwear and helmet(headwear, head)
	local shell = if on and headwear then (A.Entries[headwear].fit :: any).shell else nil
	if shell then
		character:SetAttribute("HairShell", shell)
	end
	-- the head wrap on (src/server/Healing): the helmet-on hair even bareheaded
	local h = hair(
		character,
		head,
		shell or (if character:GetAttribute("HeadWrap") == true then shortShell(character) else nil)
	)
	if h then
		h.Parent = character
	end
	if on then
		on:SetAttribute("Entry", headwear)
		-- its box in the head's space, for shots that pass over or beside the head (Helmets.crown)
		local box, size = on:GetBoundingBox()
		on:SetAttribute("HitBox", head.CFrame:ToObjectSpace(box))
		on:SetAttribute("HitSize", size)
		on.Parent = character
	end
	character:SetAttribute("HelmetOn", on ~= nil)
end

-- A shot along `line` (unit) from `origin` that meets a worn helmet's shape (Rules/Looks.crownAt) within `reach` studs,
-- among `soldiers` (not `shooter`): the nearest, as its character, Head, the point and its distance; or nil.
function Helmets.crown(
	soldiers: { Model },
	origin: Vector3,
	line: Vector3,
	reach: number,
	shooter: Model
): (Model?, BasePart?, Vector3?, number?)
	local best: number? = nil
	local who: Model?, at: BasePart? = nil, nil
	for _, character in soldiers do
		if character == shooter or character:GetAttribute("HelmetOn") ~= true then
			continue
		end
		local head = character:FindFirstChild("Head") :: BasePart?
		local worn = character:FindFirstChild("Helmet")
		local rel, size = worn and worn:GetAttribute("HitBox"), worn and worn:GetAttribute("HitSize")
		if not head or typeof(rel) ~= "CFrame" or typeof(size) ~= "Vector3" then
			continue
		end
		local box = head.CFrame * rel
		local t = Looks.crownAt(box:PointToObjectSpace(origin), box:VectorToObjectSpace(line), size / 2)
		if t and t <= reach and (not best or t < best) then
			best, who, at = t, character, head
		end
	end
	if not best then
		return nil, nil, nil, nil
	end
	return who, at, origin + line * best, best
end

-- The head wrap went on (src/server/Healing): bareheaded, the hair becomes its helmet-on version so the wrap shows and
-- nothing pokes through (user 2026-10-18); under a helmet it already is.
function Helmets.shortHair(character: Model)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head or character:GetAttribute("HelmetOn") == true then
		return
	end
	local old = character:FindFirstChild("Hair")
	if old then
		old:Destroy()
	end
	local h = hair(character, head, shortShell(character))
	if h then
		h.Parent = character
	end
end

-- A shot hit `part` at `point` going along `direction`: if it is a soldier's Head with the helmet on and the point is
-- in the helmet's half, the helmet comes off. True when it did.
function Helmets.hit(part: Instance?, point: Vector3, direction: Vector3): boolean
	if not part or part.Name ~= "Head" or not part:IsA("BasePart") then
		return false
	end
	local character = part.Parent
	if not character or not character:IsA("Model") or character:GetAttribute("HelmetOn") ~= true then
		return false
	end
	local p = part.CFrame:PointToObjectSpace(point)
	if not Looks.onHelmet({ X = p.X, Y = p.Y, Z = p.Z }) then
		return false
	end
	Helmets.knockOff(character, direction)
	return true
end

-- The helmet flies off along `direction` and the original hair goes on.
function Helmets.knockOff(character: Model, direction: Vector3)
	local head = character:FindFirstChild("Head") :: BasePart?
	local worn = character:FindFirstChild("Helmet") :: Model?
	if not head or not worn then
		return
	end
	character:SetAttribute("HelmetOn", false)
	-- the loose helmet: the worn copy, unwelded from the head, its parts welded to the shell, thrown
	local loose = worn:Clone()
	worn:Destroy()
	local old = character:FindFirstChild("Hair")
	if old then
		old:Destroy()
	end
	local h = hair(character, head, if character:GetAttribute("HeadWrap") == true then shortShell(character) else nil)
	if h then
		h.Parent = character
	end
	loose.Name = "LooseHelmet"
	local parts = {}
	for _, d in loose:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local root = parts[1]
	if not root then
		return
	end
	for _, p in parts do
		p.Massless = false
		p.CanCollide = p == root
		p.CanQuery = false
		p.CollisionGroup = "Debris"
		if p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = root, p
			w.Parent = p
		end
	end
	loose.Parent = workspace
	local O = U.HelmetOff
	local flat = Vector3.new(direction.X, 0, direction.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
	root:SetNetworkOwner(nil)
	root.AssemblyLinearVelocity = flat * O.speed + Vector3.new(0, O.up, 0)
	root.AssemblyAngularVelocity = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
		* O.spin
	Debris:AddItem(loose, O.despawn)
end

return Helmets
