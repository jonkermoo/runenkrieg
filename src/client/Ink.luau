--!strict
-- Ink drawing for the Field Grimoire UI (UI overhaul, user 2026-10-30): straight strokes as thin rotated Frames, so lines,
-- runes (Config/Runes) and the title's trench line stay crisp at any size and take any colour; and the torn ink plate
-- (Config/SketchMap.Slab, a 9-slice image) under buttons. Drawings are in pixels and redrawn whenever their box
-- changes size.
--   Ink.draw(box, paint(holder, w, h)): paints a full-size Frame in `box`, cleared and painted again on resize
--   Ink.canvas(box) -> { set(paint) }: the same, its contents replaced by each set
--   Ink.segment(parent, a, b, thick, colour, transparency?) -> Frame: one stroke from a to b (pixels in parent)
--   Ink.rune(parent, name, x, y, w, h, thick, colour, transparency?): a rune in the box at x, y (w x h pixels)
--   Ink.inscription(box, names, colour, transparency): runes in a row, right-aligned, as tall as the box
--   Ink.trench(box, ink, line): a trench line as the trench maps drew it, square bays and traverses, across the box
--   Ink.slab(parent) -> ImageLabel: the torn ink plate, filling its parent

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Runes = require(Shared.Config.Runes) :: any
local SketchCfg = require(Shared.Config.SketchMap)

local Ink = {}

function Ink.segment(
	parent: Instance,
	a: Vector2,
	b: Vector2,
	thick: number,
	colour: Color3,
	transparency: number?
): Frame
	local d = b - a
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = colour
	f.BackgroundTransparency = transparency or 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	-- a little past each end, so joined strokes meet without a notch
	f.Size = UDim2.fromOffset(d.Magnitude + thick * 0.9, thick)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.Parent = parent
	return f
end

export type Canvas = { set: (paint: (holder: Frame, w: number, h: number) -> ()) -> () }

-- a drawing that can be painted again with new contents (one resize hook for its life)
function Ink.canvas(box: GuiObject): Canvas
	local holder = Instance.new("Frame")
	holder.Name = "Ink"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = box
	local paint: ((Frame, number, number) -> ())? = nil
	local last = Vector2.zero
	local function redraw(force: boolean?)
		local s = box.AbsoluteSize
		if not paint or s.X <= 0 or s.Y <= 0 or (s == last and not force) then
			return
		end
		last = s
		holder:ClearAllChildren()
		paint(holder, s.X, s.Y)
	end
	box:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		redraw()
	end)
	return {
		set = function(p)
			paint = p
			redraw(true)
			if box.AbsoluteSize.X <= 0 then
				task.defer(redraw, true)
			end
		end,
	}
end

function Ink.draw(box: GuiObject, paint: (holder: Frame, w: number, h: number) -> ())
	Ink.canvas(box).set(paint)
end

function Ink.rune(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	thick: number,
	colour: Color3,
	transparency: number?
)
	local strokes = Runes[name]
	if not strokes then
		return
	end
	for _, s in strokes do
		Ink.segment(
			parent,
			Vector2.new(x + s[1] * w, y + s[2] * h),
			Vector2.new(x + s[3] * w, y + s[4] * h),
			thick,
			colour,
			transparency
		)
	end
end

function Ink.inscription(box: GuiObject, names: { string }, colour: Color3, transparency: number)
	Ink.draw(box, function(holder, w, h)
		local rw, gap = h * 0.62, h * 0.32
		local x = w - #names * (rw + gap) + gap
		for _, n in names do
			Ink.rune(holder, n, x, 0, rw, h, math.max(1, h * 0.09), colour, transparency)
			x += rw + gap
		end
	end)
end

function Ink.trench(box: GuiObject, ink: Color3, line: Color3)
	Ink.draw(box, function(holder, w, h)
		-- one bay every `step`: flat, up, across, down (the gallery's 26 x 7 units), ending on a flat run
		local step, depth = h * 1.2, h * 0.32
		local base, top = h * 0.68, h * 0.68 - depth
		local pts = { Vector2.new(0, base) }
		local x = 0
		while x + step <= w do
			local a, b = x + step * 0.31, x + step * 0.69
			table.insert(pts, Vector2.new(a, base))
			table.insert(pts, Vector2.new(a, top))
			table.insert(pts, Vector2.new(b, top))
			table.insert(pts, Vector2.new(b, base))
			x += step
		end
		table.insert(pts, Vector2.new(x, base))
		for _, layer in { { thick = h * 0.32, colour = ink }, { thick = h * 0.13, colour = line } } do
			for i = 2, #pts do
				Ink.segment(holder, pts[i - 1], pts[i], math.max(1, layer.thick), layer.colour)
			end
		end
	end)
end

function Ink.slab(parent: Instance): ImageLabel
	local s = SketchCfg.Slab
	local img = Instance.new("ImageLabel")
	img.Name = "Slab"
	img.BackgroundTransparency = 1
	img.Image = `rbxassetid://{s.image}`
	img.ScaleType = Enum.ScaleType.Slice
	img.SliceCenter = Rect.new(s.slice[1], s.slice[2], s.slice[3], s.slice[4])
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = 0
	img.Parent = parent
	return img
end

return Ink
