--!strict
-- Dev teleport menu: a pin button next to the settings gear, opening a list of destinations
-- (Rules/DevTeleports). Only shown when the server marked this player with the DevTools attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local Map1 = require(Shared.Config.Maps.Map1)
local Rules = require(Shared.Rules.DevTeleports)
local Net = require(Shared.Net)
local DevPanel = require(script.Parent.DevPanel)

local DevTeleportMenu = {}

local function build(player: Player): ScreenGui
	local p = DevPanel.new(player, "DevTeleportMenu", "📍", 1, "Teleport (dev)")
	for i, dest in Rules.list(Map1, Cfg) do
		DevPanel.button(p.panel, dest.id, dest.name, i).Activated:Connect(function()
			Net.event("DevTeleport"):FireServer(dest.id)
			p.panel.Visible = false
		end)
	end
	return p.gui
end

function DevTeleportMenu.start()
	local player = Players.LocalPlayer
	local gui: ScreenGui? = nil
	local function refresh()
		local allowed = player:GetAttribute(Cfg.Attribute) == true
		if allowed and not gui then
			gui = build(player)
		elseif not allowed and gui then
			gui:Destroy()
			gui = nil
		end
	end
	player:GetAttributeChangedSignal(Cfg.Attribute):Connect(refresh)
	refresh()
end

return DevTeleportMenu
