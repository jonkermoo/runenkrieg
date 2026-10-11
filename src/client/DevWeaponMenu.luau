--!strict
-- Dev weapon menu: a button next to the teleport pin, listing every weapon (Config/Weapons) by slot. Picking one
-- makes it your loadout's weapon for that slot: the server swaps it in now, exactly as if you had spawned with it,
-- and gives it again on every respawn (src/server/Armory). The current pick is highlighted. Only shown when the
-- server marked this player with the DevTools attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local Palette = require(Shared.Config.Palette)
local W = require(Shared.Config.Weapons)
local Net = require(Shared.Net)
local DevPanel = require(script.Parent.DevPanel)

local DevWeaponMenu = {}

local function build(player: Player): ScreenGui
	local p = DevPanel.new(player, "DevWeaponMenu", "🎒", 2, "Weapons (dev)")
	local names = {}
	for name in W do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		local sa, sb = W[a].slot, W[b].slot
		return if sa == sb then W[a].display < W[b].display else sa < sb
	end)
	local buttons: { [string]: TextButton } = {}
	local function highlight()
		for name, b in buttons do
			local picked = player:GetAttribute("Loadout_" .. W[name].slot) == name
			b.BackgroundColor3 = Color3.fromRGB(table.unpack(if picked then Palette.UI.accent else Palette.UI.button))
		end
	end
	for i, name in names do
		local w = W[name]
		local b = DevPanel.button(p.panel, name, `{w.display}  ({w.slot})`, i)
		b.Activated:Connect(function()
			Net.event("DevGiveWeapon"):FireServer(name)
			p.panel.Visible = false
		end)
		buttons[name] = b
		player:GetAttributeChangedSignal("Loadout_" .. w.slot):Connect(highlight)
	end
	highlight()
	return p.gui
end

function DevWeaponMenu.start()
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

return DevWeaponMenu
