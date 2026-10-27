--!strict
-- The gun's ammo display (Config/Hud.Gun; layout src/shared/ui/CombatHud.json "Gun"): a three-quarter cut-away of the
-- held weapon's action, bottom right, drawn live in two ViewportFrames with one camera (user 2026-10-26: "make it 3d and
-- off angle", "only keep this part clear (the bullet, bolt, magwell)", "make everything else just a simple shadow
-- sillouette", "make sure the animations are accurate, doesnt clip, and plays well in reload animation"):
-- - GunShadow: the gun's own parts in one flat colour, the whole layer see-through (one even shadow, no overlaps);
-- - GunView over it, the clear parts:
--   - the bolt, a simple 3D piece (a round body, its lugs, the cocking piece, its handle out to the gun's own knob),
--     moving exactly as the gun's Bolt part does (src/client/GunFx moves it; turned, slid back);
--   - the rounds (the shared round, Config/Assets ammo_rifle; a pump gun's own shells) one by one in the magazine,
--     staggered as a double stack, rising a round each time one is fed; the round or the fired case in the chamber,
--     pulled back by the bolt and thrown out; the next round pushed by the bolt's face up out of the magazine into
--     the chamber; a stripper clip's rounds coming down into the well; an empty en-bloc clip dropping out;
--   - the magazine well, an open box with its near side cut away (no follower or spring, user 2026-10-26: "just make
--     the bullet come up on its own"); a detachable box moves with the gun's own rounds (swapped), an en-bloc clip
--     comes in with them.
--   Nothing passes through anything: the stack sits under the bolt and its heads ahead of the open bolt's face; a
--   clip's rounds are down on the stack before the closing bolt's face reaches them.
--   The chamber shows what the bolt really has: working the bolt changes the state before the bolt moves, so a fired
--   case stays a case until the bolt pulls it out. A semi-automatic's action cycles itself in ~0.1 s, too quick to
--   see: after a shot the cut-away plays its own slower cycle (Config/Hud.Gun.auto), the case out and the next round
--   up into the chamber.
-- - a red line saying what to do next.
-- src/client/Firing feeds it the predicted state every frame (AmmoHud.show).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudCfg = require(Shared.Config.Hud)
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

-- a gun-space box grown to take in another (centre, size)
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
	shadowView: ViewportFrame,
	camera: Camera,
	shadowCamera: Camera,
	cut: Model,
	shade: Model,
	shadows: { { part: BasePart, source: BasePart } }, -- the gun's body, flat, following its parts
	dia: number, -- a round's width (studs)
	-- the bolt
	boltParts: { { part: BasePart, rel: CFrame } }, -- the drawn bolt, about its face
	handle: { stem: BasePart, knob: BasePart, pivot: Vector3, at: Vector3 }?, -- (rest, gun space)
	boltRestCF: CFrame,
	bolt: BasePart?,
	boltRest: number, -- its z at rest
	travel: number,
	-- the magazine
	rounds: { Piece },
	held: { Piece }, -- a stripper clip's rounds coming down
	strip: BasePart?,
	slot: (k: number, count: number, i: number) -> CFrame, -- gun space: the round `i` of `count` at slot k (1: top)
	headZ: number, -- the stack's heads, gun space
	midX: number, -- the stack's middle, side to side
	pitch: number,
	shift: number, -- how far the stack sits below the gun's own rounds (no clipping under the bolt)
	follow: BasePart?, -- the stack moves with this part (the gun's merged rounds) from its rest
	followRest: CFrame,
	tube: boolean,
	shown: number, -- the count drawn
	lift: number, -- slots the stack is still to rise (+) or settle (-)
	rate: number, -- slots a second it settles at (a clip's rounds pushed in: all in Hud.Gun.settle)
	mag: { BasePart }, -- the parts that move with the gun's rounds (a box's well, an en-bloc clip)
	magAt: { CFrame },
	conns: { RBXScriptConnection },
	-- the chamber
	chamber: CFrame, -- gun space: the round's head there, closed
	live: Piece,
	case: Piece,
	feed: Piece,
	wasOpen: boolean,
	carry: string?, -- what the opening bolt pulls back ("case" / "round" thrown out; "keep": a round it brings home)
	maxD: number,
	fed: boolean, -- closing: the next round has left the magazine
	pending: boolean, -- a round still in the magazine for this cycle (the state has already chambered it)
	atRest: string?, -- what the chamber showed closed
	flying: { Fly },
	clipWas: boolean,
	allow: number?, -- a clip reload under way: the most rounds the stack shows (those already pushed down)
	pushN: number, -- rounds the clip being pushed down holds
	wasPushing: boolean,
	magWas: number, -- a semi-automatic: the state's magazine and open bolt last frame (a shot drops one or opens it)
	openWas: boolean,
	cycleAt: number?, -- a semi-automatic: when the cut-away's own cycle after a shot began (clock)
	wasAway: boolean, -- a box swap: the old box has gone out
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
	v.shade:Destroy()
end

local function camera(view: ViewportFrame): Camera
	local c = view:FindFirstChildOfClass("Camera") or Instance.new("Camera")
	c.Parent = view
	view.CurrentCamera = c
	return c
end

local function build(tool: Tool, weapon: string, gun: BasePart, view: ViewportFrame, shadowView: ViewportFrame): View
	local w = W[weapon]
	local s = w.scale
	local scale = Vector3.new(s[1], s[2], s[3])
	local own = G.weapons[weapon] :: any
	local cut = Instance.new("Model")
	cut.Name = "Cutaway"
	local shade = Instance.new("Model")
	shade.Name = "Shadow"

	local v: View = {
		tool = tool,
		weapon = weapon,
		gun = gun,
		view = view,
		shadowView = shadowView,
		camera = camera(view),
		shadowCamera = camera(shadowView),
		cut = cut,
		shade = shade,
		shadows = {},
		dia = 0,
		boltParts = {},
		handle = nil,
		boltRestCF = CFrame.identity,
		bolt = nil,
		boltRest = 0,
		travel = w.action.travel * s[3],
		rounds = {},
		held = {},
		strip = nil,
		slot = function()
			return CFrame.identity
		end,
		headZ = 0,
		midX = 0,
		pitch = 0,
		shift = 0,
		follow = nil,
		followRest = CFrame.identity,
		tube = w.ammo.clip == "Loose",
		shown = 0,
		lift = 0,
		rate = 0,
		mag = {},
		magAt = {},
		conns = {},
		chamber = CFrame.identity,
		live = { parts = {}, model = cut },
		case = { parts = {}, model = cut },
		feed = { parts = {}, model = cut },
		wasOpen = false,
		carry = nil,
		maxD = 0,
		fed = true,
		pending = false,
		atRest = nil,
		flying = {},
		clipWas = false,
		allow = nil,
		pushN = 0,
		wasPushing = false,
		magWas = 0,
		openWas = false,
		cycleAt = nil,
		wasAway = false,
		length = G.fallback.length,
		last = os.clock(),
	}

	local function part(name: string): BasePart?
		local p = tool:FindFirstChild(name)
		return if p and p:IsA("BasePart") then p else nil
	end
	local bolt = part("Bolt")
	if bolt then
		v.bolt = bolt
		v.boltRestCF = restRel(gun, bolt)
		v.boltRest = v.boltRestCF.Z
	end

	-- the shadow: every other part of the gun, one flat colour (the layer's lights: ambient only)
	local skip: { [string]: boolean } = {}
	for _, name in G.clear do
		skip[name] = true
	end
	for _, name in w.feed and w.feed.parts or {} do
		skip[name] = true
	end
	for _, p in tool:GetDescendants() do
		if p:IsA("BasePart") and not skip[p.Name] then
			local c = p:Clone()
			anchored(c)
			if c:IsA("MeshPart") then
				c.TextureID = ""
			end
			c.Material = Enum.Material.SmoothPlastic
			c.Color = HudKit.rgb("shadow")
			c.Parent = shade
			table.insert(v.shadows, { part = c, source = p })
		end
	end
	shadowView.Ambient = HudKit.rgb("shadowAmbient")
	shadowView.LightColor = HudKit.rgb("shadowLight")
	shadowView.ImageTransparency = G.shadow.see
	if not shadowView:FindFirstChildOfClass("UIGradient") then
		-- (fading out toward the stock and the muzzle)
		local fade = Instance.new("UIGradient")
		local e = G.shadow.fade
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(e, 0),
			NumberSequenceKeypoint.new(1 - e, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = shadowView
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
	local L = v.length
	local d = G.fallback.width
	if liveSources[1] then
		d = if v.tube then liveSources[1].Size.Y else liveSources[1].Size.X * (if pieceScale then pieceScale.X else 1)
	end
	v.dia = d

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
	local ch = v.chamber.Position

	local function block(name: string, color: string, size: Vector3, parent: Instance?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Material = Enum.Material.SmoothPlastic
		p.Color = HudKit.rgb(color)
		p.Size = size
		anchored(p)
		p.Parent = parent or cut
		return p
	end
	local along = CFrame.Angles(0, math.pi / 2, 0) -- (a cylinder's axis is its X: turned onto the gun's Z)

	-- the bolt: a round body from the face back toward the gun's bolt's rear, the lugs at the face, the cocking piece
	local B = G.bolt
	local rear = if bolt then v.boltRest + bolt.Size.Z / 2 else ch.Z + L
	local full = math.max(rear - ch.Z, L / 2)
	local bodyLen = full * B.body
	local radius = d * B.radius
	local body = block("Bolt", "bolt", Vector3.new(bodyLen, radius * 2, radius * 2))
	body.Shape = Enum.PartType.Cylinder
	local lug = block("Lugs", "steel", Vector3.new(d * B.lugLength, radius * 2 * B.lug, radius * 2 * B.lug))
	lug.Shape = Enum.PartType.Cylinder
	local cock = block("CockingPiece", "steel", Vector3.new(full - bodyLen, radius * 2 * B.cock, radius * 2 * B.cock))
	cock.Shape = Enum.PartType.Cylinder
	v.boltParts = {
		{ part = body, rel = CFrame.new(0, 0, bodyLen / 2) * along },
		{ part = lug, rel = CFrame.new(0, 0, d * B.lugLength / 2) * along },
		{ part = cock, rel = CFrame.new(0, 0, bodyLen + (full - bodyLen) / 2) * along },
	}
	-- its handle, out to the gun's own knob (gun space at rest), on the bolt's axis at the knob
	local knob = w.reload and (w.reload :: any).knob
	if bolt and knob and math.abs(knob[1]) > B.side then
		local at = Vector3.new(knob[1] * s[1], knob[2] * s[2], knob[3] * s[3])
		local stem = block("Handle", "bolt", Vector3.new(1, d * B.stem, d * B.stem))
		stem.Shape = Enum.PartType.Cylinder
		local ball = block("Knob", "bolt", Vector3.one * d * B.knob)
		ball.Shape = Enum.PartType.Ball
		v.handle = { stem = stem, knob = ball, pivot = Vector3.new(ch.X, ch.Y, at.Z), at = at }
	end
	local box = grow(
		nil,
		CFrame.new(ch.X, ch.Y, (ch.Z - L * G.frame.ahead + rear + v.travel) / 2),
		Vector3.new(
			2 * d * G.frame.side,
			2 * d * G.frame.above,
			rear + v.travel + d * G.frame.behind - (ch.Z - L * G.frame.ahead)
		)
	)

	-- the magazine's slots
	local cap = w.ammo.capacity
	for _ = 1, cap do
		table.insert(v.rounds, newLive())
	end
	local wellLo: Vector3?, wellHi: Vector3? = nil, nil -- the well's inside (gun space at rest)
	local Wl = G.well
	if v.tube then
		local t = own and own.tube
		local first = if t then CFrame.new(t[1] * s[1], t[2] * s[2], t[3] * s[3]) else carrier * CFrame.new(0, 0, -L)
		local step = L * G.tubeStep
		v.slot = function(k: number)
			return first * CFrame.new(0, 0, -(k - 1) * step)
		end
		v.headZ = first.Z
		local r = d * G.trough
		wellLo = Vector3.new(first.X - r, first.Y - r, first.Z - cap * step)
		wellHi = Vector3.new(first.X + r, first.Y + r, first.Z)
	else
		local merged = part("Rounds")
		if merged then
			-- the stack where the gun's own rounds sit, a step apart (spread down a detachable box to its bottom, as the
			-- gun's rounds are spaced if that is roomy enough, else Hud.Gun.pitch), but its top round under the bolt's
			-- body and its heads ahead of the open bolt's face (no clipping)
			local rest = restRel(gun, merged)
			v.follow, v.followRest = merged, rest
			local size = merged.Size
			local top0 = rest.Y + size.Y / 2 - d / 2
			local top = math.min(top0, ch.Y - radius - d * G.gap.under)
			v.shift = top0 - top
			local bottom = rest.Y - size.Y / 2 + d / 2 - v.shift
			local box2 = part("Magazine")
			if box2 then
				local m = restRel(gun, box2)
				bottom = math.min(bottom, m.Y - box2.Size.Y / 2 + d / 2 + d * G.floor)
			end
			local pitch = if cap > 1 then math.max(0, top - bottom) / (cap - 1) else 0
			if pitch < d * G.tight then
				pitch = d * G.pitch
			end
			v.pitch = pitch
			local stagger = if pitch < d * G.double then G.stagger * d else 0
			local head = math.min(rest.Z + size.Z / 2, ch.Z + v.travel - d * G.gap.behind)
			v.headZ, v.midX = head, rest.X
			v.slot = function(k: number, count: number, i: number)
				local side = if (count - i) % 2 == 0 then 1 else -1
				return CFrame.new(rest.X + side * stagger, top - (k - 1) * pitch, head)
			end
			local low = top - (cap - 1) * pitch - d / 2 - d * Wl.room
			wellLo = Vector3.new(rest.X - d * Wl.inside, low, head - L - d * Wl.front)
			wellHi = Vector3.new(rest.X + d * Wl.inside, top + d * Wl.above, head + d * Wl.rear)
		end
	end

	-- the magazine well: an open box (the far wall, the ends, the floor, a low rim on the near side: the camera is on
	-- the gun's right, +X); a box magazine's moves with the gun's rounds, a fixed well's stays
	local moves = w.ammo.clip == "Box"
	if wellLo and wellHi then
		local lo, hi = wellLo :: Vector3, wellHi :: Vector3
		local t = d * Wl.wall
		local mid = (lo + hi) / 2
		local span = hi - lo
		local walls = {
			block("Far", "well", Vector3.new(t, span.Y, span.Z)),
			block("Front", "well", Vector3.new(span.X + t, span.Y, t)),
			block("Rear", "well", Vector3.new(span.X + t, span.Y, t)),
			block("Floor", "wellEdge", Vector3.new(span.X + 2 * t, t, span.Z + 2 * t)),
			block("Lip", "wellEdge", Vector3.new(t, d * Wl.lip, span.Z)),
		}
		walls[1].CFrame = CFrame.new(lo.X - t / 2, mid.Y, mid.Z)
		walls[2].CFrame = CFrame.new(mid.X - t / 2, mid.Y, lo.Z - t / 2)
		walls[3].CFrame = CFrame.new(mid.X - t / 2, mid.Y, hi.Z + t / 2)
		walls[4].CFrame = CFrame.new(mid.X, lo.Y - t / 2, mid.Z)
		walls[5].CFrame = CFrame.new(hi.X + t / 2, lo.Y + d * Wl.lip / 2, mid.Z)
		if v.tube then
			walls[5]:Destroy() -- (a trough: no rim)
			table.remove(walls, 5)
		end
		if moves then
			for _, p in walls do
				table.insert(v.mag, p)
			end
		end
		box = grow(box, CFrame.new(mid), span + Vector3.new(2, 2, 2) * t + Vector3.new(0, 2 * d * G.frame.below, 0))
	end
	-- an en-bloc clip: a plate behind its rounds, coming in and dropping out with them
	if w.ammo.clip == "Enbloc" and wellLo then
		local lo = wellLo :: Vector3
		local t = d * G.enbloc.thick
		local plate = block("Enbloc", "clip", Vector3.new(t, v.pitch * (cap - 1) + d, L))
		local top = v.slot(1, 1, 1)
		plate.CFrame = CFrame.new(lo.X + t / 2, top.Y + d / 2 - plate.Size.Y / 2, top.Z - L / 2)
		table.insert(v.mag, plate)
	end
	for i, p in v.mag do
		v.magAt[i] = p.CFrame
	end
	-- a stripper clip's rounds coming down into the well, on their strip
	if w.ammo.clip == "Stripper" then
		for _ = 1, (w.ammo :: any).clipSize or cap do
			table.insert(v.held, newLive())
		end
		local S = G.strip
		v.strip = block("Strip", "clip", Vector3.new(d * S.width, 1, d * S.thick))
	end
	-- the camera, three-quarters on, the same for both layers
	local b = box
	local centre = CFrame.new((b.lo + b.hi) / 2)
	local size = b.hi - b.lo
	local f = G.from
	local from = Vector3.new(f[1], f[2], f[3]).Unit
	local function frame()
		HudKit.frameBox(view, v.camera, centre, size, from, Vector3.yAxis, G.fov, G.margin)
		v.shadowCamera.FieldOfView = v.camera.FieldOfView
		v.shadowCamera.CFrame = v.camera.CFrame
	end
	frame()
	table.insert(v.conns, view:GetPropertyChangedSignal("AbsoluteSize"):Connect(frame))
	cut.Parent = view
	shade.Parent = shadowView
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

-- a thin rod between two points (a cylinder: its axis is its X)
local function rod(p: BasePart, a: Vector3, b: Vector3)
	local len = (b - a).Magnitude
	if len < 1e-4 then
		p.Transparency = 1
		return
	end
	p.Size = Vector3.new(len, p.Size.Y, p.Size.Z)
	p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	p.Transparency = 0
end

local function update(v: View, state: F.State, gun: F.Gun, now: number, clock: number)
	-- the shadow follows the gun's parts (a box swapped, a pump worked, hidden parts hidden)
	for _, s in v.shadows do
		s.part.CFrame = v.gun.CFrame:ToObjectSpace(s.source.CFrame)
		s.part.Transparency = if s.source.Transparency >= 1 then 1 else 0
	end

	-- a semi-automatic's shot (the state has already put the next round in the chamber, or held the bolt open): the
	-- chamber holds the fired case until the bolt opens, and the cut-away plays its own cycle
	if gun.auto then
		local shot = state.magazine < v.magWas or (state.open and not v.openWas)
		if shot and not state.load and not v.wasOpen then
			v.atRest = "case"
			v.cycleAt = clock
		end
		v.magWas, v.openWas = state.magazine, state.open
	end

	-- the bolt: how far back it is (0 closed, travel fully back)
	local d = 0
	local boltNow = v.boltRestCF
	if v.bolt then
		boltNow = v.gun.CFrame:ToObjectSpace(v.bolt.CFrame)
		d = math.max(0, boltNow.Z - v.boltRest)
	end
	local cycleAt = v.cycleAt
	if cycleAt then
		local A = G.auto
		local u = (clock - cycleAt) / A.time
		if u >= 1 then
			v.cycleAt = nil
		else
			local k = if u < A.back then smooth(u / A.back) elseif u < A.hold then 1 else smooth((1 - u) / (1 - A.hold))
			if k * v.travel > d then
				-- (straight back: a semi-automatic's bolt doesn't turn)
				d = k * v.travel
				boltNow = CFrame.new(0, 0, d) * v.boltRestCF
			end
		end
	end
	local open = d > v.travel * G.openFrom
	local face = v.chamber.Z + d
	local boltAt = v.chamber * CFrame.new(0, 0, d)
	for _, q in v.boltParts do
		q.part.CFrame = boltAt * q.rel
	end
	local h = v.handle
	if h then
		-- (moved exactly as the gun's bolt: turned about its axis, slid back)
		local move = boltNow * v.boltRestCF:Inverse()
		local pivot, at = move:PointToWorldSpace(h.pivot), move:PointToWorldSpace(h.at)
		rod(h.stem, pivot, at)
		h.knob.CFrame = CFrame.new(at)
	end
	local truth = if state.chambered then "round" elseif state.spent then "case" else nil
	local busy = F.busy(state, now)
	if not open then
		if v.wasOpen or truth == "case" or not busy then
			-- (a shot leaves its case at once; anything else waits for the bolt to open: working the bolt or a reload
			-- changes the state before the bolt moves, and a fired case mustn't turn back into a round)
			v.atRest = truth
		end
		v.wasOpen, v.carry, v.fed, v.pending, v.maxD = false, nil, true, false, 0
	else
		if not v.wasOpen then
			-- the bolt has just come off the chamber: it pulls back what was in it (a round the state still has
			-- chambered rides back on its face and home again); the state has already chambered the next round, which
			-- waits in the magazine until the bolt comes forward
			v.wasOpen, v.maxD = true, 0
			v.carry = if v.atRest == "round" and state.chambered then "keep" else v.atRest
			v.fed = false
			v.pending = state.chambered and v.carry ~= "keep"
			v.atRest = nil
		elseif not v.fed and not v.pending and state.chambered and v.carry ~= "keep" then
			-- (a round chambered while the bolt is open: a reload from a bolt held open, single rounds ending)
			v.pending = true
		end
		v.maxD = math.max(v.maxD, d)
		if v.carry and v.carry ~= "keep" and d >= v.travel * G.eject then
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
		-- closing: the bolt's face picks up the top round once it is ahead of its head
		if not v.fed and v.pending and d < v.maxD - v.travel * G.closing and (v.tube or face <= v.headZ) then
			v.fed = true
		end
	end

	-- the magazine's count
	local follow = v.follow
	local visible = if follow then follow.Transparency < 1 else true
	local count = F.magazineAt(state, now)
	if (open and v.pending and not v.fed) or (not open and state.chambered and v.atRest ~= "round") then
		count += 1 -- (the state has chambered a round the bolt hasn't fed yet)
	end
	-- a box swapped (the state fills it at once): the old box keeps its rounds until it is out, the new one comes in
	-- full; neither moves the stack (it goes with its box)
	local swap = gun.clip == "Box" and busy and not state.load
	if not swap then
		v.wasAway = false
	elseif not visible then
		v.wasAway = true
	elseif not v.wasAway then
		count = math.min(count, v.shown)
	end
	if not visible then
		count = 0
	end
	local snap = swap and (not visible or v.wasAway)
	-- a clip's rounds being pushed down out of it (the gun's "HeldRounds" showing; gone once the closing bolt's face
	-- reaches their heads): through a clip reload the stack shows only the rounds already pushed down
	local held = v.tool:FindFirstChild("HeldRounds")
	local pushing = held ~= nil and held:IsA("BasePart") and held.Transparency < 1 and open and face > v.headZ
	if v.wasPushing and not pushing and v.allow then
		v.allow = (v.allow :: number) + v.pushN
	end
	v.wasPushing = pushing
	if v.strip and busy and not state.load then
		v.allow = v.allow or v.shown
	else
		v.allow = nil
	end
	if v.allow then
		count = math.min(count, v.allow :: number)
	end
	count = math.clamp(count, 0, #v.rounds)

	-- the chamber, and the round being fed
	local feeding = 0 -- (how far the fed round has risen: the stack under it waits)
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
		if v.carry == "case" then
			place(v.case, v.chamber * CFrame.new(0, 0, d))
			hide(v.live)
		elseif v.carry == "round" or (v.carry == "keep" and not pushing) then
			-- (a kept round makes way for a clip's rounds coming down where it is)
			place(v.live, v.chamber * CFrame.new(0, 0, d))
			hide(v.case)
		else
			hide(v.live)
			hide(v.case)
		end
		if v.fed and v.pending then
			local at = v.chamber * CFrame.new(0, 0, d)
			local top = slotCF(v, 1, count + 1, 1)
			if v.tube then
				-- a pump gun's shell rides up onto the carrier as the bolt comes forward
				local u = smooth(1 - d / math.max(v.maxD * G.tubeFeed, 1e-3))
				place(v.feed, CFrame.new(at.X, top.Y + (at.Y - top.Y) * u, at.Z) * at.Rotation)
			else
				-- its head on the bolt's face, rising to the chamber's line as the face goes from the stack's heads to
				-- the chamber, nose up on the way
				local u = math.clamp((v.headZ - at.Z) / math.max(v.headZ - v.chamber.Z, 1e-3), 0, 1)
				feeding = u
				u = smooth(u)
				local p = top.Position:Lerp(at.Position, u)
				place(
					v.feed,
					CFrame.new(p.X, p.Y, at.Z) * CFrame.Angles(math.rad(G.feed.tilt) * math.sin(u * math.pi), 0, 0)
				)
			end
		else
			hide(v.feed)
		end
	end

	-- the stack
	if count ~= v.shown then
		v.lift = math.clamp(v.lift + (v.shown - count), -#v.rounds, #v.rounds)
		if count > v.shown then
			-- (rounds pushed in come down all in Hud.Gun.settle)
			v.rate = -v.lift / G.settle
		end
		v.shown = count
		if snap then
			v.lift = 0
		end
	end
	local dt = math.clamp(clock - v.last, 0, 0.1)
	v.last = clock
	if v.lift > 0 then
		v.lift = math.max(0, v.lift - dt / G.rise)
	elseif v.lift < 0 then
		v.lift = math.min(0, v.lift + dt * math.max(v.rate, 1 / G.rise))
		if open and face <= v.headZ then
			v.lift = 0 -- (down before the closing bolt's face passes over their heads)
		end
	end
	local lift = v.lift
	if open and v.fed and v.pending and not v.tube then
		-- (still a round down until the fed round clears it)
		lift = math.max(lift, 1 - math.min(1, feeding * G.feed.clear))
	end
	for i, r in v.rounds do
		if i <= count then
			-- rounds rising (a round fed) start a slot lower; rounds pushed in start above
			place(r, slotCF(v, i + lift, count, i))
		else
			hide(r)
		end
	end
	-- a stripper clip's rounds on their strip, coming down with the gun's own (as far below them as the stack is)
	local strip = v.strip
	if strip then
		local n = math.min(#v.held, #v.rounds - count)
		if pushing and n > 0 then
			v.pushN = n
			local hp = held :: BasePart
			local hc = v.gun.CFrame:ToObjectSpace(hp.CFrame)
			local bottom = hc.Y - hp.Size.Y / 2 + v.dia / 2 - v.shift
			local step = if n > 1 then math.max(v.dia, (hp.Size.Y - v.dia) / (n - 1)) else 0
			local x = v.midX
			for i, r in v.held do
				if i <= n then
					place(r, CFrame.new(x, bottom + (n - i) * step, v.headZ))
				else
					hide(r)
				end
			end
			local span = (n - 1) * step + v.dia * G.strip.width
			strip.Size = Vector3.new(strip.Size.X, span, strip.Size.Z)
			strip.CFrame = CFrame.new(x, bottom + (n - 1) * step / 2, v.headZ + strip.Size.Z / 2)
			strip.Transparency = 0
		else
			for _, r in v.held do
				hide(r)
			end
			strip.Transparency = 1
		end
	end

	local delta = if follow then v.gun.CFrame:ToObjectSpace(follow.CFrame) * v.followRest:Inverse() else CFrame.identity
	local away = (gun.clip == "Enbloc" or gun.clip == "Box") and not visible

	-- what moves with the gun's rounds (a box's well, an en-bloc clip): gone while out of the gun; an empty en-bloc
	-- clip drops out of the bottom as its last round goes up
	local clipGone = gun.clip == "Enbloc" and count == 0
	for i, p in v.mag do
		p.CFrame = delta * v.magAt[i]
		p.Transparency = if away or (clipGone and p.Name == "Enbloc") then 1 else 0
	end
	if gun.clip == "Enbloc" then
		local plate = nil
		for _, p in v.mag do
			if p.Name == "Enbloc" then
				plate = p
			end
		end
		local there = not away and count > 0
		if plate and v.clipWas and not there then
			throw(
				v,
				{ parts = { { part = plate, rel = CFrame.identity } }, model = v.cut },
				plate.CFrame,
				"clip",
				clock,
				plate.Size.Y
			)
		end
		v.clipWas = there
	end

	-- what's flying: cases thrown up, out and back, clips falling
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
			cf = CFrame.new(fl.out * f.size * u, fl.up * f.size * 4 * u * (1 - u), fl.back * f.size * u)
				* f.from
				* CFrame.Angles(-u * fl.turns * math.pi * 2, 0, 0)
		end
		for _, q in f.piece.parts do
			q.part.CFrame = cf * q.rel
			q.part.Transparency = fade
		end
	end
end

function AmmoHud.start()
	panel = HudKit.panel("Gun", "AmmoHud", true) -- (the HUD size setting scales it)
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
		current = build(tool, weapon, body, p.node.GunView :: ViewportFrame, p.node.GunShadow :: ViewportFrame)
		current.shown = F.magazineAt(state, now)
		current.magWas, current.openWas = state.magazine, state.open
	end
	update(current :: View, state, gun, now, os.clock())

	-- the hint
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
