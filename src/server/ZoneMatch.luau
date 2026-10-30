--!strict
-- The zone-capture free-for-all (Config/ZoneMatch, Rules/ZoneMatch) on the playtest map (Config/Maps/Playtest
-- .zoneMatch). Runs in the DEV place while the server's mode is FFA (src/server/Modes starts and stops it) and the map
-- is built: one live zone moving between the map's spots every MoveEvery seconds (the next one marked
-- Warning seconds before), a soldier alone in it, alive and on their feet, scoring PointsPerSecond, two or more
-- contesting it; timed matches with a results pause, then scores reset and everyone respawns; everyone an enemy
-- (Workspace's FreeForAll attribute, Rules/Teams); each life spawned at the map's spawn point farthest from the
-- others and clear of the zone, protected for a moment (src/server/Damage.protect). The marker models carry the state
-- as attributes; src/client/ZoneMarker colours them. The admin panel ends, restarts and lengthens a match, moves the
-- zone on and hands out score (src/server/DevTools).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.ZoneMatch)
local DevCfg = require(Shared.Config.DevTools)
local Map = require(Shared.Config.Maps.Playtest)
local Modes = require(Shared.Rules.Modes)
local Rules = require(Shared.Rules.ZoneMatch)
local Damage = require(script.Parent.Damage)
local Ragdoll = require(script.Parent.Ragdoll)

local ZoneMatch = {}

local MK = Cfg.Marker
local spots: { { number } } = Map.zoneMatch.spots
local spawns: { { number } } = Map.zoneMatch.spawns

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

local function ground(x: number, z: number): number
	local hit =
		workspace:Raycast(Vector3.new(x, Cfg.GroundRay.top, z), Vector3.new(0, -Cfg.GroundRay.depth, 0), terrainOnly)
	return if hit then hit.Position.Y else 0
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function piece(model: Model, name: string, size: Vector3, color: { number }, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = rgb(color)
	p.Transparency = transparency
	p.Parent = model
	return p
end

local function beam(name: string, parent: BasePart, a0: Attachment, a1: Attachment, layer: any)
	local b = Instance.new("Beam")
	b.Name = name
	b.Attachment0, b.Attachment1 = a0, a1
	b.Width0, b.Width1 = layer.width, layer.width
	b.FaceCamera = true
	b.LightEmission = MK.Beacon.lightEmission
	b.LightInfluence = 0
	b.Segments = 1
	b.Color = ColorSequence.new(rgb(MK.Colors.Free))
	b.Transparency = NumberSequence.new(layer.foot, layer.top)
	b.Parent = parent
end

-- a zone's marker (Config/ZoneMatch.Marker): the ring's segments and the dashes inside it (laid out by moveTo) and,
-- for the live zone, the beacon: a hidden anchor at the middle carrying the core and halo beams up and the light
local function marker(name: string, parent: Instance, withBeacon: boolean, transparency: number): Model
	local model = Instance.new("Model")
	model.Name = name
	local R, D = MK.Ring, MK.Dashes
	for _ = 1, R.segments do
		piece(model, "Ring", Vector3.new(R.width, R.height, 1), MK.Colors.Free, math.max(R.transparency, transparency))
	end
	for _ = 1, D.count do
		piece(model, "Dash", Vector3.new(D.width, D.height, 1), MK.Colors.Free, math.max(D.transparency, transparency))
	end
	if withBeacon then
		local B = MK.Beacon
		local anchor = piece(model, "Beacon", Vector3.one, MK.Colors.Free, 1)
		local foot, top = Instance.new("Attachment"), Instance.new("Attachment")
		foot.Name, top.Name = "Foot", "Top"
		top.Position = Vector3.new(0, B.height, 0)
		foot.Parent, top.Parent = anchor, anchor
		beam("Halo", anchor, foot, top, B.halo)
		beam("Core", anchor, foot, top, B.core)
		local light = Instance.new("PointLight")
		light.Range = MK.Light.range
		light.Brightness = MK.Light.brightness
		light.Shadows = false
		light.Color = rgb(MK.Colors.Free)
		light.Parent = anchor
	end
	model.Parent = parent
	return model
end

-- a point `r` out from (x, z) at angle `a`, just over the ground there
local function onGround(x: number, z: number, r: number, a: number, lift: number): Vector3
	local px, pz = x + r * math.cos(a), z + r * math.sin(a)
	return Vector3.new(px, ground(px, pz) + lift, pz)
end

-- lays a ring of `parts` round (x, z) at radius `r`: each piece from one point on the ground to the next (`fill` of
-- its share of the round; a whole ring overlaps a touch so the corners close)
local function lay(parts: { BasePart }, x: number, z: number, r: number, lift: number, fill: number)
	local n = #parts
	for k, p in parts do
		local a0 = (k - 1) / n * 2 * math.pi
		local a1 = a0 + fill / n * 2 * math.pi
		local p0, p1 = onGround(x, z, r, a0, lift), onGround(x, z, r, a1, lift)
		local length = (p1 - p0).Magnitude + if fill >= 1 then p.Size.X / 2 else 0
		p.Size = Vector3.new(p.Size.X, p.Size.Y, length)
		p.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
	end
end

-- moves a marker onto spot `i`: its rings laid over the ground, the beacon at the middle; its pivot the middle's ground
local function moveTo(model: Model, i: number)
	local x, z = spots[i][1], spots[i][2]
	local R, D = MK.Ring, MK.Dashes
	local ring, dashes = {}, {}
	for _, p in model:GetChildren() do
		if p.Name == "Ring" then
			table.insert(ring, p :: BasePart)
		elseif p.Name == "Dash" then
			table.insert(dashes, p :: BasePart)
		end
	end
	lay(ring, x, z, Cfg.Radius, R.lift, 1)
	lay(dashes, x, z, Cfg.Radius - D.inset, R.lift, D.fill)
	local y = ground(x, z)
	local anchor = model:FindFirstChild("Beacon") :: BasePart?
	if anchor then
		anchor.CFrame = CFrame.new(x, y + MK.Beacon.base, z)
	end
	model.WorldPivot = CFrame.new(x, y, z)
end

local function alive(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

local zone: Model
local nextZone: Model
local LD = Cfg.Leader
local leader: number? = nil
local spot: number = 1
-- this live spot's seconds held alone per player (UserId), and who has captured it
local held: { [number]: number } = {}
local captured: { [number]: boolean } = {}
local captureWatchers: { (Player) -> () } = {}
local matchWatchers: { () -> () } = {}
-- while running: the match loop, the player hooks, when this match ends (server time)
local thread: thread? = nil
local conns: { RBXScriptConnection } = {}
local endsAt = 0

-- `fn(player)` on each capture (Config/ZoneMatch.CaptureSeconds); `fn()` at each match's start
function ZoneMatch.onCapture(fn: (Player) -> ())
	table.insert(captureWatchers, fn)
end
function ZoneMatch.onMatchStart(fn: () -> ())
	table.insert(matchWatchers, fn)
end

local function spawnAt(player: Player)
	local others = {}
	for _, p in Players:GetPlayers() do
		local root = if p ~= player then (alive(p)) else nil
		if root then
			table.insert(others, { root.Position.X, root.Position.Z })
		end
	end
	local i = Rules.pickSpawn(spawns, others, spots[spot], Cfg.SpawnZoneClear)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return
	end
	local x, z = spawns[i][1], spawns[i][2]
	local pos = Vector3.new(x, ground(x, z) + Cfg.SpawnLift, z)
	local face = Vector3.new(spots[spot][1], pos.Y, spots[spot][2])
	character:PivotTo(CFrame.lookAt(pos, face))
	root.AssemblyLinearVelocity = Vector3.zero
	Damage.protect(character, Cfg.SpawnProtection)
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(pos)
		end)
	end)
end

-- the leader's glow on their living character (none while nobody leads, or they're dead)
local glowing: Highlight? = nil
local function glow()
	local p = if leader then Players:GetPlayerByUserId(leader) else nil
	local model = if p and alive(p) then p.Character else nil
	if glowing and glowing.Parent == model then
		return
	end
	if glowing then
		glowing:Destroy()
		glowing = nil
	end
	if model then
		local h = Instance.new("Highlight")
		h.Name = LD.name
		h.FillColor, h.FillTransparency = rgb(LD.fill), LD.fillTransparency
		h.OutlineColor, h.OutlineTransparency = rgb(LD.outline), LD.outlineTransparency
		h.DepthMode = (Enum.HighlightDepthMode :: any)[LD.depthMode]
		h.Parent = model
		glowing = h
	end
end

local function scores(): { [number]: number }
	local t = {}
	for _, p in Players:GetPlayers() do
		t[p.UserId] = (p:GetAttribute(Cfg.ScoreAttribute) :: number?) or 0
	end
	return t
end

-- the point leader now (Rules/ZoneMatch.leader), on the marker and glowing
local function lead()
	leader = Rules.leader(scores(), leader)
	zone:SetAttribute(Cfg.LeaderAttribute, leader)
	glow()
end

local function join(player: Player)
	player:SetAttribute(Cfg.ScoreAttribute, 0)
	local function spawned(character: Model)
		character:WaitForChild("HumanoidRootPart", Cfg.SpawnWait)
		task.wait() -- after Roblox has stood it on a spawn
		spawnAt(player)
	end
	table.insert(conns, player.CharacterAdded:Connect(spawned))
	if player.Character then
		task.spawn(spawned, player.Character)
	end
end

local function setSpot(i: number)
	spot = i
	table.clear(held)
	table.clear(captured)
	moveTo(zone, i)
	zone:SetAttribute("Spot", i)
	zone:SetAttribute("MoveAt", workspace:GetServerTimeNow() + Cfg.MoveEvery)
	zone:SetAttribute("NextSpot", nil)
	nextZone.Parent = nil -- shown again for the next warning
end

local function run()
	local random = Random.new()
	while true do
		-- a match
		for _, p in Players:GetPlayers() do
			p:SetAttribute(Cfg.ScoreAttribute, 0)
		end
		leader = nil
		lead()
		for _, fn in matchWatchers do
			task.spawn(fn)
		end
		setSpot(Rules.nextSpot(nil, #spots, random:NextNumber()))
		endsAt = workspace:GetServerTimeNow() + Cfg.MatchSeconds
		zone:SetAttribute("Phase", "Match")
		zone:SetAttribute("EndsAt", endsAt)
		zone:SetAttribute("Winner", nil)
		local pending: number? = nil
		local last = os.clock()
		while workspace:GetServerTimeNow() < endsAt do
			task.wait(Cfg.Tick)
			local dt = os.clock() - last
			last = os.clock()
			local now = workspace:GetServerTimeNow()
			local moveAt = zone:GetAttribute("MoveAt") :: number
			if not pending and now >= moveAt - Cfg.Warning then
				pending = Rules.nextSpot(spot, #spots, random:NextNumber())
				zone:SetAttribute("NextSpot", pending)
				nextZone.Parent = zone.Parent
				moveTo(nextZone, pending :: number)
			end
			if pending and now >= moveAt then
				setSpot(pending)
				pending = nil
			end
			local centre = zone:GetPivot().Position
			local inside = {}
			for _, p in Players:GetPlayers() do
				local r = alive(p)
				local character = p.Character
				if
					r
					and character
					and not Ragdoll.active(character)
					and not Damage.protected(character)
					and Rules.inside(
						r.Position.X,
						r.Position.Y - Cfg.FeetBelowRoot,
						r.Position.Z,
						centre.X,
						centre.Y,
						centre.Z,
						Cfg
					)
				then
					table.insert(inside, p.UserId)
				end
			end
			local state, holder = Rules.occupancy(inside)
			zone:SetAttribute("State", state)
			zone:SetAttribute("Holder", holder)
			if holder then
				local p = Players:GetPlayerByUserId(holder)
				if p then
					local score = (p:GetAttribute(Cfg.ScoreAttribute) :: number?) or 0
					p:SetAttribute(Cfg.ScoreAttribute, score + Cfg.PointsPerSecond * dt)
					held[holder] = (held[holder] or 0) + dt
					if Rules.captured(held[holder], Cfg.CaptureSeconds, captured[holder] == true) then
						captured[holder] = true
						for _, fn in captureWatchers do
							task.spawn(fn, p)
						end
					end
				end
			end
			lead()
		end
		-- the results: the leader at the end wins (user 2026-10-29)
		lead()
		zone:SetAttribute("Phase", "Results")
		zone:SetAttribute("State", "Free")
		zone:SetAttribute("Holder", nil)
		zone:SetAttribute("NextSpot", nil)
		zone:SetAttribute("Winner", leader)
		zone:SetAttribute("EndsAt", workspace:GetServerTimeNow() + Cfg.ResultsSeconds)
		task.wait(Cfg.ResultsSeconds)
		for _, p in Players:GetPlayers() do
			task.spawn(function()
				p:LoadCharacter()
			end)
		end
	end
end

-- Whether the match is running (the server's mode is FFA).
function ZoneMatch.running(): boolean
	return thread ~= nil
end

-- Starts the match (src/server/Modes, switching to FFA): false outside the DEV place or with the map unbuilt.
function ZoneMatch.start(): boolean
	if thread or game.PlaceId ~= DevCfg.DevPlaceId then
		return false
	end
	local root = workspace:FindFirstChild(Map.name)
	if not root then
		warn(`[ZoneMatch] the map isn't built: Greybox.build("{Map.name}")`)
		return false
	end
	workspace:SetAttribute(Cfg.FreeForAllAttribute, true)
	zone = marker(Cfg.MarkerName, root, true, 0)
	nextZone = marker(Cfg.NextMarkerName, root, false, MK.NextTransparency)
	table.insert(conns, Players.PlayerAdded:Connect(join))
	for _, p in Players:GetPlayers() do
		join(p)
	end
	thread = task.spawn(run)
	return true
end

-- Stops the match and takes its markers, scores and free-for-all away (src/server/Modes, switching away from FFA).
function ZoneMatch.stop()
	if not thread then
		return
	end
	task.cancel(thread :: thread)
	thread = nil
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	leader = nil
	glow()
	zone:Destroy()
	nextZone:Destroy()
	workspace:SetAttribute(Cfg.FreeForAllAttribute, nil)
	for _, p in Players:GetPlayers() do
		p:SetAttribute(Cfg.ScoreAttribute, nil)
	end
end

-- Admin: a fresh match now (scores reset, a new spot; nobody respawns).
function ZoneMatch.restart()
	if not thread then
		return
	end
	task.cancel(thread :: thread)
	thread = task.spawn(run)
end

local function playing(): boolean
	return thread ~= nil and zone:GetAttribute("Phase") == "Match"
end

-- Admin: the match ends now (the results, then the next match).
function ZoneMatch.finish()
	if playing() then
		endsAt = workspace:GetServerTimeNow()
	end
end

-- Admin: `delta` seconds more (or less) on the match clock.
function ZoneMatch.extend(delta: number)
	if playing() then
		endsAt = Modes.extend(endsAt, delta, workspace:GetServerTimeNow())
		zone:SetAttribute("EndsAt", endsAt)
	end
end

-- Admin: the zone moves to its next spot now.
function ZoneMatch.skip()
	if playing() then
		zone:SetAttribute("MoveAt", workspace:GetServerTimeNow())
	end
end

-- Admin: `amount` zone score for `player`.
function ZoneMatch.addScore(player: Player, amount: number)
	if playing() then
		player:SetAttribute(Cfg.ScoreAttribute, ((player:GetAttribute(Cfg.ScoreAttribute) :: number?) or 0) + amount)
		lead()
	end
end

return ZoneMatch
