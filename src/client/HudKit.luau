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
-- fully dead as it recharges when its a stage 3 blast", "use effects that surround the crystal instead? actual effects
-- and not just blocks"). HudKit.crystal(parts, view) -> state; HudKit.shine(state, share, dead, colors, now): its look
-- this frame. Flat, dark colours: the grey crystal at no charge, its own colour (darkened) full; dead: the darker grey,
-- flickering. Round it, behind the view: a soft glow (rings fading out) and motes circling it, in its colour, as strong
-- as the charge (none dead).
export type Crystal = {
	parts: { BasePart },
	glow: { Frame },
	motes: { Frame },
	flickerUntil: number,
	nextFlicker: number,
}

local CR = HudCfg.Crystal
local rng = Random.new()

local function circle(parent: Instance, z: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.ZIndex = z
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	f.Parent = parent
	return f
end

function HudKit.crystal(parts: { BasePart }, view: ViewportFrame): Crystal
	-- (behind the view: it is see-through, so they show round the crystal at its centre)
	local holder = Instance.new("Frame")
	holder.Name = "CrystalFx"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = view.AnchorPoint
	holder.Position = view.Position
	holder.Size = view.Size
	holder.ZIndex = view.ZIndex - 1
	holder.ClipsDescendants = true
	holder.Parent = view.Parent
	local glow, motes = {}, {}
	for i, r in CR.glow.rings do
		local f = circle(holder, i)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(r, r)
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.DominantAxis = Enum.DominantAxis.Height
		ratio.Parent = f
		table.insert(glow, f)
	end
	for _ = 1, CR.motes.count do
		local m = circle(holder, #CR.glow.rings + 1)
		table.insert(motes, m)
	end
	return { parts = parts, glow = glow, motes = motes, flickerUntil = 0, nextFlicker = 0 }
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
	-- the effects: as strong as the charge (a curve, so a low charge is faint), nothing while dead
	local strength = if dead then 0 else share ^ CR.glow.curve
	local color = colors[1]
	for i, g in c.glow do
		g.BackgroundColor3 = color
		g.BackgroundTransparency = 1 - (1 - CR.glow.see[i]) * strength
	end
	local M = CR.motes
	for i, m in c.motes do
		local a = now * M.speed + i / #c.motes * math.pi * 2
		local r = M.radius + M.wobble * math.sin(now * M.speed * 2.3 + i)
		m.Position = UDim2.fromScale(0.5 + math.cos(a) * r * 0.5, 0.5 + math.sin(a) * r * M.squash)
		local s = M.size * (0.7 + 0.3 * math.sin(now * 3 + i * 1.7))
		m.Size = UDim2.fromOffset(s, s)
		m.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), M.light)
		m.BackgroundTransparency = 1 - (1 - M.see) * strength
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
