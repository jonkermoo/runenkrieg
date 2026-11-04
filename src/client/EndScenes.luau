--!strict
-- The end of a Normal match after the fade (user 2026-11-02; Config/Cutscenes Table / Board / Armory / Speech,
-- Workspace.Frontline's Phase "Table", "Vote", "Loading"), on the server's clock for every player:
-- - Table: the war table in the command post (src/client/CommandPost), the played map's sketch over its whole sheet
--   with this match's captures redrawn in red pencil over the phase, each side's painted block moving with them and the
--   points' pennants flipping to their takers, the after-action report on its clipboard typing itself out (Net
--   "MatchResults": the winner, the length, the top soldiers, your own line) and ticked in red pencil; the lamp sways;
--   the losing side's piece topples once it's all drawn; the table turns to the board once the replay and the report are
--   both done (the server's Table length: Rules/Cutscenes.tableSeconds);
-- - Vote: the camera turns round to the orders board: an OPERATION ORDER per offered map (an empty slot "to be
--   announced"), the field telegram with the plan. Those who may sign (the Player's MaySign: the winners, src/server/
--   MapVote) click an order to sign it (Net "MapVote"), once: a signature can't be taken back, so the orders stop
--   taking clicks and the strip under the sign says it's signed; every signature is written letter by letter in the
--   winners' ink down the order's grid (the names alone). A brass stopwatch sweeps the time, a red string runs from the
--   VOTE sign to the leading order. At the pick (VotePick) the camera closes on it and an R6 arm in the winners'
--   uniform holding a wooden stamp stamps NEXT on it; the losing orders swing on one pin;
-- - Loading: the empty armory, a slow drift on each approved angle in turn, a loading ring with its % in the bottom
--   left, while the narrator speaks the first part (src/client/Speech) and the next map streams in (Net "MapLoad",
--   src/client/MatchCutscene: the ring shows whichever is behind); it gives way to the pre-match flight at the
--   countdown (src/client/MatchCutscene), or, if the match waits for players, once the narrator is done;
-- - Fresh: a fresh server's first countdown (nothing played yet: no narrator's subject, user 2026-11-03): the armory
--   and the ring as a loading screen, full at the whistle, then into the game.
-- Between scenes the screen dips to black (src/client/MatchCutscene, Config/Cutscenes.Dip).
-- The sets are built on each client at Config/Cutscenes.Stage (the armory a placeholder until its render is modelled).
-- Widescreen bars throughout; the HUD and the rest are covered (MatchCutscene.cover).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Cutscenes)
local FrontCfg = require(Shared.Config.Frontline)
local ResultsCfg = require(Shared.Config.Results)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local LiveMap = require(Shared.LiveMap)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.Cutscenes)
local MatchCam = require(script.Parent.MatchCam)
local MatchCutscene = require(script.Parent.MatchCutscene)
local SketchMap = require(script.Parent.SketchMap)
local Speech = require(script.Parent.Speech)
local CommandPost = require(script.Parent.CommandPost)

local EndScenes = {}

local GR = (Palette.UI :: any).Grimoire
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local INK = rgb(GR.ink)
local V = Vector3.new
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function v3(a: { number }): Vector3
	return V(a[1], a[2], a[3])
end
local function nationOf(kit: string?): string
	local k = kit and (U.Kits :: any)[kit]
	return if k then k.team else ""
end
-- a nation's ink on paper: its name colour taken most of the way to ink
local function inkOf(kit: string?): Color3
	local c = kit and GR.Name[kit]
	return if c then rgb(c):Lerp(INK, 0.55) else INK
end

-- the sets ------------------------------------------------------------------------------------------------------------
local set: Folder? = nil
local post: CommandPost.Post = nil :: any
local armory: Vector3
local armoryModel = false -- the modelled hall stands (else the placeholder room)
local reportLines: { TextLabel }, reportTick: ((number) -> ())? = {}, nil
local mapSheet: any = nil

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Size, p.CFrame, p.Color = size, cf, color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = set
	return p
end

-- the armory (placeholder room): an empty hall, racks with gaps, a stripped field gun, helmets, a workbench, a door
local function buildArmory(o: Vector3)
	local brick, floor, wood, steel =
		Color3.fromRGB(122, 84, 64), Color3.fromRGB(92, 92, 86), Color3.fromRGB(104, 74, 46), Color3.fromRGB(78, 84, 80)
	part("Floor", V(36, 1, 40), CFrame.new(o - V(0, 0.5, 0)), floor, Enum.Material.Concrete)
	for _, w in { { V(36, 14, 1), V(0, 7, -20) }, { V(1, 14, 40), V(-18, 7, 0) }, { V(1, 14, 40), V(18, 7, 0) } } do
		part("Wall", w[1], CFrame.new(o + w[2]), brick, Enum.Material.Brick)
	end
	-- the doorway wall: two halves and a lintel round a lit opening
	part("Wall", V(15, 14, 1), CFrame.new(o + V(-10.5, 7, 20)), brick, Enum.Material.Brick)
	part("Wall", V(15, 14, 1), CFrame.new(o + V(10.5, 7, 20)), brick, Enum.Material.Brick)
	part("Lintel", V(6, 6, 1), CFrame.new(o + V(0, 11, 20)), brick, Enum.Material.Brick)
	local day =
		part("Daylight", V(6, 8, 0.2), CFrame.new(o + V(0, 4, 20.6)), Color3.fromRGB(250, 236, 200), Enum.Material.Neon)
	local sun = Instance.new("SurfaceLight")
	sun.Face, sun.Range, sun.Brightness, sun.Angle = Enum.NormalId.Back, 30, 3, 70
	sun.Parent = day
	part("Roof", V(36, 1, 40), CFrame.new(o + V(0, 14, 0)), wood, Enum.Material.WoodPlanks)
	local shaft = part(
		"Shaft",
		V(3, 14, 3),
		CFrame.new(o + V(4, 7, -6)) * CFrame.Angles(0, 0, math.rad(18)),
		Color3.fromRGB(255, 236, 190),
		Enum.Material.Neon
	)
	shaft.Transparency = 0.93
	-- the rifle racks (gaps where rifles went), the field gun off its carriage, the helmets, the workbench
	for k = 0, 1 do
		part("Rack", V(0.6, 6, 10), CFrame.new(o + V(-17, 3, -4 + k * 12)), wood, Enum.Material.Wood)
		for r = 0, 7 do
			if r % 3 ~= 1 then
				part(
					"Rifle",
					V(0.3, 4.6, 0.3),
					CFrame.new(o + V(-16.4, 2.6, -8 + k * 12 + r * 1.1)) * CFrame.Angles(0, 0, math.rad(-8)),
					Color3.fromRGB(70, 50, 34)
				)
			end
		end
	end
	local barrel = part(
		"Barrel",
		V(9, 1.1, 1.1),
		CFrame.new(o + V(7, 0.6, -1)) * CFrame.Angles(0, math.rad(24), 0),
		steel,
		Enum.Material.Metal
	)
	barrel.Shape = Enum.PartType.Cylinder
	part("Carriage", V(4, 1.6, 2.4), CFrame.new(o + V(9, 0.8, 4)), Color3.fromRGB(86, 92, 72), Enum.Material.Metal)
	local wheel = part(
		"Wheel",
		V(0.5, 4.5, 4.5),
		CFrame.new(o + V(4, 2.2, -8)) * CFrame.Angles(0, 0, math.rad(12)),
		wood,
		Enum.Material.Wood
	)
	wheel.Shape = Enum.PartType.Cylinder
	part("Shelf", V(1.2, 0.3, 10), CFrame.new(o + V(17.2, 5, -2)), wood, Enum.Material.Wood)
	for k = 0, 3 do
		if k ~= 2 then
			part(
				"Helmet",
				V(1.4, 0.7, 1.4),
				CFrame.new(o + V(17.2, 5.5, -6 + k * 2.6)),
				Color3.fromRGB(96, 104, 92),
				Enum.Material.Metal
			)
		end
	end
	part("Workbench", V(8, 0.5, 3), CFrame.new(o + V(-2, 2.6, -18)), wood, Enum.Material.Wood)
	part("Vice", V(0.8, 0.8, 0.8), CFrame.new(o + V(-4.5, 3.2, -17.6)), steel, Enum.Material.Metal)
	for _, x in { -5, 1 } do
		part("Crate", V(2.4, 2, 2.4), CFrame.new(o + V(x, 1, 10)), wood, Enum.Material.WoodPlanks)
	end
	armory = o
end

local function buildSets()
	if set then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "EndScenesSet"
	set = f
	post = CommandPost.build(f, v3(Cfg.Stage.tent))
	local at = v3(Cfg.Stage.armory)
	local A = Cfg.Armory.set
	armoryModel = CommandPost.loadSet(f, A.asset, at, A.turn, A.images, A.looks) ~= nil
	if armoryModel then
		-- its lights, and the fields past the door (in the part list's space: the model once turned)
		local function place(p: { number }): Vector3
			return at + v3(p)
		end
		for _, l in A.points do
			local holder = part("Light", V(0.2, 0.2, 0.2), CFrame.new(place(l.at)), rgb(l.colour))
			holder.Transparency = 1
			local light = Instance.new("PointLight")
			light.Range, light.Brightness, light.Color, light.Shadows =
				l.range, l.brightness, rgb(l.colour), l.shadows == true
			light.Parent = holder
		end
		for _, l in A.fills do
			local from = place(l.at)
			local holder = part("Fill", V(0.2, 0.2, 0.2), CFrame.lookAt(from, from + v3(l.face)), rgb(l.colour))
			holder.Transparency = 1
			local light = Instance.new("SurfaceLight")
			light.Face, light.Range, light.Brightness, light.Angle = Enum.NormalId.Front, l.range, l.brightness, l.angle
			light.Color = rgb(l.colour)
			light.Parent = holder
		end
		for _, o in A.outside do
			local lo, hi = place(o.min), place(o.max)
			local mid = (lo + hi) / 2
			local size = V(math.abs(hi.X - lo.X), math.max(math.abs(hi.Y - lo.Y), 0.2), math.abs(hi.Z - lo.Z))
			part(
				"Field",
				V(math.min(size.X, 2048), math.min(size.Y, 2048), math.min(size.Z, 2048)),
				CFrame.new(mid),
				rgb(o.colour)
			)
		end
		armory = at
	else
		buildArmory(at)
	end
	f.Parent = workspace
end

-- the screen: the bars, a modal button that frees the mouse while signing, the loading ring
local gui: ScreenGui, freeMouse: TextButton, ring: Frame, ringText: TextLabel
local ringDots: { Frame } = {}
local loadEnds = 0 -- the server time the least loading time is up
local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "EndScenes"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = Cfg.DisplayOrder
	gui.Enabled = false
	for i = 0, 1 do
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromScale(1, Cfg.Bars)
		bar.AnchorPoint = Vector2.new(0, i)
		bar.Position = UDim2.fromScale(0, i)
		bar.Parent = gui
	end
	-- the loading ring in the bottom left: dots round a circle lit in turn, the % in its middle
	local R = Cfg.Armory.ring
	ring = Instance.new("Frame")
	ring.Name = "Loading"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(R.at[1], 1 - R.at[2])
	ring.Size = UDim2.fromScale(R.size, R.size)
	ring.SizeConstraint = Enum.SizeConstraint.RelativeYY
	ring.Visible = false
	ring.Parent = gui
	for k = 1, R.dots do
		local a = (k - 1) / R.dots * 2 * math.pi -- (clockwise from the top)
		local dot = Instance.new("Frame")
		dot.BorderSizePixel = 0
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5 + math.sin(a) * (0.5 - R.dot / 2), 0.5 - math.cos(a) * (0.5 - R.dot / 2))
		dot.Size = UDim2.fromScale(R.dot, R.dot)
		dot.BackgroundColor3 = rgb(R.track)
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = dot
		dot.Parent = ring
		ringDots[k] = dot
	end
	ringText = Instance.new("TextLabel")
	ringText.BackgroundTransparency = 1
	ringText.AnchorPoint = Vector2.new(0.5, 0.5)
	ringText.Position = UDim2.fromScale(0.5, 0.5)
	ringText.Size = UDim2.fromScale(0.7, R.text)
	ringText.TextScaled = true
	ringText.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
	ringText.TextColor3 = rgb(R.fill)
	ringText.Text = "0%"
	ringText.Parent = ring
	freeMouse = Instance.new("TextButton")
	freeMouse.BackgroundTransparency = 1
	freeMouse.Text = ""
	freeMouse.Size = UDim2.fromOffset(1, 1)
	freeMouse.Modal = true
	freeMouse.Visible = false
	freeMouse.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

-- the ring at `k` (0..1) loaded
local function showLoaded(k: number)
	local lit = math.floor(k * #ringDots + 0.5)
	for i, d in ringDots do
		d.BackgroundColor3 = rgb(if i <= lit then Cfg.Armory.ring.fill else Cfg.Armory.ring.track)
	end
	ringText.Text = `{math.floor(k * 100 + 0.5)}%`
end

-- whether we've signed an order of this vote (folder's Votes_<key>: our name in one): it's final
local function signedVote(folder: Instance): boolean
	for _, o in post.orders do
		local raw = o.key and folder:GetAttribute(`Votes_{o.key}`)
		for _, entry in (if type(raw) == "string" and raw ~= "" then string.split(raw, "|") else {}) do
			if string.match(entry, "^(.-):") == player.DisplayName then
				return true
			end
		end
	end
	return false
end

-- the stamping arm: an R6 right arm in the winners' uniform, a wooden stamp in its hand
local arm: Model? = nil
local function stampArm(kit: string?, sheet: CommandPost.Order, at: CFrame, from: Vector3)
	if arm then
		(arm :: Model):Destroy()
	end
	local A = Cfg.Board.arm
	local k = (U.Kits :: any)[kit or U.Default] or (U.Kits :: any)[U.Default]
	local m = Instance.new("Model")
	m.Name = "StampArm"
	local hum = Instance.new("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.RigType = Enum.HumanoidRigType.R6
	hum.Parent = m
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size, torso.Transparency = V(2, 2, 1), 1
	torso.Anchored, torso.CanCollide = true, false
	torso.Parent = m
	local limb = Instance.new("Part")
	limb.Name = "Right Arm"
	limb.Size = V(1, 2, 1)
	limb.Anchored, limb.CanCollide = true, false
	limb.Color = rgb(k.skin)
	limb.Parent = m
	local colors = Instance.new("BodyColors")
	colors.RightArmColor3 = rgb(k.skin)
	colors.Parent = m
	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = `rbxassetid://{k.shirt}`
	shirt.Parent = m
	local block = Instance.new("Part")
	block.Name = "Stamp"
	block.Size = v3(A.stamp)
	block.Anchored, block.CanCollide = true, false
	block.Color = Color3.fromRGB(110, 78, 48)
	block.Material = Enum.Material.Wood
	block.Parent = m
	m.Parent = set
	arm = m
	-- the stamp pressed square to the sheet; the arm reaches in from `from` (our shoulder, at the screen's lower right),
	-- its hand (the arm's lower end) on the stamp's back
	local axis = (from - (at.Position + at.LookVector * A.stamp[3])).Unit
	local across = axis:Cross(at.UpVector).Unit
	local function place(out: number)
		local face = at.Position + at.LookVector * (A.stamp[3] / 2 + out)
		block.CFrame = CFrame.lookAt(face, face + at.LookVector)
		local hand = face + at.LookVector * (A.stamp[3] / 2)
		limb.CFrame = CFrame.fromMatrix(hand + axis * 1, across, axis)
		torso.CFrame = CFrame.fromMatrix(hand + axis * 2.5, across, axis)
	end
	task.spawn(function()
		local side = axis * A.reach
		local t0 = os.clock()
		-- in from our shoulder, over the sheet
		while os.clock() - t0 < A.down + 0.4 do
			local u = math.clamp((os.clock() - t0) / (A.down + 0.4), 0, 1)
			local ease = Rules.ease(u)
			place(A.lift)
			local shift = side * (1 - ease)
			for _, p in { block, limb, torso } do
				p.CFrame += shift
			end
			task.wait()
		end
		-- down: the thump, the stamp left on the sheet
		t0 = os.clock()
		while os.clock() - t0 < A.down do
			place(A.lift * (1 - math.clamp((os.clock() - t0) / A.down, 0, 1)))
			task.wait()
		end
		place(0)
		sheet.stamp.Visible = true
		local S = Cfg.Board.stampSound
		local thump = Instance.new("Sound")
		thump.SoundId = `rbxassetid://{S.id}`
		thump.Volume, thump.PlaybackSpeed = S.volume, S.speed
		thump.Parent = block
		thump:Play()
		task.wait(A.hold)
		t0 = os.clock()
		while os.clock() - t0 < A.up do
			place(A.lift * math.clamp((os.clock() - t0) / A.up, 0, 1))
			task.wait()
		end
		-- and back out of sight, the stamp left on the order
		t0 = os.clock()
		while os.clock() - t0 < A.down + 0.4 do
			place(A.lift)
			local shift = side * Rules.ease(math.clamp((os.clock() - t0) / (A.down + 0.4), 0, 1))
			for _, p in { block, limb, torso } do
				p.CFrame += shift
			end
			task.wait()
		end
		if arm == m then
			m:Destroy()
			arm = nil
		end
	end)
end

-- the scenes ------------------------------------------------------------------------------------------------------------
local results: any = nil -- the latest Normal results (Net "MatchResults")
local scene: string? = nil
local sceneAt = 0 -- server time the scene started
local covered = false
local picked: string? = nil
local signed = false -- (we've signed this vote: it's final)
local speechStarted = false

local function lookCf(from: Vector3, to: Vector3): CFrame
	return CFrame.lookAt(from, to)
end

local pickedAt = 0 -- os.clock() of the pick (we step up to the order from it)

-- first person (Config/Cutscenes.View): an eye at `pos` turned `yaw`, tipped `pitch`, breathing
local function eyeCf(pos: Vector3, yaw: number, pitch: number): CFrame
	local W = Cfg.View
	local breath = W.sway.amount * math.sin(os.clock() * W.sway.rate * 2 * math.pi)
	return CFrame.new(pos + V(0, breath, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

local function aimAt(from: Vector3, to: Vector3): (number, number)
	local d = to - from
	return Rules.aim(d.X, d.Y, d.Z)
end

-- at the table: standing at its near side, the eyes on the map, then on the report
local function tableView(t: number): (Vector3, number, number)
	local W = Cfg.View
	local pos = post.origin + v3(W.over)
	local looks = W.table.looks
	local i, k = Rules.glance(looks, W.table.glance, t)
	local from, to = looks[math.max(i - 1, 1)], looks[i]
	-- (moving along the table with the glance where a look has its own eye)
	local function eyeOf(l: any): Vector3
		return if l.eye then post.origin + v3(l.eye) else pos
	end
	pos = eyeOf(from):Lerp(eyeOf(to), k)
	local y1, p1 = aimAt(pos, post.origin + v3(from.look))
	local y2, p2 = aimAt(pos, post.origin + v3(to.look))
	return pos, Rules.turn(y1, y2, k, 0), p1 + (p2 - p1) * k
end

-- the eye standing in front of the picked order, looking at it
local function pickEye(o: CommandPost.Order): (Vector3, number, number)
	local P = Cfg.View.pick
	local mid = o.part.Position
	local eye = mid + o.part.CFrame.LookVector * P.back + V(0, P.up, 0)
	local yaw, pitch = aimAt(eye, mid)
	return eye, yaw, pitch
end

-- the vote: turning round to the board (to the right), a few steps toward it, and at the pick up to the order
local function boardView(t: number): (Vector3, number, number)
	local W = Cfg.View
	local pos0, y0, p0 = tableView(math.huge) -- (where the table left the eyes: its last look)
	local look = post.origin + v3(W.board)
	local to = post.origin + V(W.walk.to[1], W.eye, W.walk.to[2])
	local yB, pB = aimAt(pos0, look)
	local pos, yaw, pitch
	if t < W.turn then
		local k = Rules.ease(math.clamp(t / W.turn, 0, 1))
		pos, yaw, pitch = pos0, Rules.turn(y0, yB, k, -1), p0 + (pB - p0) * k
	else
		local k = Rules.ease(math.clamp((t - W.turn) / (W.walk.t1 - W.turn), 0, 1))
		pos = pos0:Lerp(to, k)
		yaw, pitch = aimAt(pos, look)
	end
	for _, o in post.orders do
		if picked and o.key == picked then
			local eye, yP, pP = pickEye(o)
			local k = Rules.ease(math.clamp((os.clock() - pickedAt) / W.pick.ease, 0, 1))
			pos, yaw, pitch = pos:Lerp(eye, k), Rules.turn(yaw, yP, k, 0), pitch + (pP - pitch) * k
		end
	end
	return pos, yaw, pitch
end

-- the armory's shots in turn, each drifting over its cut (the modelled hall's, else the placeholder room's)
local function armoryCam(t: number): (CFrame, number)
	local A = Cfg.Armory
	local u = (t % A.cut) / A.cut
	if not armoryModel then
		local s = A.placeholder[math.floor(t / A.cut) % #A.placeholder + 1]
		return lookCf(armory + v3(s.from):Lerp(v3(s.to), u), armory + v3(s.look)), Cfg.Fov
	end
	local s = A.shots[math.floor(t / A.cut) % #A.shots + 1]
	local from, look = v3(s.from), v3(s.look) -- (the part list's space: the model once turned)
	local kind, amount = s.drift[1], s.drift[2] * u
	if kind == "push" then
		from += (look - from).Unit * amount
	elseif kind == "rise" then
		from += V(0, amount, 0)
	elseif kind == "truck" then
		from += V(amount, 0, 0)
		look += V(amount, 0, 0)
	elseif kind == "arc" then
		from = look + CFrame.Angles(0, math.rad(amount), 0) * (from - look)
	end
	return lookCf(armory + from, armory + look), s.fov
end

local function typeReport(t: number)
	local T = Cfg.Table
	for k, l in reportLines do
		local start = T.typing.lead + (k - 1) * T.typing.type
		local u = math.clamp((t - start) / T.typing.type, 0, 1)
		l.MaxVisibleGraphemes = math.floor(u * (utf8.len(l.Text) or #l.Text) + 0.5)
	end
	if reportTick then
		local typed = T.typing.lead + #reportLines * T.typing.type
		reportTick((t - typed - T.tick.after) / T.tick.draw)
	end
end

local function fillReport()
	local r = results or {}
	reportLines, reportTick = CommandPost.report(post, r, nationOf)
	-- the played map on the sheet, this match's captures redrawn on it
	if mapSheet then
		mapSheet.destroy()
		mapSheet = nil
	end
	local key = if type(r.map) == "string" then r.map else LiveMap.key()
	mapSheet = SketchMap.new(post.strip, key, { sheet = post.strip.Parent :: GuiObject })
	-- (its span by how many captures it draws, as the server times the table: Rules/Cutscenes.tableSeconds)
	local P = Cfg.Table.replay
	local n = math.min(#(r.log or {}), ResultsCfg.Replay.most)
	mapSheet.replay(
		r.log or {},
		r.winner ~= nil,
		{ seconds = Rules.replaySeconds(P, n), lead = P.lead, tail = P.tail, draw = P.draw }
	)
end

local function finish()
	if not scene then
		return
	end
	scene = nil
	RunService:UnbindFromRenderStep("EndScenes")
	gui.Enabled = false
	freeMouse.Visible = false
	if arm then
		(arm :: Model):Destroy()
		arm = nil
	end
	if covered then
		covered = false
		MatchCutscene.cover(false)
	end
	if not MatchCam.running() then
		camera.CameraType = Enum.CameraType.Custom
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then
			camera.CameraSubject = h
		end
	end
end

local function step()
	local folder = workspace:FindFirstChild(FrontCfg.FolderName)
	if not folder or not scene then
		return
	end
	local t = workspace:GetServerTimeNow() - sceneAt
	local cf, fov = nil, Cfg.View.fov
	if scene == "Table" then
		fov = Cfg.View.table.fov
		cf = eyeCf(tableView(t))
		typeReport(t)
		CommandPost.stepTable(post, mapSheet, folder, t)
	elseif scene == "Vote" then
		CommandPost.signatures(post, folder, inkOf)
		-- once signed, it's final: the orders take no more clicks and the mouse goes back
		if not signed and signedVote(folder) then
			signed = true
			CommandPost.signedHint(post, true)
			freeMouse.Visible = false
		end
		local pick = folder:GetAttribute("VotePick")
		if type(pick) == "string" and pick ~= picked then
			picked = pick
			pickedAt = os.clock()
			for _, o in post.orders do
				if o.key == pick then
					local spoken = folder:GetAttribute(FrontCfg.SpeechAttribute)
					local kitText = if type(spoken) == "string" then string.split(spoken, ",")[1] else "none"
					-- our arm, once we stand at the order: from our shoulder at the screen's lower right
					local W = Cfg.View
					local eye, yaw, pitch = pickEye(o)
					local at = CFrame.new(eye) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
					local from = eye
						+ at.RightVector * W.arm.right
						- at.UpVector * W.arm.down
						+ at.LookVector * W.arm.ahead
					task.delay(W.pick.ease * 0.6, function()
						if picked == pick and scene == "Vote" then
							stampArm(if kitText ~= "none" then kitText else nil, o, o.part.CFrame, from)
						end
					end)
				end
			end
			freeMouse.Visible = false
		end
		-- the time left: the stopwatch's hand and the window in its dial
		local left = math.max(0, math.ceil(FrontCfg.VoteSeconds - t))
		post.timer.Text = if picked then Cfg.Board.watch.closed else string.format("%d:%02d", left // 60, left % 60)
		post.timer.TextColor3 = if picked or left <= Cfg.Board.timer.warn then rgb(GR.pencil) else INK
		local sweep = if picked then 0 else math.clamp(FrontCfg.VoteSeconds - t, 0, FrontCfg.VoteSeconds)
		post.hand.Color = if picked or left <= Cfg.Board.timer.warn then rgb(GR.pencil) else rgb(GR.ink)
		CommandPost.stepBoard(post, sweep, FrontCfg.VoteSeconds, picked, os.clock() - pickedAt)
		cf = eyeCf(boardView(t))
		local W = Cfg.View
		fov = W.table.fov + (W.fov - W.table.fov) * Rules.ease(math.clamp(t / W.turn, 0, 1))
	else
		cf, fov = armoryCam(t)
		local phaseNow = folder:GetAttribute("Phase")
		local span = math.max(loadEnds - sceneAt, 0.1)
		-- (loading: the narrator's first part and the next map streamed in, whichever is behind, full once both are
		-- done; a fresh server's screen full at the whistle)
		local k = if phaseNow == "Loading"
			then Rules.loadRing(t / span, MatchCutscene.loaded(), Cfg.Armory.ring.most)
			elseif phaseNow == "Countdown" then math.clamp(t / span, 0, 1)
			else 1
		showLoaded(k)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cf
	camera.FieldOfView = fov
	UserInputService.MouseIconEnabled = scene == "Vote" and not signed
end

local function begin(name: string, folder: Instance)
	buildSets()
	local endsAt = folder:GetAttribute("PhaseEndsAt")
	local startedAt = folder:GetAttribute("PhaseAt")
	sceneAt = if type(startedAt) == "number" then startedAt else workspace:GetServerTimeNow()
	scene = name
	if not covered then
		covered = true
		MatchCutscene.cover(true)
	end
	gui.Enabled = true
	freeMouse.Visible = false
	if arm then -- (the arm comes only with the pick)
		(arm :: Model):Destroy()
		arm = nil
	end
	local spoken = folder:GetAttribute(FrontCfg.SpeechAttribute)
	local parts = if type(spoken) == "string" then string.split(spoken, ",") else { "none", LiveMap.key() }
	local winnerKit = if parts[1] ~= "none" then parts[1] else nil
	if name == "Table" then
		fillReport()
	elseif name == "Vote" then
		picked = nil
		signed = false
		CommandPost.resetBoard(post)
		local offer = folder:GetAttribute("VoteOffer")
		CommandPost.orders(post, if type(offer) == "string" then string.split(offer, ",") else {}, function(key: string)
			if player:GetAttribute("MaySign") == true and not signed then
				Net.event("MapVote"):FireServer(key)
			end
		end)
		CommandPost.signedHint(post, false)
		CommandPost.plan(post, if winnerKit then nationOf(winnerKit) else nil)
		local may = player:GetAttribute("MaySign") == true
		freeMouse.Visible = may
	end
	ring.Visible = name == "Loading" or name == "Fresh"
	if name == "Loading" or name == "Fresh" then
		loadEnds = if type(endsAt) == "number" then endsAt else workspace:GetServerTimeNow() + 8
		showLoaded(0)
	end
	if name == "Loading" and not speechStarted then
		speechStarted = true
		Speech.stop()
		local played = parts[2] or LiveMap.key()
		local playedMap = LiveMap.get(played)
		Speech.queue(
			Rules.partOne(Cfg.Speech, winnerKit, played, nationOf(winnerKit), playedMap and playedMap.name),
			os.clock()
		)
	end
	MatchCutscene.clearFade() -- (the set is up: the fade's colour gives way to it)
	RunService:UnbindFromRenderStep("EndScenes")
	RunService:BindToRenderStep("EndScenes", Enum.RenderPriority.Camera.Value + 3, step)
end

function EndScenes.start()
	buildGui()
	Net.event("MatchResults").OnClientEvent:Connect(function(r: any)
		if type(r) == "table" and r.mode == "Normal" then
			results = r
		end
	end)
	local seen: string? = nil
	task.spawn(function()
		while true do
			local folder = workspace:FindFirstChild(FrontCfg.FolderName)
			local phase = folder and folder:GetAttribute("Phase")
			if phase ~= seen then
				seen = phase :: string?
				if folder and (phase == "Table" or phase == "Vote" or phase == "Loading") then
					begin(phase :: string, folder)
				elseif folder and phase == "Countdown" and folder:GetAttribute(FrontCfg.SpeechAttribute) == nil then
					begin("Fresh", folder) -- (a fresh server: a loading screen, no flight)
				elseif phase == "Fade" then
					speechStarted = false
					MatchCutscene.forgetLoad()
				elseif scene then
					-- the countdown takes over (the flight); waiting for players, the armory stays till the narrator ends
					-- (and through the dip to black into the countdown, when it comes at once)
					if phase == "Waiting" and scene == "Loading" then
						task.spawn(function()
							local function dipping(): boolean
								local at = folder and folder:GetAttribute(FrontCfg.DipAttribute)
								return type(at) == "number" and workspace:GetServerTimeNow() < at + Cfg.Dip.hold
							end
							while (Speech.busy() or dipping()) and scene == "Loading" do
								task.wait(0.1)
							end
							if scene == "Loading" then
								finish()
							end
						end)
					else
						finish()
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

return EndScenes
