--!strict
-- The staff's mana bar, bottom right (user 2026-10-13: "a mana bar in the bottom right ... 6 quick shots, 3 charged
-- shot, and 1 mega shot"; Config/Spells.Mana, colors Config/Palette.UI). Shown while the staff is drawn, in the ammo
-- display's place (guns show that instead). Read from the attributes src/client/StaffAttack writes:
-- - a short plain rectangle, the fill the mana (user 2026-10-13: no guides or text);
-- - while a cast is held, the part the shot would spend glows white (ManaCost);
-- - a mega shot burns it out (the extended cooldown, shown): the empty bar smoulders (its edge flickering ember), then
--   refills slowly in a dull violet; full again, it flashes back to blue;
-- - a shot refused for want of mana: the edge flashes red and the bar shakes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Config.Palette)
local Spells = require(Shared.Config.Spells)
local W = require(Shared.Config.Weapons)
local Held = require(script.Parent.Held)

local ManaBar = {}

local WIDTH, HEIGHT = 190, 12 -- a tad shorter (user 2026-10-13; was 240 x 14)
local MARGIN = 24

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function frame(parent: Instance, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.ZIndex = z
	f.Parent = parent
	return f
end

function ManaBar.start()
	local player = Players.LocalPlayer
	local UI = Palette.UI
	local max = Spells.Mana.max

	local gui = Instance.new("ScreenGui")
	gui.Name = "ManaBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false

	local bar = frame(gui, rgb(UI.slot), 1)
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	local edge = Instance.new("UIStroke")
	edge.Thickness = UI.stroke
	edge.Color = rgb(UI.outline)
	edge.Parent = bar
	local fill = frame(bar, rgb(UI.mana), 2)
	fill.Size = UDim2.fromScale(0, 1)
	local spend = frame(bar, rgb(UI.manaSpend), 3)
	spend.Size = UDim2.fromScale(0, 1)
	local flash = frame(bar, rgb(UI.manaSpend), 5)
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	gui.Parent = player:WaitForChild("PlayerGui")

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local weapon = character and Held.weapon(character)
		local staff = weapon ~= nil and W[weapon.name] ~= nil and W[weapon.name].class == "Staff"
		gui.Enabled = staff
		if not character or not staff then
			return
		end
		local now = os.clock()
		local value = (character:GetAttribute("Mana") :: number?) or max
		local locked = character:GetAttribute("ManaLocked") == true
		local smoulder = character:GetAttribute("ManaSmoulder") == true
		local cost = character:GetAttribute("ManaCost") :: number?
		local deniedAt = (character:GetAttribute("ManaDenied") :: number?) or -math.huge
		local refilledAt = (character:GetAttribute("ManaRefilled") :: number?) or -math.huge

		-- refused: a short shake
		local d = now - deniedAt
		local shake = if d < 0.3 then math.sin(d * 70) * 4 * (1 - d / 0.3) else 0
		bar.Position = UDim2.new(1, -MARGIN + shake, 1, -MARGIN)

		fill.Size = UDim2.fromScale(value / max, 1)
		fill.BackgroundColor3 = rgb(if locked then UI.manaBurnt else UI.mana)
		-- the share the held cast would spend, pulsing
		if cost and not locked and value >= cost then
			spend.Position = UDim2.fromScale((value - cost) / max, 0)
			spend.Size = UDim2.fromScale(cost / max, 1)
			spend.BackgroundTransparency = 0.35 + 0.25 * math.sin(now * 8)
		else
			spend.Size = UDim2.fromScale(0, 1)
		end
		-- the edge: red when refused, ember flicker while burnt out, else plain
		if d < 0.3 then
			edge.Color = rgb(UI.manaDenied)
		elseif smoulder then
			edge.Color = rgb(UI.outline):Lerp(rgb(UI.manaBurnt), 0.5 + 0.5 * math.noise(now * 9, 0.3))
		elseif locked then
			edge.Color = rgb(UI.outline):Lerp(rgb(UI.manaBurnt), 0.35 + 0.15 * math.sin(now * 4))
		else
			edge.Color = rgb(UI.outline)
		end
		-- full again after burning out: a white flash fading
		local r = now - refilledAt
		flash.BackgroundTransparency = if r < 0.4 then r / 0.4 else 1
	end)
end

return ManaBar
