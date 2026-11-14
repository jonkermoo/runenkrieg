--!strict
-- The gun crew's panel, quartermaster's brass (Config/Hud.Artillery; layout src/shared/ui/CombatHud.json
-- "Artillery"; user 2026-10-26: "similar chamber concept for the field cannon and similar crystal concept for the
-- artillery"). Shown while I'm on a gun (its "Gunner" is me), bottom right:
-- - a cut-away drawn live in a ViewportFrame: the whole gun copied, posed every frame as src/client/Artillery poses
--   it (a gun with a drawing is drawn flat instead: Config/HudArt, `Flat` below), every part as see-through as the next (user 2026-10-26: "make it general transparency, i should be able to see
--   the inside of the gun (besides the round and the crystal)"), seen from the gun's mount (so the barrel's elevation and
--   recoil show, and the breech swinging open); the field gun's round (Config/Artillery.Load.round) sits in its
--   chamber, slides in as the loader puts it in (Load.loaded), and the fired case is thrown out as the breech opens;
--   the howitzer's crystal is the 3D gem (src/client/HudKit.gem, the staff's: user 2026-10-26, "replace the howizer
--   gem with the same 3d gem we are making"), its shards floating round it, dying out toward grey until it can fire;
-- - how far the reload has got, a plain percentage in tenths (nothing once it can fire); no panel or background, at the
--   bottom right like the gun's;
-- - why it can't fire, in the bottom centre (user 2026-11-02: "put the warning more center bottom/top of the screen so
--   players know"): while it is laid on a spawn (its Config/Artillery.SpawnGuard `attribute`), and a refused shot's
--   reason a moment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery)
local HudCfg = require(Shared.Config.Hud)
local GunArt = require(Shared.Config.GunArt)
local HudArt = require(Shared.Config.HudArt)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Artillery)
local Net = require(Shared.Net)
local HudKit = require(script.Parent.HudKit)

local ArtilleryHud = {}

local A = HudCfg.Artillery

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function template(name: string): Model?
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, sub in { "Weapons", "Shared", "Artillery", name } do
		f = f and f:FindFirstChild(sub)
	end
	return if f and f:IsA("Model") then f else nil
end

local function anchored(p: BasePart)
	p:ClearAllChildren()
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
end

type Piece = { parts: { { part: BasePart, rel: CFrame } }, model: Model }

local function place(p: Piece, cf: CFrame, transparency: number)
	for _, q in p.parts do
		q.part.CFrame = cf * q.rel
		q.part.Transparency = transparency
	end
end

type Throw = { piece: Piece, from: CFrame, start: number }

-- The gun drawn flat (Config/HudArt, Config/Hud.Artillery.flat; user 2026-11-12: "cutaway drawing ... accurate to our
-- actual model asset"): the field gun's breech side on from its right, the muzzle to the right, each drawing laid where
-- its part is in the mount's space (the cradle and the barrel elevate, the barrel recoils, the breech block swings
-- through its frames, the round slides in, the fired case is thrown out); the machine gun the same way, each round on
-- its belt following its own part; the howitzer's crystal in the brass ring.
type Sprite = { img: ImageLabel, z: { number }, y: { number } }
type Flat = {
	layer: Frame,
	kx: number, -- the layer's width, and its height, per stud
	ky: number,
	cz: number, -- gun space at the layer's middle
	cy: number,
	cradle: Sprite?,
	cradlePart: BasePart?,
	cradleRest: CFrame,
	barrel: Sprite?,
	breech: Sprite?,
	frames: { { number } },
	frame: number,
	round: Sprite?,
	case: Sprite?,
	gem: HudKit.GemArt?,
	belt: { { sprite: Sprite, part: BasePart, rest: CFrame } }, -- a machine gun's rounds on the belt
	throws: { { sprite: Sprite, from: CFrame, start: number } },
}

local function lay(f: Flat, sp: Sprite, cf: CFrame, transparency: number)
	local c = cf:PointToWorldSpace(Vector3.new(0, (sp.y[1] + sp.y[2]) / 2, (sp.z[1] + sp.z[2]) / 2))
	local look = cf.LookVector
	sp.img.Position = UDim2.fromScale(0.5 + (f.cz - c.Z) * f.kx, 0.5 + (f.cy - c.Y) * f.ky)
	sp.img.Size = UDim2.fromScale((sp.z[2] - sp.z[1]) * f.kx, (sp.y[2] - sp.y[1]) * f.ky)
	sp.img.Rotation = math.deg(math.atan2(-look.Y, -look.Z))
	sp.img.ImageTransparency = transparency
	sp.img.Visible = transparency < 1
end

type View = {
	flat: Flat?,
	model: Model,
	gun: any,
	cut: Model,
	copies: { [BasePart]: { part: BasePart, see: number } },
	mount: BasePart?,
	mountRest: CFrame, -- the mount at rest, gun space (from the library's model)
	barrel: BasePart?,
	barrelRest: CFrame,
	chamber: CFrame, -- gun space at rest: the round's case head in the chamber
	round: Piece?,
	case: Piece?,
	length: number,
	thrownFor: number, -- the shot whose case has been thrown out
	gem: HudKit.Gem?, -- the 3D gem in the howitzer's crystal's place
	gemAnchor: BasePart?, -- (the gun's own crystal's copy, hidden: where the gem sits)
	gemTurn: CFrame,
	from: Vector3, -- the camera's side of the crystal (gun space), and how far off
	dist: number,
	throws: { Throw },
}

local function destroy(v: View)
	if v.flat then
		v.flat.layer:Destroy()
	end
	v.cut:Destroy()
end

local function build(model: Model, view: ViewportFrame, camera: Camera): View?
	local key = model:GetAttribute("Gun") :: string?
	local gun = key and (Cfg.Guns :: any)[key]
	if not gun then
		return nil
	end
	local t = template(gun.asset)
	local cut = Instance.new("Model")
	cut.Name = "Cutaway"
	local v: View = {
		flat = nil,
		model = model,
		gun = gun,
		cut = cut,
		copies = {},
		mount = nil,
		mountRest = CFrame.identity,
		barrel = nil,
		barrelRest = CFrame.identity,
		chamber = CFrame.new(0, gun.hinge[2], gun.hinge[3] - A.chamberBack),
		round = nil,
		case = nil,
		length = 1,
		thrownFor = -math.huge,
		gem = nil,
		gemAnchor = nil,
		gemTurn = CFrame.identity,
		from = Vector3.zAxis,
		dist = 1,
		throws = {},
	}
	local function rest(name: string): CFrame?
		local p = t and t:FindFirstChild(name, true)
		return if p and p:IsA("BasePart") then (t :: Model):GetPivot():ToObjectSpace(p.CFrame) else nil
	end
	v.mount = model:FindFirstChild(gun.mount[1], true) :: BasePart?
	v.mountRest = rest(gun.mount[1]) or CFrame.identity
	v.barrel = model:FindFirstChild(gun.barrel[1], true) :: BasePart?
	v.barrelRest = rest(gun.barrel[1]) or CFrame.identity

	-- the gun's own breech parts
	-- drawn flat where there is a drawing for it (the field gun; the howitzer's crystal in its ring)
	local F = A.flat
	local schemes = HudArt.guns[gun.asset]
	local crystal = model:FindFirstChild(A.solid[1], true)
	if schemes or (crystal and not gun.breechOpens) then
		local parent = view.Parent :: GuiObject
		local layer = Instance.new("Frame")
		layer.Name = "Flat"
		layer.BackgroundTransparency = 1
		layer.Position, layer.Size, layer.ZIndex = view.Position, view.Size, view.ZIndex
		layer.ClipsDescendants = true
		layer.Parent = parent
		local w = parent.Size.X.Offset * view.Size.X.Scale + view.Size.X.Offset
		local h = parent.Size.Y.Offset * view.Size.Y.Scale + view.Size.Y.Offset
		local f: Flat = {
			layer = layer,
			kx = 1,
			ky = 1,
			cz = 0,
			cy = 0,
			cradle = nil,
			cradlePart = nil,
			cradleRest = CFrame.identity,
			barrel = nil,
			breech = nil,
			frames = {},
			frame = 0,
			round = nil,
			case = nil,
			gem = nil,
			belt = {},
			throws = {},
		}
		if schemes then
			-- (the paint the gun wears: the nearest of the drawn ones to its carriage's colour)
			local carriage = model:FindFirstChild("Carriage", true)
			local worn = if carriage and carriage:IsA("BasePart") then carriage.Color else Color3.new()
			local art, best = nil, math.huge
			for name, sch in schemes do
				local c = rgb((Palette.Artillery :: any).Paint[name])
				local d = (Vector3.new(c.R, c.G, c.B) - Vector3.new(worn.R, worn.G, worn.B)).Magnitude
				if d < best then
					art, best = sch, d
				end
			end
			local sch = art :: HudArt.Scheme
			local function sprite(
				image: number,
				rect: { number }?,
				z: { number },
				y: { number },
				zindex: number
			): Sprite
				local img = Instance.new("ImageLabel")
				img.BackgroundTransparency = 1
				img.Image = `rbxassetid://{image}`
				if rect then
					img.ImageRectOffset = Vector2.new(rect[1], rect[2])
					img.ImageRectSize = Vector2.new(rect[3], rect[4])
				end
				img.AnchorPoint = Vector2.new(0.5, 0.5)
				img.ZIndex = zindex
				img.Parent = layer
				return { img = img, z = z, y = y }
			end
			-- the breech framed: from `reach.front` ahead of the chambered round's nose to `reach.back` behind the block
			-- (or as Config/Hud.Artillery.flat.frames has it: the machine gun)
			local len = HudArt.round.length
			local br = rest("Breech") or CFrame.new(gun.hinge[1], gun.hinge[2], gun.hinge[3])
			local zlo = v.chamber.Z - len - A.reach.front
			local zhi = br.Z + A.reach.back
			local cy = v.chamber.Y - F.drop
			local own = (F.frames :: any)[gun.asset]
			if own then
				zlo, zhi, cy = own.z[1], own.z[2], own.y
			end
			f.kx = 1 / (zhi - zlo)
			f.ky = f.kx * w / h
			f.cz, f.cy = (zlo + zhi) / 2, cy
			-- (behind it the gun card's brushed ink wash, Config/GunArt.wash)
			local wash = Instance.new("ImageLabel")
			wash.Name = "Wash"
			wash.BackgroundTransparency = 1
			wash.Image = `rbxassetid://{GunArt.wash}`
			wash.Size = UDim2.fromScale(1, 1)
			wash.ZIndex = 0
			wash.Parent = layer
			local still = sprite(sch.still.image, nil, sch.still.z, sch.still.y, 1)
			still.img.ImageColor3 = Color3.new(1, 1, 1):Lerp(Color3.new(), F.stillShade)
			lay(f, still, CFrame.identity, 0)
			f.cradle = sprite(sch.parts, sch.cradle.rect, sch.cradle.z, sch.cradle.y, 2)
			local cp = model:FindFirstChild("Cradle", true)
			f.cradlePart = if cp and cp:IsA("BasePart") then cp else nil
			f.cradleRest = rest("Cradle") or CFrame.identity
			f.barrel = sprite(sch.parts, sch.barrel.rect, sch.barrel.z, sch.barrel.y, 3)
			local shell, case, block = sch.round, sch.case, sch.breech
			if shell and case and block then
				f.round = sprite(sch.parts, shell.rect, shell.z, shell.y, 4)
				f.case = sprite(sch.parts, case.rect, case.z, case.y, 4)
				f.frames = block.frames
				f.breech = sprite(sch.parts, block.frames[1], block.z, block.y, 5)
				v.length = len
			end
			-- a machine gun's belt: each round's drawing follows its own part (src/client/Artillery bends the belt with
			-- the gun and empties it)
			for i, b in sch.belt or {} do
				local name = string.format("Rounds%02d", i)
				local part = model:FindFirstChild(name, true)
				local at = rest(name)
				if part and part:IsA("BasePart") and at then
					table.insert(f.belt, { sprite = sprite(sch.parts, b.rect, b.z, b.y, 4), part = part, rest = at })
				end
			end
		else
			local holder = Instance.new("Frame")
			holder.Name = "Crystal"
			holder.BackgroundTransparency = 1
			holder.AnchorPoint = Vector2.new(1, 0.5)
			holder.Position = UDim2.fromScale(1, 0.5)
			holder.Size = UDim2.fromScale(F.ring * h / w, F.ring)
			holder.Parent = layer
			f.gem = HudKit.gemArt(holder)
		end
		v.flat = f
		view.Visible = false
		return v
	end
	view.Visible = true

	local box: { lo: Vector3, hi: Vector3 }? = nil
	local function grow(cf: CFrame, size: Vector3)
		local h = size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local p = cf:PointToWorldSpace(h * Vector3.new(x, y, z))
					box = if box then { lo = box.lo:Min(p), hi = box.hi:Max(p) } else { lo = p, hi = p }
				end
			end
		end
	end
	-- (a view may draw only some of the gun: the howitzer's, what moves with its barrel round the crystal)
	local o = (A.views :: any)[key] or A.views.default
	for _, d in model:GetDescendants() do
		local drawn = not o.only or table.find(o.only, d.Name) or table.find(A.solid, d.Name)
		if d:IsA("BasePart") and drawn and not table.find(A.skip, d.Name) then
			local c = d:Clone()
			anchored(c)
			c.Parent = cut
			v.copies[d] = { part = c, see = if table.find(A.solid, d.Name) then 0 else A.see }
		end
	end
	-- framed on the first of Hud.Artillery.frame the gun has (the howitzer's crystal, the field gun's breech)
	for _, name in A.frame do
		local r = rest(name)
		local p = model:FindFirstChild(name, true)
		if r and p and p:IsA("BasePart") then
			grow(r, p.Size)
			break
		end
	end
	-- the 3D gem in the gun's crystal's place (src/client/HudKit.gem), as long as it, pointing out of the breech face
	-- (gun +Z), turning with the barrel; the view takes in its shards
	for src, c in v.copies do
		local r = rest(src.Name)
		if src.Name == A.solid[1] and r then
			local s = src.Size
			v.gem = HudKit.gem(cut, math.max(s.X, s.Y, s.Z))
			v.gemAnchor = c.part
			v.gemTurn = r.Rotation:Inverse() * CFrame.Angles(math.pi / 2, 0, 0)
			if v.gem then
				grow(CFrame.new(r.Position), Vector3.one * math.max(v.gem.size.X, v.gem.size.Z))
			end
		end
	end
	-- the gun's own crystal hidden under it (shown, solid, if the gem's model isn't there)
	if v.gem then
		for src, c in v.copies do
			if table.find(A.solid, src.Name) then
				c.see = 1
			end
		end
	end

	-- the field gun's round, and its case for after the shot
	if gun.breechOpens then
		local rt = template(Cfg.Load.round)
		local origin = rt and rt:FindFirstChild("Origin")
		if rt and origin and origin:IsA("BasePart") then
			local function make(names: { string }?): Piece
				local m = Instance.new("Model")
				local parts = {}
				for _, d in rt:GetDescendants() do
					if d:IsA("BasePart") and d.Name ~= "Origin" and (not names or table.find(names, d.Name)) then
						local c = d:Clone()
						anchored(c)
						local col = (Palette.Artillery :: any)[d.Name]
						if col then
							c.Color = rgb(col)
						end
						c.Material = Enum.Material.SmoothPlastic
						c.Transparency = 1
						c.Parent = m
						table.insert(parts, { part = c, rel = origin.CFrame:ToObjectSpace(d.CFrame) })
					end
				end
				m.Parent = cut
				return { parts = parts, model = m }
			end
			v.round = make(nil)
			v.case = make({ "Case" })
			local _, size = rt:GetBoundingBox()
			v.length = math.max(size.X, size.Y, size.Z)
		end
		grow(v.chamber * CFrame.new(0, 0, -v.length / 2), Vector3.new(A.chamberWidth, A.chamberWidth, v.length))
	end
	if box and gun.breechOpens then
		-- reach behind the breech (the case thrown out, the round coming in) and in front of it
		local b = box :: any
		b.hi = b.hi + Vector3.new(0, 0, A.reach.back)
		b.lo = b.lo - Vector3.new(0, 0, A.reach.front)
	elseif not box then
		grow(v.chamber, Vector3.one * 2)
	end
	local b = box :: any
	local centre = CFrame.new((b.lo + b.hi) / 2)
	local size = b.hi - b.lo
	local from = Vector3.new(o.from[1], o.from[2], o.from[3]).Unit
	v.from = from
	local function frame()
		HudKit.frameBox(view, camera, centre, size, from, Vector3.yAxis, A.fov, A.margin)
		v.dist = (camera.CFrame.Position - centre.Position).Magnitude
	end
	frame()
	cut.Parent = view
	return v
end

local function update(v: View, t: number, clock: number, camera: Camera)
	-- gun space now: the mount's rest undone (it turns with the traverse; the view turns with it)
	local ref = if v.mount then v.mount.CFrame * v.mountRest:Inverse() else v.model:GetPivot()
	local f = v.flat
	if f then
		local readyAt = (v.model:GetAttribute("ReadyAt") :: number?) or -math.huge
		local gem = f.gem
		if gem then
			-- the howitzer's crystal: dying out toward grey until it can fire
			local share = Rules.loaded(t, readyAt, v.gun.reload)
			local S = HudCfg.Staff
			HudKit.poseGemArt(gem, clock, math.sin(clock * S.bob.speed * math.pi * 2) * S.bob.height, 1)
			HudKit.shineArt(gem, share, false, rgb((Palette.Artillery :: any)[A.solid[1]]), clock)
			return
		end
		local barrel = if v.barrel then ref:ToObjectSpace(v.barrel.CFrame) * v.barrelRest:Inverse() else CFrame.identity
		if f.cradle then
			local cp = f.cradlePart
			lay(f, f.cradle, if cp then ref:ToObjectSpace(cp.CFrame) * f.cradleRest:Inverse() else barrel, 0)
		end
		if f.barrel then
			lay(f, f.barrel, barrel, 0)
		end
		for _, b in f.belt do
			lay(
				f,
				b.sprite,
				ref:ToObjectSpace(b.part.CFrame) * b.rest:Inverse(),
				if b.part.Transparency >= 1 then 1 else 0
			)
		end
		local firedAt = (v.model:GetAttribute("FiredAt") :: number?) or -math.huge
		local breech = f.breech
		local open = if breech then Rules.breechAt(t, firedAt, readyAt, v.gun.breechTimes, Cfg.BreechSwing) else 0
		if breech then
			local i = math.clamp(math.round(open * (#f.frames - 1)) + 1, 1, #f.frames)
			if i ~= f.frame then
				f.frame = i
				local r = f.frames[i]
				breech.img.ImageRectOffset = Vector2.new(r[1], r[2])
				breech.img.ImageRectSize = Vector2.new(r[3], r[4])
			end
			lay(f, breech, barrel, 0)
		end
		local round, case = f.round, f.case
		if not round or not case then
			return
		end
		-- (the round as the 3D view has it: in the chamber, sliding in, or its fired case waiting to be thrown out)
		local seat = barrel * v.chamber
		local inAt = readyAt - Cfg.Load.lead + Cfg.Load.loaded
		local loaded = firedAt == -math.huge or t >= inAt
		if loaded then
			lay(f, round, seat, 0)
			lay(f, case, seat, 1)
		elseif t >= inAt - A.slide then
			lay(f, round, seat * CFrame.new(0, 0, v.length * (inAt - t) / A.slide), 0)
			lay(f, case, seat, 1)
		else
			lay(f, round, seat, 1)
			if open >= A.openAt and v.thrownFor ~= firedAt then
				v.thrownFor = firedAt
				local img = case.img:Clone()
				img.ZIndex = 6
				img.Parent = f.layer
				table.insert(f.throws, { sprite = { img = img, z = case.z, y = case.y }, from = seat, start = clock })
			end
			lay(f, case, seat, if v.thrownFor == firedAt then 1 else 0)
		end
		for i = #f.throws, 1, -1 do
			local th = f.throws[i]
			local u = (clock - th.start) / A.fly.time
			if u >= 1 then
				th.sprite.img:Destroy()
				table.remove(f.throws, i)
				continue
			end
			local cf = CFrame.new(0, A.fly.up * v.length * 4 * u * (1 - u), A.fly.back * v.length * u)
				* th.from
				* CFrame.Angles(u * A.fly.turns * math.pi * 2, 0, 0)
			lay(f, th.sprite, cf, math.clamp((u - A.fade) / (1 - A.fade), 0, 1))
		end
		return
	end
	for src, c in v.copies do
		c.part.CFrame = ref:ToObjectSpace(src.CFrame)
		c.part.Color = src.Color
		c.part.Material = src.Material
		c.part.Transparency = 1 - (1 - src.Transparency) * (1 - c.see)
	end
	if v.gem then
		local readyAt = (v.model:GetAttribute("ReadyAt") :: number?) or -math.huge
		local share = Rules.loaded(t, readyAt, v.gun.reload)
		local colors = {}
		for _, name in A.solid do
			table.insert(colors, rgb((Palette.Artillery :: any)[name]))
		end
		local anchor = v.gemAnchor :: BasePart
		HudKit.poseGem(v.gem, anchor.CFrame * v.gemTurn, clock)
		HudKit.shine(v.gem.crystal, share, false, colors, clock)
	end
	-- the camera on the crystal wherever the gun has laid it (elevation, recoil), as far off as framed (with or without
	-- the gem: user 2026-10-26, "make sure the howitzer camera is acttually aimmed at this")
	if v.gemAnchor then
		local at = v.gemAnchor.Position
		camera.CFrame = CFrame.lookAt(at + v.from * v.dist, at)
	end
	local round, case = v.round, v.case
	if not round or not case then
		return
	end
	local barrel = if v.barrel then ref:ToObjectSpace(v.barrel.CFrame) * v.barrelRest:Inverse() else CFrame.identity
	local seat = barrel * v.chamber
	local gun = v.gun
	local firedAt = (v.model:GetAttribute("FiredAt") :: number?) or -math.huge
	local readyAt = (v.model:GetAttribute("ReadyAt") :: number?) or -math.huge
	local inAt = readyAt - Cfg.Load.lead + Cfg.Load.loaded -- the round goes in
	local loaded = firedAt == -math.huge or t >= inAt -- (never fired: loaded as placed)
	local sliding = not loaded and t >= inAt - A.slide
	if loaded then
		place(round, seat, 0)
		place(case, seat, 1)
	elseif sliding then
		local u = 1 - (inAt - t) / A.slide
		place(round, seat * CFrame.new(0, 0, v.length * (1 - u)), 0)
		place(case, seat, 1)
	else
		place(round, seat, 1)
		-- the fired case, until the breech has swung open far enough to throw it out
		local open = Rules.breechAt(t, firedAt, readyAt, gun.breechTimes, Cfg.BreechSwing)
		if open >= A.openAt and v.thrownFor ~= firedAt then
			v.thrownFor = firedAt
			local m = Instance.new("Model")
			local parts = {}
			for _, q in case.parts do
				local c = q.part:Clone()
				c.Parent = m
				table.insert(parts, { part = c, rel = q.rel })
			end
			m.Parent = v.cut
			table.insert(v.throws, { piece = { parts = parts, model = m }, from = seat, start = clock })
		end
		place(case, seat, if v.thrownFor == firedAt then 1 else 0)
	end
	for i = #v.throws, 1, -1 do
		local th = v.throws[i]
		local u = (clock - th.start) / A.fly.time
		if u >= 1 then
			th.piece.model:Destroy()
			table.remove(v.throws, i)
			continue
		end
		local cf = CFrame.new(0, A.fly.up * v.length * 4 * u * (1 - u), A.fly.back * v.length * u)
			* th.from
			* CFrame.Angles(u * A.fly.turns * math.pi * 2, 0, 0)
		place(th.piece, cf, math.clamp((u - A.fade) / (1 - A.fade), 0, 1))
	end
end

function ArtilleryHud.start()
	local player = Players.LocalPlayer
	local panel = HudKit.panel("Artillery", "ArtilleryHud")
	local warn = HudKit.panel("ArtilleryWarn", "ArtilleryWarn")
	local view = panel.node.ArtilleryView :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.Parent = view
	view.CurrentCamera = camera
	local current: View? = nil
	-- a machine gun's count between the server's updates (Rules/Artillery.mgShown): the shots seen since its "Rounds"
	-- last changed, and when that was (server time)
	local counted: Model? = nil
	local seenRounds: number? = nil
	local roundsAt, shotsSince = 0, 0
	Net.event("MGShot").OnClientEvent:Connect(function(model: Model)
		if model == counted then
			shotsSince += 1
		end
	end)

	local function mine(): Model?
		local f = workspace:FindFirstChild(Cfg.Folder)
		if not f then
			return nil
		end
		for _, m in f:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Gunner") == player.UserId and m:GetAttribute("Broken") ~= true then
				return m
			end
		end
		return nil
	end

	-- a refused shot's reason (src/server/Artillery: a Normal match's own sector, a spawn), shown a moment
	local notice: { text: string, untilAt: number }? = nil
	Net.event("Artillery").OnClientEvent:Connect(function(kind: any, text: any)
		if kind == "Refused" and type(text) == "string" then
			notice = { text = text, untilAt = os.clock() + 2.5 }
		end
	end)

	RunService.RenderStepped:Connect(function()
		local model = mine()
		panel.gui.Enabled = model ~= nil
		local said = if notice and os.clock() < notice.untilAt then notice.text else nil
		if model and model:GetAttribute(Cfg.SpawnGuard.attribute) == true then
			said = Cfg.SpawnGuard.why
		end
		warn.gui.Enabled = said ~= nil
		warn.set("warn", said or "")
		if current and current.model ~= model then
			destroy(current)
			current = nil
		end
		if not model then
			return
		end
		if not current then
			current = build(model, view, camera)
		end
		local v = current
		if not v then
			return
		end
		local t = workspace:GetServerTimeNow()
		update(v, t, os.clock(), camera)

		-- how far the reload has got, in tenths of a percent, until it can fire again (user 2026-10-26: "a simple text
		-- timer that just displays the percentage until it can fire again(by tenths). no ready text, no bar")
		local readyAt = (model:GetAttribute("ReadyAt") :: number?) or -math.huge
		local share = Rules.loaded(t, readyAt, v.gun.reload)
		-- (a machine gun: the rounds left in its box while it isn't swapping it, counted down with each shot seen)
		local rounds = model:GetAttribute("Rounds") :: number?
		if model ~= counted or rounds ~= seenRounds then
			counted, seenRounds, roundsAt, shotsSince = model, rounds, t, 0
		end
		local mg = v.gun.mg
		local idle = if mg and rounds
			then tostring(
				Rules.mgShown(rounds, mg.box, shotsSince, model:GetAttribute("ReadyAt") :: number?, roundsAt, t)
			)
			else ""
		panel.set("timer", if share >= 1 then idle else string.format(A.timer, math.floor(share * 1000) / 10))
	end)
end

return ArtilleryHud
