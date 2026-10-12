--!strict
-- Dev admin menu: a button next to the weapon pin with Fly (on/off) and a speed multiplier (Config/DevTools.Admin).
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
