--!strict
-- Colours the zone-capture marker (src/server/ZoneMatch builds it; Config/ZoneMatch.Marker) for this player: free,
-- theirs (held by someone else), mine (held by me), contested (flashing between contested and free). The next spot's
-- disc stays free-coloured. Both are hidden while this player aims (user 2026-10-27: "make it disappear when ADS").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.ZoneMatch)
local Map = require(Shared.Config.Maps.Playtest)

local ZoneMarker = {}

local MK = Cfg.Marker
local colors: { [string]: Color3 } = {}
for k, c in MK.Colors do
	colors[k] = Color3.fromRGB(c[1], c[2], c[3])
end

local function hide(model: Instance?, hidden: boolean)
	if not model then
		return
	end
	local m = if hidden then 1 else 0
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.LocalTransparencyModifier ~= m then
			p.LocalTransparencyModifier = m
		end
	end
end

local function paint(model: Model, color: Color3)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Color ~= color then
			p.Color = color
		end
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
		local character = me.Character
		local aiming = character ~= nil and character:GetAttribute("Aiming") == true
		hide(zone, aiming)
		hide(root and root:FindFirstChild(Cfg.NextMarkerName), aiming)
	end)
end

return ZoneMarker
