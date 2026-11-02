--!strict
-- One capture point's seal, the same on the sketch map (src/client/SketchMap) and on the beacon over its flag in the
-- world (src/client/ModeHud): an ink disc, a ring in its holder's magic colour (amber, beating, while contested) and the
-- point's rune in that colour (user 2026-11-02: "make the flag beacons match its symbol on the map"). Its rune comes from
-- its place in the chain (Config/SketchMap.Runes), so every map gets the same symbols in the same order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.SketchMap) :: any
local Ink = require(script.Parent.Ink)

local PointSeal = {}

export type Seal = { disc: Frame, ring: UIStroke, canvas: Ink.Canvas, rune: string, colour: Color3? }

-- the rune of the `i`-th point of `n` (the two ends are the HQs)
function PointSeal.rune(i: number, n: number): string
	local R = Cfg.Runes
	if i == 1 or i == n then
		return R.hq
	end
	return R.order[i] or R.fallback
end

-- Dresses `disc` (a Frame sized and placed by the caller) as the seal of rune `rune`: round, ink-filled, ringed.
function PointSeal.new(disc: Frame, rune: string, ink: Color3, neutral: Color3): Seal
	disc.BackgroundColor3 = ink
	disc.BorderSizePixel = 0
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = disc
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	local ring = Instance.new("UIStroke")
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Color = neutral
	ring.Parent = disc
	local runeBox = Instance.new("Frame")
	runeBox.BackgroundTransparency = 1
	runeBox.AnchorPoint = Vector2.new(0.5, 0.5)
	runeBox.Position = UDim2.fromScale(0.5, 0.5)
	runeBox.Size = UDim2.fromScale(Cfg.Point.rune * 0.6, Cfg.Point.rune)
	runeBox.Parent = disc
	return { disc = disc, ring = ring, canvas = Ink.canvas(runeBox), rune = rune }
end

-- The rune in `colour` (its holder's magic colour, or neutral), redrawn only when the colour changes; the ring in `ring`
-- (the same, or the contested beat's amber).
function PointSeal.paint(s: Seal, colour: Color3, ring: Color3)
	s.ring.Color = ring
	if s.colour == colour then
		return
	end
	s.colour = colour
	s.canvas.set(function(holder, w, h)
		Ink.rune(holder, s.rune, 0, 0, w, h, math.max(1, h * 0.13), colour)
	end)
end

-- The seal's colours for a point now: its holder's magic colour (kit = the holding side's team), and the ring beating
-- toward amber while it is contested (as many of each side in its zone) at `now`.
function PointSeal.colours(kit: string?, contested: boolean, now: number): (Color3, Color3)
	local C = (require(Shared.Config.Palette) :: any).UI.Grimoire
	local magic = kit and C.Magic[kit]
	local base = if magic then Color3.fromRGB(magic[1], magic[2], magic[3]) else Color3.fromRGB(table.unpack(C.neutral))
	if not contested then
		return base, base
	end
	local beat = (math.sin(now / Cfg.ContestedPulse * 2 * math.pi) + 1) / 2
	return base, base:Lerp(Color3.fromRGB(table.unpack(C.amber)), 0.4 + 0.6 * beat)
end

return PointSeal
