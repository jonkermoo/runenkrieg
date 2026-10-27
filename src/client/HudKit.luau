--!strict
-- Builds one panel of the combat HUD from its spec (src/shared/ui/CombatHud.json; colours Config/Palette.UI.Hud):
-- no panels (user 2026-10-26: "no background or color or even a panel"): labels, ViewportFrames for the cut-aways
-- (`model` nodes, see-through) and a bar, each in its own
-- ScreenGui (src/client/AmmoHud, StaffHud, ArtilleryHud; Config/DevTools.Admin.Cinematic.HudGuis hides them by name).
-- Offsets are reference pixels: one UIScale per panel does the rest.
--   HudKit.panel(id, guiName) -> { gui, panel, node: { [id]: GuiObject }, set(bind, text), fill(id, share) }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudCfg = require(Shared.Config.Hud) :: any
local Palette = require(Shared.Config.Palette)
local Spec = require(Shared.ui.CombatHud) :: any

local HudKit = {}

local C = Palette.UI.Hud :: any
local T = Spec.theme

local FONTS: { [string]: Font } = {}
for name, f in T.fonts do
	FONTS[name] = Font.new(`rbxasset://fonts/families/{f.family}.json`, (Enum.FontWeight :: any)[f.weight])
end

function HudKit.rgb(name: string): Color3
	local c = C[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end
local rgb = HudKit.rgb

local function find(n: any, id: string): any
	if n.id == id then
		return n
	end
	for _, c in n.children or {} do
		local f = find(c, id)
		if f then
			return f
		end
	end
	return nil
end

local function udim(a: { number }): UDim2
	return UDim2.new(a[1], a[2], a[3], a[4])
end

local function place(obj: GuiObject, n: any)
	obj.Position = udim(n.pos or { 0, 0, 0, 0 })
	obj.Size = udim(n.size or { 1, 0, 1, 0 })
	if n.anchor then
		obj.AnchorPoint = Vector2.new(n.anchor[1], n.anchor[2])
	end
end

local function box(obj: GuiObject, n: any)
	if not n.color then
		obj.BackgroundTransparency = 1 -- (no colour: nothing behind it)
		obj.BorderSizePixel = 0
		return
	end
	obj.BackgroundColor3 = rgb(n.color)
	obj.BackgroundTransparency = 0
	obj.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if n.round then UDim.new(0.5, 0) else UDim.new(0, T.corner)
	corner.Parent = obj
	if n.line then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = T.outline
		stroke.Color = rgb(n.line)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = obj
	end
end

local ALIGN = { left = Enum.TextXAlignment.Left, right = Enum.TextXAlignment.Right }

export type Panel = {
	gui: ScreenGui,
	panel: Frame,
	node: { [string]: GuiObject },
	set: (bind: string, text: string) -> (),
	fill: (id: string, share: number, color: Color3?) -> (),
}

function HudKit.panel(id: string, guiName: string): Panel
	local spec = assert(find(Spec.root, id), id)
	local gui = Instance.new("ScreenGui")
	gui.Name = guiName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	-- (children over their parents: with Global layering a panel's own background drew over the cut-away in it)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local nodes: { [string]: GuiObject } = {}
	local binds: { [string]: TextLabel } = {}
	local fills: { [string]: Frame } = {}

	local function make(n: any, parent: Instance): GuiObject
		local obj: GuiObject
		if n.kind == "label" then
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Text = n.text or ""
			l.FontFace = FONTS[n.font or "body"]
			l.TextSize = n.textSize
			l.TextColor3 = rgb(n.textColor)
			l.TextXAlignment = ALIGN[n.align] or Enum.TextXAlignment.Center
			if n.stroke then
				l.TextStrokeColor3 = rgb(n.stroke)
				l.TextStrokeTransparency = 0
			end
			if n.bind then
				binds[n.bind] = l
			end
			obj = l
		elseif n.kind == "model" then
			local v = Instance.new("ViewportFrame")
			v.BackgroundTransparency = 1 -- (the cut-away floats over the game)
			v.BorderSizePixel = 0
			v.Ambient = rgb("viewAmbient")
			v.LightColor = rgb("viewLight")
			local l = HudCfg.Light
			v.LightDirection = Vector3.new(l[1], l[2], l[3])
			obj = v
		elseif n.kind == "group" then
			local g = Instance.new("Frame")
			g.BackgroundTransparency = 1
			obj = g
		else -- panel, bar
			local f = Instance.new("Frame")
			box(f, n)
			if n.kind == "bar" then
				local fill = Instance.new("Frame")
				fill.Name = "Fill"
				fill.BorderSizePixel = 0
				fill.BackgroundColor3 = rgb("brass")
				fill.Size = UDim2.fromScale(0, 1)
				fill.Parent = f
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, T.corner)
				corner.Parent = fill
				fills[n.id] = fill
			end
			obj = f
		end
		obj.Name = n.id
		place(obj, n)
		obj.ZIndex = if n.overlay then 4 else 2
		nodes[n.id] = obj
		for _, c in n.children or {} do
			make(c, obj)
		end
		obj.Parent = parent
		return obj
	end

	local panel = make(spec, gui) :: Frame
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function rescale()
		local h = gui.AbsoluteSize.Y
		scale.Scale = math.clamp(h / T.scale.referenceHeight, T.scale.min, T.scale.max)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	rescale()

	return {
		gui = gui,
		panel = panel,
		node = nodes,
		set = function(bind: string, text: string)
			local l = binds[bind]
			if l and l.Text ~= text then
				l.Text = text
			end
		end,
		fill = function(fid: string, share: number, color: Color3?)
			local f = fills[fid]
			if f then
				f.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
				if color then
					f.BackgroundColor3 = color
				end
			end
		end,
	}
end

-- A crystal in a cut-away (the staff's rock, the howitzer's gem; Config/Hud.Crystal; user 2026-10-26: "the crystal
-- should not be fully gray. the crystal also doesnt have to be so bright. make it simple and dark so players can tell if
-- its fully charged or not. have it gradually die out to look like the gray crystal as the charge is low. only have it
-- fully dead as it recharges when its a stage 3 blast"). HudKit.crystal(parts) -> state; HudKit.shine(state, share,
-- dead, colors, now): its look this frame. Flat, dark colours: the grey crystal at no charge, its own colour (darkened)
-- full; dead: the darker grey, flickering. (No glow or motes behind it: user 2026-10-26, "remove this blue orb circle
-- thing"; the gem's own floating shards are what surrounds it.)
export type Crystal = {
	parts: { BasePart },
	flickerUntil: number,
	nextFlicker: number,
}

local CR = HudCfg.Crystal
local rng = Random.new()

function HudKit.crystal(parts: { BasePart }): Crystal
	return { parts = parts, flickerUntil = 0, nextFlicker = 0 }
end

function HudKit.shine(c: Crystal, share: number, dead: boolean, colors: { Color3 }, now: number)
	share = math.clamp(share, 0, 1)
	local grey, deadGrey = rgb("crystalHollow"), rgb("crystalDead")
	local light = 1
	if dead then
		local f = CR.flicker
		if now >= c.nextFlicker then
			c.flickerUntil = now + f.time
			c.nextFlicker = now + f.every * (1 + f.jitter * (2 * rng:NextNumber() - 1))
		end
		light = if now < c.flickerUntil then f.depth else 1
	end
	for i, p in c.parts do
		local own = (colors[i] or colors[1]):Lerp(Color3.new(), CR.dim)
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = 0
		p.Color = if dead then Color3.new():Lerp(deadGrey, light) else grey:Lerp(own, share)
	end
end

-- The 3D gem (Config/Hud.Gem, Config/Assets hud_gem: user 2026-10-26, "trace a real gem", "add floating shards around
-- it", "replace the howizer gem with the same 3d gem"): HudKit.gem(parent, length) -> copies of its parts in `parent`,
-- centred on the Crystal, scaled so the Crystal is `length` studs long (nil: as modelled); HudKit.poseGem(gem, at, now)
-- puts it at `at` (its c axis `at`'s +Y), the shards floating round it at their own pace, bobbing and spinning.
export type Gem = { parts: { { part: BasePart, rel: CFrame } }, crystal: Crystal, size: Vector3 }

local G = HudCfg.Gem

function HudKit.gem(parent: Instance, length: number?): Gem?
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, name in G.model do
		f = f and f:FindFirstChild(name)
	end
	local first = f and f:FindFirstChild(G.parts[1], true)
	if not f or not first or not first:IsA("BasePart") then
		return nil
	end
	local k = if length then length / math.max(first.Size.X, first.Size.Y, first.Size.Z) else 1
	local parts, list = {}, {}
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, name in G.parts do
		local p = (f :: Instance):FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			local c = p:Clone()
			c:ClearAllChildren()
			c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false, false
			c.Size *= k
			c.Parent = parent
			local rel = first.CFrame:ToObjectSpace(p.CFrame)
			rel = rel - rel.Position + rel.Position * k
			table.insert(parts, { part = c, rel = rel })
			table.insert(list, c)
			local h = c.Size.Magnitude / 2
			lo, hi = lo:Min(rel.Position - Vector3.one * h), hi:Max(rel.Position + Vector3.one * h)
		end
	end
	return { parts = parts, crystal = HudKit.crystal(list), size = hi - lo }
end

function HudKit.poseGem(g: Gem, at: CFrame, now: number)
	local F = G.shards
	for i, q in g.parts do
		local k = i - 2 -- (the shards come after the Crystal and its cracks)
		if k >= 1 then
			local round = CFrame.Angles(0, math.rad((F.orbit[k] or 0) * now), 0)
			local up = math.sin(now * F.speed * math.pi * 2 + k * 1.9) * F.bob
			q.part.CFrame = at
				* round
				* CFrame.new(0, up, 0)
				* q.rel
				* CFrame.Angles(0, math.rad(F.spin * now + k * 40), 0)
		else
			q.part.CFrame = at * q.rel
		end
	end
end

-- A cut-away's camera: looking at `box` (centre CFrame + size, in the viewport's space) square on from `from`
-- (a unit direction in the box's space toward the camera), through a `fov` degree lens, the box filling the
-- viewport with `margin` to spare.
function HudKit.frameBox(
	view: ViewportFrame,
	camera: Camera,
	centre: CFrame,
	size: Vector3,
	from: Vector3,
	up: Vector3,
	fov: number,
	margin: number
)
	local aspect = math.max(view.AbsoluteSize.X, 1) / math.max(view.AbsoluteSize.Y, 1)
	if view.AbsoluteSize.X < 1 then
		aspect = 2
	end
	-- the box's extent across the view (its width and height seen from `from`)
	local right = up:Cross(from).Unit
	local half = size / 2
	local function extent(axis: Vector3): number
		return math.abs(axis.X) * half.X + math.abs(axis.Y) * half.Y + math.abs(axis.Z) * half.Z
	end
	local w, h = extent(right) * 2 * (1 + margin), extent(up) * 2 * (1 + margin)
	local depth = extent(from)
	local t = math.tan(math.rad(fov / 2))
	local dist = math.max(h / 2 / t, w / 2 / (t * aspect)) + depth
	local eye = centre:PointToWorldSpace(from * dist)
	camera.FieldOfView = fov
	camera.CFrame = CFrame.lookAt(eye, centre.Position, centre:VectorToWorldSpace(up))
end

return HudKit
