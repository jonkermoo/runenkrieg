--!strict
-- The gun's ammo display (Config/Hud.Gun; layout src/shared/ui/CombatHud.json "Gun"), bottom right: a flat 2D side view
-- of the held weapon's action (user 2026-11-12: "can we make it 2d instead ... still show the bolt and the animations
-- and the ammo"), drawn in GunCanvas with plain frames, the gun seen from its right, the muzzle to the right:
-- - the gun's body drawn plain under it all, see-through: the receiver the bolt slides in and the barrel ahead, fading
--   toward the muzzle (the guns are merged meshes, of no use as outlines);
-- - over it, each a flat outlined piece:
--   - the bolt (its body, the lugs at the face, the cocking piece) and its handle out to the gun's own knob, moving
--     exactly as the gun's Bolt part does (src/client/GunFx moves it; the handle swings up as it turns, it slides back);
--   - the rounds (case, rim and bullet in the weapon's own colours; a pump gun's shells, hull and brass head) one by
--     one in the magazine, a double stack's far column darker behind the near one, rising a round each time one is
--     fed; the round or the fired case in the chamber, pulled back by the bolt and thrown out spinning; the next round
--     pushed by the bolt's face up out of the magazine into the chamber, nose up on the way; a stripper clip's rounds
--     coming down into the well; an empty en-bloc clip dropping out;
--   - the magazine well, an open box (no follower or spring, user 2026-10-26: "just make the bullet come up on its
--     own"); a detachable box moves with the gun's own rounds (swapped), an en-bloc clip comes in with them.
--   Nothing passes through anything: the stack sits under the bolt and its heads ahead of the open bolt's face; a
--   clip's rounds are down on the stack before the closing bolt's face reaches them.
--   The chamber shows what the bolt really has: working the bolt changes the state before the bolt moves, so a fired
--   case stays a case until the bolt pulls it out. A semi-automatic's action cycles itself in ~0.1 s, too quick to
--   see: after a shot the display plays its own slower cycle (Config/Hud.Gun.auto), the case out and the next round
--   up into the chamber.
-- - a revolver: its cylinder seen from behind, flat, each chamber a hole with a live round's head in it, turning with
--   the gun's own cylinder;
-- - the rounds left as a number, RELOAD in red once none is left, and a red line saying what to do next.
-- The motion is worked out in gun space (studs) as before and only drawn flat: gun space +Y is up the screen, -Z to the
-- right; a piece's own -Z (a round's nose) points along its length.
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

-- ---- the flat canvas: gun space to the canvas's own pixels (its size in the spec, before the HUD's UIScale) ----
type Proj = { k: number, cz: number, cy: number, w: number, h: number }

local function at(pr: Proj, p: Vector3): (number, number)
	return pr.w / 2 + (pr.cz - p.Z) * pr.k, pr.h / 2 + (pr.cy - p.Y) * pr.k
end

-- a frame centred at (x, y), w by h pixels, turned `rot` degrees clockwise (all as shares of the canvas, so the HUD's
-- scale carries it)
local function put(pr: Proj, g: GuiObject, x: number, y: number, w: number, h: number, rot: number)
	g.Position = UDim2.fromScale(x / pr.w, y / pr.h)
	g.Size = UDim2.fromScale(w / pr.w, h / pr.h)
	g.Rotation = rot
end

local function roundCorners(g: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = g
end

local function ink(g: GuiObject): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = HudKit.rgb("gunInk")
	s.Thickness = G.flat.outline
	s.Parent = g
	return s
end

-- One drawn piece (a round, a case, the bolt, the well, a clip): flat shapes on a frame laid along the piece's own Z
-- from z0 to z1 (studs about its origin; the origin of a round is its case head, its nose toward -Z), h studs across.
type Shape = { obj: Frame, color: Color3, see: number, stroke: UIStroke? }
type Piece = {
	frame: Frame,
	proj: Proj,
	z0: number,
	z1: number,
	h: number,
	shapes: { Shape },
	tint: number,
	alpha: number,
}

local function newPiece(pr: Proj, parent: Instance, z0: number, z1: number, h: number, zindex: number): Piece
	local f = Instance.new("Frame")
	f.Name = "Piece"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = zindex
	f.Visible = false
	f.Parent = parent
	return { frame = f, proj = pr, z0 = z0, z1 = z1, h = h, shapes = {}, tint = 0, alpha = 0 }
end

type ShapeOpts = { see: number?, round: boolean?, line: boolean?, z: number? }

-- a flat shape over [za, zb] along the piece and [ya, yb] across it (studs about its origin)
local function shape(p: Piece, za: number, zb: number, ya: number, yb: number, color: Color3, opts: ShapeOpts?): Frame
	local o: ShapeOpts = opts or {}
	local len, h = p.z1 - p.z0, p.h
	local s = Instance.new("Frame")
	s.Name = `S{#p.shapes + 1}`
	s.BorderSizePixel = 0
	s.BackgroundColor3 = color
	s.BackgroundTransparency = o.see or 0
	s.Position = UDim2.fromScale((p.z1 - zb) / len, (h / 2 - yb) / h)
	s.Size = UDim2.fromScale((zb - za) / len, (yb - ya) / h)
	s.ZIndex = o.z or 1
	if o.round then
		roundCorners(s)
	end
	local stroke = if o.line == false then nil else ink(s)
	s.Parent = p.frame
	table.insert(p.shapes, { obj = s, color = color, see = o.see or 0, stroke = stroke })
	return s
end

local function fade(p: Piece, t: number)
	if p.alpha == t then
		return
	end
	p.alpha = t
	for _, s in p.shapes do
		s.obj.BackgroundTransparency = 1 - (1 - s.see) * (1 - t)
		if s.stroke then
			s.stroke.Transparency = t
		end
	end
end

-- darkened by `k` (a double stack's far column)
local function tint(p: Piece, k: number)
	if p.tint == k then
		return
	end
	p.tint = k
	for _, s in p.shapes do
		s.obj.BackgroundColor3 = s.color:Lerp(Color3.new(), k)
	end
end

-- the piece with its origin at `cf` (gun space), its length along cf's -Z as drawn
local function place(p: Piece, cf: CFrame, transparency: number?)
	local pr = p.proj
	local c = cf:PointToWorldSpace(Vector3.new(0, 0, (p.z0 + p.z1) / 2))
	local look = cf.LookVector
	local x, y = at(pr, c)
	put(pr, p.frame, x, y, (p.z1 - p.z0) * pr.k, p.h * pr.k, math.deg(math.atan2(-look.Y, -look.Z)))
	fade(p, transparency or 0)
	p.frame.Visible = true
end

local function hide(p: Piece)
	p.frame.Visible = false
end

local function copy(p: Piece): Piece
	local f = p.frame:Clone()
	f.Parent = p.frame.Parent
	local q: Piece = {
		frame = f,
		proj = p.proj,
		z0 = p.z0,
		z1 = p.z1,
		h = p.h,
		shapes = {},
		tint = p.tint,
		alpha = p.alpha,
	}
	for _, s in p.shapes do
		local o = f:FindFirstChild(s.obj.Name) :: Frame
		table.insert(q.shapes, { obj = o, color = s.color, see = s.see, stroke = o:FindFirstChildOfClass("UIStroke") })
	end
	return q
end

-- a thin bar between two gun-space points, `width` pixels
local function bar(pr: Proj, g: GuiObject, a: Vector3, b: Vector3, width: number)
	local ax, ay = at(pr, a)
	local bx, by = at(pr, b)
	local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	if len < 0.5 then
		g.Visible = false
		return
	end
	put(pr, g, (ax + bx) / 2, (ay + by) / 2, len, width, math.deg(math.atan2(by - ay, bx - ax)))
	g.Visible = true
end

-- the drawing order, back to front
local Z = { body = 1, well = 2, clip = 3, far = 4, round = 5, chamber = 6, bolt = 7, handle = 8, flying = 9 }

-- How a round is drawn: a cartridge (case, rim, bullet) or a pump gun's shell (hull, brass head); length, width, the
-- case's share of the length, colours.
type Look = {
	shell: boolean,
	L: number,
	d: number,
	case: number,
	caseColor: Color3,
	bullet: Color3,
	spent: Color3,
}

local function cartridge(pr: Proj, parent: Instance, look: Look, spent: boolean, zindex: number): Piece
	local Fl = G.flat
	local L, d = look.L, look.d
	local p = newPiece(pr, parent, -L, 0, d, zindex)
	local caseColor = if spent then look.spent else look.caseColor
	local rimColor = caseColor:Lerp(Color3.new(), 0.25)
	if look.shell then
		local head = L * Fl.shellHead
		shape(p, -L, -head, -d * Fl.body / 2, d * Fl.body / 2, if spent then look.spent else look.bullet)
		shape(p, -head, 0, -d * Fl.body / 2, d * Fl.body / 2, look.caseColor, { z = 2 })
		shape(p, -d * Fl.rim, 0, -d / 2, d / 2, rimColor, { z = 3 })
		return p
	end
	local caseLen = L * look.case
	if not spent then
		-- (the bullet's back half tucked under the case's mouth: only its rounded nose shows)
		local tuck = d * Fl.nose
		shape(p, -L, -caseLen + tuck, -d * Fl.nose / 2, d * Fl.nose / 2, look.bullet, { round = true })
	end
	shape(p, -caseLen, -d * Fl.rim, -d * Fl.body / 2, d * Fl.body / 2, caseColor, { z = 2 })
	shape(p, -d * Fl.rim, 0, -d / 2, d / 2, rimColor, { z = 3 })
	return p
end

type Fly = { piece: Piece, from: CFrame, start: number, time: number, kind: string, size: number }

type Mag = { piece: Piece, at: CFrame, enbloc: boolean }

type View = {
	tool: Tool,
	weapon: string,
	gun: BasePart,
	pr: Proj,
	layer: Frame, -- the clear pieces
	look: Look,
	dia: number, -- a round's width (studs)
	-- the bolt
	boltPiece: Piece, -- about its face
	handle: { stem: Frame, knob: Frame, pivot: Vector3, at: Vector3, width: number, knobSize: number }?, -- (rest)
	boltRestCF: CFrame,
	bolt: BasePart?,
	boltRest: number, -- its z at rest
	travel: number,
	-- the magazine
	rounds: { Piece },
	held: { Piece }, -- a stripper clip's rounds coming down
	strip: Piece?,
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
	mag: { Mag }, -- what moves with the gun's rounds (a box's well, an en-bloc clip), at rest
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
	cycleAt: number?, -- a semi-automatic: when the display's own cycle after a shot began (clock)
	wasAway: boolean, -- a box swap: the old box has gone out
	length: number, -- a round's length (studs)
	last: number, -- the last frame's clock
}

local panel: HudKit.Panel? = nil
local current: View? = nil

local function roundTemplate(weapon: string): Model?
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, name in HudCfg.Rounds[weapon] or HudCfg.Round do
		f = f and f:FindFirstChild(name)
	end
	return if f and f:IsA("Model") then f else nil
end

-- the canvas's own size (its spec size inside the Gun panel's, before the HUD's UIScale)
local function canvasSize(canvas: GuiObject): (number, number)
	local parent = canvas.Parent :: GuiObject
	local ps, cs = parent.Size, canvas.Size
	return ps.X.Offset * cs.X.Scale + cs.X.Offset, ps.Y.Offset * cs.Y.Scale + cs.Y.Offset
end

local function destroy(v: View)
	v.layer:Destroy()
end

local function build(tool: Tool, weapon: string, gun: BasePart, canvas: Frame): View
	local w = W[weapon]
	local s = w.scale
	local own = G.weapons[weapon] :: any
	local cw, chh = canvasSize(canvas)
	local pr: Proj = { k = 1, cz = 0, cy = 0, w = cw, h = chh }
	local layer = Instance.new("Frame")
	layer.Name = "Clear"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 2
	layer.Parent = canvas

	local v = {
		tool = tool,
		weapon = weapon,
		gun = gun,
		pr = pr,
		layer = layer,
		dia = 0,
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
		chamber = CFrame.identity,
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
	} :: any

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

	-- the round (and the spent case) as drawn: its length, width and the case's share from the round's own model
	local parts = w.parts :: any
	local L = G.fallback.length
	local d = G.fallback.width
	local caseShare = G.flat.case
	local carrier = CFrame.identity -- a pump gun's shell on the carrier at rest (its head, gun space)
	local caseColor = rgb(parts.Rounds or { 196, 160, 84 })
	local bulletColor = rgb(parts.Bullets or { 184, 115, 72 })
	local spentColor = rgb(parts.Casing or parts.Rounds or { 196, 160, 84 }):Lerp(Color3.new(), 0.18)
	if v.tube then
		-- a pump gun: its own shell (the one on the carrier), head at its pivot
		local first = part((w.feed and w.feed.parts or {})[1] or "")
		if first then
			local pivot = (w.moving :: any)[first.Name]
			carrier = CFrame.new(pivot[1] * s[1], pivot[2] * s[2], pivot[3] * s[3])
			L = first.Size.Z
			d = first.Size.Y
			bulletColor = first.Color -- (the hull)
			spentColor = first.Color:Lerp(Color3.new(), G.spentShade)
		end
	else
		local t = roundTemplate(weapon)
		local origin = t and t:FindFirstChild("Origin")
		local case, bullet = t and t:FindFirstChild("Case"), t and t:FindFirstChild("Bullet")
		if t and origin and case and bullet and case:IsA("BasePart") and bullet:IsA("BasePart") then
			local o = (origin :: BasePart).CFrame
			-- (head to tip: a pistol's bullet sits deep in its case)
			local tip = bullet.CFrame * CFrame.new(0, 0, -bullet.Size.Z / 2)
			L = (o.Position - tip.Position).Magnitude * s[3]
			d = case.Size.X * s[1]
			local caseBox = grow(nil, o:ToObjectSpace(case.CFrame), case.Size)
			caseShare = math.clamp(-caseBox.lo.Z * s[3] / math.max(L, 1e-4), 0.4, 0.9)
		else
			-- not in the library yet: the gun's own spent case stands in
			local c = part("Casing")
			if c then
				L, d = c.Size.Z, c.Size.X
			end
		end
	end
	v.length, v.dia = L, d
	local look: Look = {
		shell = v.tube,
		L = L,
		d = d,
		case = caseShare,
		caseColor = caseColor,
		bullet = bulletColor,
		spent = spentColor,
	}
	v.look = look
	local function newLive(zindex: number?): Piece
		return cartridge(pr, layer, look, false, zindex or Z.round)
	end
	v.live, v.feed = newLive(Z.chamber), newLive(Z.chamber)
	v.case = cartridge(pr, layer, look, true, Z.chamber)

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

	-- the bolt: a round body from the face back toward the gun's bolt's rear, the lugs at the face, the cocking piece
	local B = G.bolt
	local rear = if bolt then v.boltRest + bolt.Size.Z / 2 else ch.Z + L
	local full = math.max(rear - ch.Z, L / 2)
	local bodyLen = full * B.body
	local radius = d * B.radius
	local boltColor, steel = HudKit.rgb("bolt"), HudKit.rgb("steel")
	local bp = newPiece(pr, layer, 0, full, radius * 2 * math.max(B.lug, 1), Z.bolt)
	shape(bp, 0, bodyLen, -radius, radius, boltColor)
	shape(bp, bodyLen, full, -radius * B.cock, radius * B.cock, steel)
	shape(bp, 0, d * B.lugLength, -radius * B.lug, radius * B.lug, steel, { z = 2 })
	-- (a flat highlight along its top)
	shape(
		bp,
		d * B.lugLength,
		bodyLen * 0.94,
		radius * 0.3,
		radius * 0.62,
		boltColor:Lerp(Color3.new(1, 1, 1), 0.35),
		{ line = false, z = 2 }
	)
	v.boltPiece = bp
	-- its handle, out to the gun's own knob (gun space at rest), on the bolt's axis at the knob
	local knob = w.reload and (w.reload :: any).knob
	if bolt and knob and math.abs(knob[1]) > B.side then
		local kat = Vector3.new(knob[1] * s[1], knob[2] * s[2], knob[3] * s[3])
		local stem = Instance.new("Frame")
		stem.Name = "Handle"
		stem.AnchorPoint = Vector2.new(0.5, 0.5)
		stem.BorderSizePixel = 0
		stem.BackgroundColor3 = boltColor
		stem.ZIndex = Z.handle
		ink(stem)
		stem.Parent = layer
		local ball = Instance.new("Frame")
		ball.Name = "Knob"
		ball.AnchorPoint = Vector2.new(0.5, 0.5)
		ball.BorderSizePixel = 0
		ball.BackgroundColor3 = boltColor
		ball.ZIndex = Z.handle
		roundCorners(ball)
		ink(ball)
		ball.Parent = layer
		v.handle = {
			stem = stem,
			knob = ball,
			pivot = Vector3.new(ch.X, ch.Y, kat.Z),
			at = kat,
			width = d * B.stem,
			knobSize = d * B.knob,
		}
	end
	-- the gun's body: the receiver from the chamber's front back past the bolt fully back, the barrel ahead of it
	local Bd = G.body
	local front = ch.Z - L * Bd.ahead
	local back = rear + v.travel + d * Bd.behind
	local hr = d * Bd.receiver / 2
	local breech = -L - d * Bd.breech
	local body = newPiece(pr, layer, front - ch.Z, back - ch.Z, 2 * hr, Z.body)
	local dark = HudKit.rgb("shadow")
	shape(body, breech, back - ch.Z, -hr, hr, dark, { see = Bd.see })
	local barrel = shape(body, front - ch.Z, breech, -d * Bd.barrel / 2, d * Bd.barrel / 2, dark, { see = Bd.see })
	local toMuzzle = Instance.new("UIGradient")
	toMuzzle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1 - Bd.fade, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	toMuzzle.Parent = barrel
	local still: { { piece: Piece, at: CFrame } } = { { piece = body, at = CFrame.new(ch) } } -- (placed once framed)
	-- (framed tight round the body, the handle's knob as far as the bolt turns either way, and the well)
	local box: Box = { lo = Vector3.new(0, ch.Y - hr, front), hi = Vector3.new(0, ch.Y + hr, back) }
	local hd = v.handle
	if hd then
		local turn = math.rad(math.abs(w.action.turn or 0))
		local off = hd.at - hd.pivot
		for i = -4, 4 do
			local a = turn * i / 4
			local y = ch.Y + off.Y * math.cos(a) + off.X * math.sin(a)
			box.lo = box.lo:Min(Vector3.new(0, y - hd.knobSize / 2, hd.at.Z))
			box.hi = box.hi:Max(Vector3.new(0, y + hd.knobSize / 2, hd.at.Z + v.travel))
		end
	end

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

	-- the magazine well: an open box seen side on (its floor and ends, the inside a dark see-through fill); a box
	-- magazine's moves with the gun's rounds, a fixed well's stays
	local moves = w.ammo.clip == "Box"
	if wellLo and wellHi then
		local lo, hi = wellLo :: Vector3, wellHi :: Vector3
		local t = d * Wl.wall
		local mid = (lo + hi) / 2
		local span = hi - lo
		local hz, hy = span.Z / 2, span.Y / 2
		local wp = newPiece(pr, layer, -hz - t, hz + t, span.Y + 2 * t, Z.well)
		local edge = HudKit.rgb("wellEdge")
		shape(wp, -hz, hz, -hy, hy, HudKit.rgb("well"), { see = Wl.see, line = false })
		shape(wp, -hz - t, -hz, -hy - t, hy, edge)
		shape(wp, hz, hz + t, -hy - t, hy, edge)
		shape(wp, -hz - t, hz + t, -hy - t, -hy, edge)
		local atRest = CFrame.new(mid)
		table.insert(still, { piece = wp, at = atRest })
		if moves then
			table.insert(v.mag, { piece = wp, at = atRest, enbloc = false })
		end
		box = grow(box, atRest, span + Vector3.new(2, 2, 2) * t)
	end
	-- an en-bloc clip: a plate behind its rounds, coming in and dropping out with them
	if w.ammo.clip == "Enbloc" and wellLo then
		local hgt = v.pitch * (cap - 1) + d
		local plate = newPiece(pr, layer, -L / 2, L / 2, hgt, Z.clip)
		shape(plate, -L / 2, L / 2, -hgt / 2, hgt / 2, HudKit.rgb("clip"), { see = 0.25 })
		local top = v.slot(1, 1, 1)
		table.insert(
			v.mag,
			{ piece = plate, at = CFrame.new(top.X, top.Y + d / 2 - hgt / 2, top.Z - L / 2), enbloc = true }
		)
	end
	-- a stripper clip's rounds coming down into the well, on their strip
	if w.ammo.clip == "Stripper" then
		for _ = 1, (w.ammo :: any).clipSize or cap do
			table.insert(v.held, newLive())
		end
		local S = G.strip
		local th = d * S.thick
		local strip = newPiece(pr, layer, -th / 2, th / 2, 1, Z.clip)
		shape(strip, -th / 2, th / 2, -0.5, 0.5, HudKit.rgb("clip"))
		v.strip = strip -- (its rounds come down from over the canvas's top: they aren't framed)
	end
	-- the framing: the box side on, fitted to the canvas
	local m = G.margin
	pr.cz, pr.cy = (box.lo.Z + box.hi.Z) / 2, (box.lo.Y + box.hi.Y) / 2
	pr.k = math.min(
		pr.w * (1 - 2 * m) / math.max(box.hi.Z - box.lo.Z, 1e-3),
		pr.h * (1 - 2 * m) / math.max(box.hi.Y - box.lo.Y, 1e-3)
	)
	for _, q in still do
		place(q.piece, q.at)
	end
	return v :: View
end

-- the stack's slot k of the magazine in gun space, moving with the gun's own rounds (a clip coming in, a box
-- swapped)
local function slotCF(v: View, k: number, count: number, i: number): CFrame
	local at0 = v.slot(k, count, i)
	if v.follow then
		local now = v.gun.CFrame:ToObjectSpace(v.follow.CFrame)
		return now * v.followRest:Inverse() * at0
	end
	return at0
end

local function throw(v: View, which: Piece, from: CFrame, kind: string, now: number, size: number)
	local p = copy(which)
	p.frame.ZIndex = Z.flying
	table.insert(v.flying, {
		piece = p,
		from = from,
		start = now,
		time = if kind == "clip" then G.drop.time else G.fly.time,
		kind = kind,
		size = size,
	})
end

local function update(v: View, state: F.State, gun: F.Gun, now: number, clock: number)
	local pr = v.pr
	-- a semi-automatic's shot (the state has already put the next round in the chamber, or held the bolt open): the
	-- chamber holds the fired case until the bolt opens, and the display plays its own cycle
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
	place(v.boltPiece, v.chamber * CFrame.new(0, 0, d))
	local h = v.handle
	if h then
		-- (moved exactly as the gun's bolt: turned about its axis, slid back; side on, the knob swings up)
		local move = boltNow * v.boltRestCF:Inverse()
		local pivot, knobAt = move:PointToWorldSpace(h.pivot), move:PointToWorldSpace(h.at)
		bar(pr, h.stem, pivot, knobAt, h.width * pr.k)
		local kx, ky = at(pr, knobAt)
		put(pr, h.knob, kx, ky, h.knobSize * pr.k, h.knobSize * pr.k, 0)
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
	-- a stripper clip's rounds being pushed down out of it (the gun's "HeldRounds" seated in the guides, its "Drop" how
	-- far down they are): through a clip reload the stack shows the rounds already in and takes the clip's one by one
	-- as they go down (user 2026-10-29, the C96: "the rounds just jump to full instead of going in with the clip")
	local held = v.tool:FindFirstChild("HeldRounds")
	local drop = if held and held:IsA("BasePart") and held.Transparency < 1 then held:GetAttribute("Drop") else nil
	local pushing = typeof(drop) == "number" and open
	if v.strip and busy and not state.load then
		v.allow = v.allow or v.shown
	else
		v.allow = nil
	end
	local pushed, push = 0, 0 -- (rounds of the clip in, and how far the next one is on its way: 0..1)
	if pushing and v.allow then
		if not v.wasPushing then
			v.pushN = math.min(#v.held, #v.rounds - (v.allow :: number))
		end
		local k = math.clamp(drop :: number, 0, 1) * v.pushN
		pushed = math.min(math.floor(k), v.pushN)
		push = if pushed < v.pushN then k - pushed else 0
	elseif v.wasPushing and v.allow then
		v.allow = (v.allow :: number) + v.pushN -- (the clip's rounds all in)
	end
	local feedingClip = pushing or v.wasPushing -- (rounds pushed in move the stack down a slot each, no settling)
	v.wasPushing = pushing
	if v.allow then
		count = math.min(count, v.allow :: number + pushed)
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
			local fedAt = v.chamber * CFrame.new(0, 0, d)
			local top = slotCF(v, 1, count + 1, 1)
			if v.tube then
				-- a pump gun's shell rides up onto the carrier as the bolt comes forward
				local u = smooth(1 - d / math.max(v.maxD * G.tubeFeed, 1e-3))
				place(v.feed, CFrame.new(fedAt.X, top.Y + (fedAt.Y - top.Y) * u, fedAt.Z) * fedAt.Rotation)
			else
				-- its head on the bolt's face, rising to the chamber's line as the face goes from the stack's heads to
				-- the chamber, nose up on the way
				local u = math.clamp((v.headZ - fedAt.Z) / math.max(v.headZ - v.chamber.Z, 1e-3), 0, 1)
				feeding = u
				u = smooth(u)
				local p = top.Position:Lerp(fedAt.Position, u)
				place(
					v.feed,
					CFrame.new(p.X, p.Y, fedAt.Z) * CFrame.Angles(math.rad(G.feed.tilt) * math.sin(u * math.pi), 0, 0)
				)
			end
		else
			hide(v.feed)
		end
	end

	-- the stack
	if count ~= v.shown and feedingClip and count > v.shown then
		v.shown = count -- (the round coming down out of the clip is already where it goes: the stack stays put)
	elseif count ~= v.shown then
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
	local lift = v.lift + push -- (a clip's round going in pushes the stack down under it)
	if open and v.fed and v.pending and not v.tube then
		-- (still a round down until the fed round clears it)
		lift = math.max(lift, 1 - math.min(1, feeding * G.feed.clear))
	end
	for i, r in v.rounds do
		if i <= count then
			-- rounds rising (a round fed) start a slot lower; rounds pushed in start above; a double stack's far
			-- column darker, behind the near one
			local cf = slotCF(v, i + lift, count, i)
			local far = cf.X < v.midX - 1e-4
			tint(r, if far then G.flat.far else 0)
			r.frame.ZIndex = if far then Z.far else Z.round
			place(r, cf)
		else
			hide(r)
		end
	end
	-- a stripper clip's rounds still on their strip, in the guides over the well: a round apart, the lowest a round over
	-- the stack's top, coming down into it one by one; the strip stays where it was seated
	local strip = v.strip
	if strip then
		local left = if pushing then v.pushN - pushed else 0
		if left > 0 then
			local x, step = v.midX, v.dia
			local topY = slotCF(v, 1 + lift, count, 1).Y -- (the stack's top round, drawn)
			-- (the lowest goes from a round over the top round to the top slot as the stack goes down a slot under it,
			-- over to its side of the stagger)
			local nextX = slotCF(v, 1, count + 1, 1).X
			for i, r in v.held do
				if i <= left then
					local y = topY + (i - push) * step + push * v.pitch
					place(r, CFrame.new(if i == 1 then x + (nextX - x) * push else x, y, v.headZ))
				else
					hide(r)
				end
			end
			local seat = slotCF(v, 1, count, 1).Y -- (the strip: over the full well, as it was seated)
			strip.h = (v.pushN - 1) * step + v.dia * G.strip.width
			place(strip, CFrame.new(x, seat + (v.pushN + 1) / 2 * step, v.headZ + strip.z1))
		else
			for _, r in v.held do
				hide(r)
			end
			hide(strip)
		end
	end

	local delta = if follow then v.gun.CFrame:ToObjectSpace(follow.CFrame) * v.followRest:Inverse() else CFrame.identity
	local away = (gun.clip == "Enbloc" or gun.clip == "Box") and not visible

	-- what moves with the gun's rounds (a box's well, an en-bloc clip): gone while out of the gun; an empty en-bloc
	-- clip drops out of the bottom as its last round goes up
	local clipGone = gun.clip == "Enbloc" and count == 0
	for _, m in v.mag do
		if away or (clipGone and m.enbloc) then
			hide(m.piece)
		else
			place(m.piece, delta * m.at)
		end
	end
	if gun.clip == "Enbloc" then
		local plate = nil
		for _, m in v.mag do
			if m.enbloc then
				plate = m
			end
		end
		local there = not away and count > 0
		if plate and v.clipWas and not there then
			place(plate.piece, delta * plate.at)
			throw(v, plate.piece, delta * plate.at, "clip", clock, plate.piece.h)
			hide(plate.piece)
		end
		v.clipWas = there
	end

	-- what's flying: cases thrown up and back, spinning; clips falling
	for i = #v.flying, 1, -1 do
		local f = v.flying[i]
		local u = (clock - f.start) / f.time
		if u >= 1 then
			f.piece.frame:Destroy()
			table.remove(v.flying, i)
			continue
		end
		local gone = math.clamp((u - G.fade) / (1 - G.fade), 0, 1)
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
		place(f.piece, cf, gone)
	end
end

-- ---- a revolver (ammo.clip "Gate" or "BreakOpen": the Nagant, the Webley): its cylinder seen from behind, flat: a
-- disc with a hole per chamber and a live round's head in each loaded one, following the gun's own rounds every frame
-- (src/client/GunFx turns them and shows a chamber's round while it is live), so it turns on each shot and fills
-- chamber by chamber on a load ----
type Chamber = { source: BasePart, hole: Frame, head: Frame }
type Drum = {
	tool: Tool,
	gun: BasePart,
	cyl: BasePart?,
	group: Frame,
	chambers: { Chamber },
	k: number,
	w: number,
	h: number,
}
local drum: Drum? = nil

local function circle(parent: Instance, color: Color3, zindex: number, outlined: boolean): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.ZIndex = zindex
	roundCorners(f)
	if outlined then
		ink(f)
	end
	f.Parent = parent
	return f
end

local function buildDrum(tool: Tool, weapon: string, gun: BasePart, canvas: Frame): Drum
	local w = W[weapon]
	local rv = w.revolver :: any
	local D = G.drum
	local cw, chh = canvasSize(canvas)
	local group = Instance.new("Frame")
	group.Name = "Drum"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.Parent = canvas
	local cylPart = tool:FindFirstChild(rv.turns[1])
	local cyl = if cylPart and cylPart:IsA("BasePart") then cylPart else nil
	local centre = if cyl then gun.CFrame:ToObjectSpace(cyl.CFrame).Position else Vector3.zero
	local sources: { BasePart } = {}
	local reach, dia = 0, G.fallback.width
	for _, name in rv.rounds do
		local p = tool:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			table.insert(sources, p)
			local rel = gun.CFrame:ToObjectSpace(p.CFrame).Position - centre
			reach += Vector2.new(rel.X, rel.Y).Magnitude
			local dims = { p.Size.X, p.Size.Y, p.Size.Z }
			table.sort(dims)
			dia = dims[2]
		end
	end
	reach = if #sources > 0 then reach / #sources else dia * 2
	local radius = reach + dia * 0.8
	local k = chh * D.fill / (2 * radius)
	local disc = circle(group, HudKit.rgb("bolt"), 1, true)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(2 * radius * k / cw, 2 * radius * k / chh)
	local hub = circle(group, HudKit.rgb("steel"), 2, true)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromScale(dia * 0.7 * k / cw, dia * 0.7 * k / chh)
	local parts = w.parts :: any
	local brass = rgb(parts.Rounds or { 196, 160, 84 })
	local chambers = {}
	for _, src in sources do
		local hole = circle(group, HudKit.rgb("chamberHole"), 2, true)
		hole.Size = UDim2.fromScale(dia * D.hole * k / cw, dia * D.hole * k / chh)
		local head = circle(hole, brass, 3, true)
		head.Position = UDim2.fromScale(0.5, 0.5)
		head.Size = UDim2.fromScale(0.86, 0.86)
		local primer = circle(head, brass:Lerp(Color3.new(), 0.3), 4, false)
		primer.Position = UDim2.fromScale(0.5, 0.5)
		primer.Size = UDim2.fromScale(D.primer, D.primer)
		table.insert(chambers, { source = src, hole = hole, head = head })
	end
	return { tool = tool, gun = gun, cyl = cyl, group = group, chambers = chambers, k = k, w = cw, h = chh }
end

local function updateDrum(dr: Drum)
	local centre = if dr.cyl then dr.gun.CFrame:ToObjectSpace(dr.cyl.CFrame).Position else Vector3.zero
	for _, c in dr.chambers do
		-- (from behind: the gun's +X to the right, +Y up)
		local rel = dr.gun.CFrame:ToObjectSpace(c.source.CFrame).Position - centre
		c.hole.Position = UDim2.fromScale(0.5 + rel.X * dr.k / dr.w, 0.5 - rel.Y * dr.k / dr.h)
		c.head.Visible = c.source.Transparency < 1
	end
end

function AmmoHud.start()
	panel = HudKit.panel("Gun", "AmmoHud", true) -- (the HUD size setting scales it)
	local words = panel.node.HintText :: TextLabel
	words.RichText = true
end

-- a hint as shown: its key ("Click", "R") as a red chip, then what it does (UI overhaul, user 2026-10-30)
local function chip(hint: string): string
	local key, rest = hint:match("^(.-):%s*(.*)$")
	if not key or key == "" then
		return hint
	end
	local back, fore = HudKit.rgb("hintKey"):ToHex(), HudKit.rgb("hintKeyText"):ToHex()
	return `<mark color="#{back}" transparency="0"><font color="#{fore}" size="13"> {string.upper(key)} </font></mark>  {rest}`
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
		if drum then
			drum.group:Destroy()
			drum = nil
		end
		return
	end
	p.gui.Enabled = true
	-- the rounds as a number under the display (review 2026-11-12), RELOAD in red once none is left
	local left = F.magazineAt(state, now) + (if state.chambered then 1 else 0)
	p.set("ammo", if left > 0 then tostring(left) else "RELOAD")
	local count = p.node.AmmoCount :: TextLabel
	count.TextColor3 = HudKit.rgb(if left > 0 then "readout" else "countLow")
	local canvas = p.node.GunCanvas :: Frame
	if drum and (drum.tool ~= tool or not F.revolver(gun)) then
		drum.group:Destroy()
		drum = nil
	end
	if F.revolver(gun) then -- a revolver: its cylinder
		if current then
			destroy(current)
			current = nil
		end
		if not drum then
			drum = buildDrum(tool, weapon, body, canvas)
		end
		updateDrum(drum :: Drum)
		local next = F.next(state, now)
		local hint = if next == "Load"
			then G.hints.Load
			elseif next == "Dry" then (G.hints.Rounds:gsub("{key}", tostring(Settings.get("Key_Reload"))))
			else ""
		p.set("hint", chip(hint))
		p.node.Hint.Visible = hint ~= ""
		return
	end
	if current and current.tool ~= tool then
		destroy(current)
		current = nil
	end
	if not current then
		current = build(tool, weapon, body, canvas)
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
	p.set("hint", chip((hint:gsub("{key}", tostring(key)))))
	p.node.Hint.Visible = hint ~= ""
end

return AmmoHud
