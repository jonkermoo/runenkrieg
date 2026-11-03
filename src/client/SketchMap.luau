--!strict
-- The sketch map (UI overhaul, Field Grimoire; Config/SketchMap; user 2026-10-30: "lets do the sketch map", top right in
-- play, the live match on the title screen): the map's still image (the ground: tools/ui/sketchmap.py) with, drawn live
-- over it,
-- - the sector borders (Config/Maps/<key>.dividers; the river's from its meander, Rules/MapTerrain), dashed blue;
-- - each side's land washed in its colour up to the front, and the front inked between the borders: the front sits as
--   far along the chain as the sectors' control adds up (each sector 0..1 toward the West), within a sector a blend of
--   its two borders;
-- - each point as an ink seal with its rune, ringed in its holder's magic colour (neutral: plain), amber and beating
--   while contested, its name under it.
-- The live state is Territory Push's (Workspace.<Config/Frontline FolderName>: per sector Owner, Control, West, East;
-- the folder's West / East = the two teams' kits). Without it (another mode, or none) the map shows the ground and the
-- points only.
--   SketchMap.new(box, mapKey?, opts?) -> { frame, front(): string?, destroy() }: fills `box` (keep its aspect: size /
--   the image's); front() names the sector the front is in (nil without a match); opts.you: the local soldier as a red
--   pencil arrow pointing where the camera looks (in play; never on the title screen); opts.deploy: a red pencil ring
--   round the point the team of the kit given to deploy(kit) spawns at (Rules/Frontline.spawn; the loadout menu),
--   named by deployName(); opts.teammates: a dot per living teammate (Rules/Teams: the same "Kit" as your soldier, or
--   in the loadout the kit you deploy in; never an enemy, nobody in a free-for-all) in the team's magic colour (in play
--   and the loadout; never on the title screen); teammate bots (tagged "Bot") too; opts.zone: the zone-capture match's
--   zone where it stands now (the Playtest map's Config/ZoneMatch marker): plain while free, your team's magic colour
--   while you hold it, red pencil while someone else does, flashing amber while contested. The markers are layers in
--   MARKERS: later kinds go there. opts.still: never the live state (the map vote's sheets); a map that isn't the
--   match's (src/shared/LiveMap) never shows it either.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.SketchMap) :: any
local Palette = require(Shared.Config.Palette)
local FrontRules = require(Shared.Rules.Frontline)
local FrontCfg = require(Shared.Config.Frontline)
local ResultsCfg = require(Shared.Config.Results)
local StatsRules = require(Shared.Rules.MatchStats)
local TeamRules = require(Shared.Rules.Teams)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local Playtest = require(Shared.Config.Maps.Playtest)
local LiveMap = require(Shared.LiveMap)
local Ink = require(script.Parent.Ink)
local PointSeal = require(script.Parent.PointSeal)

local SketchMap = {}

local C = (Palette.UI :: any).Grimoire
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local FONT = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
local HAND = Font.fromEnum(Enum.Font.IndieFlower) -- (the replay's times, written in pencil)
local BOT_TAG = require(Shared.Config.Bots).Tag -- the bot soldiers (src/server/Bots)
local FOLDER = "Frontline" -- Config/Frontline.FolderName (Territory Push; read by name so main without it still runs)

type Point = { id: string, name: string, x: number, z: number, hq: boolean, start: string }

-- What the markers see each frame: the local player and the kit of their team (nil: none known).
type Seen = { me: Player, kit: string? }
-- A kind of marker: `on` names the opt that turns it on; `list` gives this frame's marks (the world position and the
-- colour of each); `make` builds one mark's frame (anchored at its middle, sized as a share of the area's width).
type Marker = {
	on: string,
	list: (seen: Seen) -> { { at: Vector3, colour: Color3 } },
	make: (ink: Color3) -> Frame,
}

-- the marker kinds, drawn in this order under the local arrow; each is pooled (its frames reused, hidden when spare)
local MARKERS: { Marker } = {
	-- teammates: a small ink-edged dot in the team's magic colour per living soldier of your kit
	{
		on = "teammates",
		list = function(seen)
			local marks = {}
			local magic = seen.kit and C.Magic[seen.kit]
			if not magic then
				return marks
			end
			local ffa = workspace:GetAttribute(ZoneCfg.FreeForAllAttribute) == true
			for _, p in Players:GetPlayers() do
				local character = p.Character
				if
					p == seen.me
					or not character
					or not TeamRules.same(character:GetAttribute("Kit"), seen.kit, ffa)
				then
					continue
				end
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if humanoid and humanoid.Health > 0 and root then
					table.insert(marks, { at = root.Position, colour = rgb(magic) })
				end
			end
			-- teammate bots too (each carries its "Kit" like a character; far ones may not have streamed in)
			for _, m in CollectionService:GetTagged(BOT_TAG) do
				if not m:IsDescendantOf(workspace) or not TeamRules.same(m:GetAttribute("Kit"), seen.kit, ffa) then
					continue
				end
				local humanoid = m:FindFirstChildOfClass("Humanoid")
				local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
				if humanoid and humanoid.Health > 0 and root then
					table.insert(marks, { at = root.Position, colour = rgb(magic) })
				end
			end
			return marks
		end,
		make = function(ink)
			local dot = Instance.new("Frame")
			dot.BorderSizePixel = 0
			dot.Size = UDim2.fromScale(Cfg.Teammate.size, Cfg.Teammate.size)
			local aspect = Instance.new("UIAspectRatioConstraint")
			aspect.Parent = dot
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = dot
			local edge = Instance.new("UIStroke")
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.Color = ink
			edge.Parent = dot
			return dot
		end,
	},
}

-- the zone-capture match's zone (FFA, the Playtest map): one ink-ringed disc in its state's colour
table.insert(MARKERS, {
	on = "zone",
	list = function(seen)
		local map = workspace:FindFirstChild(Playtest.name)
		local zone = map and map:FindFirstChild(ZoneCfg.MarkerName)
		if not zone or not zone:IsA("Model") then
			return {}
		end
		local state = zone:GetAttribute("State")
		local colour = rgb(C.paper)
		if state == "Held" then
			local mine = zone:GetAttribute("Holder") == seen.me.UserId
			local magic = seen.kit and C.Magic[seen.kit]
			colour = if mine then (if magic then rgb(magic) else rgb(C.blue)) else rgb(C.pencil)
		elseif state == "Contested" and (os.clock() // Cfg.Zone.flash) % 2 == 0 then
			colour = rgb(C.amber)
		end
		return { { at = zone:GetPivot().Position, colour = colour } }
	end,
	make = function(ink)
		local disc = Instance.new("Frame")
		disc.BorderSizePixel = 0
		disc.Size = UDim2.fromScale(Cfg.Zone.size, Cfg.Zone.size)
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = disc
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc
		local edge = Instance.new("UIStroke")
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Color = ink
		edge.Parent = disc
		return disc
	end,
})

-- the map's sectors west to east and the borders between them (each a polyline of { x, z }, z from min to max),
-- with the drawn area's edges as the first and last
local function layout(key: string, m: any): ({ Point }, { { { number } } })
	local mapCfg = require(Shared.Config.Maps[key]) :: any
	local points: { Point } = {}
	for _, s in mapCfg.sectors do
		table.insert(points, {
			id = s.id,
			name = if s.isHQ then "HQ" else s.name,
			x = s.x,
			z = s.z,
			hq = s.isHQ == true,
			start = s.startOwner,
		})
	end
	local borders: { { { number } } } = { { { m.x[1], m.z[1] }, { m.x[1], m.z[2] } } }
	for _, d in mapCfg.dividers or {} do
		if d.river and mapCfg.river then
			local r, line = mapCfg.river, {}
			for z = m.z[1], m.z[2], 25 do
				table.insert(line, { r.x + r.meanderAmp * math.sin(z / r.meanderLen * 2 * math.pi), z })
			end
			table.insert(borders, line)
		elseif d.points then
			table.insert(borders, d.points)
		end
	end
	table.insert(borders, { { m.x[2], m.z[1] }, { m.x[2], m.z[2] } })
	return points, borders
end

local function borderX(b: { { number } }, z: number): number
	for k = 2, #b do
		if z <= b[k][2] then
			local a, c = b[k - 1], b[k]
			local u = if c[2] == a[2] then 0 else (z - a[2]) / (c[2] - a[2])
			return a[1] + (c[1] - a[1]) * u
		end
	end
	return b[#b][1]
end

function SketchMap.new(
	box: GuiObject,
	mapKey: string?,
	opts: { you: boolean?, deploy: boolean?, teammates: boolean?, zone: boolean?, still: boolean? }?
)
	local key = mapKey or "Map1"
	local m = Cfg.Maps[key]
	local points, borders = layout(key, m)

	local img = Instance.new("ImageLabel")
	img.Name = "SketchMap"
	img.BackgroundTransparency = 1
	img.Image = `rbxassetid://{m.image}`
	img.Size = UDim2.fromScale(1, 1)
	img.Parent = box
	-- the drawn area inside the torn edge: everything live is placed in it, x / z as shares of it
	local area = Instance.new("Frame")
	area.Name = "Area"
	area.BackgroundTransparency = 1
	area.Position = UDim2.fromScale(m.pad / m.size[1], m.pad / m.size[2])
	area.Size = UDim2.fromScale(1 - 2 * m.pad / m.size[1], 1 - 2 * m.pad / m.size[2])
	area.ClipsDescendants = true
	area.Parent = img
	local function u(x: number): number
		return (x - m.x[1]) / (m.x[2] - m.x[1])
	end
	local function v(z: number): number
		return (z - m.z[1]) / (m.z[2] - m.z[1])
	end

	-- the washes: strips per side, their inner ends at the front (Scale only, so they follow any size)
	local washes = Instance.new("Frame")
	washes.Name = "Washes"
	washes.BackgroundTransparency = 1
	washes.Size = UDim2.fromScale(1, 1)
	washes.Parent = area
	local bands = Cfg.WashBands
	local westBands, eastBands = {}, {}
	for i = 1, bands do
		for _, list in { westBands, eastBands } do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundTransparency = 1
			f.Position = UDim2.fromScale(0, (i - 1) / bands)
			f.Size = UDim2.fromScale(0, 1 / bands)
			f.Parent = washes
			table.insert(list, f)
		end
	end

	-- the borders (still) and the front (live): pixel strokes, redrawn on resize
	local blue, ink = rgb(C.blue), rgb(C.ink)
	Ink.draw(area, function(holder, w, h)
		local thick, dash, gap = math.max(1, Cfg.Border.thick * w), Cfg.Border.dash * w, Cfg.Border.gap * w
		for i = 2, #borders - 1 do
			local line = borders[i]
			for k = 2, #line do
				local a = Vector2.new(u(line[k - 1][1]) * w, v(line[k - 1][2]) * h)
				local b = Vector2.new(u(line[k][1]) * w, v(line[k][2]) * h)
				local len, dir = (b - a).Magnitude, (b - a).Unit
				local t = 0
				while t < len do
					local e = math.min(len, t + dash)
					Ink.segment(holder, a + dir * t, a + dir * e, thick, blue, Cfg.Border.transparency)
					t = e + gap
				end
			end
		end
	end)
	local frontBox = Instance.new("Frame")
	frontBox.Name = "Front"
	frontBox.BackgroundTransparency = 1
	frontBox.Size = UDim2.fromScale(1, 1)
	frontBox.Parent = area
	local frontCanvas = Ink.canvas(frontBox)
	local frontAt: number? = nil -- the front's place along the chain (0..#points), nil without a match
	local drawnFront: number? = -1
	local function drawFront()
		local f = frontAt
		if f == drawnFront then
			return
		end
		drawnFront = f
		if not f then
			frontCanvas.set(function() end)
			return
		end
		frontCanvas.set(function(holder, w, h)
			local k = math.clamp(math.floor(f), 0, #borders - 2)
			local fr = f - k
			local prev: Vector2? = nil
			for q = 0, 16 do
				local z = m.z[1] + (m.z[2] - m.z[1]) * q / 16
				local x = borderX(borders[k + 1], z) + (borderX(borders[k + 2], z) - borderX(borders[k + 1], z)) * fr
				local p = Vector2.new(u(x) * w, v(z) * h)
				if prev then
					Ink.segment(holder, prev, p, math.max(2, Cfg.Front.thick * w), ink)
				end
				prev = p
			end
		end)
	end

	-- the points: a seal (ink disc, ring, rune: src/client/PointSeal, the same as the beacon over its flag) and the name
	-- under it
	type Seal = PointSeal.Seal & { label: TextLabel }
	local seals: { [string]: Seal } = {}
	for i, p in points do
		local r = if p.hq then Cfg.Point.hqRadius else Cfg.Point.radius
		local disc = Instance.new("Frame")
		disc.Name = "Point" .. p.id
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(u(p.x), v(p.z))
		disc.Size = UDim2.fromScale(2 * r, 2 * r)
		local seal = PointSeal.new(disc, PointSeal.rune(i, #points), ink, rgb(C.neutral))
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.fromScale(u(p.x), v(p.z) + r + Cfg.Label.below)
		label.Size = UDim2.fromScale(0.1, 0.06)
		label.FontFace = FONT
		label.Text = p.name
		label.TextScaled = true
		label.TextColor3 = rgb(C.text)
		label.TextStrokeColor3 = ink
		label.TextStrokeTransparency = 0
		label.Parent = area
		disc.Parent = area
		local s = seal :: Seal
		s.label = label
		seals[p.id] = s
	end
	local function placeLabels()
		local a = area.AbsoluteSize
		if a.X <= 0 then
			return
		end
		for _, p in points do
			local s = seals[p.id]
			local r = if p.hq then Cfg.Point.hqRadius else Cfg.Point.radius
			s.label.Position = UDim2.fromScale(u(p.x), v(p.z) + (r + Cfg.Label.below) * a.X / a.Y)
			s.label.Size = UDim2.fromScale(0.1, Cfg.Label.size * a.X / a.Y)
			s.ring.Thickness = math.max(1, Cfg.Point.ring * a.X)
		end
	end
	area:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeLabels)
	task.defer(placeLabels)

	-- where you deploy: a red pencil ring
	local ring: Frame? = nil
	local deployKit: string? = nil
	local deployName: string? = nil
	if opts and opts.deploy then
		local r = Instance.new("Frame")
		r.Name = "Deploy"
		r.BackgroundTransparency = 1
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Visible = false
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = r
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = r
		local line = Instance.new("UIStroke")
		line.Color = rgb(C.pencil)
		line.Parent = r
		r.Parent = area
		ring = r
		area:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			line.Thickness = math.max(2, Cfg.Deploy.thick * area.AbsoluteSize.X)
		end)
	end

	-- The match's replay at its end (src/client/Results; user 2026-10-31: "a slight animation of the progression of the
	-- way (arrows, drawings, markers, all leading to the end of the game)"): each capture an arrow in its taker's colour
	-- with its time, drawn in turn (Config/Results.Replay, Rules/MatchStats.replayAt); the sectors' owners follow the
	-- replay; the winning capture ringed in red pencil.
	-- (`timing`: its seconds, lead, tail and draw, Config/Results.Replay unless the caller gives its own; `progress`: how
	-- far each capture's arrow is drawn, 0..1)
	type Replay = {
		log: { any },
		timed: { boolean },
		start: number,
		winner: boolean,
		owners: { string },
		drawn: number,
		timing: any,
		progress: { number },
	}
	local replay: Replay? = nil
	local A, RP = ResultsCfg.Arrow, ResultsCfg.Replay
	local replayBox = Instance.new("Frame")
	replayBox.Name = "Replay"
	replayBox.BackgroundTransparency = 1
	replayBox.Size = UDim2.fromScale(1, 1)
	replayBox.ZIndex = 4
	replayBox.Parent = area
	local replayCanvas = Ink.canvas(replayBox)
	local stamps: { TextLabel } = {}
	local winRing = Instance.new("Frame")
	winRing.Name = "Won"
	winRing.BackgroundTransparency = 1
	winRing.AnchorPoint = Vector2.new(0.5, 0.5)
	winRing.Visible = false
	winRing.ZIndex = 5
	do
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = winRing
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = winRing
		local line = Instance.new("UIStroke")
		line.Color = rgb(C.pencil)
		line.Parent = winRing
		area:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			line.Thickness = math.max(2, ResultsCfg.Win.thick * area.AbsoluteSize.X)
		end)
	end
	winRing.Parent = area
	-- capture `e`'s arrow (the k-th): from the neighbour its taker came from toward the point, in map shares
	local function arrowOf(e: any, k: number): (Vector2, Vector2, Vector2)
		local p = points[e.index]
		local here = Vector2.new(u(p.x), v(p.z))
		local n = points[e.index + (if e.side == "West" then -1 else 1)]
		local from = if n
			then Vector2.new(u(n.x), v(n.z))
			else here + Vector2.new(if e.side == "West" then -0.12 else 0.12, 0)
		local a = from:Lerp(here, A.from)
		local b = from:Lerp(here, A.to)
		local d = b - a
		local side = if k % 2 == 0 then 1 else -1
		local mid = (a + b) / 2 + Vector2.new(-d.Y, d.X) * A.bend * side
		return a, mid, b
	end
	local function drawReplay(r: Replay, now: number)
		local folder = workspace:FindFirstChild(FOLDER)
		local elapsed = now - r.start
		local n = #r.log
		for i, p in points do
			r.owners[i] = p.start
		end
		local progress: { number } = r.progress
		local P = r.timing
		for k, e in r.log do
			local at = StatsRules.replayAt(k, n, P.seconds, P.lead, P.tail)
			progress[k] = math.clamp((elapsed - at) / P.draw, 0, 1)
			if progress[k] >= 1 then
				r.owners[e.index] = e.side
			end
		end
		local total = 0
		for k in r.log do
			total += progress[k]
		end
		if total ~= r.drawn then
			r.drawn = total
			replayCanvas.set(function(holder, w, h)
				local size = Vector2.new(w, h)
				for k, e in r.log do
					local q = progress[k]
					if q <= 0 then
						continue
					end
					local kit = folder and folder:GetAttribute(e.side)
					local magic = kit and C.Magic[kit]
					local colour = if magic then rgb(magic):Lerp(rgb(C.ink), 0.35) else rgb(C.ink)
					local a, mid, b = arrowOf(e, k)
					local thick = math.max(2, A.thick * w)
					-- in pencil: the line wavers and its weight comes and goes, a fainter stroke beside it
					local across = (b - a).Unit
					across = Vector2.new(-across.Y, across.X)
					local function at(t: number, wob: number): Vector2
						local pt = (a:Lerp(mid, t)):Lerp(mid:Lerp(b, t), t)
						return (pt + across * wob * A.wobble * math.noise(k * 1.7, t * 5.3, wob)) * size
					end
					local steps = math.max(1, math.floor(A.steps * q + 0.5))
					for _, pass in { 0, 1 } do
						local last = at(0, 1) + across * size * A.pass * pass
						for i = 1, steps do
							local t = i / A.steps
							local pt = at(t, 1) + across * size * A.pass * pass
							local weight = 1 + A.weight * math.noise(k * 0.9, t * 7.1, 0.5)
							Ink.segment(
								holder,
								last,
								pt,
								thick * weight * (if pass == 1 then 0.6 else 1),
								colour,
								if pass == 1 then A.passFade else 0.08
							)
							last = pt
						end
					end
					if q >= 1 then
						local tip = b * size
						local back = ((mid:Lerp(b, 0.9)) * size - tip).Unit * ((b - a) * size).Magnitude * A.head
						for _, deg in { A.spread, -A.spread } do
							local r2 = math.rad(deg)
							local c, sn = math.cos(r2), math.sin(r2)
							local turned = Vector2.new(back.X * c - back.Y * sn, back.X * sn + back.Y * c)
							Ink.segment(holder, tip, tip + turned, thick, colour)
						end
					end
				end
			end)
		end
		for k, e in r.log do
			local stamp = stamps[k]
			if not stamp then
				stamp = Instance.new("TextLabel")
				stamp.BackgroundTransparency = 1
				stamp.AnchorPoint = Vector2.new(0.5, 0.5)
				stamp.FontFace = HAND
				stamp.TextScaled = true
				stamp.Rotation = (math.noise(k * 2.3, 0.4) * 2) * A.tilt
				stamp.TextColor3 = rgb(C.ink)
				stamp.ZIndex = 5
				stamp.Parent = area
				stamps[k] = stamp
			end
			local _, mid = arrowOf(e, k)
			-- (above the arrow's bend: the points' names sit under them)
			local tall = A.stamp * area.AbsoluteSize.X / math.max(area.AbsoluteSize.Y, 1)
			local at = mid - Vector2.new(0, tall * A.lift)
			stamp.Text = StatsRules.clock(e.t)
			stamp.Position = UDim2.fromScale(at.X, at.Y)
			stamp.Size = UDim2.fromScale(A.stamp * 3, A.stamp * area.AbsoluteSize.X / math.max(area.AbsoluteSize.Y, 1))
			stamp.Visible = progress[k] >= 0.5 and r.timed[k] ~= false
		end
		for k = n + 1, #stamps do
			stamps[k].Visible = false
		end
		local final = r.log[n]
		if r.winner and final and progress[n] >= 1 then
			local p = points[final.index]
			local rr = (if p.hq then Cfg.Point.hqRadius else Cfg.Point.radius) * ResultsCfg.Win.ring
			winRing.Position = UDim2.fromScale(u(p.x), v(p.z))
			winRing.Size = UDim2.fromScale(2 * rr, 2 * rr)
			winRing.Visible = true
		else
			winRing.Visible = false
		end
	end

	-- the live state
	local frontName: string? = nil
	local function update(now: number)
		-- (only the match's own map shows its state; a still map, the ground and the points alone)
		local folder = if (opts and opts.still) or key ~= LiveMap.key() then nil else workspace:FindFirstChild(FOLDER)
		local west = folder and folder:GetAttribute("West")
		local east = folder and folder:GetAttribute("East")
		local total = 0
		local live = folder ~= nil
		local r = replay
		if r then
			drawReplay(r, now)
		end
		for i, p in points do
			local s = seals[p.id]
			local sector = folder and folder:FindFirstChild(p.id)
			if not sector then
				live = false
				PointSeal.paint(s, rgb(C.neutral), rgb(C.neutral))
				continue
			end
			local owner = if r then r.owners[i] else sector:GetAttribute("Owner")
			local control = if r then FrontRules.rest(owner) else (sector:GetAttribute("Control") :: number?) or 0
			total += (control + 1) / 2
			local kit = if owner == "West" then west elseif owner == "East" then east else nil
			local w, e = (sector:GetAttribute("West") :: number?) or 0, (sector:GetAttribute("East") :: number?) or 0
			PointSeal.paint(s, PointSeal.colours(kit, not r and w > 0 and w == e, now))
			if total >= i - 1 and total < i then
				frontName = p.name
			end
		end
		-- the deploy ring: the side of the kit given, its spawn point by the shared rule
		if ring then
			local side = if deployKit and deployKit == west
				then "West"
				elseif deployKit and deployKit == east then "East"
				else nil
			if live and side and folder then
				local owners, captured = {}, false
				for i, p in points do
					local sector = folder:FindFirstChild(p.id)
					owners[i] = sector and sector:GetAttribute("Owner") or p.start
					captured = captured or owners[i] ~= p.start
				end
				-- (the server's own pick when it says, which also steps back while the enemy leads there:
				-- src/server/Frontline "<Side>Spawn")
				local given = folder:GetAttribute(side .. FrontCfg.SpawnAttribute)
				local at = points[if type(given) == "number" and points[given]
					then given
					else FrontRules.spawn({ owner = owners, control = {} }, side, captured)]
				local rad = (if at.hq then Cfg.Point.hqRadius else Cfg.Point.radius) * Cfg.Deploy.ring
				ring.Position = UDim2.fromScale(u(at.x), v(at.z))
				ring.Size = UDim2.fromScale(2 * rad, 2 * rad)
				ring.Visible = true
				deployName = at.name
			else
				ring.Visible = false
				deployName = nil
			end
		end
		frontAt = if live then math.round(total * 200) / 200 else nil -- (steps of 1/200: the front isn't redrawn every frame)
		if not live then
			frontName = nil
		end
		-- the washes up to the front, band by band
		local wc = west and C.Wash[west]
		local ec = east and C.Wash[east]
		for b = 1, bands do
			local z = m.z[1] + (m.z[2] - m.z[1]) * (b - 0.5) / bands
			local fx = 0
			if frontAt then
				local k = math.clamp(math.floor(frontAt), 0, #borders - 2)
				local fr = frontAt - k
				fx = u(borderX(borders[k + 1], z) + (borderX(borders[k + 2], z) - borderX(borders[k + 1], z)) * fr)
			end
			local wb, eb = westBands[b], eastBands[b]
			wb.Size = UDim2.fromScale(fx, 1 / bands)
			eb.Position = UDim2.fromScale(fx, (b - 1) / bands)
			eb.Size = UDim2.fromScale(1 - fx, 1 / bands)
			wb.BackgroundTransparency = if frontAt and wc then Cfg.WashTransparency else 1
			eb.BackgroundTransparency = if frontAt and ec then Cfg.WashTransparency else 1
			if wc then
				wb.BackgroundColor3 = rgb(wc)
			end
			if ec then
				eb.BackgroundColor3 = rgb(ec)
			end
		end
		drawFront()
	end
	-- you: a red pencil arrow (a diamond and a stroke ahead of it), turned the way the camera looks
	local you: Frame? = nil
	if opts and opts.you then
		local arrow = Instance.new("Frame")
		arrow.Name = "You"
		arrow.BackgroundTransparency = 1
		arrow.AnchorPoint = Vector2.new(0.5, 0.5)
		arrow.Size = UDim2.fromScale(Cfg.You.size, Cfg.You.size)
		arrow.ZIndex = 3
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = arrow
		local body = Instance.new("Frame")
		body.BorderSizePixel = 0
		body.BackgroundColor3 = rgb(C.pencil)
		body.AnchorPoint = Vector2.new(0.5, 0.5)
		body.Position = UDim2.fromScale(0.5, 0.62)
		body.Size = UDim2.fromScale(0.5, 0.5)
		body.Rotation = 45
		body.Parent = arrow
		local edge = Instance.new("UIStroke")
		edge.Color = ink
		edge.Parent = body
		local tip = Instance.new("Frame")
		tip.BorderSizePixel = 0
		tip.BackgroundColor3 = rgb(C.pencil)
		tip.AnchorPoint = Vector2.new(0.5, 1)
		tip.Position = UDim2.fromScale(0.5, 0.5)
		tip.Size = UDim2.fromScale(0.16, 0.5)
		tip.Parent = arrow
		arrow.Parent = area
		you = arrow
	end
	local function placeYou()
		local arrow = you
		if not arrow then
			return
		end
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		arrow.Visible = root ~= nil
		if not root then
			return
		end
		local p = root.Position
		arrow.Position = UDim2.fromScale(math.clamp(u(p.X), 0, 1), math.clamp(v(p.Z), 0, 1))
		local look = workspace.CurrentCamera.CFrame.LookVector
		-- the map's x is the world's X, its down the world's +Z: the arrow's up is the world's -Z
		arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end

	-- the markers on: a pool of frames each
	type Layer = { marker: Marker, box: Frame, pool: { Frame } }
	local layers: { Layer } = {}
	for i, marker in MARKERS do
		if opts and (opts :: any)[marker.on] then
			local holder = Instance.new("Frame")
			holder.Name = "Markers" .. i
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.fromScale(1, 1)
			holder.ZIndex = 2
			holder.Parent = area
			table.insert(layers, { marker = marker, box = holder, pool = {} })
		end
	end
	local function placeMarkers()
		if #layers == 0 then
			return
		end
		local me = Players.LocalPlayer
		local character = me.Character
		local seen: Seen = { me = me, kit = deployKit or (character and character:GetAttribute("Kit") :: string?) }
		local edge = math.max(1, Cfg.Teammate.edge * area.AbsoluteSize.X)
		for _, layer in layers do
			local marks = layer.marker.list(seen)
			for n, mark in marks do
				local f = layer.pool[n]
				if not f then
					f = layer.marker.make(ink)
					f.AnchorPoint = Vector2.new(0.5, 0.5)
					f.ZIndex = 2
					f.Parent = layer.box
					layer.pool[n] = f
				end
				f.Position = UDim2.fromScale(math.clamp(u(mark.at.X), 0, 1), math.clamp(v(mark.at.Z), 0, 1))
				f.BackgroundColor3 = mark.colour
				local stroke = f:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Thickness = edge
				end
				f.Visible = true
			end
			for n = #marks + 1, #layer.pool do
				layer.pool[n].Visible = false
			end
		end
	end

	local conn = RunService.Heartbeat:Connect(function()
		-- (on a screen, or on a paper in the world: the war table's sheet, src/client/CommandPost)
		local gui = box:FindFirstAncestorWhichIsA("LayerCollector")
		if img.Parent and box.Visible and gui then
			if gui.Enabled then
				update(os.clock())
				placeMarkers()
				placeYou()
			end
		end
	end)
	update(os.clock())

	return {
		frame = img,
		front = function(): string?
			return frontName
		end,
		deploy = function(kit: string?)
			deployKit = kit
		end,
		deployName = function(): string?
			return deployName
		end,
		-- plays the match's captures (`log`: { { t, index, side } } in order) from now; `won`: the last took the match;
		-- `timing` (seconds, lead, tail, draw) in place of Config/Results.Replay's
		replay = function(log: { any }, won: boolean, timing: any?)
			local shown, timed = StatsRules.replayLog(log, RP.most)
			replay = {
				log = shown,
				timed = timed,
				start = os.clock(),
				winner = won,
				owners = {},
				drawn = -1,
				timing = timing or RP,
				progress = {},
			}
		end,
		-- where things stand on the sketch, for props laid on it (the command post's blocks and pennants): each point's
		-- place and whether it's an HQ, and the replay's captures (their point, taker, how far drawn, and their arrow's
		-- start, bend and end), all in shares of the whole image (its torn edge included: x right, y down); nil captures
		-- without a replay
		state = function(): ({ { at: Vector2, hq: boolean, start: string } }, { any }?)
			local o = Vector2.new(m.pad / m.size[1], m.pad / m.size[2])
			local span = Vector2.new(1, 1) - o * 2
			local function image(p: Vector2): Vector2
				return o + p * span
			end
			local places = {}
			for i, p in points do
				places[i] = { at = image(Vector2.new(u(p.x), v(p.z))), hq = p.hq, start = p.start }
			end
			local r = replay
			if not r then
				return places, nil
			end
			local caps = {}
			for k, e in r.log do
				local a, mid, b = arrowOf(e, k)
				caps[k] = {
					index = e.index,
					side = e.side,
					q = r.progress[k] or 0,
					a = image(a),
					mid = image(mid),
					b = image(b),
				}
			end
			return places, caps
		end,
		-- back to the live state
		stopReplay = function()
			replay = nil
			replayCanvas.set(function() end)
			for _, st in stamps do
				st.Visible = false
			end
			winRing.Visible = false
		end,
		destroy = function()
			conn:Disconnect()
			img:Destroy()
		end,
	}
end

return SketchMap
