--!strict
-- Build mode on the local client (Config/Build; the server decides: src/server/Build). With the shovel in the hands,
-- Key_Build opens build mode: a ghost of the picked piece follows the crosshair on the ground, green where it can go
-- and red with the reason where not (shared/BuildSurvey, the same survey the server runs); the mouse wheel picks the
-- piece, Key_BuildTurn turns it (Shift turns back), a click lays its blueprint (Net "Build" "Place") and leaves build
-- mode. Out of build mode each dig swing (src/client/Shovel "DugAt") goes to the nearest piece in reach in front of
-- you (Net "Build" "Work"): your team's rises, another team's comes down. A small line at the bottom of the screen
-- says what is going on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local M = require(Shared.Config.Metrics)
local Palette = require(Shared.Config.Palette)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Build)
local Survey = require(Shared.BuildSurvey)
local Net = require(Shared.Net)
local Held = require(script.Parent.Held)
local Settings = require(script.Parent.Settings)

local Build = {}

local active = false
local index = 1
local turn = 0
local ghost: Model? = nil
local ghostFor: string? = nil
local current: { frame: CFrame, ok: boolean, reason: string? }? = nil
local notice: { text: string, untilAt: number }? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- whether build mode is open (src/client/Shovel: a click then lays a piece instead of digging)
function Build.active(): boolean
	return active
end

local function shovelHeld(character: Model?): boolean
	local weapon = Held.weapon(character)
	return weapon ~= nil and W[weapon.name] ~= nil and W[weapon.name].class == "Shovel"
end

local function piece(): Rules.Piece
	return C.Pieces[index]
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
	end
	ghost, ghostFor = nil, nil
end

-- the ghost: the footprint as a box (a trench: its cut band, flat on the ground)
local function makeGhost(): Model
	local m = Instance.new("Model")
	m.Name = "BuildGhost"
	local part = Instance.new("Part")
	part.Name = "Box"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = C.Ghost.transparency
	part.Parent = m
	m.PrimaryPart = part
	m.Parent = workspace.CurrentCamera
	return m
end

local function ghostFrame(p: Rules.Piece, frame: CFrame, low: number): (CFrame, Vector3)
	local size, offset = Survey.footprint(p)
	if p.kind == "Trench" then
		local T = C.Trench
		local fw = M.Trench.FirestepWidth
		local across = T.front + fw - T.back
		local mid = (T.back + T.front + fw) / 2
		return CFrame.new(frame.Position.X, frame.Position.Y + 0.15, frame.Position.Z) * frame.Rotation * CFrame.new(
			0,
			0,
			-mid
		),
			Vector3.new(size.X, 0.3, across)
	end
	return CFrame.new(frame.Position.X, low + size.Y / 2, frame.Position.Z) * frame.Rotation * CFrame.new(0, 0, -offset),
		size
end

-- where the crosshair meets the world (not the soldier, not the ghost)
local function aimPoint(character: Model): Vector3?
	local cam = workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, cam }
	local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * (C.Reach + 20), params)
	return hit and hit.Position
end

local function survey(character: Model, root: BasePart)
	local p = piece()
	local at = aimPoint(character)
	if not at then
		current = nil
		return
	end
	local look = workspace.CurrentCamera.CFrame.LookVector
	local yaw = CFrame.Angles(0, math.rad(turn), 0)
	local frame = Survey.frame(at, yaw:VectorToWorldSpace(look))
	local f = workspace:FindFirstChild(C.Folder)
	local team = character:GetAttribute("Kit")
	local joins = {}
	if p.kind == "Trench" and type(team) == "string" then
		frame, joins = Survey.snap(f, team, frame)
	end
	local report = Survey.ground(p, frame)
	frame = CFrame.new(frame.Position.X, report.centre, frame.Position.Z) * frame.Rotation
	local ignore: { Instance } = { character }
	if ghost then
		table.insert(ignore, ghost)
	end
	local ok, reason = Rules.canPlace({
		piece = p,
		distance = (root.Position - frame.Position).Magnitude,
		reach = C.Reach,
		slope = report.slope,
		maxSlope = p.maxSlope or C.Trench.maxSlope,
		ground = report.ground,
		water = report.water,
		overlap = Survey.blocked(p, frame, report.low, f, joins, ignore),
		mine = 0, -- (the caps are the server's to check)
		team = 0,
		perPlayer = C.PerPlayer,
		perTeam = C.PerTeam,
	})
	current = { frame = frame, ok = ok, reason = reason }
	if not ghost or ghostFor ~= p.key then
		clearGhost()
		ghost = makeGhost()
		ghostFor = p.key
	end
	local cf, size = ghostFrame(p, frame, report.low)
	local box = (ghost :: Model).PrimaryPart :: BasePart
	box.Size = size
	box.CFrame = cf
	box.Color = rgb(if ok then C.Ghost.ok else C.Ghost.bad)
end

-- the piece in swing reach, the one most in front of you
local function target(root: BasePart): Model?
	local f = workspace:FindFirstChild(C.Folder)
	if not f then
		return nil
	end
	local look = workspace.CurrentCamera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local best, bestScore = nil, -math.huge
	for _, m in f:GetChildren() do
		if m:IsA("Model") then
			local d = Survey.distanceTo(m, root.Position)
			if d <= C.SwingReach then
				local frame = m:GetAttribute("Frame")
				local towards = if typeof(frame) == "CFrame" then frame.Position - root.Position else Vector3.zero
				towards = Vector3.new(towards.X, 0, towards.Z)
				local facing = if towards.Magnitude > 1e-3 and flat.Magnitude > 1e-3
					then towards.Unit:Dot(flat.Unit)
					else 1
				local score = facing - d / C.SwingReach
				if score > bestScore then
					best, bestScore = m, score
				end
			end
		end
	end
	return best
end

local function hud(player: Player): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -96)
	label.Size = UDim2.fromOffset(640, 30)
	label.BackgroundColor3 = rgb(Palette.UI.Settings.panel)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = rgb(Palette.UI.Settings.text)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.Visible = false
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = label
	gui.Parent = player:WaitForChild("PlayerGui")
	return label
end

local function keyName(action: string): string
	local k = Settings.key(action)
	return string.gsub(k.Name, "MouseButton1", "Click")
end

function Build.start()
	local player = Players.LocalPlayer
	local label = hud(player)

	local function leave()
		active = false
		current = nil
		clearGhost()
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local character = player.Character
		if Settings.pressed("Key_Build", input) then
			if active then
				leave()
			elseif shovelHeld(character) then
				active = true
				turn = 0
			end
		elseif active and Settings.pressed("Key_BuildTurn", input) then
			local back = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			turn = (turn + (if back then -C.TurnStep else C.TurnStep)) % 360
		elseif active and Settings.pressed("Key_Fire", input) then
			if current and current.ok then
				Net.event("Build"):FireServer("Place", piece().key, current.frame)
				leave()
			elseif current and current.reason then
				notice = { text = current.reason, untilAt = os.clock() + 1.5 }
			end
		elseif active and input.UserInputType == Enum.UserInputType.MouseButton2 then
			leave()
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if not active or processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			turn = (turn + (if input.Position.Z > 0 then C.TurnStep else -C.TurnStep)) % 360
		else
			index = (index - 1 + (if input.Position.Z > 0 then -1 else 1)) % #C.Pieces + 1
		end
	end)
	Net.event("Build").OnClientEvent:Connect(function(kind: any, text: any)
		if kind == "Refused" and type(text) == "string" then
			notice = { text = text, untilAt = os.clock() + 2.5 }
		end
	end)

	-- a dig swing goes to the piece in front of you
	local function hook(character: Model)
		character:GetAttributeChangedSignal("DugAt"):Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if active or not root or character:GetAttribute("DugAt") == nil then
				return
			end
			local m = target(root)
			if m then
				Net.event("Build"):FireServer("Work", m)
			end
		end)
	end
	player.CharacterAdded:Connect(hook)
	if player.Character then
		hook(player.Character)
	end

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local holding = shovelHeld(character)
		if active and (not holding or not root) then
			leave()
		end
		local text: string? = nil
		if active and character and root then
			survey(character, root)
			local p = piece()
			text =
				`{p.name}  ·  wheel: piece  ·  {keyName("Key_BuildTurn")}: turn  ·  {keyName("Key_Fire")}: lay  ·  {keyName(
					"Key_Build"
				)}: done`
			if current and not current.ok and current.reason then
				text = `{current.reason}  ·  {text}`
			end
		elseif holding and character and root then
			local m = target(root)
			if m then
				local p = Rules.piece(m:GetAttribute("Piece"), C.Pieces)
				local work, need = m:GetAttribute("Work"), m:GetAttribute("Need")
				if p and type(work) == "number" and type(need) == "number" then
					local ours = m:GetAttribute("Team") == character:GetAttribute("Kit")
					text = if ours
						then (if work >= need
							then `{p.name}  ·  done`
							else `{p.name}  ·  {work} / {need}  ·  dig to build`)
						else `Enemy {string.lower(p.name)}  ·  {work} left  ·  dig to tear down`
				end
			else
				text = `{keyName("Key_Build")}: build`
			end
		end
		if notice and os.clock() < notice.untilAt then
			text = notice.text
		end
		label.Visible = text ~= nil
		label.Text = text or ""
	end)
end

return Build
