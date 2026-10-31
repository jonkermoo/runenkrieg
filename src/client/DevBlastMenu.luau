--!strict
-- Dev blast menu: a button next to the target pin setting off an explosion at the aim point (the middle of the screen:
-- DevAim; Config/DevTools.Blasts): a staff stage's blast or a real charge in kg. The server does the damage, knocks and
-- destruction (src/server/Damage.blast) and sends Net "DevBlast" to everyone, shown here (src/client/Vfx/Blast).
-- The artillery buttons place a field gun or a howitzer at the aim point, muzzle away from you, or remove them all
-- (src/server/Artillery; E mans one); "Place MG nest" lays a finished MG nest there, its gun facing away from you
-- (src/server/Build.devPlace; dig it apart to remove it).
-- "My blasts hurt me": off, your own blast knocks you but never hurts you (as in the game). The menu is only shown when
-- the server marked this player with the DevTools attribute; every client shows the explosions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local Palette = require(Shared.Config.Palette)
local Net = require(Shared.Net)
local DevAim = require(script.Parent.DevAim)
local DevPanel = require(script.Parent.DevPanel)
local Vfx = require(script.Parent.Vfx)

local DevBlastMenu = {}

local B = Cfg.Blasts

local function build(player: Player): ScreenGui
	local p = DevPanel.new(player, "DevBlastMenu", "💥", 5, "Blasts at aim (dev)")
	local order = 0
	local function fire(action: string, value: number)
		local aim = DevAim.point()
		if aim then
			Net.event("DevAction"):FireServer(action, value, aim)
		end
	end
	for _, s in B.Stages do
		order += 1
		DevPanel.button(p.panel, "Stage" .. s, `Staff stage {s}`, order).Activated:Connect(function()
			fire("BlastStage", s)
		end)
	end
	for _, kg in B.Kg do
		order += 1
		DevPanel.button(p.panel, `Kg{kg}`, `{kg} kg TNT`, order).Activated:Connect(function()
			fire("BlastKg", kg)
		end)
	end
	-- artillery at the aim point (src/server/Artillery), and clearing them
	local names = { artillery_qf18 = "Place field gun", artillery_howitzer = "Place rune mortar" }
	for _, key in B.Guns do
		order += 1
		DevPanel.button(p.panel, "Gun_" .. key, names[key] or key, order).Activated:Connect(function()
			local aim = DevAim.point()
			if aim then
				Net.event("DevAction"):FireServer("PlaceGun", key, aim)
			end
		end)
	end
	local pieceNames = { MGNest = "Place MG nest" }
	for _, key in B.Pieces do
		order += 1
		DevPanel.button(p.panel, "Piece_" .. key, pieceNames[key] or key, order).Activated:Connect(function()
			local aim = DevAim.point()
			if aim then
				Net.event("DevAction"):FireServer("PlacePiece", key, aim)
			end
		end)
	end
	order += 1
	DevPanel.button(p.panel, "ClearGuns", "Remove guns", order).Activated:Connect(function()
		Net.event("DevAction"):FireServer("ClearGuns")
	end)
	local hurts = DevPanel.button(p.panel, "Hurts", "", order + 1)
	local function show()
		local on = player:GetAttribute(B.HurtAttribute) == true
		hurts.Text = if on then "My blasts hurt me: on" else "My blasts hurt me: off"
		hurts.BackgroundColor3 = Color3.fromRGB(table.unpack(if on then Palette.UI.accent else Palette.UI.button))
	end
	hurts.Activated:Connect(function()
		Net.event("DevAction"):FireServer("BlastHurts", player:GetAttribute(B.HurtAttribute) ~= true)
	end)
	player:GetAttributeChangedSignal(B.HurtAttribute):Connect(show)
	show()
	return p.gui
end

function DevBlastMenu.start()
	local player = Players.LocalPlayer
	Net.event("DevBlast").OnClientEvent:Connect(function(position: Vector3, stage: number?, kg: number?)
		Vfx.Blast.play(position, { normal = Vector3.yAxis, stage = stage, kg = kg })
	end)
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

return DevBlastMenu
