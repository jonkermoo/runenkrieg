--!strict
-- What suppression does to the picture and the ears (Config/Suppression.Screen / Muffle / Dirt.Specks; user 2026-11-06:
-- "machine guns should be a terrifying threat as a soldier"). By src/client/Suppression.level(): the screen's edges go
-- dark and the colour drains as the level rises; pinned (machine-gun fire only) the dark closes in and pulses like a
-- racing heart, and every game sound's highs are pulled down (src/client/Audio.muffle, its own source). Dirt from a
-- bullet landing right by the head spatters the screen (SuppressionScreen.specks, from src/client/Impacts). Client only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Suppression)
local Rules = require(Shared.Rules.Suppression)
local Audio = require(script.Parent.Audio)
local Suppression = require(script.Parent.Suppression)

local S, M, K = Cfg.Screen, Cfg.Muffle, Cfg.Dirt.Specks

local SuppressionScreen = {}

local gui: ScreenGui? = nil
local edges: { Frame } = {}
local grade: ColorCorrectionEffect? = nil
local shown = 0 -- the eased level the picture follows
local shownPin = 0
local t = 0
local specks: { { f: Frame, born: number, life: number } } = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function build(): ScreenGui
	if gui then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "Suppression"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = -11 -- (under the HUD and a concussion's own edges)
	g.Enabled = false
	-- top, bottom, left, right: each dark at the screen's edge, clear inwards
	for _, rotation in { 90, 270, 0, 180 } do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = rgb(S.color)
		f.BorderSizePixel = 0
		f.Parent = g
		local gr = Instance.new("UIGradient")
		gr.Rotation = rotation
		gr.Transparency = NumberSequence.new(0, 1)
		gr.Parent = f
		table.insert(edges, f)
	end
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
	local c = Instance.new("ColorCorrectionEffect")
	c.Name = "Suppression"
	c.Enabled = false
	c.Parent = workspace.CurrentCamera
	grade = c
	return g
end

local function place(depth: number, dark: number)
	local d = math.clamp(depth, 0, 0.5)
	local frames = {
		{ UDim2.fromScale(1, d), UDim2.fromScale(0, 0) },
		{ UDim2.fromScale(1, d), UDim2.fromScale(0, 1 - d) },
		{ UDim2.fromScale(d, 1), UDim2.fromScale(0, 0) },
		{ UDim2.fromScale(d, 1), UDim2.fromScale(1 - d, 0) },
	}
	for i, f in edges do
		f.Size, f.Position = frames[i][1], frames[i][2]
		f.BackgroundTransparency = 1 - math.clamp(dark, 0, 1)
	end
end

-- `n` specks of dirt in `color` thrown onto the screen (a bullet landing right by the head)
function SuppressionScreen.specks(color: Color3, n: number?)
	local g = build()
	g.Enabled = true
	local now = os.clock()
	for _ = 1, n or K.count do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.35)
		local size = K.size[1] + math.random() * (K.size[2] - K.size[1])
		f.SizeConstraint = Enum.SizeConstraint.RelativeYY
		f.Size = UDim2.fromScale(size * (0.6 + math.random() * 0.8), size)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5 + (math.random() * 2 - 1) * K.spread, 0.5 + (math.random() * 2 - 1) * K.spread)
		f.Rotation = math.random() * 360
		f.Parent = g
		table.insert(specks, { f = f, born = now, life = K.life * (0.7 + math.random() * 0.6) })
	end
end

local function step(dt: number)
	t += dt
	local level, pinned = Suppression.level()
	local k = 1 - math.exp(-S.ease * math.min(dt, 0.1))
	shown += (math.min(level, 1) - shown) * k
	shownPin += (pinned - shownPin) * k
	if shown < 1e-3 then
		shown, shownPin = 0, 0
	end

	local now = os.clock()
	for i = #specks, 1, -1 do
		local s = specks[i]
		local age = (now - s.born) / s.life
		if age >= 1 then
			s.f:Destroy()
			table.remove(specks, i)
		else
			s.f.BackgroundTransparency = age * age
		end
	end

	local on = shown > 0
	if not on and #specks == 0 then
		if gui and gui.Enabled then
			gui.Enabled = false
			if grade then
				grade.Enabled = false
			end
			Audio.muffle(0, 0, 0, "Suppression")
		end
		return
	end
	local g = build()
	g.Enabled = true
	local beat = math.sin(t * S.beat * math.pi * 2) * S.pulse * shownPin
	place(
		Rules.blend(shown, shownPin, S.depth, S.pinnedDepth),
		Rules.blend(shown, shownPin, S.dark, S.pinnedDark) + beat * shown
	)
	local c = grade :: ColorCorrectionEffect
	c.Enabled = on
	c.Saturation = Rules.blend(shown, shownPin, S.saturation, S.pinnedSaturation)
	c.Contrast = S.contrast * shown
	if on then
		Audio.muffle(
			Rules.blend(shown, shownPin, M.high, M.pinnedHigh),
			Rules.blend(shown, shownPin, M.mid, M.pinnedMid),
			0,
			"Suppression"
		)
	else
		Audio.muffle(0, 0, 0, "Suppression")
	end
end

function SuppressionScreen.start()
	RunService.RenderStepped:Connect(step)
end

return SuppressionScreen
