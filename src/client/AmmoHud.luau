--!strict
-- The gun's ammo display, quartermaster's brass (Config/Hud.Gun; layout src/shared/ui/CombatHud.json "Gun"; user
-- 2026-10-26: "show the chamber, the shell empty if fired, an animation of the chamber / bolt moving and have the
-- magazine box be the actual magazine (semi transparent showing ammo and show ammo going up). same for the shotgun,
-- show the tube, then the chamber"). A brass panel, bottom right, with a cut-away of the held weapon drawn live in a
-- ViewportFrame, seen from its right side. Only the ammo is a real model (user 2026-10-26: "make it much simpler ...
-- only the ammo has to use real models"); the magazine and the chamber are flat brass-edged shapes:
-- - the magazine's rounds one by one (the shared round, Config/Assets ammo_rifle) stacked as the gun's own merged
--   rounds sit, rising a round each time one is fed; rounds pushed down out of a clip settle in from the top; a pump
--   gun's shells (copies of its own) end to end in the tube, stepping back toward the receiver; the magazine moves
--   as the gun's rounds do (an en-bloc clip coming in, a box swapped), and an empty en-bloc clip drops out;
-- - the chamber: the live round, or the fired case; as the gun's bolt (src/client/GunFx moves it) comes back the case
--   rides back with it and is thrown out, and closing pushes the next round up out of the magazine into the chamber;
-- - the count (magazine + chamber), and a red plate saying what to do next; the box in the team's colours.
-- src/client/Firing feeds it the predicted state every frame (AmmoHud.show).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudCfg = require(Shared.Config.Hud)
local GunOutlines = require(Shared.Config.GunOutlines)
local W = require(Shared.Config.Weapons)
local F = require(Shared.Rules.Firing)
local HudKit = require(script.Parent.HudKit)
local Settings = require(script.Parent.Settings)

local AmmoHud = {}

local G = HudCfg.Gun

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function anchored(p: BasePart)
	p:ClearAllChildren()
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.LocalTransparencyModifier = 0
end

-- a moving part's place at rest in gun space (its Motor6D's rest, src/server/Armory), else where it is now
local function restRel(gun: BasePart, part: BasePart): CFrame
	for _, m in gun:GetChildren() do
		if m:IsA("Motor6D") and m.Part1 == part then
			local rest = m:GetAttribute("RestC0")
			return (if typeof(rest) == "CFrame" then rest else m.C0) * m.C1:Inverse()
		end
	end
	return gun.CFrame:ToObjectSpace(part.CFrame)
end

-- a gun-space box (centre, size) grown to take in another
type Box = { lo: Vector3, hi: Vector3 }
local function grow(b: Box?, cf: CFrame, size: Vector3): Box
	local h = size / 2
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	if b then
		lo, hi = b.lo, b.hi
	end
	for _, s in { Vector3.new(-1, -1, -1), Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, -1) } do
		for _, t in { Vector3.new(1, 1, 1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1) } do
			local p = cf:PointToWorldSpace(h * s * t)
			lo, hi = lo:Min(p), hi:Max(p)
		end
	end
	return { lo = lo, hi = hi }
end

-- One loaded round or shell for the cut-away: parts placed about the head (the case head at the origin, pointing -Z).
type Piece = { parts: { { part: BasePart, rel: CFrame } }, model: Model }

local function place(p: Piece, cf: CFrame, transparency: number?)
	for _, q in p.parts do
		q.part.CFrame = cf * q.rel
		q.part.Transparency = transparency or 0
	end
end

local function hide(p: Piece)
	for _, q in p.parts do
		q.part.Transparency = 1
	end
end

type Fly = { piece: Piece, from: CFrame, start: number, time: number, kind: string, size: number }

type View = {
	tool: Tool,
	weapon: string,
	gun: BasePart,
	view: ViewportFrame,
	camera: Camera,
	cut: Model,
	dia: number, -- a round's width (studs)
	boltParts: { { part: BasePart, rel: CFrame } }, -- the drawn bolt, about its face
	handle: { stem: BasePart, knob: BasePart, at: CFrame }?,
	boltTurn: number, -- radians the gun's bolt turns its handle up
	boltRestCF: CFrame,
	follower: BasePart,
	mag: { BasePart }, -- the magazine's flat shapes (face, brass edge), as they sit with the gun's rounds at rest
	magAt: { CFrame },
	conns: { RBXScriptConnection },
	-- the magazine: rounds (or shells) one by one
	rounds: { Piece },
	slot: (k: number, count: number, i: number) -> CFrame, -- gun space: the round `i` of `count` at slot k (1: top)
	follow: BasePart?, -- the stack moves with this part (the gun's merged rounds) from its rest
	followRest: CFrame,
	tube: boolean,
	shown: number, -- the count drawn
	lift: number, -- slots the stack is still to rise (+) or settle (-)
	-- the chamber
	chamber: CFrame, -- gun space: the round's head there, closed
	live: Piece,
	case: Piece,
	feed: Piece,
	bolt: BasePart?,
	boltRest: number, -- its z at rest
	travel: number,
	wasOpen: boolean,
	carry: string?, -- what the opening bolt pulls back ("case" / "round")
	maxD: number,
	fed: boolean, -- closing: the next round has left the magazine
	pending: boolean, -- a round still in the magazine for this cycle (the state has already chambered it)
	atRest: string?, -- what the chamber showed closed
	flying: { Fly },
	clipWas: boolean,
	frozen: number?, -- a clip's rounds being pushed down: the stack as it was until they're in
	length: number, -- a round's length (studs)
	last: number, -- the last frame's clock
}

local panel: HudKit.Panel? = nil
local current: View? = nil

local function roundTemplate(): Model?
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, name in HudCfg.Round do
		f = f and f:FindFirstChild(name)
	end
	return if f and f:IsA("Model") then f else nil
end

-- copies of parts as a piece about `origin` (a CFrame in the source's space), into `cut`
local function piece(
	cut: Model,
	sources: { BasePart },
	origin: CFrame,
	scale: Vector3?,
	colors: { [string]: Color3 }?
): Piece
	local m = Instance.new("Model")
	m.Name = "Piece"
	local parts = {}
	for _, s in sources do
		local c = s:Clone()
		anchored(c)
		local rel = origin:ToObjectSpace(s.CFrame)
		if scale then
			c.Size = s.Size * scale
			rel = CFrame.new(rel.Position * scale) * rel.Rotation
		end
		if colors and colors[s.Name] then
			c.Color = colors[s.Name]
		end
		c.Transparency = 1
		c.Parent = m
		table.insert(parts, { part = c, rel = rel })
	end
	m.Parent = cut
	return { parts = parts, model = m }
end

local function destroy(v: View)
	for _, c in v.conns do
		c:Disconnect()
	end
	v.cut:Destroy()
end

local function build(tool: Tool, weapon: string, gun: BasePart, view: ViewportFrame): View
	local w = W[weapon]
	local s = w.scale
	local scale = Vector3.new(s[1], s[2], s[3])
	local own = G.weapons[weapon] :: any
	local cut = Instance.new("Model")
	cut.Name = "Cutaway"
	local camera = view:FindFirstChildOfClass("Camera") or Instance.new("Camera")
	camera.Parent = view
	view.CurrentCamera = camera

	local v: View = {
		tool = tool,
		weapon = weapon,
		gun = gun,
		view = view,
		camera = camera,
		cut = cut,
		dia = 0,
		boltParts = {},
		handle = nil,
		boltTurn = 0,
		boltRestCF = CFrame.identity,
		follower = nil :: any,
		mag = {},
		magAt = {},
		conns = {},
		rounds = {},
		slot = function()
			return CFrame.identity
		end,
		follow = nil,
		followRest = CFrame.identity,
		tube = w.ammo.clip == "Loose",
		shown = 0,
		lift = 0,
		chamber = CFrame.identity,
		live = { parts = {}, model = cut },
		case = { parts = {}, model = cut },
		feed = { parts = {}, model = cut },
		bolt = nil,
		boltRest = 0,
		travel = w.action.travel * s[3],
		wasOpen = false,
		carry = nil,
		maxD = 0,
		fed = true,
		pending = false,
		atRest = nil,
		flying = {},
		clipWas = false,
		frozen = nil,
		length = G.fallback.length,
		last = os.clock(),
	}

	local function part(name: string): BasePart?
		local p = tool:FindFirstChild(name)
		return if p and p:IsA("BasePart") then p else nil
	end
	local box: Box? = nil
	local bolt = part("Bolt")
	if bolt then
		v.bolt = bolt
		local r = restRel(gun, bolt)
		v.boltRest = r.Z
	end

	-- the round (and the spent case) the cut-away shows
	local colors: { [string]: Color3 } = {}
	local parts = w.parts :: any
	local liveSources: { BasePart } = {}
	local liveOrigin = CFrame.identity
	local caseSources: { BasePart } = {}
	local caseOrigin = CFrame.identity
	local pieceScale: Vector3? = nil
	local carrier = CFrame.identity -- a pump gun's shell on the carrier at rest (its head, gun space)
	if v.tube then
		-- a pump gun: copies of its own shell (the one on the carrier), head at its pivot
		for _, name in w.feed and w.feed.parts or {} do
			local p = part(name)
			if p then
				table.insert(liveSources, p)
			end
		end
		local first = liveSources[1]
		if first then
			-- its head (the pivot, gun space at rest), carried along with the shell wherever it is now
			local pivot = (w.moving :: any)[first.Name]
			carrier = CFrame.new(pivot[1] * s[1], pivot[2] * s[2], pivot[3] * s[3])
			liveOrigin = first.CFrame * restRel(gun, first):Inverse() * carrier
			v.length = first.Size.Z
		end
		caseSources, caseOrigin = liveSources, liveOrigin
	else
		local t = roundTemplate()
		local origin = t and t:FindFirstChild("Origin")
		local case, bullet = t and t:FindFirstChild("Case"), t and t:FindFirstChild("Bullet")
		local casing = t and t:FindFirstChild("Casing")
		if t and origin and case and bullet and casing then
			local o = (origin :: BasePart).CFrame
			liveSources = { case :: BasePart, bullet :: BasePart }
			liveOrigin = o
			caseSources = { casing :: BasePart }
			caseOrigin = o * CFrame.new((casing :: BasePart).Position.X - o.Position.X, 0, 0)
			pieceScale = scale
			colors.Case = rgb(parts.Rounds or { 196, 160, 84 })
			colors.Bullet = rgb(parts.Bullets or { 184, 115, 72 })
			colors.Casing = rgb(parts.Casing or parts.Rounds or { 196, 160, 84 })
			v.length = ((case :: BasePart).Size.Z + (bullet :: BasePart).Size.Z) * s[3]
		else
			-- not in the library yet: the gun's own spent case stands in
			local c = part("Casing")
			if c then
				liveSources, caseSources = { c }, { c }
				liveOrigin = c.CFrame * CFrame.new(0, 0, c.Size.Z / 2)
				caseOrigin = liveOrigin
				v.length = c.Size.Z
			end
		end
	end
	local function newLive(): Piece
		return piece(cut, liveSources, liveOrigin, pieceScale, colors)
	end
	v.live, v.feed = newLive(), newLive()
	v.case = piece(cut, caseSources, caseOrigin, pieceScale, colors)
	if v.tube then
		for _, q in v.case.parts do
			q.part.Color = q.part.Color:Lerp(Color3.new(), G.spentShade)
		end
	end

	-- the chamber: the round's head at the bolt face closed, where the gun's own case template sits (a weapon's own
	-- `chamber`, gun space, else that template's head, else the bolt's face on the bore's line)
	local template = part("Casing")
	if own and own.chamber then
		local c = own.chamber
		v.chamber = CFrame.new(c[1] * s[1], c[2] * s[2], c[3] * s[3])
	elseif template then
		local r = restRel(gun, template)
		v.chamber = CFrame.new(r.X, r.Y, r.Z + template.Size.Z / 2)
	else
		local bore = part("Bore")
		local y = if bore then restRel(gun, bore).Y else 0
		local face = if bolt then v.boltRest - bolt.Size.Z / 2 else 0
		v.chamber = CFrame.new(0, y, face)
	end

	-- the magazine's slots
	local cap = w.ammo.capacity
	local magBox, magSize = CFrame.identity, Vector3.zero
	for _ = 1, cap do
		table.insert(v.rounds, newLive())
	end
	if v.tube then
		local t = own and own.tube
		local first = if t
			then CFrame.new(t[1] * s[1], t[2] * s[2], t[3] * s[3])
			else carrier * CFrame.new(0, 0, -v.length)
		local step = v.length * G.tubeStep
		v.slot = function(k: number)
			return first * CFrame.new(0, 0, -(k - 1) * step)
		end
		magBox = first * CFrame.new(0, 0, -(cap * step - v.length) / 2 - v.length / 2)
		magSize = Vector3.new(v.length / 4, v.length / 4, cap * step)
		box = grow(box, magBox, magSize)
	else
		local merged = part("Rounds")
		local d = G.fallback.width
		if liveSources[1] then
			d = liveSources[1].Size.X * (if pieceScale then pieceScale.X else 1)
		end
		if merged then
			-- the stack top-aligned where the gun's own rounds sit, a step apart: spread down a detachable box (its
			-- bottom), as the gun's rounds are spaced if that is roomy enough, else Hud.Gun.pitch
			local rest = restRel(gun, merged)
			v.follow, v.followRest = merged, rest
			local size = merged.Size
			local top = rest.Y + size.Y / 2 - d / 2
			local bottom = rest.Y - size.Y / 2 + d / 2
			local box2 = part("Magazine")
			if box2 then
				local m = restRel(gun, box2)
				bottom = math.min(bottom, m.Y - box2.Size.Y / 2 + d / 2 + d * G.floor)
			end
			local pitch = if cap > 1 then (top - bottom) / (cap - 1) else 0
			if not box2 and pitch < d * G.tight then
				pitch = d * G.pitch
			end
			local stagger = if pitch < d * G.double then G.stagger * d else 0
			local head = rest.Z + size.Z / 2
			v.slot = function(k: number, count: number, i: number)
				local side = if (count - i) % 2 == 0 then 1 else -1
				return CFrame.new(rest.X + side * stagger, top - (k - 1) * pitch, head)
			end
			local depth = (cap - 1) * pitch + d
			magBox = CFrame.new(rest.X, top + d / 2 - depth / 2, head - v.length / 2)
			magSize = Vector3.new(d, depth, v.length)
			box = grow(box, magBox, magSize)
		end
	end

	-- the plain shapes the ammo sits in (no gun parts: user 2026-10-26, "only the ammo has to use real models", "can
	-- you still show the bolt, magazine, and chamber?"): flat slabs behind the magazine, the barrel's breech end round
	-- the chamber and the channel the bolt slides in, each on a brass-edged one a little bigger; the bolt a block
	-- with its handle; the magazine's follower a plate under its last round
	local function block(name: string, color: string, size: Vector3): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Material = Enum.Material.SmoothPlastic
		p.Color = HudKit.rgb(color)
		p.Size = size
		anchored(p)
		p.Parent = cut
		return p
	end
	local function slab(cf: CFrame, size: Vector3, color: string?): { BasePart }
		local out = {}
		for i, look in { { color or "magazine", 0 }, { "brassDark", G.slab.edge } } do
			local p = Instance.new("Part")
			p.Name = "Slab"
			p.Material = Enum.Material.SmoothPlastic
			p.Color = HudKit.rgb(look[1])
			p.Size = Vector3.new(
				G.slab.thick,
				size.Y + 2 * (G.slab.pad + look[2]) * v.length,
				size.Z + 2 * (G.slab.pad + look[2]) * v.length
			)
			p.CFrame = cf * CFrame.new(-G.slab.back * v.length - i * G.slab.thick, 0, 0)
			anchored(p)
			p.Transparency = G.slab.see
			p.Parent = cut
			out[i] = p
		end
		return out
	end
	v.mag = slab(magBox, magSize)
	v.magAt = {}
	for i, p in v.mag do
		v.magAt[i] = p.CFrame
	end

	local P, L = G.shapes, v.length
	local dia = L / 4
	if liveSources[1] then
		dia = if v.tube then liveSources[1].Size.Y else liveSources[1].Size.X * (if pieceScale then pieceScale.X else 1)
	end
	v.dia = dia
	-- the gun's body, drawn behind it all as its traced outline in thin lines (user 2026-10-26: "keep the body of the
	-- gun in the visual somehow, but dont overshadow the bullets and the mechanism", "dont use the physical model for
	-- the body. maybe you can trace it and create a design"; Config/GunOutlines)
	local O = G.outline
	local width = O.width * dia
	for _, line in (GunOutlines :: any)[weapon] or {} do
		local n = #line // 2
		for i = 1, n do
			local j = i % n + 1
			local a = Vector3.new(-O.back, line[i * 2] * s[2], line[i * 2 - 1] * s[3])
			local b = Vector3.new(-O.back, line[j * 2] * s[2], line[j * 2 - 1] * s[3])
			local len = (b - a).Magnitude
			if len > 1e-4 then
				local seg = Instance.new("Part")
				seg.Name = "Outline"
				seg.Material = Enum.Material.SmoothPlastic
				seg.Color = HudKit.rgb("outline")
				seg.Size = Vector3.new(width, width, len + width)
				seg.CFrame = CFrame.lookAt((a + b) / 2, b)
				anchored(seg)
				seg.Transparency = O.see
				seg.Parent = cut
			end
		end
	end
	-- the barrel's breech end, from the chamber's mouth forward, and the channel behind it the bolt slides back in
	local barrel = Vector3.new(dia, dia * P.barrel.height, L * P.barrel.length)
	slab(v.chamber * CFrame.new(0, 0, -barrel.Z / 2), barrel, "steel")
	local channel = Vector3.new(dia, dia * P.channel.height, L * P.bolt.length + v.travel)
	slab(v.chamber * CFrame.new(0, 0, channel.Z / 2), channel)
	box = grow(
		box,
		v.chamber * CFrame.new(0, 0, (channel.Z - barrel.Z) / 2),
		Vector3.new(dia, barrel.Y, channel.Z + barrel.Z)
	)
	-- the bolt, a simple 3D piece of its own (user 2026-10-26: "dont use real models for the bolts. create a simple but
	-- 3d design"): a round body, its face at the case head, the cocking piece behind it, its handle (a rod and a ball
	-- knob) at the back, turned up as the gun's bolt turns
	local B = P.bolt
	local along = CFrame.Angles(0, math.pi / 2, 0) -- (a cylinder's axis is its X: turned onto the gun's Z)
	local body = block("Bolt", "bolt", Vector3.new(L * B.length, dia * B.height, dia * B.height))
	body.Shape = Enum.PartType.Cylinder
	local cock = block("CockingPiece", "steel", Vector3.new(L * B.cock, dia * B.cockWidth, dia * B.cockWidth))
	cock.Shape = Enum.PartType.Cylinder
	v.boltParts = {
		{ part = body, rel = CFrame.new(0, 0, L * B.length / 2) * along },
		{ part = cock, rel = CFrame.new(0, 0, L * (B.length + B.cock / 2)) * along },
	}
	box = grow(box, CFrame.new(v.chamber.Position), Vector3.new(dia, dia, L * (B.length + B.cock) * 2))
	v.boltTurn = math.rad(w.action.turn or 0)
	if v.boltTurn > 0 then
		local stem = block("Handle", "bolt", Vector3.new(dia * B.handle, dia * B.stem, dia * B.stem))
		stem.Shape = Enum.PartType.Cylinder
		local knob = block("Knob", "bolt", Vector3.one * dia * B.knob)
		knob.Shape = Enum.PartType.Ball
		-- (on the right: in front of the rounds)
		v.handle = { stem = stem, knob = knob, at = CFrame.new(dia * B.out, 0, L * B.length * B.handleAt) }
		box = grow(
			box,
			CFrame.new(v.chamber.X, v.chamber.Y, v.chamber.Z + L * B.length / 2),
			Vector3.new(dia, dia * B.handle * 2.2, L * B.length)
		)
	end
	if bolt then
		v.boltRestCF = restRel(gun, bolt)
	end
	-- the follower
	local Fo = P.follower
	v.follower = block(
		"Follower",
		"follower",
		if v.tube
			then Vector3.new(dia * Fo.width, dia * Fo.width, dia * Fo.thick)
			else Vector3.new(dia * Fo.width, dia * Fo.thick, L * Fo.length)
	)
	box = grow(box, magBox, magSize + Vector3.new(0, 2, 2) * G.slab.pad * v.length)

	local b = box or grow(nil, CFrame.identity, Vector3.one)
	local centre = CFrame.new((b.lo + b.hi) / 2)
	local size = b.hi - b.lo
	local function frame()
		HudKit.frameBox(view, camera, centre, size, Vector3.xAxis, Vector3.yAxis, G.fov, G.margin)
	end
	frame()
	table.insert(v.conns, view:GetPropertyChangedSignal("AbsoluteSize"):Connect(frame))
	cut.Parent = view
	return v
end

-- the stack's slot k of the magazine in gun space, moving with the gun's own rounds (a clip coming in, a box
-- swapped)
local function slotCF(v: View, k: number, count: number, i: number): CFrame
	local at = v.slot(k, count, i)
	if v.follow then
		local now = v.gun.CFrame:ToObjectSpace(v.follow.CFrame)
		return now * v.followRest:Inverse() * at
	end
	return at
end

local function throw(v: View, which: Piece, from: CFrame, kind: string, now: number, size: number)
	local m = Instance.new("Model")
	m.Name = "Flying"
	local p: Piece = { parts = {}, model = m }
	for _, q in which.parts do
		local c = q.part:Clone()
		c.Parent = m
		table.insert(p.parts, { part = c, rel = q.rel })
	end
	m.Parent = v.cut
	local time = if kind == "clip" then G.drop.time else G.fly.time
	table.insert(v.flying, { piece = p, from = from, start = now, time = time, kind = kind, size = size })
end

local function update(v: View, state: F.State, gun: F.Gun, now: number, clock: number)
	-- the bolt: how far back it is (0 closed, travel fully back)
	local d = 0
	if v.bolt then
		d = math.max(0, v.gun.CFrame:ToObjectSpace(v.bolt.CFrame).Z - v.boltRest)
	end
	local open = d > v.travel * G.openFrom
	-- the drawn bolt: back as far as the gun's, its handle up as far as the gun's has turned
	local boltAt = v.chamber * CFrame.new(0, 0, d)
	for _, q in v.boltParts do
		q.part.CFrame = boltAt * q.rel
	end
	local h = v.handle
	if h and v.bolt then
		local r = v.boltRestCF.Rotation:Inverse() * v.gun.CFrame:ToObjectSpace(v.bolt.CFrame).Rotation
		local spun = math.abs(math.atan2(r.RightVector.Y, r.RightVector.X))
		local turned = math.clamp(spun / v.boltTurn, 0, 1)
		local B = G.shapes.bolt
		local pivot = boltAt * h.at * CFrame.Angles(math.rad(B.down + (B.up - B.down) * turned), 0, 0)
		h.stem.CFrame = pivot * CFrame.new(0, -h.stem.Size.X / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
		h.knob.CFrame = pivot * CFrame.new(0, -h.stem.Size.X, 0)
	end
	local truth = if state.chambered then "round" elseif state.spent then "case" else nil
	if not open then
		v.wasOpen, v.carry, v.fed, v.pending, v.maxD = false, nil, true, false, 0
		v.atRest = truth
	else
		if not v.wasOpen then
			-- the bolt has just come off the chamber: it pulls back what was in it; the state has already chambered the
			-- next round, which waits in the magazine until the bolt comes forward
			v.wasOpen, v.maxD = true, 0
			v.carry = v.atRest
			v.fed = false
			v.pending = state.chambered
			v.atRest = nil
		end
		v.maxD = math.max(v.maxD, d)
		if v.carry and d >= v.travel * G.eject then
			throw(
				v,
				if v.carry == "case" then v.case else v.live,
				v.chamber * CFrame.new(0, 0, d),
				"case",
				clock,
				v.length
			)
			v.carry = nil
		end
		if not v.fed and v.pending and d < v.maxD - v.travel * G.closing then
			v.fed = true -- closing: the bolt has picked up the top round
		end
	end

	-- the chamber
	if not open then
		if v.atRest == "round" then
			place(v.live, v.chamber)
			hide(v.case)
		elseif v.atRest == "case" then
			place(v.case, v.chamber)
			hide(v.live)
		else
			hide(v.live)
			hide(v.case)
		end
		hide(v.feed)
	else
		hide(v.live)
		if v.carry == "case" then
			place(v.case, v.chamber * CFrame.new(0, 0, d))
		elseif v.carry == "round" then
			place(v.live, v.chamber * CFrame.new(0, 0, d))
			hide(v.case)
		else
			hide(v.case)
		end
		if v.fed and v.pending then
			-- riding up out of the magazine in front of the bolt face into the chamber
			local top = slotCF(v, 1, 1, 1)
			local u = smooth(1 - d / math.max(v.maxD * G.feed, 1e-3))
			local at = v.chamber * CFrame.new(0, 0, d)
			place(v.feed, CFrame.new(at.X, top.Y + (at.Y - top.Y) * u, at.Z) * at.Rotation)
		else
			hide(v.feed)
		end
	end

	-- the magazine
	local follow = v.follow
	local visible = if follow then follow.Transparency < 1 else true
	local count = F.magazineAt(state, now)
	if open and v.pending and not v.fed then
		count += 1
	end
	if not visible then
		count = 0
	end
	-- a clip's rounds being pushed down out of it (the gun's "HeldRounds" showing): the stack as it was
	local held = v.tool:FindFirstChild("HeldRounds")
	if held and held:IsA("BasePart") and held.Transparency < 1 then
		v.frozen = v.frozen or v.shown
		count = v.frozen :: number
	else
		v.frozen = nil
	end
	count = math.clamp(count, 0, #v.rounds)
	if count ~= v.shown then
		v.lift = math.clamp(v.lift + (v.shown - count), -#v.rounds, #v.rounds)
		v.shown = count
	end
	local dt = math.clamp(clock - v.last, 0, 0.1)
	v.last = clock
	if v.lift ~= 0 then
		local step = dt / G.rise
		v.lift = if v.lift > 0 then math.max(0, v.lift - step) else math.min(0, v.lift + step)
	end
	for i, r in v.rounds do
		if i <= count then
			-- rounds rising (a round fed) start a slot lower; rounds pushed in start above
			place(r, slotCF(v, i + v.lift, count, i))
		else
			hide(r)
		end
	end
	-- the follower under the last round (at the top when empty), pushing them up
	local Fo = G.shapes.follower
	if v.tube then
		v.follower.CFrame = slotCF(v, count + 1 + v.lift, count, count) * CFrame.new(0, 0, -v.length * Fo.gap)
	else
		local under = slotCF(v, math.max(count, 1) + v.lift, count, count)
		local drop = if count == 0 then -Fo.gap - 0.5 else Fo.gap + 0.5
		v.follower.CFrame = under * CFrame.new(0, -v.dia * drop, -v.length * Fo.length / 2)
	end
	v.follower.Transparency = if (gun.clip == "Enbloc" or gun.clip == "Box") and not visible then 1 else 0

	-- the magazine's shapes: with the gun's rounds (an en-bloc clip coming in, a box swapped), gone while a clip or a
	-- box is out of the gun; an empty en-bloc clip drops out of the bottom as its last round goes up
	local delta = if follow then v.gun.CFrame:ToObjectSpace(follow.CFrame) * v.followRest:Inverse() else CFrame.identity
	local away = (gun.clip == "Enbloc" or gun.clip == "Box") and not visible
	for i, p in v.mag do
		p.CFrame = delta * v.magAt[i]
		p.Transparency = if away then 1 else G.slab.see
	end
	if gun.clip == "Enbloc" then
		if v.clipWas and away and count == 0 then
			local parts = {}
			for _, p in v.mag do
				table.insert(parts, { part = p, rel = v.mag[1].CFrame:ToObjectSpace(p.CFrame) })
			end
			throw(v, { parts = parts, model = v.cut }, v.mag[1].CFrame, "clip", clock, v.mag[1].Size.Y)
		end
		v.clipWas = not away
	end

	-- what's flying: cases thrown up and back, clips falling
	for i = #v.flying, 1, -1 do
		local f = v.flying[i]
		local u = (clock - f.start) / f.time
		if u >= 1 then
			f.piece.model:Destroy()
			table.remove(v.flying, i)
			continue
		end
		local fade = math.clamp((u - G.fade) / (1 - G.fade), 0, 1)
		local cf
		if f.kind == "clip" then
			cf = f.from
				* CFrame.new(0, -G.drop.fall * f.size * u * u, 0)
				* CFrame.Angles(u * math.rad(G.drop.tilt), 0, 0)
		else
			local fl = G.fly
			cf = CFrame.new(0, fl.up * f.size * 4 * u * (1 - u), fl.back * f.size * u)
				* f.from
				* CFrame.Angles(-u * fl.turns * math.pi * 2, 0, 0)
		end
		for _, q in f.piece.parts do
			q.part.CFrame = cf * q.rel
			q.part.Transparency = if f.kind == "clip" then G.slab.see + (1 - G.slab.see) * fade else fade
		end
	end
end

function AmmoHud.start()
	panel = HudKit.panel("Gun", "AmmoHud")
end

-- Every frame from src/client/Firing: the held gun and its predicted state (nil: no gun in the hands).
function AmmoHud.show(tool: Tool?, weapon: string?, state: F.State?, gun: F.Gun?, now: number)
	local p = panel
	if not p then
		return
	end
	local body = tool and tool:FindFirstChild("Gun")
	if not tool or not weapon or not state or not gun or not body or not body:IsA("BasePart") then
		p.gui.Enabled = false
		if current then
			destroy(current)
			current = nil
		end
		return
	end
	p.gui.Enabled = true
	if current and current.tool ~= tool then
		destroy(current)
		current = nil
	end
	if not current then
		current = build(tool, weapon, body, p.node.GunView :: ViewportFrame)
		current.shown = F.magazineAt(state, now)
	end
	update(current :: View, state, gun, now, os.clock())

	-- the box in the team's colours, the count and the hint
	p.team(tool.Parent and (tool.Parent :: Instance):GetAttribute("Kit"))
	local total = F.magazineAt(state, now) + (if state.chambered then 1 else 0)
	p.set("count", `{F.magazineAt(state, now)}+{if state.chambered then 1 else 0}`)
	local countLabel = p.node.Count :: TextLabel
	countLabel.TextColor3 = HudKit.rgb(if total == 0 then "countLow" else "count")
	local next = F.next(state, now)
	local key = Settings.get("Key_Reload")
	local H = G.hints
	local hint = if next == "Load"
		then H.Load
		elseif next == "Bolt" then (if gun.clip == "Loose" then H.Pump else H.Bolt)
		elseif next == "Dry" or next == "Open" or (state.magazine == 0 and not state.chambered) then (if gun.clip
				== "Loose"
			then H.Shells
			elseif gun.clip == "Box" then H.Box
			else H.Clip)
		else ""
	p.set("hint", (hint:gsub("{key}", tostring(key))))
	p.node.Hint.Visible = hint ~= ""
end

return AmmoHud
