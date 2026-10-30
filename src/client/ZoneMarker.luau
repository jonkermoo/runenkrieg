--!strict
-- Colours the zone-capture marker (src/server/ZoneMatch builds it; Config/ZoneMatch.Marker) for this player: free,
-- theirs (held by someone else), mine (held by me), contested (flashing between contested and free): its rings, its
-- beacon's beams and its light. The beacon breathes (its widths and light swing slowly). The next spot's rings stay
-- free-coloured. Both are hidden while this player aims (user 2026-10-27: "make it disappear when ADS").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.ZoneMatch)
local Map = require(Shared.Config.Maps.Playtest)

local ZoneMarker = {}

local MK = Cfg.Marker
local B = MK.Beacon
local colors: { [string]: Color3 } = {}
for k, c in MK.Colors do
	colors[k] = Color3.fromRGB(c[1], c[2], c[3])
end

local function hide(model: Instance?, hidden: boolean)
	if not model then
		return
	end
	local m = if hidden then 1 else 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			if p.LocalTransparencyModifier ~= m then
				p.LocalTransparencyModifier = m
			end
		elseif p:IsA("Beam") or p:IsA("PointLight") then
			if p.Enabled == hidden then
				p.Enabled = not hidden
			end
		end
	end
end

local function paint(model: Model, color: Color3)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			if p.Color ~= color then
				p.Color = color
			end
		elseif p:IsA("Beam") then
			if p.Color.Keypoints[1].Value ~= color then
				p.Color = ColorSequence.new(color)
			end
		elseif p:IsA("PointLight") and p.Color ~= color then
			p.Color = color
		end
	end
end

-- the beacon's breath: its beams' widths and its light's brightness, `u` from -1 to 1
local function breathe(model: Model, u: number)
	local anchor = model:FindFirstChild("Beacon")
	if not anchor then
		return
	end
	for _, name in { "Core", "Halo" } do
		local b = anchor:FindFirstChild(name) :: Beam?
		local w = (if name == "Core" then B.core else B.halo).width * (1 + B.pulse * u)
		if b then
			b.Width0, b.Width1 = w, w
		end
	end
	local light = anchor:FindFirstChildOfClass("PointLight")
	if light then
		light.Brightness = MK.Light.brightness * (1 + MK.Light.pulse * u)
	end
end

function ZoneMarker.start()
	local me = Players.LocalPlayer
	RunService.Heartbeat:Connect(function()
		local root = workspace:FindFirstChild(Map.name)
		local zone = root and root:FindFirstChild(Cfg.MarkerName)
		if not zone or not zone:IsA("Model") then
			return
		end
		local state = zone:GetAttribute("State")
		local color = colors.Free
		if state == "Held" then
			color = if zone:GetAttribute("Holder") == me.UserId then colors.Mine else colors.Theirs
		elseif state == "Contested" then
			local on = (os.clock() // MK.FlashSeconds) % 2 == 0
			color = if on then colors.Contested else colors.Free
		end
		paint(zone, color)
		breathe(zone, math.sin(os.clock() / B.pulseSeconds * 2 * math.pi))
		local character = me.Character
		local aiming = character ~= nil and character:GetAttribute("Aiming") == true
		hide(zone, aiming)
		hide(root and root:FindFirstChild(Cfg.NextMarkerName), aiming)
	end)
end

return ZoneMarker
