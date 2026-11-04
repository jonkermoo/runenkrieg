--!strict
-- Dev blast menu: a button next to the target pin setting off an explosion at the aim point (the middle of the screen:
-- DevAim; Config/DevTools.Blasts): a staff stage's blast or a real charge in kg. The beam rows fire a staff stage's beam from
-- your head at the aim point (src/server/Damage.staff: by the zone it hits; its button shows the zone and the health
-- it took, e.g. a dummy's head). The server does the damage, knocks and
-- destruction (src/server/Damage.blast) and sends Net "DevBlast" to everyone, shown here (src/client/Vfx/Blast).
-- The look rows play an explosion's look at the aim point on this client only (no damage; Config/DevTools.Blasts
-- .Looks), then show its cost and the worst frame after it. The artillery buttons place a field gun or a howitzer at the aim point, muzzle away from you, or remove them all
-- (src/server/Artillery; E mans one); "Place MG nest" lays a finished MG nest there, its gun facing away from you
-- (src/server/Build.devPlace; dig it apart to remove it). The gun HP rows set the gun at the aim point to a share of its
-- HP (under half it is out of service). The bot rows act at the aim point too (src/server/Bots.dev).
-- "My blasts hurt me": off, your own blast knocks you but never hurts you (as in the game). The menu is only shown when
-- the server marked this player with the DevTools attribute; every client shows the explosions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local Artillery = require(Shared.Config.Artillery)
local Grenades = require(Shared.Config.Grenades)
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
	-- (the beams' buttons show what they did: the refusals below)
	local beamButtons: { [string]: TextButton } = {}
	for _, s in B.Stages do
		order += 1
		local label = `Staff beam {s} at aim`
		local button = DevPanel.button(p.panel, "Beam" .. s, label, order)
		beamButtons["Beam" .. s] = button
		button.Activated:Connect(function()
			fire("BeamStage", s)
		end)
	end
	for _, kg in B.Kg do
		order += 1
		DevPanel.button(p.panel, `Kg{kg}`, `{kg} kg TNT`, order).Activated:Connect(function()
			fire("BlastKg", kg)
		end)
	end
	-- each explosion's look at the aim point, here only (no damage): its cost and the worst frame after it on the button
	local function look(button: TextButton, label: string, play: () -> ())
		local t0 = os.clock()
		play()
		local cost = (os.clock() - t0) * 1000
		local worst, stop = 0, os.clock() + B.LookWatch
		local beat: RBXScriptConnection
		beat = RunService.RenderStepped:Connect(function(dt: number)
			worst = math.max(worst, dt)
			if os.clock() >= stop then
				beat:Disconnect()
				button.Text = `{label}: {string.format("%.1f", cost)} ms, worst frame {math.round(worst * 1000)} ms`
			end
		end)
	end
	local function lookAt(entry: any, at: Vector3)
		if entry.gun then
			local gun = (Artillery.Guns :: any)[entry.gun]
			Vfx.Blast.play(at, { normal = Vector3.yAxis, kg = gun.kg, scheme = gun.vfx.scheme, magic = gun.vfx.magic })
		elseif entry.grenade then
			local kg = (Grenades.Types :: any)[entry.grenade].kg
			Vfx.Blast.play(
				at,
				{ normal = Vector3.yAxis, kg = kg, scheme = Grenades.Vfx.scheme, magic = false, pop = Grenades.Vfx.pop }
			)
		else
			Vfx.Blast.play(at, { normal = Vector3.yAxis, stage = entry.stage, scheme = "Arcane" })
		end
	end
	for i, entry in B.Looks do
		order += 1
		local label = `Look: {entry.label} at aim`
		local button = DevPanel.button(p.panel, "Look" .. i, label, order)
		button.Activated:Connect(function()
			local aim = DevAim.point()
			if aim then
				look(button, label, function()
					lookAt(entry, aim)
				end)
			end
		end)
	end
	do
		local S = B.LookSalvo
		order += 1
		local label = `Look: {S.count} field gun shells at aim`
		local button = DevPanel.button(p.panel, "LookSalvo", label, order)
		button.Activated:Connect(function()
			local aim = DevAim.point()
			if not aim then
				return
			end
			look(button, label, function()
				for k = 1, S.count do
					task.delay((k - 1) * S.every, function()
						local a = math.random() * 2 * math.pi
						local r = S.spread * math.sqrt(math.random())
						lookAt({ gun = S.gun }, aim + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
					end)
				end
			end)
		end)
	end
	-- a gun's shells landing round the aim point (src/server/Artillery.devShells: a trench line shelled)
	local shellNames = { artillery_qf18 = "field gun", artillery_howitzer = "rune howitzer" }
	for _, key in B.Guns do
		order += 1
		local label = `{B.Shells.count} {shellNames[key] or key} shells at aim`
		DevPanel.button(p.panel, "Shells_" .. key, label, order).Activated:Connect(function()
			local aim = DevAim.point()
			if aim then
				Net.event("DevAction"):FireServer("Shells", key, aim)
			end
		end)
	end
	-- artillery at the aim point (src/server/Artillery), and clearing them
	local names = { artillery_qf18 = "Place field gun", artillery_howitzer = "Place rune howitzer" }
	for _, key in B.Guns do
		order += 1
		DevPanel.button(p.panel, "Gun_" .. key, names[key] or key, order).Activated:Connect(function()
			local aim = DevAim.point()
			if aim then
				Net.event("DevAction"):FireServer("PlaceGun", key, aim)
			end
		end)
	end
	-- (a refused piece shows why on its button for a moment: src/server/DevTools)
	local pieceNames: { [string]: string } = { MGNest = "Place MG nest", Dugout = "Place dugout (at a trench wall)" }
	local pieceButtons: { [string]: TextButton } = {}
	for key, button in beamButtons do
		pieceButtons[key], pieceNames[key] = button, button.Text
	end
	for _, key in B.Pieces do
		order += 1
		local button = DevPanel.button(p.panel, "Piece_" .. key, pieceNames[key] or key, order)
		pieceButtons[key] = button
		button.Activated:Connect(function()
			local aim = DevAim.point()
			if aim then
				Net.event("DevAction"):FireServer("PlacePiece", key, aim)
			end
		end)
	end
	-- the gun nearest the aim point to a share of its HP (src/server/DevTools; Config/Artillery.Man: under half it can't
	-- be manned)
	for _, pct in B.GunHp do
		order += 1
		local key = `GunHp{pct}`
		local button = DevPanel.button(p.panel, key, `Gun at aim to {pct}% HP`, order)
		pieceButtons[key] = button
		pieceNames[key] = `Gun at aim to {pct}% HP`
		button.Activated:Connect(function()
			local aim = DevAim.point()
			if aim then
				Net.event("DevAction"):FireServer("GunHp", pct, aim)
			end
		end)
	end
	-- the bots at the aim point (Normal; src/server/Bots.dev): the nearest squad pushes there, the nearest bot
	-- butt-strokes toward it, the nearest free gun goes to the nearest bot, the nearest bot digs a foxhole there (gun out
	-- until it is safe to dig: the bot labels show "going", "waiting" or "Build"), the nearest bot knocked down there (its
	-- teammates guard it until they may drag or heal it: "covering"), the trench there shelled (Config/DevTools.Admin.Shell:
	-- the holders near it go down into its dugouts, the Bot dugouts readout says who and why)
	local botRows = {
		{ action = "BotPush", label = "Nearest squad pushes here" },
		{ action = "BotStrike", label = "Nearest bot butt-strokes here" },
		{ action = "BotGun", label = "Nearest gun to nearest bot" },
		{ action = "BotWork", label = "Nearest bot digs here (gun out until safe)" },
		{ action = "BotDown", label = "Nearest bot knocked down here (teammates guard it)" },
		{ action = "BotShellHere", label = "Shell the trench here (bots take to its dugouts)" },
	}
	for _, r in botRows do
		order += 1
		local button = DevPanel.button(p.panel, r.action, r.label, order)
		pieceButtons[r.action] = button
		pieceNames[r.action] = r.label
		button.Activated:Connect(function()
			local aim = DevAim.point()
			if aim then
				Net.event("DevAction"):FireServer(r.action, nil, aim)
			end
		end)
	end
	local refusals = Net.event("DevAction").OnClientEvent:Connect(function(kind: any, key: any, reason: any)
		local button = type(key) == "string" and pieceButtons[key]
		if (kind ~= "Refused" and kind ~= "Done") or not button or type(reason) ~= "string" then
			return
		end
		local label = pieceNames[key] or key
		button.Text = `{label}: {reason}`
		task.delay(B.RefusedSeconds, function()
			if button.Text == `{label}: {reason}` then
				button.Text = label
			end
		end)
	end)
	p.gui.Destroying:Once(function()
		refusals:Disconnect()
	end)
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
