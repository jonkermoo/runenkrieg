--!strict
-- The gun crew's panel, quartermaster's brass (Config/Hud.Artillery; layout src/shared/ui/CombatHud.json
-- "Artillery"; user 2026-10-26: "similar chamber concept for the field cannon and similar crystal concept for the
-- artillery"). Shown while I'm on a gun (its "Gunner" is me), bottom right:
-- - a cut-away drawn live in a ViewportFrame: the whole gun copied, posed every frame as src/client/Artillery poses
--   it, every part as see-through as the next (user 2026-10-26: "make it general transparency, i should be able to see
--   the inside of the gun (besides the round and the crystal)"), seen from the gun's mount (so the barrel's elevation and
--   recoil show, and the breech swinging open); the field gun's round (Config/Artillery.Load.round) sits in its
--   chamber, slides in as the loader puts it in (Load.loaded), and the fired case is thrown out as the breech opens;
--   the howitzer's living crystal (src/client/ArtilleryCrystal) glows in it as it does on the gun;
-- - how far the reload has got, a plain percentage in tenths (nothing once it can fire); no panel or background, at the
--   bottom right like the gun's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery)
local HudCfg = require(Shared.Config.Hud)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Artillery)
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

type View = {
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
	gem: HudKit.Crystal?, -- the howitzer's crystal
	gemSources: { BasePart },
	from: Vector3, -- the camera's side of the crystal (gun space), and how far off
	dist: number,
	throws: { Throw },
}

local function destroy(v: View)
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
		gemSources = {},
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
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not table.find(A.skip, d.Name) then
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
	-- the crystal's look (src/client/HudKit.shine)
	local gems = {}
	for src, c in v.copies do
		if table.find(A.solid, src.Name) then
			table.insert(gems, c.part)
			table.insert(v.gemSources, src)
		end
	end
	if #gems > 0 then
		v.gem = HudKit.crystal(gems, view)
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
	local o = (A.views :: any)[key] or A.views.default
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
		for _, src in v.gemSources do
			local c = (Palette.Artillery :: any)[src.Name] or { 175, 235, 255 }
			table.insert(colors, rgb(c))
		end
		HudKit.shine(v.gem, share, false, colors, clock)
		-- the camera on the crystal wherever the gun has laid it (elevation, recoil), as far off as framed
		local gem = v.gem.parts[1]
		camera.CFrame = CFrame.lookAt(gem.Position + v.from * v.dist, gem.Position)
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
	local view = panel.node.ArtilleryView :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.Parent = view
	view.CurrentCamera = camera
	local current: View? = nil

	local function mine(): Model?
		local f = workspace:FindFirstChild(Cfg.Folder)
		if not f then
			return nil
		end
		for _, m in f:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Gunner") == player.UserId then
				return m
			end
		end
		return nil
	end

	RunService.RenderStepped:Connect(function()
		local model = mine()
		panel.gui.Enabled = model ~= nil
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
		panel.set("timer", if share >= 1 then "" else string.format(A.timer, math.floor(share * 1000) / 10))
	end)
end

return ArtilleryHud
