--!strict
-- Species ears and tails (Config/Species; user 2026-10-18/20). At spawn a soldier of a species gets its ears on the
-- Head and its tail on the Torso, from the library models (Config/Assets `ears_<species>` / `tail_<species>`). Each
-- ear swings on a Motor6D at its root and each tail segment on one at its joint (the one before it, the first on the
-- Torso), so src/client/SpeciesMotion can move them locally; the rest of an ear (inner, tufts) is welded to it. The
-- fur round each ear's root ("Ruff") stays on the head and hides while a helmet is on (it pokes through the shell).
-- Colours by piece role (Rules/Species.color): the fur the hair colour, the elf ears the skin. Purely visual: no
-- collisions, never hit (CanQuery off), massless. The character's "Species" attribute says which ("human": none).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Assets)
local Cfg = require(Shared.Config.Species)
local Palette = require(Shared.Config.Palette)
local Rule = require(Shared.Rules.Species)

local Species = {}

type Kind = Cfg.Kind

-- characters whose ruff already follows the helmet
local watching: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

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
		warn(`[Species] {name} is not in the asset library: run the Library sync (src/dev/Library)`)
		return nil
	end
	return m :: Model
end

local function rgbOf(c: any, fallback: { number }): { number }
	if typeof(c) == "Color3" then
		return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
	end
	return fallback
end

local function vec(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
end

-- The library copy of `entry` with each piece's CFrame relative to the Origin marker (the body part's center),
-- coloured; nil when it is missing.
local function pieces(entry: string, character: Model): (Model?, { [string]: BasePart }, { [string]: CFrame })
	local src = library(entry)
	if not src then
		return nil, {}, {}
	end
	local model = src:Clone()
	local origin = model:FindFirstChild("Origin", true) :: BasePart?
	if not origin then
		warn(`[Species] {entry}: the model has no Origin marker`)
		return nil, {}, {}
	end
	local frame = CFrame.new(origin.Position) -- the body part's space: the Origin's position, the model's axes
	local hair = rgbOf(character:GetAttribute("HairColor"), Palette.Species.FallbackHair)
	local skin = rgbOf(character:GetAttribute("SkinColor"), Palette.Species.FallbackSkin)
	local byName: { [string]: BasePart } = {}
	local rel: { [string]: CFrame } = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= origin then
			local piece, role = Rule.split(p.Name)
			local c = Rule.color(role, hair, skin, Palette.Species)
			p.Color = Color3.fromRGB(c[1], c[2], c[3])
			p.Material = Enum.Material.SmoothPlastic
			p.Anchored = false
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			p.CastShadow = false
			byName[piece] = p
			rel[piece] = frame:ToObjectSpace(p.CFrame)
		end
	end
	origin:Destroy()
	return model, byName, rel
end

-- A Weld holding `p` at `offset` from `to` (Welds keep the offset written down: KNOWN_TRAPS).
local function weld(to: BasePart, p: BasePart, offset: CFrame)
	local w = Instance.new("Weld")
	w.Part0, w.Part1, w.C0 = to, p, offset
	w.Parent = p
end

-- A Motor6D named `name` turning `p` round `pivot` (a CFrame in the shared body-part space) on `parent`, whose own
-- place in that space is `parentRel`; `rel` is `p`'s.
local function motor(name: string, parent: BasePart, parentRel: CFrame, p: BasePart, rel: CFrame, pivot: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0, m.Part1 = parent, p
	m.C0 = parentRel:Inverse() * pivot
	m.C1 = rel:Inverse() * pivot
	m.Parent = p
end

local function ears(character: Model, head: BasePart, kind: Kind)
	local model, byName, rel = pieces(kind.ears, character)
	if not model then
		return
	end
	model.Name = "Ears"
	for piece, p in byName do
		local tag, shell, ruff = Rule.ear(piece)
		local pivot = tag and kind.earPivots[tag]
		if not tag or not pivot then
			weld(head, p, rel[piece])
		elseif shell then
			motor(tag, head, CFrame.identity, p, rel[piece], CFrame.new(vec(pivot)))
		elseif ruff then
			p:SetAttribute("Ruff", true)
			weld(head, p, rel[piece])
		else
			local ear = byName[tag]
			if ear then
				weld(ear, p, rel[tag]:Inverse() * rel[piece])
			else
				weld(head, p, rel[piece])
			end
		end
	end
	model.Parent = character
end

local function tail(character: Model, torso: BasePart, kind: Kind)
	local entry = kind.tail
	local pivots = kind.tailPivots
	if not entry or not pivots then
		return
	end
	local model, byName, rel = pieces(entry, character)
	if not model then
		return
	end
	model.Name = "Tail"
	local segs: { [number]: string } = {}
	for piece in byName do
		local n = Rule.segment(piece)
		if n then
			segs[n] = piece
		else
			weld(torso, byName[piece], rel[piece])
		end
	end
	local parent, parentRel = torso, CFrame.identity
	for n = 1, #pivots do
		local piece = segs[n]
		if not piece then
			warn(`[Species] {entry}: no Tail{n}`)
			break
		end
		local p = byName[piece]
		motor(`Tail{n}`, parent, parentRel, p, rel[piece], CFrame.new(vec(pivots[n])))
		parent, parentRel = p, rel[piece]
	end
	model.Parent = character
end

-- The ruff round each ear's root shows only bareheaded (it pokes through a helmet's shell).
local function showRuff(character: Model)
	local helmeted = character:GetAttribute("HelmetOn") == true
	local worn = character:FindFirstChild("Ears")
	if not worn then
		return
	end
	for _, p in worn:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("Ruff") then
			p.Transparency = if helmeted then 1 else 0
		end
	end
end

-- Spawn: the species of uniform `kit` (or the player's "Species" attribute) on the character, after its helmet
-- (src/server/Helmets sets "HelmetOn") and its looks ("HairColor", "SkinColor": src/server/Bodies).
function Species.dress(character: Model, kit: string)
	for _, name in { "Ears", "Tail" } do
		local old = character:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local player = Players:GetPlayerFromCharacter(character)
	local name = Rule.of(kit, player and player:GetAttribute("Species"), Cfg)
	character:SetAttribute("Species", name or "human")
	local kind = name and Cfg.Kinds[name]
	local head = character:FindFirstChild("Head") :: BasePart?
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if not kind or not head or not torso then
		return
	end
	ears(character, head, kind)
	tail(character, torso, kind)
	showRuff(character)
	if not watching[character] then
		watching[character] = true
		character:GetAttributeChangedSignal("HelmetOn"):Connect(function()
			showRuff(character)
		end)
	end
end

return Species
