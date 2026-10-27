--!strict
-- Build mode on the local client (Config/Build; the server decides: src/server/Build, src/server/Trenches). With the
-- shovel in the hands (Roblox's own camera stays: Config/Camera.FreeClasses, so everything here aims at the cursor):
-- - Key_Build opens build mode. Key_BuildPrev / Key_BuildNext (Q / E) pick the piece. A piece's ghost follows the cursor on the ground,
--   green where it can go and red with the reason where not (shared/BuildSurvey, the same survey the server runs);
--   Key_BuildTurn turns it (Shift turns back), a click lays its blueprint (Net "Build" "Place"). A trench is planned
--   with two clicks: the start, then the end (the plan follows the cursor between them, snapped as the server will
--   snap it), sent as Net "Build" "Plan". Key_BuildExit (X) or Key_Build leaves build mode, dropping a start (right mouse stays
--   Roblox's camera turn). Laying leaves build mode.
-- - The trench planner's ghost (Config/Build.Plan; user 2026-10-24: "make the entire planning thing better and more
--   stylish") previews what the server will peg out: per
--   square a chalk cord, a faint fill with the dug floor's band, ghost stakes (no flags, user 2026-10-24); an icon
--   over each end, a new trench or extending one; a length tag over the end; and the reach circles of Trench.firstReach dashed on the
--   ground (round you before the first click, round both ends after it), red when you're too far.
-- - Key_Reload switches the shovel between Build and Destroy (user 2026-10-23). Out of build mode each dig swing
--   (src/client/Shovel "DugAt") goes to what you point at in reach (Net "Build" "Work" with the mode): a piece or
--   trench block, or in Destroy mode a tree.
-- A panel at the bottom of the screen says what is going on (src/client/BuildHud draws it, user 2026-10-27: a look of its
-- own for each mode): Build or Destroy with what you point at and its HP (Destroy: in stage blocks, and the swings to
-- clear it), Placing with the pieces before and after and whether it fits, the trench plan with its length on a rule;
-- an edge green / red where it can / can't go, the keys underneath.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local Palette = require(Shared.Config.Palette)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Build)
local ArtilleryCfg = require(Shared.Config.Artillery)
local ArtilleryRules = require(Shared.Rules.Artillery)
local Classes = require(Shared.Config.Classes)
local DevCfg = require(Shared.Config.DevTools)
local ClassRules = require(Shared.Rules.Classes)
local Survey = require(Shared.BuildSurvey)
local Net = require(Shared.Net)
local Held = require(script.Parent.Held)
local BuildHud = require(script.Parent.BuildHud)
local Settings = require(script.Parent.Settings)

local Build = {}

local T = C.Trench
local P = C.Plan
local TOP = Rules.trenchTop(T)
local HUD = Palette.UI.BuildHud

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
local focus: Model? = nil -- the trench square the plan snaps to (extending or branching off), lit faintly

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- whether build mode is open (src/client/Shovel: a click then lays a piece instead of digging)
function Build.active(): boolean
	return active
end

-- the shovel's mode, "Build" or "Destroy" (src/client/Shovel swings by it)
function Build.mode(): string
	return mode
end

local function shovelHeld(character: Model?): boolean
	local weapon = Held.weapon(character)
	return weapon ~= nil and W[weapon.name] ~= nil and W[weapon.name].class == "Shovel"
end

-- the pieces this life's class may build (src/server/Loadouts' "Class"; the rest never show in the cycle), or every
-- piece with the admin panel's build anything
local function pieces(): { Rules.Piece }
	local player = Players.LocalPlayer
	if player:GetAttribute(DevCfg.Admin.BuildAllAttribute) == true then
		return C.Pieces
	end
	local character = player.Character
	return ClassRules.buildable(character and character:GetAttribute("Class"), C.Pieces, Classes.Defs, Classes.Default)
end

local function piece(): Rules.Piece
	local list = pieces()
	return list[math.clamp(index, 1, #list)]
end

-- the trench planner's ghost: its model and the pieces drawn each frame
type Square = { fill: Part, floor: Part, cords: { Part }, pegs: { Part }, shown: number }
-- an action icon over a point being placed (user 2026-10-24: "add an icon for what action you're doing instead of a
-- green square. one icon for new trenches, one more extending"): a round badge on a chalk pin
type Badge = { gui: BillboardGui, anchor: Part, pin: Part, ring: UIStroke, new: Frame, extend: Frame }
type Plan = {
	model: Model,
	squares: { Square },
	badges: { Badge },
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
		for _, bd in plan.badges do
			bd.gui:Destroy()
		end
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

-- a gun piece's ghost (Config/Build.GunGhost; user 2026-10-27: "for the field gun and artillery, dont show the actual
-- model ... just show how much space it actually takes (the visible model with applicable trench)"): a see-through box
-- round the gun's visible model in gun space (as src/server/Artillery finds it, from the Bore at rest) and, dug in, its
-- pit (out to the top of its wall) and ramp outlined on the ground; nil without the gun's model
local function makeGunGhost(gun: ArtilleryCfg.Gun): Model?
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, sub in { "Weapons", "Shared", "Artillery", gun.asset } do
		f = f and f:FindFirstChild(sub)
	end
	local src = if f and f:IsA("Model") then f else nil
	local bore = src and src:FindFirstChild("Bore", true)
	local barrel = src and src:FindFirstChild(gun.barrel[1], true)
	if not src or not bore or not barrel or not bore:IsA("BasePart") or not barrel:IsA("BasePart") then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "BuildGhost"
	local dir = bore.Position - barrel.Position
	local rot = CFrame.Angles(0, math.rad(ArtilleryRules.yawOf(dir.X, dir.Z)), 0)
	local mz = gun.muzzle
	local origin = bore.Position - rot:VectorToWorldSpace(Vector3.new(mz[1], mz[2], mz[3] + gun.boreCentre))
	-- the box round its visible parts (gun space: lined up with the gun, from its pivot)
	local pivot = CFrame.new(origin) * rot
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in src:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local half = d.Size / 2
			for _, c in
				{
					Vector3.new(-1, -1, -1),
					Vector3.new(1, -1, -1),
					Vector3.new(-1, 1, -1),
					Vector3.new(1, 1, -1),
					Vector3.new(-1, -1, 1),
					Vector3.new(1, -1, 1),
					Vector3.new(-1, 1, 1),
					Vector3.new(1, 1, 1),
				}
			do
				local q = pivot:PointToObjectSpace(d.CFrame:PointToWorldSpace(half * c))
				lo, hi = lo:Min(q), hi:Max(q)
			end
		end
	end
	local body = ghostPart(m)
	body.Name = "Gun"
	body.Transparency = C.Ghost.transparency
	body.Size = hi - lo
	body:SetAttribute("Offset", CFrame.new((lo + hi) / 2))
	local d = gun.dig
	if d then
		local G = C.GunGhost
		local top = d.radius + (if d.wall then d.depth / math.tan(math.rad(d.wall)) else 0)
		local pit = ghostPart(m)
		pit.Name = "Pit"
		pit.Shape = Enum.PartType.Cylinder
		pit.Transparency = G.outlineSee
		pit.Size = Vector3.new(G.outline, top * 2, top * 2)
		if d.ramp then
			local ramp = ghostPart(m)
			ramp.Name = "Ramp"
			ramp.Transparency = G.outlineSee
			ramp.Size = Vector3.new(d.ramp.width, G.outline, d.ramp.length)
		end
	end
	m.Parent = workspace.CurrentCamera
	return m
end

-- shows a gun piece's ghost: the gun where it will stand (`at`: the ground at the click, `look`: flat), its pit and ramp
-- on the ground there. False without the gun's model (its box is shown instead).
local function showGunGhost(key: string, gun: ArtilleryCfg.Gun, at: CFrame, ok: boolean): boolean
	if not ghost or ghostFor ~= key then
		clearGhost()
		ghost = makeGunGhost(gun)
		ghostFor = if ghost then key else nil
	end
	local m = ghost
	local body = m and m:FindFirstChild("Gun") :: BasePart?
	if not m or not body then
		return false
	end
	local color = rgb(if ok then C.Ghost.ok else C.Ghost.bad)
	local d = gun.dig
	body.CFrame = at * CFrame.new(0, -(if d then d.depth else 0), 0) * (body:GetAttribute("Offset") :: CFrame)
	body.Color = color
	local lift = C.GunGhost.outline / 2 + 0.05
	local pit = m:FindFirstChild("Pit") :: BasePart?
	if pit then
		pit.CFrame = at * CFrame.new(0, lift, 0) * CFrame.Angles(0, 0, math.rad(90))
		pit.Color = color
	end
	local ramp = m:FindFirstChild("Ramp") :: BasePart?
	if ramp and d and d.ramp then
		-- (behind the gun, +Z, from the floor's edge out)
		ramp.CFrame = at * CFrame.new(0, lift + 0.02, d.radius + d.ramp.length / 2)
		ramp.Color = color
	end
	return true
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

-- the game's basic font (user 2026-10-27), for the plan's length tag as for the panel (src/client/BuildHud)
local TITLE = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)

-- a shape in an icon, in the badge's unit square (x, y, width, height), rotated by `rotation` degrees
local function shape(parent: Instance, x: number, y: number, w: number, h: number, color: { number }, rotation: number?)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x + w / 2, y + h / 2)
	f.Size = UDim2.fromScale(w, h)
	f.Rotation = rotation or 0
	f.BackgroundColor3 = rgb(color)
	f.Parent = parent
end

local function icon(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.Parent = parent
	return f
end

local function badge(player: Player, model: Model): Badge
	local anchor = ghostPart(model)
	local pin = ghostPart(model)
	pin.Color = rgb(Palette.Build.Chalk)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BuildPlanIcon"
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromScale(P.badge.size, P.badge.size) -- (studs: it sits on the pin at any distance)
	gui.StudsOffsetWorldSpace = Vector3.new(0, P.badge.height + P.badge.size / 2, 0)
	gui.Enabled = false
	local disc = Instance.new("Frame")
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundColor3 = rgb(HUD.panel)
	disc.BackgroundTransparency = 0.12
	disc.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = disc
	local ring = Instance.new("UIStroke")
	ring.Thickness = 3
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = disc
	local chalk, dim = Palette.Build.Chalk, Palette.Build.IconDim
	-- new trench: a stake (its top dim) and a plus
	local new = icon(disc, "New")
	shape(new, 0.276, 0.237, 0.092, 0.5, chalk)
	shape(new, 0.276, 0.237, 0.092, 0.105, dim)
	shape(new, 0.5, 0.447, 0.29, 0.079, chalk)
	shape(new, 0.605, 0.342, 0.079, 0.29, chalk)
	-- extend: a trench piece (dim) and an arrow leading on from it
	local extend = icon(disc, "Extend")
	shape(extend, 0.158, 0.368, 0.237, 0.263, dim)
	shape(extend, 0.44, 0.46, 0.33, 0.079, chalk)
	shape(extend, 0.57, 0.377, 0.26, 0.079, chalk, 40)
	shape(extend, 0.57, 0.543, 0.26, 0.079, chalk, -40)
	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, anchor = anchor, pin = pin, ring = ring, new = new, extend = extend }
end

local function makePlan(player: Player): Plan
	local m = Instance.new("Model")
	m.Name = "BuildGhost"
	m.Parent = workspace.CurrentCamera
	local badges = { badge(player, m), badge(player, m) }
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
	local sub = label(box, TITLE, 11, HUD.hint)
	tag.Parent = player:WaitForChild("PlayerGui")
	return {
		model = m,
		squares = {},
		badges = badges,
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
	if p.kind == "Bridge" then
		-- a bridge snaps across the trench square under the cursor (Survey.bridgeSpot), its ghost the deck
		local s, onSquare, length = Survey.bridgeSpot(workspace:FindFirstChild(C.Folder), hit.Position)
		local at = onSquare or Survey.frame(hit.Position, look)
		local ok, reason = Rules.canPlace({
			piece = p,
			distance = (root.Position - at.Position).Magnitude,
			reach = C.Reach,
			spot = Rules.bridgeSpot(s, C.Bridge),
			slope = 0,
			maxSlope = 0,
			ground = true,
			water = false,
			overlap = onSquare ~= nil and Survey.onPiece(p, at, workspace:FindFirstChild(C.Folder)),
			mine = 0, -- (the caps are the server's to check)
			team = 0,
			perPlayer = C.PerPlayer,
			perTeam = C.PerTeam,
		})
		current = { frame = at, ok = ok, reason = reason }
		local deck = if onSquare then p.height else 0
		local g = C.Bridge.ghost
		showGhost(p.key, at * CFrame.new(0, deck - g / 2, 0), Vector3.new(length or p.width, g, p.depth), ok)
		return
	end
	local frame = Survey.frame(hit.Position, CFrame.Angles(0, math.rad(turn), 0):VectorToWorldSpace(look))
	-- (a gun: the click is where the gun goes, its ghost the ground it needs: Survey.box)
	local gun = p.kind == "Gun"
	local at = frame.Position
	local box = Survey.box(p, frame)
	local report = Survey.ground(p, box)
	box = CFrame.new(box.Position.X, report.centre, box.Position.Z) * box.Rotation
	local ignore: { Instance } = { character }
	if ghost then
		table.insert(ignore, ghost)
	end
	local f = workspace:FindFirstChild(C.Folder)
	local ok, reason = Rules.canPlace({
		piece = p,
		distance = (root.Position - (if gun then at else box.Position)).Magnitude,
		reach = C.Reach,
		slope = report.slope,
		maxSlope = p.maxSlope or T.maxSlope,
		ground = report.ground,
		water = report.water,
		overlap = Survey.blocked(p, box, report.low, ignore) or Survey.onPiece(p, box, f),
		gunGap = gun and Survey.gunGap(p, at, f),
		nearTrench = (gun or p.kind == "Wire") and Survey.nearTrench(p, box, f),
		mine = 0, -- (the caps are the server's to check)
		team = 0,
		perPlayer = C.PerPlayer,
		perTeam = C.PerTeam,
	})
	current = { frame = if gun then frame else box, ok = ok, reason = reason }
	local gunCfg = if gun then ArtilleryCfg.Guns[p.gun or ""] else nil
	if gunCfg then
		-- (the gun as it will stand, not its whole box: user 2026-10-27)
		if showGunGhost(p.key, gunCfg, frame, ok) then
			return
		end
	end
	local size = Survey.footprint(p)
	showGhost(p.key, CFrame.new(box.Position.X, report.low + size.Y / 2, box.Position.Z) * box.Rotation, size, ok)
end

-- draw the planner's ghost: the squares along `dir` from `a` (none before the first click), the action icons over
-- the ends (`kinds`: what each joins, nil for a new trench), the reach circles and the tag
local function drawPlan(
	player: Player,
	character: Model,
	root: BasePart,
	a: Vector3,
	b: Vector3?,
	spans: { { from: number, to: number } },
	ok: boolean,
	tooFar: boolean,
	kinds: { string? },
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
	-- the action icons: over the cursor before the first click, over both ends after it; a new trench or extending one
	-- (an end on a trench: Survey.trenchSnap's "end" or "tee")
	local points: { Vector3 } = if b then { a, b } else { a }
	for i, bd in p.badges do
		local at = points[i]
		bd.gui.Enabled = at ~= nil
		bd.pin.Transparency = if at then P.cordSee else 1
		if at then
			bd.anchor.CFrame = CFrame.new(at)
			bd.pin.Size = Vector3.new(0.07, P.badge.height, 0.07)
			bd.pin.CFrame = CFrame.new(at + Vector3.new(0, P.badge.height / 2, 0))
			bd.ring.Color = rgb(if ok then HUD.ok else HUD.bad)
			local joins = kinds[i] ~= nil
			bd.new.Visible, bd.extend.Visible = not joins, joins
		end
	end
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
	focus = aimModel
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
		local far = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z).Magnitude > T.firstReach
		if far then
			ok, reason = false, `Too far: start within {T.firstReach} studs of you`
		elseif not aimKind and Rules.tooClose(aim.X, aim.Z, aim.X, aim.Z, false, false, segs, T.spacing) then
			ok, reason = false, spacingMsg
		end
		current = { a = aim, ok = ok, reason = reason }
		planInfo = nil
		drawPlan(player, character, root, aim, nil, {}, ok, far, { aimKind }, dt)
		return
	end
	local a, aKind, aModel, aOut = Survey.trenchSnap(f, team, planStart)
	focus = aimModel or aModel
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
	-- one square per segment, gaps between, so each square shows (user 2026-10-23: "have a string during planning for
	-- each square too")
	local spans = Rules.planBlocks(math.max(length, T.minBlock), T.block, T.minBlock) or {}
	planInfo = { length = length, squares = #spans, clamped = clamped }
	drawPlan(player, character, root, a, aim, spans, ok, tooFar, { aKind, aimKind }, dt)
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
	local panel = BuildHud.new(player)

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
		-- (Key_BuildExit leaves build mode: right mouse is Roblox's camera turn, user 2026-10-24: "because right click is
		-- cancel, players are unable to change their camera angle while planning. make it Q to exit plan mode")
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
		elseif active and Settings.pressed("Key_BuildExit", input) then
			leave()
		elseif
			active
			and not planStart
			and (Settings.pressed("Key_BuildPrev", input) or Settings.pressed("Key_BuildNext", input))
		then
			-- (not the mouse wheel: it fought the other scrolling, user 2026-10-27)
			local step = if Settings.pressed("Key_BuildPrev", input) then -1 else 1
			local n = #pieces()
			index = (math.clamp(index, 1, n) - 1 + step) % n + 1
			clearGhost()
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if not active or processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			turn = (turn + (if input.Position.Z > 0 then C.TurnStep else -C.TurnStep)) % 360
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

	-- the faint light on the trench square in focus
	local glow = Instance.new("Highlight")
	glow.Name = "BuildFocus"
	glow.FillColor = rgb(Palette.Build.Focus)
	glow.OutlineColor = rgb(Palette.Build.Focus)
	glow.FillTransparency = C.Focus.fill
	glow.OutlineTransparency = C.Focus.outline
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Enabled = false
	glow.Parent = workspace.CurrentCamera -- (client only)

	RunService.RenderStepped:Connect(function(dt)
		focus = nil
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local holding = shovelHeld(character)
		if active and (not holding or not root) then
			leave()
		end
		local view: BuildHud.View? = nil
		local fire, build, reload = keyName("Key_Fire"), keyName("Key_Build"), keyName("Key_Reload")
		local exit = keyName("Key_BuildExit")
		if active and character and root then
			local p = piece()
			local trench = p.kind == "Trench"
			if trench then
				surveyPlan(player, character, root, dt)
			else
				surveyPiece(character, root)
			end
			if trench and planStart then
				-- the trench plan: the run so far on a rule as long as the longest plan, a tick per square
				local info = planInfo
				view = {
					mode = "Plan",
					edge = "ok",
					title = "Pick the end",
					sub = if info
						then `{math.floor(info.length + 0.5)} studs · {info.squares} {if info.squares == 1
							then "square"
							else "squares"}{if info.clamped then ` · max {T.maxPlan}` else ""}`
						else nil,
					ruler = { length = if info then info.length else 0, max = T.maxPlan, step = T.block },
					keys = { { fire, "lay the plan" }, { exit, "drop it" } },
				}
			else
				-- placing: the piece between the ones before and after it on Q / E, what it costs and does
				local list = pieces()
				local i = math.clamp(index, 1, #list)
				local swings = Rules.buildSwings(p, C)
				local about = BuildHud.about(p.key)
				view = {
					mode = "Place",
					edge = "ok",
					title = p.name,
					prev = if #list > 1 then { keyName("Key_BuildPrev"), list[(i - 2) % #list + 1].name } else nil,
					next = if #list > 1 then { keyName("Key_BuildNext"), list[i % #list + 1].name } else nil,
					stat = {
						icon = "ok",
						text = `{if trench then "click to peg the start" else "fits: click to lay"} · {swings} {if swings
								== 1
							then "swing"
							else "swings"}{if trench then " a square" else ""}{if about then ` · {about}` else ""}`,
					},
					keys = if trench
						then { { fire, "lay the start" }, { exit, "exit" } }
						else { { fire, "lay" }, { keyName("Key_BuildTurn"), "turn" }, { exit, "exit" } },
				}
			end
			if view and current and not current.ok and current.reason then
				local head, rest = split(current.reason)
				view.edge = "bad"
				view.titleBad = view.mode == "Place"
				view.stat = { icon = "bad", tone = "bad", text = if rest then `{head} · {rest}` else head }
			end
		elseif holding and character and root then
			local other = if mode == "Build" then "Destroy" else "Build"
			local m = target(character, root)
			if m and m:IsA("Model") then
				-- (every structure in reach is lit, not only trench squares: user 2026-10-27, "be sure to give all
				-- structures the white border that the trenches have when near with a shovel"; a standing gun's own
				-- model, which stands outside its holder: src/server/Build's "Gun" link)
				local gun = m:FindFirstChild("Gun")
				focus = if gun and gun:IsA("ObjectValue") and gun.Value and gun.Value:IsA("Model") then gun.Value else m
			end
			view = {
				mode = mode,
				title = mode,
				sub = "point at a piece",
				keys = { { fire, "dig" }, { reload, `switch to {other}` }, { build, "build" } },
			}
			if m and m:IsA("Model") then
				-- what you point at: its name and HP, yours or the enemy's (user 2026-10-27: "just keep the hp x/y");
				-- in Destroy its HP in stage blocks and the swings to clear it. A piece's own HP, else its work (a gun
				-- blueprint)
				local block = m:GetAttribute("Kind") == "TrenchBlock"
				local p = if block then nil else Rules.piece(m:GetAttribute("Piece"), C.Pieces)
				local hp, max = m:GetAttribute("HP"), m:GetAttribute("MaxHP")
				if type(hp) ~= "number" or type(max) ~= "number" then
					hp, max = m:GetAttribute("Work"), m:GetAttribute("Need")
				end
				view.title = if block then "Trench square" else ((p or { name = "Piece" }) :: any).name
				view.sub = nil
				if type(hp) == "number" and type(max) == "number" then
					view.sub = `HP {math.ceil(hp)} / {max}`
					if mode == "Destroy" then
						local verb = if block then "fill it in" else "tear it down"
						local h = Rules.hpRules(if block then "TrenchBlock" else (p and p.kind or ""), C, p)
						local n = if h and h.destroy then Rules.destroySwings(hp, h.destroy) else nil
						view.blocks = { hp = hp, max = max, count = if block then 1 else Rules.hpBlocks(p) }
						view.stat = {
							text = if n
								then `dig to {verb} · {n} {if n == 1 then "swing" else "swings"} to clear`
								else `dig to {verb}`,
						}
					end
				end
			elseif m then
				view.title, view.sub = "Tree", "dig to chop it down"
			end
		end
		if view and notice and os.clock() < notice.untilAt then
			local head, rest = split(notice.text)
			view.edge = "bad"
			view.stat = { icon = "bad", tone = "bad", text = if rest then `{head} · {rest}` else head }
		end
		panel.set(view)
		local lit = if active and piece().kind ~= "Trench" then nil else focus
		if glow.Adornee ~= lit then
			-- a staked-out square's cords take the light's green too (a Highlight doesn't draw Beams), back after
			for _, m in { glow.Adornee, lit } do
				local marks = m and m:FindFirstChild("Markers")
				for _, cord in (if marks then marks:GetChildren() else {}) do
					if cord:IsA("Beam") then
						cord.Color =
							ColorSequence.new(rgb(if m == lit then Palette.Build.FocusPlan else Palette.Build.String))
					end
				end
			end
			glow.Adornee = lit
		end
		if lit then
			local c = rgb(if lit:FindFirstChild("Markers") then Palette.Build.FocusPlan else Palette.Build.Focus)
			glow.FillColor, glow.OutlineColor = c, c
		end
		glow.Enabled = lit ~= nil
	end)
end

return Build
