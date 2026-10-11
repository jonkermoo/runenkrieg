--!strict
-- Dev-only test range (dev place): a space off the map to test movement, animations and firing.
--   require(game.ServerStorage.Dev.Range:Clone()).build()
-- Rebuilds Workspace.DevRange from Config/Range (layout) and Config/Metrics (every obstacle size):
--   firing range   body-sized targets at 25-450 studs; open, trench-bay and window firing positions
--   course         timing lane with distance marks; ledges, cover walls, slopes, stairs and a doorway
--   stage          a flat pad with a grid for reading animations
-- Teleport there with the dev menu ("Test range", Config/DevTools).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Range = {}

local DEV_PLACE_ID = 103459731368962

local function fresh(module: Instance): any
	return require(module:Clone() :: ModuleScript)
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function Range.build(): string
	assert(game.PlaceId == DEV_PLACE_ID, "the test range is built only in the DEV place")
	local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
	local R = fresh(Config.Range)
	local M = fresh(Config.Metrics)
	local old = workspace:FindFirstChild("DevRange")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "DevRange"
	model:SetAttribute("DevOnly", true)
	local O = Vector3.new(R.Origin[1], R.Origin[2], R.Origin[3])
	local count = 0

	-- a block in range-local coords: centre (x, y, z), size (sx, sy, sz)
	local function block(
		name: string,
		x: number,
		y: number,
		z: number,
		sx: number,
		sy: number,
		sz: number,
		color: string,
		parent: Instance?
	): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Material = Enum.Material.SmoothPlastic
		p.Color = rgb(R.Colors[color])
		p.Size = Vector3.new(sx, sy, sz)
		p.Position = O + Vector3.new(x, y, z)
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = parent or model
		count += 1
		return p
	end

	local function label(part: BasePart, text: string, offsetY: number, maxDistance: number?)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(200, 40)
		gui.StudsOffset = Vector3.new(0, offsetY, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = maxDistance or 120
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.3
		t.TextScaled = true
		t.Font = Enum.Font.GothamMedium
		t.Text = text
		t.Parent = gui
		gui.Parent = part
	end

	local F, Cs, St = R.Firing, R.Course, R.Stage
	local farthest = 0
	for _, t in F.Targets do
		farthest = math.max(farthest, t.distance)
	end

	-- one floor under everything (top at y = 0)
	local minX = St.X - St.Size / 2 - 6
	local maxX = Cs.StartX + 4 + 3 * (Cs.Gap + 10) + 10
	local zFront, zBack = F.Behind, -(farthest + F.Beyond)
	block("Floor", (minX + maxX) / 2, -1, (zFront + zBack) / 2, maxX - minX, 2, zFront - zBack, "Floor")

	-- ---- firing range ----
	local fire = Instance.new("Model")
	fire.Name = "FiringRange"
	fire.Parent = model
	block("FiringLine", 0, 0.02, 0, F.Width, 0.05, 0.4, "Line", fire)
	local C = M.Character
	local armW = (C.Width - C.ShoulderWidth) / 2
	for _, t in F.Targets do
		local z = -t.distance
		local line = block(`Line_{t.distance}`, 0, 0.02, z, F.Width, 0.05, 0.3, "Lane", fire)
		label(line, `{t.distance} studs`, 1.5, 600)
		local target = Instance.new("Model")
		target.Name = `Target_{t.distance}`
		target.Parent = fire
		local th = R.TargetThickness
		local legH = C.LegLength
		local torsoH = C.ShoulderHeight - legH
		block("Legs", t.x, legH / 2, z, C.ShoulderWidth, legH, th, "Target", target)
		block("Torso", t.x, legH + torsoH / 2, z, C.ShoulderWidth, torsoH, th, "Target", target)
		block("LeftArm", t.x - (C.ShoulderWidth + armW) / 2, legH + torsoH / 2, z, armW, torsoH, th, "Target", target)
		block("RightArm", t.x + (C.ShoulderWidth + armW) / 2, legH + torsoH / 2, z, armW, torsoH, th, "Target", target)
		block("Head", t.x, C.HeadCenterHeight, z, R.HeadSize, R.HeadSize, th, "TargetHead", target)
	end

	-- open position: a mark on the line
	label(block("Open", F.OpenX, 0.03, 1.5, 3, 0.05, 3, "Line", fire), "Open", 2)

	-- trench bay on the line (Metrics.Trench): walls Depth high round a FloorWidth bay, firestep against the front
	-- wall, the rear wall left open for a doorway-wide exit
	local Tr = M.Trench
	local bay = Instance.new("Model")
	bay.Name = "TrenchBay"
	bay.Parent = fire
	local L, W, D, wall = F.TrenchLength, Tr.FloorWidth, Tr.Depth, 2
	local tx = F.TrenchX
	block("Front", tx, D / 2, -W / 2 - wall / 2, L + 2 * wall, D, wall, "Block", bay)
	block(
		"Firestep",
		tx,
		Tr.FirestepHeight / 2,
		-W / 2 + Tr.FirestepWidth / 2,
		L,
		Tr.FirestepHeight,
		Tr.FirestepWidth,
		"Block",
		bay
	)
	block("Left", tx - L / 2 - wall / 2, D / 2, 0, wall, D, W, "Block", bay)
	block("Right", tx + L / 2 + wall / 2, D / 2, 0, wall, D, W, "Block", bay)
	local gap = M.Building.DoorWidth
	local rearPiece = (L + 2 * wall - gap) / 2
	block("RearL", tx - gap / 2 - rearPiece / 2, D / 2, W / 2 + wall / 2, rearPiece, D, wall, "Block", bay)
	block("RearR", tx + gap / 2 + rearPiece / 2, D / 2, W / 2 + wall / 2, rearPiece, D, wall, "Block", bay)
	label(bay:FindFirstChild("Front") :: BasePart, "Trench bay (firestep)", D / 2 + 1.5)

	-- window wall on the line (Metrics.Building window: sill, top, width)
	local Bd = M.Building
	local win = Instance.new("Model")
	win.Name = "WindowWall"
	win.Parent = fire
	local wx, ww, wh, wt = F.WindowX, F.WindowWallWidth, Bd.WindowTop + 2, 1
	local side = (ww - Bd.WindowWidth) / 2
	block("Below", wx, Bd.WindowSill / 2, -1, Bd.WindowWidth, Bd.WindowSill, wt, "Block", win)
	block("Above", wx, (Bd.WindowTop + wh) / 2, -1, Bd.WindowWidth, wh - Bd.WindowTop, wt, "Block", win)
	block("Left", wx - Bd.WindowWidth / 2 - side / 2, wh / 2, -1, side, wh, wt, "Block", win)
	block("Right", wx + Bd.WindowWidth / 2 + side / 2, wh / 2, -1, side, wh, wt, "Block", win)
	label(win:FindFirstChild("Above") :: BasePart, "Window", (wh - Bd.WindowTop) / 2 + 1.5)

	-- ---- movement course ----
	local course = Instance.new("Model")
	course.Name = "Course"
	course.Parent = model
	local lx = Cs.StartX
	block("Lane", lx, 0.02, -Cs.LaneLength / 2, 4, 0.05, Cs.LaneLength, "Lane", course)
	for d = 0, Cs.LaneLength, Cs.MarkEvery do
		local mark = block(`Mark_{d}`, lx, 0.03, -d, 4, 0.05, 0.3, "Line", course)
		label(mark, `{d}`, 1, 150)
	end
	-- obstacles in a column beside the lane, each with its rule
	local ox = lx + 4 + Cs.Gap + 5
	local z = -Cs.Gap
	local function place(name: string, depth: number, note: string, build: (z0: number) -> BasePart)
		local p = build(z - depth / 2)
		label(p, `{name}: {note}`, 3)
		z -= depth + Cs.Gap
	end
	local Mv, Cv = M.Movement, M.Cover
	for _, l in
		{
			{ C.MaxStepUp, "walk up (max step-up)" },
			{ Cv.HopableLedgeMax, "hop up (max hop)" },
			{ Cv.LowCoverMin, "low cover: can't hop" },
			{ Cv.FullCoverMin, "full cover: hides a soldier" },
		}
	do
		place(`Ledge {l[1]}`, Cs.BlockDepth, l[2], function(z0)
			return block(`Ledge_{l[1]}`, ox, l[1] / 2, z0, 10, l[1], Cs.BlockDepth, "Block", course)
		end)
	end
	for _, s in
		{ { Mv.MaxSlopeAngle - Cs.SlopeOffset, "walkable" }, { Mv.MaxSlopeAngle + Cs.SlopeOffset, "too steep" } }
	do
		local h = 4
		local run = h / math.tan(math.rad(s[1]))
		place(`Slope {s[1]} deg`, run, s[2], function(z0)
			local w = Instance.new("WedgePart")
			w.Name = `Slope_{s[1]}`
			w.Anchored = true
			w.Material = Enum.Material.SmoothPlastic
			w.Color = rgb(R.Colors.Block)
			w.Size = Vector3.new(10, h, run)
			-- the wedge rises toward -Z (walking downrange climbs it)
			w.CFrame = CFrame.new(O + Vector3.new(ox, h / 2, z0)) * CFrame.Angles(0, math.pi, 0)
			w.Parent = course
			count += 1
			return w
		end)
	end
	local stepsN = math.ceil((Bd.StoryHeight / 2) / Bd.StairRise)
	local rise = (Bd.StoryHeight / 2) / stepsN
	place("Stairs", stepsN * Bd.StairRun + 6, `rise {string.format("%.2f", rise)}, run {Bd.StairRun}`, function(z0)
		local top = z0 + (stepsN * Bd.StairRun + 6) / 2
		local first: BasePart? = nil
		for i = 1, stepsN do
			local p = block(
				`Step_{i}`,
				ox,
				i * rise / 2,
				top - (i - 0.5) * Bd.StairRun,
				Bd.StairWidthMin,
				i * rise,
				Bd.StairRun,
				"Block",
				course
			)
			first = first or p
		end
		block(
			"Landing",
			ox,
			Bd.StoryHeight / 4,
			top - stepsN * Bd.StairRun - 3,
			Bd.StairWidthMin,
			Bd.StoryHeight / 2,
			6,
			"Block",
			course
		)
		return first :: BasePart
	end)
	place("Doorway", 1, `{Bd.DoorWidth} x {Bd.DoorHeight}`, function(z0)
		local wh2 = Bd.DoorHeight + 2
		local piece = (10 - Bd.DoorWidth) / 2
		block("DoorL", ox - Bd.DoorWidth / 2 - piece / 2, wh2 / 2, z0, piece, wh2, 1, "Block", course)
		block("DoorR", ox + Bd.DoorWidth / 2 + piece / 2, wh2 / 2, z0, piece, wh2, 1, "Block", course)
		return block(
			"DoorTop",
			ox,
			(Bd.DoorHeight + wh2) / 2,
			z0,
			Bd.DoorWidth,
			wh2 - Bd.DoorHeight,
			1,
			"Block",
			course
		)
	end)

	-- ---- animation stage ----
	local stage = Instance.new("Model")
	stage.Name = "Stage"
	stage.Parent = model
	local pad = block("Pad", St.X, 0.05, 0, St.Size, 0.1, St.Size, "Stage", stage)
	label(pad, "Animation stage", 2)
	for i = -St.Size / 2, St.Size / 2, St.Grid do
		block("GridX", St.X + i, 0.11, 0, 0.06, 0.02, St.Size, "Line", stage)
		block("GridZ", St.X, 0.11, i, St.Size, 0.02, 0.06, "Line", stage)
	end

	model.Parent = workspace
	return string.format("DevRange: %d parts at %s (teleport: Test range)", count, tostring(O))
end

return Range
