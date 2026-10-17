--!strict
-- Dev admin menu: a button next to the weapon pin with Fly (on/off) and a speed multiplier (Config/DevTools.Admin), then
-- test rows the server does (Net "DevAction", src/server/DevTools): You (health steps, kill, respawn, knock, helmet off,
-- god mode) and World (the range's test shooters, undo destruction).
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
local Palette = require(Shared.Config.Palette)
local Net = require(Shared.Net)
local DevPanel = require(script.Parent.DevPanel)

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

-- the dev labels (Config/DevTools.Admin.LabelFolders), shown or hidden for this player; labels made later follow
local labelConns: { RBXScriptConnection } = {}
local function applyLabels(player: Player)
	local hidden = player:GetAttribute(A.LabelsAttribute) == true
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

local function build(player: Player): ScreenGui
	local p = DevPanel.new(player, "DevAdminMenu", "🛠", 3, "Admin (dev)")
	local function paint(b: TextButton, on: boolean)
		b.BackgroundColor3 = Color3.fromRGB(table.unpack(if on then Palette.UI.accent else Palette.UI.button))
	end
	local fly = DevPanel.button(p.panel, "Fly", "Fly: off", 1)
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
		local b = DevPanel.button(p.panel, "Speed" .. mult, `Speed x{mult}`, 1 + i)
		b.Activated:Connect(function()
			player:SetAttribute(A.Attribute, if mult == 1 then nil else mult)
		end)
		speeds[mult] = b
	end
	player:GetAttributeChangedSignal(A.Attribute):Connect(showSpeed)
	showSpeed()
	local labels = DevPanel.button(p.panel, "Labels", "Labels: shown", 2 + #A.SpeedSteps)
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

	-- You (src/server/DevTools): health steps, death, respawn, god mode, a knock, the helmet off
	local order = 3 + #A.SpeedSteps
	local function row(id: string, label: string, action: string, value: any?): TextButton
		order += 1
		local b = DevPanel.button(p.panel, id, label, order)
		b.Activated:Connect(function()
			Net.event("DevAction"):FireServer(action, value)
		end)
		return b
	end
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
	return p.gui
end

function DevAdminMenu.start()
	local player = Players.LocalPlayer
	local gui: ScreenGui? = nil
	local function refresh()
		local allowed = player:GetAttribute(Cfg.Attribute) == true
		if allowed and not gui then
			gui = build(player)
		elseif not allowed and gui then
			land(player)
			player:SetAttribute(A.Attribute, nil)
			gui:Destroy()
			gui = nil
		end
	end
	player:GetAttributeChangedSignal(Cfg.Attribute):Connect(refresh)
	player.CharacterAdded:Connect(function()
		land(player) -- a new body starts on the ground
	end)
	refresh()
end

return DevAdminMenu
