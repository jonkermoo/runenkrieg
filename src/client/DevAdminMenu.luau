--!strict
-- Dev admin menu: a button next to the weapon pin. First the Server rows (the game mode, Config/Modes: Admin / FFA /
-- Normal; everyone respawned; the sector borders; kept teams + the loadout menu's team cards for testing), the Normal Match rows (end, restart, take our next sector) and the FFA Match rows (end, restart, skip the zone, the clock, zone
-- score), then Fly (on/off) and a speed multiplier (Config/DevTools.Admin), then
-- test rows the server does (Net "DevAction", src/server/DevTools): You (health steps, kill, respawn, knock, helmet off,
-- god mode, unlimited ammo and no staff cooldown), Loadout (match points, a class every life), Team (respawn now as grey / olive / brown, kept until changed, or random again), Grenades (give yourself
-- a full count of one), Shovel (the dig step, build anything), World (the range's test shooters, undo destruction) and Time
-- (jump the clock to dawn / noon / dusk / midnight, pause the day cycle) and Weather (clear / fog / rain now, the random
-- weather off / on); Time and Weather are for everyone (src/server/Environment). Last the Cinematic rows for filming
-- (src/client/DevCinematic): one switch hides every item, a row per item. Settings Key_AdminPanel (F2) opens / closes it.
-- Client only: the client owns its character's physics, so it flies and speeds up its own character. Only shown when
-- the server marked this player with the DevTools attribute.
-- - Speed: sets the Player's DevSpeed attribute; src/client/Stance multiplies every walk speed by it.
-- - Fly: a LinearVelocity + AlignOrientation on the HumanoidRootPart with the Humanoid platform-standing. WASD moves
--   along the camera's view (looking up flies up), Space / E rise, Q / LeftControl sink; the speed multiplier
--   applies. Respawning ends the flight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local ClassCfg = require(Shared.Config.Classes)
local ModeCfg = require(Shared.Config.Modes)
local SectorCfg = require(Shared.Config.Sectors)
local TeamCfg = require(Shared.Config.Teams)
local EnvCfg = require(Shared.Config.Environment)
local GrenadeCfg = require(Shared.Config.Grenades)
local W = require(Shared.Config.Weapons)
local Palette = require(Shared.Config.Palette)
local Net = require(Shared.Net)
local DevPanel = require(script.Parent.DevPanel)
local DevCinematic = require(script.Parent.DevCinematic)
local Settings = require(script.Parent.Settings)

local DevAdminMenu = {}

local A = Cfg.Admin

local function keyList(names: { string }): { Enum.KeyCode }
	local out = {}
	for _, n in names do
		table.insert(out, (Enum.KeyCode :: any)[n])
	end
	return out
end
local UP, DOWN = keyList(A.FlyUpKeys), keyList(A.FlyDownKeys)

local function anyDown(list: { Enum.KeyCode }): boolean
	for _, k in list do
		if UserInputService:IsKeyDown(k) then
			return true
		end
	end
	return false
end

local flight: { folder: Folder, conn: RBXScriptConnection, humanoid: Humanoid }? = nil

local function land(player: Player)
	local f = flight
	if not f then
		return
	end
	flight = nil
	f.conn:Disconnect()
	f.folder:Destroy()
	if f.humanoid.Parent then
		f.humanoid.PlatformStand = false
		f.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	player:SetAttribute(A.FlyAttribute, nil)
end

local function takeOff(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or flight then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "DevFly"
	local att = Instance.new("Attachment")
	att.Parent = root
	att.Name = "DevFlyAttachment"
	local move = Instance.new("LinearVelocity")
	move.Attachment0 = att
	move.RelativeTo = Enum.ActuatorRelativeTo.World
	move.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	move.MaxForce = math.huge
	move.VectorVelocity = Vector3.zero
	move.Parent = folder
	local turn = Instance.new("AlignOrientation")
	turn.Mode = Enum.OrientationAlignmentMode.OneAttachment
	turn.Attachment0 = att
	turn.RigidityEnabled = true
	turn.CFrame = root.CFrame.Rotation
	turn.Parent = folder
	folder.Parent = root
	folder.Destroying:Connect(function()
		att:Destroy()
	end)
	humanoid.PlatformStand = true
	local conn = RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		local flatRight = flat:Cross(Vector3.yAxis)
		-- WASD arrives as the Humanoid's flat MoveDirection; re-aim it along the camera's full view
		local m = humanoid.MoveDirection
		local dir = look * m:Dot(flat) + cam.CFrame.RightVector * m:Dot(flatRight)
		if not UserInputService:GetFocusedTextBox() then
			dir += Vector3.yAxis * ((if anyDown(UP) then 1 else 0) - (if anyDown(DOWN) then 1 else 0))
		end
		if dir.Magnitude > 1 then
			dir = dir.Unit
		end
		local mult = (player:GetAttribute(A.Attribute) :: number?) or 1
		move.VectorVelocity = dir * A.FlySpeed * mult
		turn.CFrame = CFrame.lookAt(Vector3.zero, flat)
	end)
	flight = { folder = folder, conn = conn, humanoid = humanoid }
	player:SetAttribute(A.FlyAttribute, true)
end

-- the dev labels (Config/DevTools.Admin.LabelFolders), shown or hidden for this player (also by the cinematic "DevUi");
-- labels made later follow
local labelConns: { RBXScriptConnection } = {}
local function applyLabels(player: Player)
	local hidden = player:GetAttribute(A.LabelsAttribute) == true or DevCinematic.hidden(player, "DevUi")
	for _, c in labelConns do
		c:Disconnect()
	end
	table.clear(labelConns)
	local function set(d: Instance)
		if d:IsA("BillboardGui") then
			d.Enabled = not hidden
		end
	end
	local function watch(folder: Instance)
		for _, d in folder:GetDescendants() do
			set(d)
		end
		table.insert(labelConns, folder.DescendantAdded:Connect(set))
	end
	for _, name in A.LabelFolders do
		local f = workspace:FindFirstChild(name)
		if f then
			watch(f)
		end
	end
	table.insert(
		labelConns,
		workspace.ChildAdded:Connect(function(child)
			if table.find(A.LabelFolders, child.Name) then
				watch(child)
			end
		end)
	)
end

local function build(player: Player): DevPanel.Panel
	local p = DevPanel.new(player, "DevAdminMenu", "🛠", 3, "Admin (dev)")
	local function paint(b: TextButton, on: boolean)
		b.BackgroundColor3 = Color3.fromRGB(table.unpack(if on then Palette.UI.accent else Palette.UI.button))
	end
	local order = 0
	local function row(id: string, label: string, action: string, value: any?): TextButton
		order += 1
		local b = DevPanel.button(p.panel, id, label, order)
		b.Activated:Connect(function()
			Net.event("DevAction"):FireServer(action, value)
		end)
		return b
	end
	local function heading(text: string)
		order += 1
		DevPanel.heading(p.panel, text, order)
	end
	-- an on / off row: `attribute` on `owner`, sent as `action`
	local function onOff(id: string, label: string, action: string, owner: Instance, attribute: string)
		order += 1
		local b = DevPanel.button(p.panel, id, "", order)
		local function show()
			local on = owner:GetAttribute(attribute) == true
			b.Text = `{label}: {if on then "on" else "off"}`
			paint(b, on)
		end
		b.Activated:Connect(function()
			Net.event("DevAction"):FireServer(action, owner:GetAttribute(attribute) ~= true)
		end)
		owner:GetAttributeChangedSignal(attribute):Connect(show)
		show()
	end

	-- Server: the game mode (Config/Modes, src/server/Modes), the live one lit; one not built yet can't be picked
	heading("Server")
	local modes: { [string]: TextButton } = {}
	for _, key in ModeCfg.List do
		local d = ModeCfg.Defs[key]
		if d.ready then
			modes[key] = row("Mode_" .. key, `Mode: {d.name}`, "Mode", key)
		else
			order += 1
			DevPanel.button(p.panel, "Mode_" .. key, `Mode: {d.name} (not built yet)`, order, Palette.UI.outline)
		end
	end
	row("RespawnAll", "Respawn everyone", "RespawnAll")
	-- kept teams and the loadout menu's team cards in this mode too, for testing (Config/Teams)
	onOff("KeptTeams", "Kept teams + team cards", "KeptTeams", workspace, TeamCfg.DevAttribute)
	-- the sector dividers and point markers in play (src/server/Sectors; off by default in Normal)
	onOff("Sectors", "Sector borders", "Sectors", workspace, SectorCfg.ShowAttribute)
	-- Match (Normal, src/server/Frontline): end it, a fresh one, your side takes the sector it's attacking
	heading("Match (Normal)")
	local front: { TextButton } = {
		row("FrontStart", "Start now (skip waiting for players)", "FrontStart"),
		row("FrontEnd", "End match now", "MatchEnd"),
		row("FrontRestart", "Restart match", "MatchRestart"),
		row("FrontTake", "Take our next sector", "FrontTake"),
	}
	-- Match (FFA, src/server/ZoneMatch): end it, a fresh one, the zone on, the clock, your zone score; dim in other modes
	heading("Match (FFA)")
	local match: { TextButton } = {
		row("MatchEnd", "End match now", "MatchEnd"),
		row("MatchRestart", "Restart match", "MatchRestart"),
		row("ZoneSkip", "Move the zone now", "ZoneSkip"),
	}
	for _, sec in A.MatchSeconds do
		local m = sec / 60
		table.insert(
			match,
			row(`MatchTime{sec}`, `Match clock {if sec > 0 then "+" else "-"}{math.abs(m)} min`, "MatchTime", sec)
		)
	end
	for _, n in A.ZoneScore do
		table.insert(match, row(`ZoneScore{n}`, `Give me {n} zone score`, "ZoneScore", n))
	end
	local function showMode()
		local live = workspace:GetAttribute(ModeCfg.Attribute)
		for key, b in modes do
			paint(b, key == live)
		end
		for _, b in match do
			b.TextTransparency = if live == "FFA" then 0 else 0.5
		end
		for _, b in front do
			b.TextTransparency = if live == "Normal" then 0 else 0.5
		end
	end
	workspace:GetAttributeChangedSignal(ModeCfg.Attribute):Connect(showMode)
	showMode()

	heading("Movement")
	order += 1
	local fly = DevPanel.button(p.panel, "Fly", "Fly: off", order)
	local function showFly()
		local on = player:GetAttribute(A.FlyAttribute) == true
		fly.Text = if on then "Fly: on" else "Fly: off"
		paint(fly, on)
	end
	fly.Activated:Connect(function()
		if flight then
			land(player)
		else
			takeOff(player)
		end
	end)
	player:GetAttributeChangedSignal(A.FlyAttribute):Connect(showFly)
	showFly()
	local speeds: { [number]: TextButton } = {}
	local function showSpeed()
		local current = (player:GetAttribute(A.Attribute) :: number?) or 1
		for mult, b in speeds do
			paint(b, mult == current)
		end
	end
	for i, mult in A.SpeedSteps do
		local b = DevPanel.button(p.panel, "Speed" .. mult, `Speed x{mult}`, order + i)
		b.Activated:Connect(function()
			player:SetAttribute(A.Attribute, if mult == 1 then nil else mult)
		end)
		speeds[mult] = b
	end
	player:GetAttributeChangedSignal(A.Attribute):Connect(showSpeed)
	showSpeed()
	order += #A.SpeedSteps + 1
	local labels = DevPanel.button(p.panel, "Labels", "Labels: shown", order)
	local function showLabels()
		local hidden = player:GetAttribute(A.LabelsAttribute) == true
		labels.Text = if hidden then "Labels: hidden" else "Labels: shown"
		paint(labels, not hidden)
		applyLabels(player)
	end
	labels.Activated:Connect(function()
		player:SetAttribute(A.LabelsAttribute, if player:GetAttribute(A.LabelsAttribute) == true then nil else true)
	end)
	player:GetAttributeChangedSignal(A.LabelsAttribute):Connect(showLabels)
	showLabels()

	-- You (src/server/DevTools): health steps, death, respawn, god mode, a knock, the helmet off, unlimited ammo
	DevPanel.heading(p.panel, "You", order + 1)
	order += 1
	for _, h in A.Health do
		row("Health" .. h, if h >= 100 then `Heal ({h})` else `Health {h}`, "Health", h)
	end
	row("Kill", "Kill me", "Kill")
	row("Respawn", "Respawn now", "Respawn")
	row("KnockMe", "Knock me", "KnockMe")
	row("HelmetOff", "Helmet off", "HelmetOff")
	order += 1
	local god = DevPanel.button(p.panel, "God", "", order)
	local function showGod()
		local on = player:GetAttribute(A.GodAttribute) == true
		god.Text = if on then "God mode: on" else "God mode: off"
		paint(god, on)
	end
	god.Activated:Connect(function()
		Net.event("DevAction"):FireServer("God", player:GetAttribute(A.GodAttribute) ~= true)
	end)
	player:GetAttributeChangedSignal(A.GodAttribute):Connect(showGod)
	showGod()
	onOff("Ammo", "Unlimited ammo, no cooldown", "Ammo", player, A.AmmoAttribute)

	-- Loadout (src/server/Loadouts): match points, a class every life (free, locked or not) or your own picks again
	heading("Loadout")
	for _, n in A.Points do
		row(`Points{n}`, `Give me {n} match points`, "Points", n)
	end
	local classes: { [string]: TextButton } = {}
	for _, key in ClassCfg.List do
		classes[key] = row("Class_" .. key, `Be {ClassCfg.Defs[key].name} every life`, "Class", key)
	end
	classes[A.Normal] = row("Class_Normal", "Class: my own picks", "Class", A.Normal)
	local function showClass()
		local pinned = player:GetAttribute(A.ClassAttribute)
		local current = if type(pinned) == "string" and classes[pinned] then pinned else A.Normal
		for key, b in classes do
			paint(b, key == current)
		end
	end
	player:GetAttributeChangedSignal(A.ClassAttribute):Connect(showClass)
	showClass()

	-- Team: respawn now as one of Config/DevTools.Dummies.Kits, kept on every respawn (the Player's "Kit" attribute,
	-- src/server/Kits), or random again; the pinned one lit
	DevPanel.heading(p.panel, "Team", order + 1)
	order += 1
	local teams: { [string]: TextButton } = {}
	for _, k in Cfg.Dummies.Kits do
		teams[k.kit] = row("Team_" .. k.kit, `Respawn as {k.name}`, "Team", k.kit)
	end
	teams[A.Random] = row("Team_Random", "Random team each life", "Team", A.Random)
	local function showTeam()
		local pinned = player:GetAttribute("Kit")
		local current = if type(pinned) == "string" and teams[pinned] then pinned else A.Random
		for kit, b in teams do
			paint(b, kit == current)
		end
	end
	player:GetAttributeChangedSignal("Kit"):Connect(showTeam)
	showTeam()

	-- Grenades: give yourself a full count of one (Config/DevTools.Admin.Grenades)
	DevPanel.heading(p.panel, "Grenades", order + 1)
	order += 1
	for _, name in A.Grenades do
		row("Grenade_" .. name, `Give {W[name].display} x{GrenadeCfg.Carried}`, "Grenade", name)
	end

	-- Shovel: how much each of your swings works (Config/DevTools.Admin.Dig), the chosen one lit
	DevPanel.heading(p.panel, "Shovel", order + 1)
	order += 1
	local digs: { [number]: TextButton } = {}
	for _, s in A.Dig.steps do
		digs[s.share] = row(
			"Dig_" .. s.name,
			if s.share == 0 then "Dig: normal swings" else `Dig: {s.name} a swing`,
			"DigStep",
			s.share
		)
	end
	local function showDig()
		local share = player:GetAttribute(A.Dig.attribute)
		for v, b in digs do
			paint(b, v == (if type(share) == "number" then share else 0))
		end
	end
	player:GetAttributeChangedSignal(A.Dig.attribute):Connect(showDig)
	showDig()
	onOff("BuildAll", "Build anything", "BuildAll", player, A.BuildAllAttribute)

	-- World: the range's test shooters (Config/DevTools.TestShooter), undo destruction (src/server/DevWorld)
	DevPanel.heading(p.panel, "World", order + 1)
	order += 2
	local shooters = DevPanel.button(p.panel, "Shooters", "", order)
	local S = Cfg.TestShooter.Attribute
	local function showShooters()
		local on = workspace:GetAttribute(S) == true
		shooters.Text = if on then "Test shooters: on" else "Test shooters: off"
		paint(shooters, on)
	end
	shooters.Activated:Connect(function()
		Net.event("DevAction"):FireServer("Shooters", workspace:GetAttribute(S) ~= true)
	end)
	workspace:GetAttributeChangedSignal(S):Connect(showShooters)
	showShooters()
	row("Undo", "Undo destruction", "UndoDestruction")

	-- Time: jump the clock (Config/DevTools.Admin.Times), pause / resume the day cycle (src/server/Environment)
	DevPanel.heading(p.panel, "Time", order + 1)
	order += 1
	for _, t in A.Times do
		row("Time_" .. t.name, `{t.name} ({string.format("%02d:00", t.hours)})`, "Clock", t.hours)
	end
	order += 1
	local pause = DevPanel.button(p.panel, "ClockPaused", "", order)
	local P = EnvCfg.Attributes.paused
	local function showPause()
		local on = workspace:GetAttribute(P) ~= nil
		pause.Text = if on then "Day cycle: paused" else "Day cycle: running"
		paint(pause, not on)
	end
	pause.Activated:Connect(function()
		Net.event("DevAction"):FireServer("ClockPaused", workspace:GetAttribute(P) == nil)
	end)
	workspace:GetAttributeChangedSignal(P):Connect(showPause)
	showPause()

	-- Weather: one of Config/DevTools.Admin.Weather at full strength now, the random rolls off / on
	DevPanel.heading(p.panel, "Weather", order + 1)
	order += 1
	for _, kind in A.Weather do
		row("Weather_" .. kind, if kind == "Clear" then "Clear sky now" else `{kind} now`, "Weather", kind)
	end
	order += 1
	local calm = DevPanel.button(p.panel, "WeatherCalm", "", order)
	local C = EnvCfg.Attributes.calm
	local function showCalm()
		local off = workspace:GetAttribute(C) == true
		calm.Text = if off then "Random weather: off" else "Random weather: on"
		paint(calm, not off)
	end
	calm.Activated:Connect(function()
		Net.event("DevAction"):FireServer("WeatherCalm", workspace:GetAttribute(C) ~= true)
	end)
	workspace:GetAttributeChangedSignal(C):Connect(showCalm)
	showCalm()

	-- Cinematic (Config/DevTools.Admin.Cinematic): the switch hides every item (or shows them all again once all are
	-- hidden), each row one item
	local items = A.Cinematic.Items
	DevPanel.heading(p.panel, "Cinematic", order + 1)
	order += 2
	local switch = DevPanel.button(p.panel, "Cinematic", "", order)
	local rows: { [string]: TextButton } = {}
	local function showCinematic(): boolean
		local all = true
		for _, item in items do
			local on = DevCinematic.hidden(player, item.id)
			all = all and on
			rows[item.id].Text = `{item.label}: {if on then "hidden" else "shown"}`
			paint(rows[item.id], not on)
		end
		switch.Text = if all then "Cinematic: on" else "Cinematic: off"
		paint(switch, all)
		return all
	end
	for _, item in items do
		order += 1
		local b = DevPanel.button(p.panel, "Cinematic_" .. item.id, "", order)
		b.Activated:Connect(function()
			DevCinematic.set(player, item.id, not DevCinematic.hidden(player, item.id))
		end)
		rows[item.id] = b
	end
	switch.Activated:Connect(function()
		local all = showCinematic()
		for _, item in items do
			DevCinematic.set(player, item.id, not all)
		end
	end)
	for _, item in items do
		player:GetAttributeChangedSignal(A.Cinematic.AttributePrefix .. item.id):Connect(showCinematic)
	end
	player:GetAttributeChangedSignal(A.Cinematic.AttributePrefix .. "DevUi"):Connect(function()
		applyLabels(player)
	end)
	showCinematic()
	return p
end

function DevAdminMenu.start()
	local player = Players.LocalPlayer
	local panel: DevPanel.Panel? = nil
	local function refresh()
		local allowed = player:GetAttribute(Cfg.Attribute) == true
		if allowed and not panel then
			panel = build(player)
		elseif not allowed and panel then
			land(player)
			player:SetAttribute(A.Attribute, nil)
			DevCinematic.clear(player)
			panel.gui:Destroy()
			panel = nil
		end
	end
	DevCinematic.start(player)
	UserInputService.InputBegan:Connect(function(input, processed)
		if panel and not processed and Settings.pressed("Key_AdminPanel", input) then
			panel.toggle()
		end
	end)
	player:GetAttributeChangedSignal(Cfg.Attribute):Connect(refresh)
	player.CharacterAdded:Connect(function()
		land(player) -- a new body starts on the ground
	end)
	refresh()
end

return DevAdminMenu
