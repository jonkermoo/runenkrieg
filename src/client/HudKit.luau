--!strict
-- Builds one panel of the combat HUD from its spec (src/shared/ui/CombatHud.json; colours Config/Palette.UI.Hud):
-- brass-rimmed boxes, stamped labels, ViewportFrames for the cut-aways (`model` nodes), a bar, each in its own
-- ScreenGui (src/client/AmmoHud, StaffHud, ArtilleryHud; Config/DevTools.Admin.Cinematic.HudGuis hides them by name).
-- Offsets are reference pixels: one UIScale per panel does the rest.
--   HudKit.panel(id, guiName) -> { gui, panel, node: { [id]: GuiObject }, set(bind, text), fill(id, share) }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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

-- the four brass rivets in a panel's corners
local function rivets(obj: GuiObject)
	local r = T.rivet
	for _, at in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local d = Instance.new("Frame")
		d.Name = "Rivet"
		d.AnchorPoint = Vector2.new(at[1], at[2])
		d.Position = UDim2.new(at[1], (1 - 2 * at[1]) * r, at[2], (1 - 2 * at[2]) * r)
		d.Size = UDim2.fromOffset(r, r)
		d.BackgroundColor3 = rgb("brassDark")
		d.BorderSizePixel = 0
		d.ZIndex = 3
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = d
		d.Parent = obj
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
			if n.bind then
				binds[n.bind] = l
			end
			obj = l
		elseif n.kind == "model" then
			local v = Instance.new("ViewportFrame")
			v.BackgroundColor3 = rgb(n.color)
			v.BorderSizePixel = 0
			v.Ambient = Color3.fromRGB(150, 150, 150)
			v.LightColor = Color3.fromRGB(255, 244, 224)
			v.LightDirection = Vector3.new(-0.4, -1, -0.6)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, T.corner)
			corner.Parent = v
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
			if n.rivets then
				rivets(f)
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
