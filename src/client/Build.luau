--!strict
-- Build mode on the local client (Config/Build; the server decides: src/server/Build, src/server/Trenches). With the
-- shovel in the hands (Roblox's own camera stays: Config/Camera.FreeClasses, so everything here aims at the cursor):
-- - Key_Build opens build mode. The mouse wheel picks the piece. A piece's ghost follows the cursor on the ground,
--   green where it can go and red with the reason where not (shared/BuildSurvey, the same survey the server runs);
--   Key_BuildTurn turns it (Shift turns back), a click lays its blueprint (Net "Build" "Place"). A trench is planned
--   with two clicks: the start, then the end (the plan follows the cursor between them, snapped as the server will
--   snap it), sent as Net "Build" "Plan"; a short right click drops the start (a right drag turns the camera). Laying
--   leaves build mode.
-- - The trench planner's ghost (Config/Build.Plan; user 2026-10-24: "make the entire planning thing better and more
--   stylish", design page https://claude.ai/artifact/Peh9x7PLAo9wXuEca4aWQQ) previews what the server will peg out: per
--   square a chalk cord, a faint fill with the dug floor's band, ghost stakes (one at the cursor before the first
--   click; no flags, user 2026-10-24); a length tag over the end; and the reach circles of Trench.firstReach dashed on the
--   ground (round you before the first click, round both ends after it), red when you're too far.
-- - Key_Reload switches the shovel between Build and Destroy (user 2026-10-23). Out of build mode each dig swing
--   (src/client/Shovel "DugAt") goes to what you point at in reach (Net "Build" "Work" with the mode): a piece or
--   trench block, or in Destroy mode a tree.
-- A panel at the bottom of the screen says what is going on: the state as its title, an edge green / red / amber (can
-- go, can't, the shovel out but not planning), the keys underneath.

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
local P = C.Plan
local TOP = Rules.trenchTop(T)
local HUD = Palette.UI.BuildHud
local TAP = 0.3 -- a right click shorter than this (seconds), moving the mouse less than TAP_MOVE pixels, is "back"
local TAP_MOVE = 8

local active = false
local index = 1
local turn = 0
local mode = "Build"
local ghost: Model? = nil
local ghostFor: string? = nil
local current: { frame: CFrame?, a: Vector3?, b: Vector3?, ok: boolean, reason: string? }? = nil
local planStart: Vector3? = nil
local planInfo: { length: number, squares: number, clamped: boolean }? = nil
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

-- the trench planner's ghost: its model and the pieces drawn each frame
type Square = { fill: Part, floor: Part, cords: { Part }, pegs: { Part }, shown: number }
type Plan = {
	model: Model,
	squares: { Square },
	start: Part,
	rings: { { Part } },
	anchor: Part,
	tag: BillboardGui,
	title: TextLabel,
	sub: TextLabel,
}
local plan: Plan? = nil

local function clearGhost()
	if ghost then
		ghost:Destroy()
	end
	ghost, ghostFor = nil, nil
	if plan then
		plan.model:Destroy()
		plan.tag:Destroy()
		plan = nil
	end
	planInfo = nil
end

local function ghostPart(parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Parent = parent
	return part
end

-- the ghost: one box (a piece's footprint)
local function makeGhost(): Model
	local m = Instance.new("Model")
	m.Name = "BuildGhost"
	local part = ghostPart(m)
	part.Name = "Box"
	part.Transparency = C.Ghost.transparency
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

local function label(parent: Instance, font: Font, size: number, color: { number }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = rgb(color)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Size = UDim2.fromOffset(0, 0)
	l.Parent = parent
	return l
end

local TITLE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local BODY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)

local function makePlan(player: Player): Plan
	local m = Instance.new("Model")
	m.Name = "BuildGhost"
	m.Parent = workspace.CurrentCamera
	local start = ghostPart(m)
	start.Name = "Start"
	local rings = {}
	for i = 1, 2 do
		local dashes = {}
		for d = 1, P.dashes do
			dashes[d] = ghostPart(m)
		end
		rings[i] = dashes
	end
	local anchor = ghostPart(m)
	-- the length tag over the end
	local tag = Instance.new("BillboardGui")
	tag.Name = "BuildPlanTag"
	tag.Adornee = anchor
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.Size = UDim2.fromOffset(200, 48)
	tag.StudsOffsetWorldSpace = Vector3.new(0, P.tag, 0)
	tag.Enabled = false
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.fromScale(0.5, 1)
	box.AutomaticSize = Enum.AutomaticSize.XY
	box.Size = UDim2.fromOffset(0, 0)
	box.BackgroundColor3 = rgb(HUD.panel)
	box.BackgroundTransparency = 0.15
	box.Parent = tag
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 5), UDim.new(0, 6)
	pad.Parent = box
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, 1)
	list.Parent = box
	local title = label(box, TITLE, 17, HUD.title)
	local sub = label(box, BODY, 11, HUD.hint)
	tag.Parent = player:WaitForChild("PlayerGui")
	return {
		model = m,
		squares = {},
		start = start,
		rings = rings,
		anchor = anchor,
		tag = tag,
		title = title,
		sub = sub,
	}
end

local function square(p: Plan, i: number): Square
	local s = p.squares[i]
	if s then
		return s
	end
	local cords, pegs = {}, {}
	for k = 1, 4 do
		cords[k] = ghostPart(p.model)
		pegs[k] = ghostPart(p.model)
	end
	s = { fill = ghostPart(p.model), floor = ghostPart(p.model), cords = cords, pegs = pegs, shown = 0 }
	p.squares[i] = s
	return s
end

-- a dashed circle on the ground (each dash dropped onto what's under it); hidden at transparency 1
local function ring(dashes: { Part }, centre: Vector3?, color: Color3, transparency: number, params: RaycastParams)
	local n = #dashes
	for d, part in dashes do
		if not centre or transparency >= 1 then
			part.Transparency = 1
			continue
		end
		local angle = (d - 1) / n * 2 * math.pi
		local at = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * T.firstReach
		local hit = workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -10, 0), params)
		local y = if hit then hit.Position.Y else centre.Y
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local length = 2 * math.pi * T.firstReach / n * P.dash
		part.Size = Vector3.new(P.ringWidth, 0.06, length)
		part.CFrame = CFrame.lookAt(Vector3.new(at.X, y + 0.08, at.Z), Vector3.new(at.X, y + 0.08, at.Z) + tangent)
		part.Color = color
		part.Transparency = transparency
	end
end

-- where the cursor points into the world
local function aimRay(): Ray
	local mouse = UserInputService:GetMouseLocation()
	return workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
end

-- where the cursor meets the world (not the soldier, not the ghost)
local function aimHit(character: Model, reach: number): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, workspace.CurrentCamera }
	local ray = aimRay()
	return workspace:Raycast(ray.Origin, ray.Direction * (reach + 12), params)
end

local function surveyPiece(character: Model, root: BasePart)
	local p = piece()
	local hit = aimHit(character, C.Reach + 20)
	if not hit then
		current = nil
		return
	end
	local look = aimRay().Direction
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

-- draw the planner's ghost: the squares along `dir` from `a` (before the first click, a stake at `a`), the reach
-- circles and the tag
local function drawPlan(
	player: Player,
	character: Model,
	root: BasePart,
	a: Vector3,
	b: Vector3?,
	spans: { { from: number, to: number } },
	ok: boolean,
	tooFar: boolean,
	dt: number
)
	if not plan then
		clearGhost()
		plan = makePlan(player)
		ghostFor = "TrenchPlan"
	end
	local p = plan :: Plan
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, workspace.CurrentCamera }
	local flat = if b then Vector3.new(b.X - a.X, 0, b.Z - a.Z) else Vector3.zero
	local dir = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local y = if b then math.max(a.Y, b.Y) + 0.12 else a.Y + 0.12
	local fill = rgb(if ok then C.Ghost.ok else C.Ghost.bad)
	local chalk = rgb(if ok then Palette.Build.Chalk else Palette.Build.ChalkBad)
	local fade = 1 - math.exp(-P.fade * dt)
	local count = math.max(#spans, #p.squares)
	for i = 1, count do
		local s = square(p, i)
		local span = spans[i]
		s.shown += ((if span then 1 else 0) - s.shown) * fade
		if not span and s.shown < 0.02 then
			s.shown = 0
		end
		local function see(base: number): number
			return 1 - (1 - base) * s.shown
		end
		if span then
			local from, to = span.from + P.gap / 2, span.to - P.gap / 2
			local length = math.max(to - from, 0.2)
			local mid = a + dir * ((from + to) / 2)
			local centre = CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(mid.X + dir.X, y, mid.Z + dir.Z))
			s.fill.Size = Vector3.new(2 * TOP, 0.06, length)
			s.fill.CFrame = centre
			s.floor.Size = Vector3.new(2 * T.floor, 0.07, length)
			s.floor.CFrame = centre
			-- the cord round it, its stakes at the corners
			local half = TOP
			local corners = {
				centre * Vector3.new(-half, 0, length / 2),
				centre * Vector3.new(half, 0, length / 2),
				centre * Vector3.new(half, 0, -length / 2),
				centre * Vector3.new(-half, 0, -length / 2),
			}
			for k = 1, 4 do
				local c0, c1 = corners[k], corners[k % 4 + 1]
				local cord = s.cords[k]
				cord.Size = Vector3.new(P.cord, P.cord, (c1 - c0).Magnitude + P.cord)
				cord.CFrame = CFrame.lookAt((c0 + c1) / 2 + Vector3.new(0, 0.04, 0), c1 + Vector3.new(0, 0.04, 0))
				local peg = s.pegs[k]
				peg.Size = Vector3.new(P.peg[1], P.peg[2], P.peg[1])
				peg.CFrame = CFrame.new(c0 + Vector3.new(0, P.peg[2] / 2 - 0.1, 0))
			end
		end
		s.fill.Color, s.floor.Color = fill, fill
		s.fill.Transparency = see(P.fill)
		s.floor.Transparency = see(P.floor)
		for k = 1, 4 do
			s.cords[k].Color = chalk
			s.cords[k].Transparency = see(P.cordSee)
			s.pegs[k].Color = chalk
			s.pegs[k].Transparency = see(P.cordSee)
		end
	end
	-- before the first click, one ghost stake at the cursor where the start would go
	p.start.Size = Vector3.new(P.peg[1], P.peg[2], P.peg[1])
	p.start.CFrame = CFrame.new(a + Vector3.new(0, P.peg[2] / 2 - 0.1, 0))
	p.start.Color = chalk
	p.start.Transparency = if b then 1 else P.cordSee
	-- the reach circles: round you before the first click, round both ends after it (the one you're in brighter)
	local function away(q: Vector3): number
		return Vector3.new(root.Position.X - q.X, 0, root.Position.Z - q.Z).Magnitude
	end
	local ringColor = rgb(if tooFar then Palette.Build.ChalkBad else Palette.Build.Chalk)
	if b then
		local inA, inB = away(a) <= T.firstReach, away(b) <= T.firstReach
		ring(p.rings[1], a, ringColor, if inA or tooFar then P.near else P.far, params)
		ring(p.rings[2], b, ringColor, if inB and not inA or tooFar then P.near else P.far, params)
	else
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), params)
		local feet = if hit then hit.Position else root.Position - Vector3.new(0, 3, 0)
		ring(p.rings[1], feet, ringColor, P.near, params)
		ring(p.rings[2], nil, ringColor, 1, params)
	end
	-- the length tag over the end
	local info = planInfo
	p.tag.Enabled = b ~= nil and info ~= nil
	if b and info then
		p.anchor.CFrame = CFrame.new(b)
		p.title.Text = `{math.floor(info.length + 0.5)} STUDS  ·  {info.squares} {if info.squares == 1
			then "SQUARE"
			else "SQUARES"}`
		p.sub.Text = if info.clamped then `max {T.maxPlan}` else ""
		p.sub.Visible = info.clamped
	end
end

-- the trench plan between the start (or the cursor, before the first click) and the cursor
local function surveyPlan(player: Player, character: Model, root: BasePart, dt: number)
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
	if not planStart then
		local far = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z).Magnitude > T.firstReach
		if far then
			ok, reason = false, `Too far: start within {T.firstReach} studs of you`
		end
		current = { a = aim, ok = ok, reason = reason }
		planInfo = nil
		drawPlan(player, character, root, aim, nil, {}, ok, far, dt)
		return
	end
	local a, aKind, aModel, aOut = Survey.trenchSnap(f, team, planStart)
	local flat = Vector3.new(aim.X - a.X, 0, aim.Z - a.Z)
	local length = flat.Magnitude
	-- keep the end within a plan's length
	local clamped = false
	if length > T.maxPlan then
		flat = flat.Unit * T.maxPlan
		aim = Vector3.new(a.X + flat.X, aim.Y, a.Z + flat.Z)
		aimKind, aimModel, aimOut = nil, nil, nil
		length = T.maxPlan
		clamped = true
	end
	if length < T.minBlock then
		ok, reason = false, "Too short"
	end
	-- laid only while you stand near one of its ends (the server's check, Trenches.plan)
	local function away(p: Vector3): number
		return Vector3.new(root.Position.X - p.X, 0, root.Position.Z - p.Z).Magnitude
	end
	local tooFar = math.min(away(a), away(aim)) > T.firstReach
	if ok and tooFar then
		ok, reason = false, `Too far: stand within {T.firstReach} studs of either end`
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
	-- one square per segment, gaps between, so each square shows (user 2026-10-23: "have a string during planning for
	-- each square too")
	local spans = Rules.planBlocks(math.max(length, T.minBlock), T.block, T.minBlock) or {}
	planInfo = { length = length, squares = #spans, clamped = clamped }
	drawPlan(player, character, root, a, aim, spans, ok, tooFar, dt)
end

-- what a swing goes to: the trench block or piece in reach most toward the cursor, or (Destroy) a tree you point at
local function target(character: Model, root: BasePart): Instance?
	local f = workspace:FindFirstChild(C.Folder)
	local look = aimRay().Direction
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

-- the HUD panel: an edge, a title with a line beside it, the keys as key caps underneath
type Key = { string } -- the key's name, what it does
type Hud = { set: (state: string?, title: string, sub: string?, keys: { Key }) -> () }

local function hud(player: Player): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -92)
	panel.Size = UDim2.fromOffset(0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.BackgroundColor3 = rgb(HUD.panel)
	panel.BackgroundTransparency = 0.18
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = panel
	local size = Instance.new("UISizeConstraint")
	size.MinSize = Vector2.new(360, 0)
	size.Parent = panel
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.BorderSizePixel = 0
	edge.Size = UDim2.new(0, 6, 1, 0)
	edge.Parent = panel
	local edgeCorner = Instance.new("UICorner")
	edgeCorner.CornerRadius = UDim.new(0, 4)
	edgeCorner.Parent = edge
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.AutomaticSize = Enum.AutomaticSize.XY
	inner.Size = UDim2.fromOffset(0, 0)
	inner.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 20), UDim.new(0, 16)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 10)
	pad.Parent = inner
	local rows = Instance.new("UIListLayout")
	rows.FillDirection = Enum.FillDirection.Vertical
	rows.Padding = UDim.new(0, 6)
	rows.SortOrder = Enum.SortOrder.LayoutOrder
	rows.Parent = inner
	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.AutomaticSize = Enum.AutomaticSize.XY
	top.Size = UDim2.fromOffset(0, 0)
	top.LayoutOrder = 1
	top.Parent = inner
	local topList = Instance.new("UIListLayout")
	topList.FillDirection = Enum.FillDirection.Horizontal
	topList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	topList.Padding = UDim.new(0, 10)
	topList.SortOrder = Enum.SortOrder.LayoutOrder
	topList.Parent = top
	local title = label(top, TITLE, 19, HUD.title)
	title.LayoutOrder = 1
	local sub = label(top, BODY, 14, HUD.sub)
	sub.LayoutOrder = 2
	local keyRow = Instance.new("Frame")
	keyRow.BackgroundTransparency = 1
	keyRow.AutomaticSize = Enum.AutomaticSize.XY
	keyRow.Size = UDim2.fromOffset(0, 0)
	keyRow.LayoutOrder = 2
	keyRow.Parent = inner
	local keyList = Instance.new("UIListLayout")
	keyList.FillDirection = Enum.FillDirection.Horizontal
	keyList.VerticalAlignment = Enum.VerticalAlignment.Center
	keyList.Padding = UDim.new(0, 14)
	keyList.SortOrder = Enum.SortOrder.LayoutOrder
	keyList.Parent = keyRow
	gui.Parent = player:WaitForChild("PlayerGui")

	local shownKeys = ""
	local function setKeys(keys: { Key })
		local sign = ""
		for _, k in keys do
			sign ..= k[1] .. "\0" .. k[2] .. "\0"
		end
		if sign == shownKeys then
			return
		end
		shownKeys = sign
		for _, c in keyRow:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for i, k in keys do
			local item = Instance.new("Frame")
			item.BackgroundTransparency = 1
			item.AutomaticSize = Enum.AutomaticSize.XY
			item.Size = UDim2.fromOffset(0, 0)
			item.LayoutOrder = i
			item.Parent = keyRow
			local itemList = Instance.new("UIListLayout")
			itemList.FillDirection = Enum.FillDirection.Horizontal
			itemList.VerticalAlignment = Enum.VerticalAlignment.Center
			itemList.Padding = UDim.new(0, 6)
			itemList.SortOrder = Enum.SortOrder.LayoutOrder
			itemList.Parent = item
			local cap = label(item, BODY, 12, HUD.keyText)
			cap.Text = k[1]
			cap.LayoutOrder = 1
			cap.BackgroundColor3 = rgb(HUD.key)
			cap.BackgroundTransparency = 0
			local capPad = Instance.new("UIPadding")
			capPad.PaddingLeft, capPad.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
			capPad.PaddingTop, capPad.PaddingBottom = UDim.new(0, 2), UDim.new(0, 2)
			capPad.Parent = cap
			local capCorner = Instance.new("UICorner")
			capCorner.CornerRadius = UDim.new(0, 2)
			capCorner.Parent = cap
			local hint = label(item, BODY, 13, HUD.hint)
			hint.Text = k[2]
			hint.LayoutOrder = 2
		end
	end

	return {
		set = function(state: string?, text: string, line: string?, keys: { Key })
			panel.Visible = state ~= nil
			if not state then
				return
			end
			edge.BackgroundColor3 = rgb(if state == "bad" then HUD.bad elseif state == "ok" then HUD.ok else HUD.idle)
			title.Text = string.upper(text)
			title.TextColor3 = rgb(if state == "bad" then HUD.titleBad else HUD.title)
			sub.Text = line or ""
			sub.Visible = line ~= nil and line ~= ""
			setKeys(keys)
		end,
	}
end

local function keyName(action: string): string
	local k = Settings.key(action)
	return (string.gsub(k.Name, "MouseButton1", "Click"))
end

-- a reason as a title and the rest ("Too far: stand within ..." -> "Too far", "stand within ...")
local function split(reason: string): (string, string?)
	local head, rest = string.match(reason, "^(.-):%s*(.+)$")
	if not head then
		head, rest = string.match(reason, "^(.-),%s*(.+)$")
	end
	if head and rest then
		return head, rest
	end
	return reason, nil
end

function Build.start()
	local player = Players.LocalPlayer
	local panel = hud(player)

	local function leave()
		active = false
		current = nil
		planStart = nil
		clearGhost()
	end

	-- a right click: short and still it means "back" (a right drag turns Roblox's camera)
	local rightAt: number? = nil
	local rightMoved = 0

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
			rightAt, rightMoved = os.clock(), 0
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 or not rightAt then
			return
		end
		local tap = os.clock() - rightAt < TAP and rightMoved < TAP_MOVE
		rightAt = nil
		if not active or not tap then
			return
		end
		if planStart then
			planStart = nil -- drop the start
		else
			leave()
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if rightAt and input.UserInputType == Enum.UserInputType.MouseMovement then
			rightMoved += input.Delta.Magnitude
		end
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

	-- a dig swing goes to what you point at
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

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local holding = shovelHeld(character)
		if active and (not holding or not root) then
			leave()
		end
		local state: string?, title, line: string?, keys: { Key } = nil, "", nil, {}
		local fire, build, reload = keyName("Key_Fire"), keyName("Key_Build"), keyName("Key_Reload")
		if active and character and root then
			local p = piece()
			if p.kind == "Trench" then
				surveyPlan(player, character, root, dt)
				if planStart then
					local info = planInfo
					title = "Trench · pick the end"
					line = if info then `{math.floor(info.length + 0.5)} studs · {info.squares} squares` else nil
					keys = { { fire, "lay the plan" }, { "RMB", "back" }, { build, "done" } }
				else
					title = "Trench · pick the start"
					keys = { { fire, "lay the start" }, { "Wheel", "piece" }, { build, "done" } }
				end
			else
				surveyPiece(character, root)
				title = p.name
				keys = {
					{ fire, "lay" },
					{ "Wheel", "piece" },
					{ keyName("Key_BuildTurn"), "turn" },
					{ build, "done" },
				}
			end
			state = "ok"
			if current and not current.ok and current.reason then
				state = "bad"
				title, line = split(current.reason)
			end
		elseif holding and character and root then
			state = "idle"
			local other = if mode == "Build" then "Destroy" else "Build"
			local m = target(character, root)
			title = mode
			keys = { { fire, "dig" }, { reload, `switch to {other}` }, { build, "build" } }
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
					title = `{mode} · {mine}`
					line = if mode == "Destroy"
						then `{of} · dig to fill it in`
						elseif not ours then "switch to Destroy"
						elseif work >= need then "dug"
						else `{of} · dig to build`
				end
			elseif m then
				title, line = `{mode} · Tree`, "dig to chop it"
			end
		end
		if notice and os.clock() < notice.untilAt then
			state = "bad"
			title, line = split(notice.text)
		end
		panel.set(state, title, line, keys)
	end)
end

return Build
