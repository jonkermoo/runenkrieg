--!strict
-- Build mode on the local client (Config/Build; the server decides: src/server/Build, src/server/Trenches). With the
-- shovel in the hands:
-- - Key_Build opens build mode. The mouse wheel picks the piece. A piece's ghost follows the crosshair on the ground,
--   green where it can go and red with the reason where not (shared/BuildSurvey, the same survey the server runs);
--   Key_BuildTurn turns it (Shift turns back), a click lays its blueprint (Net "Build" "Place"). A trench is planned
--   with two clicks: the start, then the end (the outline follows the crosshair between them, snapped as the server
--   will snap it), sent as Net "Build" "Plan"; right click drops the start. Laying leaves build mode.
-- - Key_Reload switches the shovel between Build and Destroy (user 2026-10-23). Out of build mode each dig swing
--   (src/client/Shovel "DugAt") goes to what you face in reach (Net "Build" "Work" with the mode): a piece or trench
--   block, or in Destroy mode a tree.
-- A line at the bottom of the screen says what is going on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local Palette = require(Shared.Config.Palette)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Build)
local Survey = require(Shared.BuildSurvey)
local Net = require(Shared.Net)
local Held = require(script.Parent.Held)
local Settings = require(script.Parent.Settings)

local Build = {}

local T = C.Trench
local TOP = Rules.trenchTop(T)

local active = false
local index = 1
local turn = 0
local mode = "Build"
local ghost: Model? = nil
local ghostFor: string? = nil
local current: { frame: CFrame?, a: Vector3?, b: Vector3?, ok: boolean, reason: string? }? = nil
local planStart: Vector3? = nil
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

-- the ghost: one box (a piece's footprint, or a trench plan's band on the ground)
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

local function showGhost(key: string, cf: CFrame, size: Vector3, ok: boolean)
	if not ghost or ghostFor ~= key then
		clearGhost()
		ghost = makeGhost()
		ghostFor = key
	end
	local box = (ghost :: Model).PrimaryPart :: BasePart
	box.Size = size
	box.CFrame = cf
	box.Color = rgb(if ok then C.Ghost.ok else C.Ghost.bad)
end

-- where the crosshair meets the world (not the soldier, not the ghost)
local function aimHit(character: Model, reach: number): RaycastResult?
	local cam = workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, cam }
	return workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * reach, params)
end

local function surveyPiece(character: Model, root: BasePart)
	local p = piece()
	local hit = aimHit(character, C.Reach + 20)
	if not hit then
		current = nil
		return
	end
	local look = workspace.CurrentCamera.CFrame.LookVector
	local frame = Survey.frame(hit.Position, CFrame.Angles(0, math.rad(turn), 0):VectorToWorldSpace(look))
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
		maxSlope = p.maxSlope or T.maxSlope,
		ground = report.ground,
		water = report.water,
		overlap = Survey.blocked(p, frame, report.low, ignore),
		mine = 0, -- (the caps are the server's to check)
		team = 0,
		perPlayer = C.PerPlayer,
		perTeam = C.PerTeam,
	})
	current = { frame = frame, ok = ok, reason = reason }
	local size = Survey.footprint(p)
	showGhost(p.key, CFrame.new(frame.Position.X, report.low + size.Y / 2, frame.Position.Z) * frame.Rotation, size, ok)
end

-- the trench plan between the start (or the crosshair, before the first click) and the crosshair
local function surveyPlan(character: Model, root: BasePart)
	local hit = aimHit(character, T.maxPlan + 30)
	if not hit then
		current = nil
		return
	end
	local f = workspace:FindFirstChild(C.Folder)
	local team = character:GetAttribute("Kit")
	team = if type(team) == "string" then team else ""
	local aim, aimKind, aimModel, aimOut = Survey.trenchSnap(f, team, hit.Position)
	local ok, reason = true, nil
	-- every trench square's line, for the spacing rule (Rules.tooClose; the server's check, Trenches.plan)
	local segs = {}
	for _, m in (if f then f:GetChildren() else {}) do
		local ba, bb = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
		if typeof(ba) == "Vector3" and typeof(bb) == "Vector3" then
			table.insert(segs, { ba.X, ba.Z, bb.X, bb.Z })
		end
	end
	local spacingMsg = "Too close to another trench: extend it instead"
	if not planStart then
		if Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z).Magnitude > T.firstReach then
			ok, reason = false, `Too far: start within {T.firstReach} studs of you`
		elseif not aimKind and Rules.tooClose(aim.X, aim.Z, aim.X, aim.Z, false, false, segs, T.spacing) then
			ok, reason = false, spacingMsg
		end
		current = { a = aim, ok = ok, reason = reason }
		showGhost("TrenchStart", CFrame.new(aim + Vector3.new(0, 0.6, 0)), Vector3.new(1.2, 1.2, 1.2), ok)
		return
	end
	local a, aKind, aModel, aOut = Survey.trenchSnap(f, team, planStart)
	local flat = Vector3.new(aim.X - a.X, 0, aim.Z - a.Z)
	local length = flat.Magnitude
	-- keep the end within a plan's length
	if length > T.maxPlan then
		flat = flat.Unit * T.maxPlan
		aim = Vector3.new(a.X + flat.X, aim.Y, a.Z + flat.Z)
		aimKind, aimModel, aimOut = nil, nil, nil
		length = T.maxPlan
	end
	if length < T.minBlock then
		ok, reason = false, "Too short"
	end
	-- laid only while you stand near one of its ends (the server's check, Trenches.plan)
	local function away(p: Vector3): number
		return Vector3.new(root.Position.X - p.X, 0, root.Position.Z - p.Z).Magnitude
	end
	if ok and math.min(away(a), away(aim)) > T.firstReach then
		ok, reason = false, `Too far: stand within {T.firstReach} studs of either end`
	end
	if ok and Rules.tooClose(a.X, a.Z, aim.X, aim.Z, aKind ~= nil, aimKind ~= nil, segs, T.spacing) then
		ok, reason = false, spacingMsg
	end
	if ok and length > 0.1 then
		local dir = flat.Unit
		local sharpA = aKind == "end" and aOut and Rules.bend(aOut.X, aOut.Z, dir.X, dir.Z) > T.maxBend
		local sharpB = aimKind == "end" and aimOut and Rules.bend(aimOut.X, aimOut.Z, -dir.X, -dir.Z) > T.maxBend
		if sharpA or sharpB then
			ok, reason = false, "Too sharp a bend"
		end
		-- crossing a trench (the server has the last word; this checks the blocks it doesn't join)
		if ok and f then
			for _, m in f:GetChildren() do
				local ba, bb = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
				if typeof(ba) == "Vector3" and typeof(bb) == "Vector3" and m ~= aModel and m ~= aimModel then
					local mid = (ba + bb) / 2
					local bf = Vector3.new(bb.X - ba.X, 0, bb.Z - ba.Z)
					local t0, t1 = Rules.clipRect(
						a.X,
						a.Z,
						aim.X,
						aim.Z,
						mid.X,
						mid.Z,
						bf.Unit.X,
						bf.Unit.Z,
						bf.Magnitude / 2,
						TOP
					)
					if t0 and t1 and t0 * length > TOP + 2 and (1 - t1) * length > TOP + 2 then
						ok, reason = false, "Stop at the trench, then start again from the other side"
						break
					end
				end
			end
		end
	end
	current = { a = a, b = aim, ok = ok, reason = reason }
	-- one box per square, gaps between, so each square shows (user 2026-10-23: "have a string during planning for each
	-- square too")
	local spans = Rules.planBlocks(math.max(length, T.minBlock), T.block, T.minBlock) or {}
	if not ghost or ghostFor ~= "TrenchPlan" or #(ghost :: Model):GetChildren() ~= #spans then
		clearGhost()
		local made = Instance.new("Model")
		made.Name = "BuildGhost"
		for _ = 1, #spans do
			local box = Instance.new("Part")
			box.Anchored = true
			box.CanCollide = false
			box.CanQuery = false
			box.CanTouch = false
			box.CastShadow = false
			box.Material = Enum.Material.SmoothPlastic
			box.Transparency = C.Ghost.transparency
			box.Parent = made
		end
		made.Parent = workspace.CurrentCamera
		ghost, ghostFor = made, "TrenchPlan"
	end
	local boxes = (ghost :: Model):GetChildren()
	local y = math.max(a.Y, aim.Y) + 0.3
	local dir = if length > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	for i, span in spans do
		local mid = a + dir * ((span.from + span.to) / 2)
		local box = boxes[i] :: Part
		box.Color = rgb(if ok then C.Ghost.ok else C.Ghost.bad)
		box.Size = Vector3.new(2 * TOP, 0.3, math.max(span.to - span.from - 0.35, 0.2))
		box.CFrame = CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(mid.X + dir.X, y, mid.Z + dir.Z))
	end
end

-- what a swing goes to: the trench block or piece in reach most in front of you, or (Destroy) a tree you face
local function target(character: Model, root: BasePart): Instance?
	local f = workspace:FindFirstChild(C.Folder)
	local look = workspace.CurrentCamera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local best, bestScore = nil, -math.huge
	if f then
		for _, m in f:GetChildren() do
			if m:IsA("Model") then
				local block = m:GetAttribute("Kind") == "TrenchBlock"
				local reach = if block then T.swingReach else C.SwingReach
				local d = Survey.distanceTo(m, root.Position)
				if d <= reach then
					local a, b = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
					local frame = m:GetAttribute("Frame")
					local centre = if typeof(a) == "Vector3" and typeof(b) == "Vector3"
						then (a + b) / 2
						elseif typeof(frame) == "CFrame" then frame.Position
						else root.Position
					local towards = Vector3.new(centre.X - root.Position.X, 0, centre.Z - root.Position.Z)
					local facing = if towards.Magnitude > 1e-3 and flat.Magnitude > 1e-3
						then towards.Unit:Dot(flat.Unit)
						else 1
					local score = facing - d / reach
					if score > bestScore then
						best, bestScore = m, score
					end
				end
			end
		end
	end
	if mode == "Destroy" then
		local hit = aimHit(character, 12)
		if hit and hit.Instance.Name == "Trunk" and (not best or bestScore < 0.5) then
			return hit.Instance
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
	return (string.gsub(k.Name, "MouseButton1", "Click"))
end

function Build.start()
	local player = Players.LocalPlayer
	local label = hud(player)

	local function leave()
		active = false
		current = nil
		planStart = nil
		clearGhost()
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local character = player.Character
		local trench = piece().kind == "Trench"
		if Settings.pressed("Key_Build", input) then
			if active then
				leave()
			elseif shovelHeld(character) then
				active = true
				turn = 0
			end
		elseif not active and Settings.pressed("Key_Reload", input) and shovelHeld(character) then
			mode = if mode == "Build" then "Destroy" else "Build"
		elseif active and not trench and Settings.pressed("Key_BuildTurn", input) then
			local back = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			turn = (turn + (if back then -C.TurnStep else C.TurnStep)) % 360
		elseif active and Settings.pressed("Key_Fire", input) then
			if current and current.ok then
				if trench and not planStart then
					planStart = current.a
				elseif trench and current.a and current.b then
					Net.event("Build"):FireServer("Plan", current.a, current.b)
					leave()
				elseif current.frame then
					Net.event("Build"):FireServer("Place", piece().key, current.frame)
					leave()
				end
			elseif current and current.reason then
				notice = { text = current.reason, untilAt = os.clock() + 1.5 }
			end
		elseif active and input.UserInputType == Enum.UserInputType.MouseButton2 then
			if planStart then
				planStart = nil -- drop the start
			else
				leave()
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if not active or processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			turn = (turn + (if input.Position.Z > 0 then C.TurnStep else -C.TurnStep)) % 360
		elseif not planStart then
			index = (index - 1 + (if input.Position.Z > 0 then -1 else 1)) % #C.Pieces + 1
			clearGhost()
		end
	end)
	Net.event("Build").OnClientEvent:Connect(function(kind: any, text: any)
		if kind == "Refused" and type(text) == "string" then
			notice = { text = text, untilAt = os.clock() + 2.5 }
		end
	end)

	-- a dig swing goes to what you face
	local function hook(character: Model)
		character:GetAttributeChangedSignal("DugAt"):Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if active or not root or character:GetAttribute("DugAt") == nil then
				return
			end
			local t = target(character, root)
			if t then
				Net.event("Build"):FireServer("Work", t, mode)
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
			local p = piece()
			if p.kind == "Trench" then
				surveyPlan(character, root)
				text = if planStart
					then `Trench: {keyName("Key_Fire")} the end  ·  right click: back  ·  {keyName("Key_Build")}: done`
					else `Trench: {keyName("Key_Fire")} the start  ·  wheel: piece  ·  {keyName("Key_Build")}: done`
			else
				surveyPiece(character, root)
				text =
					`{p.name}  ·  wheel: piece  ·  {keyName("Key_BuildTurn")}: turn  ·  {keyName("Key_Fire")}: lay  ·  {keyName(
						"Key_Build"
					)}: done`
			end
			if current and not current.ok and current.reason then
				text = `{current.reason}  ·  {text}`
			end
		elseif holding and character and root then
			local m = target(character, root)
			local modeText = `{mode} ({keyName("Key_Reload")})`
			if m and m:IsA("Model") then
				local block = m:GetAttribute("Kind") == "TrenchBlock"
				local work = m:GetAttribute(if block then "HP" else "Work")
				local need = m:GetAttribute(if block then "MaxHP" else "Need")
				local name = if block
					then "Trench square"
					else ((Rules.piece(m:GetAttribute("Piece"), C.Pieces) or { name = "Piece" }) :: any).name
				if type(work) == "number" and type(need) == "number" then
					local ours = m:GetAttribute("Team") == character:GetAttribute("Kit")
					local mine = if ours then name else `Enemy {string.lower(name)}`
					local of = if block then `HP {work} / {need}` else `{work} / {need}`
					text = if mode == "Destroy"
						then `{modeText}  ·  {mine}  ·  {of}  ·  dig to fill it in`
						elseif not ours then `{modeText}  ·  {mine}: switch to Destroy`
						elseif work >= need then `{modeText}  ·  {name}  ·  dug`
						else `{modeText}  ·  {name}  ·  {of}  ·  dig to build`
				end
			elseif m then
				text = `{modeText}  ·  Tree  ·  dig to chop it`
			else
				text = `{modeText}  ·  {keyName("Key_Build")}: build`
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
