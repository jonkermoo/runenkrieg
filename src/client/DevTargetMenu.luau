--!strict
-- Dev target menu: a button next to the admin pin for the target dummies (Config/DevTools.Dummies; src/server/DevDummies):
-- pick the team kit, the helmet and how it moves, then spawn one at the aim point (the middle of the screen: DevAim),
-- facing you. Heal brings every dummy back to full health (dead ones come back), Clear removes them all. Only shown
-- when the server marked this player with the DevTools attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local Palette = require(Shared.Config.Palette)
local Net = require(Shared.Net)
local DevAim = require(script.Parent.DevAim)
local DevPanel = require(script.Parent.DevPanel)

local DevTargetMenu = {}

local D = Cfg.Dummies

local function build(player: Player): ScreenGui
	local p = DevPanel.new(player, "DevTargetMenu", "🎯", 4, "Targets (dev)")
	local kit, helmet, move = 1, true, 1
	local team = DevPanel.button(p.panel, "Team", "", 1)
	local hat = DevPanel.button(p.panel, "Helmet", "", 2)
	local walk = DevPanel.button(p.panel, "Move", "", 3)
	local function show()
		team.Text = `Team: {D.Kits[kit].name}`
		hat.Text = if helmet then "Helmet: on" else "Helmet: off"
		walk.Text = `Move: {D.Moves[move]}`
	end
	team.Activated:Connect(function()
		kit = kit % #D.Kits + 1
		show()
	end)
	hat.Activated:Connect(function()
		helmet = not helmet
		show()
	end)
	walk.Activated:Connect(function()
		move = move % #D.Moves + 1
		show()
	end)
	show()
	local spawn = DevPanel.button(p.panel, "Spawn", "Spawn at aim", 4, Palette.UI.accent)
	spawn.Activated:Connect(function()
		local aim = DevAim.point()
		if aim then
			Net.event("DevAction")
				:FireServer("Dummy", { kit = D.Kits[kit].kit, helmet = helmet, move = D.Moves[move] }, aim)
		end
	end)
	DevPanel.button(p.panel, "Heal", "Heal all dummies", 5).Activated:Connect(function()
		Net.event("DevAction"):FireServer("HealDummies")
	end)
	DevPanel.button(p.panel, "Clear", "Clear all dummies", 6).Activated:Connect(function()
		Net.event("DevAction"):FireServer("ClearDummies")
	end)
	return p.gui
end

function DevTargetMenu.start()
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

return DevTargetMenu
