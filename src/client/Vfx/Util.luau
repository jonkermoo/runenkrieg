--!strict
-- Small helpers for the spell effects (src/client/Vfx, Config/Vfx): magic colors, the Workspace.Vfx folder, plain
-- parts, a raycast for where a spell lands, and the flat line drawing on a disc (the magic circle). The reusable
-- pieces (beams, glowing parts, lights) come from Vfx/Pool.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared").Config.Palette)

local Util = {}

-- Roblox's own sparkle sprite (engine content, nothing uploaded)
Util.SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

function Util.color(name: string): Color3
	local c = (Palette.Magic :: any)[name]
	assert(c, "unknown magic color " .. name)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local folder: Folder? = nil
function Util.folder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "Vfx"
	made.Parent = workspace
	folder = made
	return made
end

-- An anchored part that touches nothing; invisible unless given a color (then Neon).
function Util.part(size: Vector3, cf: CFrame, color: Color3?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = false
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Material = if color then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Color = color or Color3.new(1, 1, 1)
	p.Transparency = if color then 0 else 1
	return p
end

-- Where a spell cast from `from` along `dir` lands within `range`: the hit point, the surface normal and the hit
-- thing's color (a part's Color, terrain's material color); full range if nothing's in the way. Skips the effects
-- and `ignore`.
function Util.cast(from: Vector3, dir: Vector3, range: number, ignore: { Instance }?): (Vector3, Vector3, Color3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { Util.folder() }
	for _, i in ignore or {} do
		table.insert(list, i)
	end
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(from, dir.Unit * range, params)
	if not hit then
		return from + dir.Unit * range, -dir.Unit, nil
	end
	local inst = hit.Instance
	local color = if inst:IsA("Terrain")
		then inst:GetMaterialColor(hit.Material)
		elseif inst:IsA("BasePart") then inst.Color
		else nil
	return hit.Position, hit.Normal, color
end

-- A flat drawing surface: a disc-sized invisible part with a SurfaceGui on both faces. `draw(root)` fills one face's
-- CanvasGroup (positions in scale, line widths in pixels via `px`); it's called once per face.
export type Disc = { part: Part, groups: { CanvasGroup }, guis: { SurfaceGui } }
function Util.disc(
	cf: CFrame,
	diameter: number,
	pixelsPerStud: number,
	brightness: number,
	draw: (root: CanvasGroup, face: Enum.NormalId) -> ()
): Disc
	local p = Util.part(Vector3.new(diameter, diameter, 0.02), cf)
	p.Name = "Disc"
	local groups, guis = {}, {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = pixelsPerStud
		gui.LightInfluence = 0
		gui.Brightness = brightness
		gui.ZOffset = 1
		local root = Instance.new("CanvasGroup")
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.Parent = gui
		draw(root, face)
		gui.Parent = p
		table.insert(groups, root)
		table.insert(guis, gui)
	end
	return { part = p, groups = groups, guis = guis }
end

-- Drawing helpers for Util.disc (all centred on (cx, cy) in scale).
function Util.ring(parent: GuiObject, cx: number, cy: number, d: number, thickness: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx, cy)
	f.Size = UDim2.fromScale(d, d)
	f.BackgroundTransparency = 1
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	f.Parent = parent
	return f
end

function Util.dot(parent: GuiObject, cx: number, cy: number, d: number, color: Color3, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx, cy)
	f.Size = UDim2.fromScale(d, d)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
	f.Parent = parent
	return f
end

-- A rounded long shape (a petal) through the centre, `w` x `h` of the canvas, turned `deg`.
function Util.petal(parent: GuiObject, w: number, h: number, deg: number, thickness: number, color: Color3): Frame
	local f = Util.ring(parent, 0.5, 0.5, 0, thickness, color)
	f.Size = UDim2.fromScale(w, h)
	f.Rotation = deg
	return f
end

-- A straight line from (x0, y0) to (x1, y1) in `parent`'s scale, `thickness` pixels wide; `pxW` x `pxH` = the
-- parent's size in pixels (keeps the angle and length right on any canvas).
function Util.line(
	parent: GuiObject,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	thickness: number,
	color: Color3,
	pxW: number,
	pxH: number
): Frame
	local dx, dy = (x1 - x0) * pxW, (y1 - y0) * pxH
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale((x0 + x1) / 2, (y0 + y1) / 2)
	f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + thickness, thickness)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

return Util
