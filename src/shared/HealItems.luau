--!strict
-- What a healer holds and how it moves through a heal (H1; Config/Healing.Held, Grab, Open, Unroll). Shared by the
-- server (src/server/Healing: the character's items, everyone sees them) and the first-person view (src/client/HealView:
-- client copies on the eye-fixed arms), so both go through the same steps at the same moments:
-- - both items: taken from the pack behind the back, in the right hand from Grab.take;
-- - the bandage: the unrolling bandage (bones Root -> Strip1..8, Config/Assets bandage_unroll); its strip pays out from
--   the roll toward the left hand as the wrap goes on (HealItems.strip, drawn on every client; bones don't replicate);
-- - the med pack (user 2026-10-19: "opening pack"): from Grab.time in the left hand; at Open.thread the red thread is
--   pulled off and drops; at Open.pad the white pad is in the right hand; at Open.drop the empty pack falls from the
--   left hand; the pad is what's pressed on.
-- Every piece is coloured from Config/Palette.Medical by name, never collides or takes hits, keeps its imported
-- rotation (the FBX pivot is rotated: never PivotTo) and is welded to its hand.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = script.Parent
local A = require(Shared.Config.Assets)
local Cfg = require(Shared.Config.Healing)
local Palette = require(Shared.Config.Palette)

local HealItems = {}

-- The library model of a Config/Assets entry (ReplicatedStorage.Assets, kept by the Library sync), or nil.
function HealItems.library(name: string): Model?
	local e = A.Entries[name]
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and f:FindFirstChild(e.category)
	for _, part in string.split(e.folder, "/") do
		f = f and f:FindFirstChild(part)
	end
	local m = f and f:FindFirstChild(name)
	if not m then
		warn(`[Healing] {name} is not in the asset library: run the Library sync`)
	end
	return m :: Model?
end

-- A copy of an entry on `part`, `scale` times its size (Model:ScaleTo: the unrolling bandage's bones scale too), its
-- Origin at the part's centre moved by `offset` (the part's axes). `ghost` marks client-only copies (the first-person
-- rig's collision group). Parented to `into`.
function HealItems.attach(
	entry: string,
	part: BasePart,
	offset: CFrame,
	name: string,
	scale: number?,
	into: Instance,
	ghost: boolean?
): Model?
	local src = HealItems.library(entry)
	if not src then
		return nil
	end
	local model = src:Clone()
	if scale and scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
	end
	local origin = model:FindFirstChild("Origin", true) :: BasePart?
	if not origin then
		warn(`[Healing] {entry}: no Origin marker`)
		return nil
	end
	local at = origin.Position
	origin:Destroy()
	for _, d in model:GetDescendants() do
		if d:IsA("AnimationController") then
			d:Destroy() -- (the skinned import's; nothing plays on it)
		end
	end
	model.Name = name
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CFrame = part.CFrame * offset * CFrame.new(p.Position - at) * p.CFrame.Rotation
			local c = Palette.Medical[p.Name]
			if c then
				p.Color = Color3.fromRGB(c[1], c[2], c[3])
			end
			if not c and not p:IsA("MeshPart") then
				p.Transparency = 1 -- the skinned import's RootPart
			end
			p.Material = Enum.Material.SmoothPlastic
			p.Anchored = false
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			p.CastShadow = false
			if ghost then
				p.CollisionGroup = "Viewmodel"
				p.LocalTransparencyModifier = 0
			end
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = part, p
			w.Parent = p
		end
	end
	model.Parent = into
	return model
end

-- A held piece let go: it falls (colliding with the ground only: the Debris group) and is gone after Open.fall.
function HealItems.drop(thing: Instance)
	local parts = {}
	if thing:IsA("BasePart") then
		table.insert(parts, thing)
	end
	for _, d in thing:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local first = parts[1]
	if not first then
		thing:Destroy()
		return
	end
	for _, p in parts do
		for _, w in p:GetChildren() do
			if w:IsA("WeldConstraint") then
				w:Destroy()
			end
		end
		p.Massless = false
		p.CanCollide = p == first
		p.CollisionGroup = "Debris"
		if p ~= first then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = first, p
			w.Parent = p
		end
	end
	thing.Parent = workspace
	if RunService:IsServer() then
		first:SetNetworkOwner(nil) -- the server drops it for everyone
	end
	Debris:AddItem(thing, Cfg.Open.fall)
end

-- One heal's items: what is out so far.
export type State = { held: Model?, pad: Model?, step: number }

function HealItems.new(): State
	return { held = nil, pad = nil, step = 0 }
end

local function grip(g: { number }): CFrame
	return CFrame.new(g[1], g[2], g[3])
end

-- Brings `state` up to `elapsed` seconds into a heal of `kind` with these arms (each step once, in order).
function HealItems.update(
	state: State,
	kind: string,
	elapsed: number,
	right: BasePart,
	left: BasePart,
	into: Instance,
	ghost: boolean?
)
	local H, O = Cfg.Held, Cfg.Open
	if state.step < 1 and elapsed >= Cfg.Grab.take then
		state.step = 1
		local g = H[kind]
		state.held = HealItems.attach(g.entry, right, grip(g.grip), "HealItem", g.scale, into, ghost)
	end
	if kind ~= "MedPack" then
		return
	end
	local t = elapsed - Cfg.Grab.time
	if state.step < 2 and t >= 0 then
		state.step = 2 -- into the left hand
		if state.held then
			state.held:Destroy()
		end
		local g = H.MedPack
		state.held = HealItems.attach(g.entry, left, grip(g.leftGrip), "HealItem", g.scale, into, ghost)
	end
	if state.step < 3 and t >= O.thread then
		state.step = 3
		local thread = state.held and state.held:FindFirstChild("Thread", true)
		if thread then
			if ghost then
				thread:Destroy()
			else
				HealItems.drop(thread)
			end
		end
	end
	if state.step < 4 and t >= O.pad then
		state.step = 4
		local g = H.Pad
		state.pad = HealItems.attach(g.entry, right, grip(g.grip), "HealPad", g.scale, into, ghost)
	end
	if state.step < 5 and t >= O.drop then
		state.step = 5
		if state.held then
			if ghost then
				state.held:Destroy()
			else
				HealItems.drop(state.held)
			end
			state.held = nil
		end
	end
end

function HealItems.clear(state: State)
	for _, m in { state.held, state.pad } do
		if m then
			m:Destroy()
		end
	end
	state.held, state.pad = nil, nil
end

-- The unrolling bandage's strip (client side, every frame): its free end reaches `length` studs from the roll toward
-- `pin` (HealItems.pin: the patient's limb being wrapped), the rest still on the roll. Bones are posed relative to
-- the part they hang under, from their pose at rest (captured on the first call).
-- (a plain table, cleared when the item goes: a weak-keyed one lost an item mid-heal and re-captured the rest from
-- the posed bones, Studio round 3; docs/KNOWN_TRAPS.md "Weak-keyed caches")
local rest: { [Instance]: { [string]: CFrame } } = {}

local function forget(item: Instance)
	item.AncestryChanged:Connect(function()
		if not item:IsDescendantOf(game) then
			rest[item] = nil
		end
	end)
end
local BONES = { "Strip1", "Strip2", "Strip3", "Strip4", "Strip5", "Strip6", "Strip7", "Strip8" }

function HealItems.strip(item: Model, pin: Vector3, length: number)
	local root = item:FindFirstChild("Root", true) :: Bone?
	local holder = root and root.Parent
	if not root or not holder or not holder:IsA("BasePart") then
		return
	end
	local frame = holder.CFrame
	local r = rest[item]
	if r and not r.Root then
		return -- (bones missing: warned once)
	end
	if not r then
		r = {}
		for _, name in { "Root", table.unpack(BONES) } do
			local b = item:FindFirstChild(name, true) :: Bone?
			if not b then
				warn(`[Healing] {item.Name}: no bone {name}, the strip can't unroll`)
				rest[item] = {}
				forget(item)
				return
			end
			r[name] = frame:ToObjectSpace(b.WorldCFrame)
		end
		rest[item] = r
		forget(item)
	end
	local s1, s2 = r.Strip1.Position, r.Strip2.Position
	local seg = (s2 - s1).Magnitude
	local restDir = (s2 - s1).Unit
	local to = frame:PointToObjectSpace(pin) - s1
	local dir = if to.Magnitude > 1e-3 then to.Unit else restDir
	local out = math.clamp(math.min(length, to.Magnitude), 0, seg * #BONES)
	-- the shortest turn from the strip's rest direction to the pin
	local axis = restDir:Cross(dir)
	local turn = CFrame.identity
	if axis.Magnitude > 1e-4 then
		turn = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(restDir:Dot(dir), -1, 1)))
	elseif restDir:Dot(dir) < 0 then
		-- straight back: half a turn about any axis across the strip
		local across = restDir:Cross(if math.abs(restDir.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis)
		turn = CFrame.fromAxisAngle(across.Unit, math.pi)
	end
	local parent = r.Root
	for i, name in BONES do
		-- this bone's place along the strip; the part beyond what's out is still on the roll
		local along = math.max(0, (i - 1) * seg - (seg * #BONES - out))
		local want = CFrame.new(s1 + dir * along) * turn * r[name].Rotation
		local b = item:FindFirstChild(name, true) :: Bone
		b.CFrame = parent:Inverse() * want
		b.Transform = CFrame.identity
		parent = want
	end
end

-- Where the strip goes (Studio round 2: the two hands are only ~0.5 apart, too close for a strip to show): the
-- patient's part getting the next wrap (Config/Healing.Wraps: left arm, right leg, head), else their torso.
function HealItems.pin(healer: Model): Vector3?
	local link = healer:FindFirstChild("HealPatient") :: ObjectValue?
	local patient = link and link.Value
	if not patient then
		return nil
	end
	local count = patient:GetAttribute("Wraps")
	local w = Cfg.Wraps[(if type(count) == "number" then count else 0) + 1]
	local part = (w and patient:FindFirstChild(w.part) or patient:FindFirstChild("Torso")) :: BasePart?
	return part and part.Position
end

-- How far the strip is out `elapsed` seconds into a bandage heal (Config/Healing.Unroll).
function HealItems.unrolled(elapsed: number): number
	local U = Cfg.Unroll
	return math.min(U.max, U.start + U.rate * math.max(0, elapsed - Cfg.Grab.time))
end

return HealItems
