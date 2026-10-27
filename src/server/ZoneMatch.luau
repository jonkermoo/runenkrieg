--!strict
-- The zone-capture free-for-all (Config/ZoneMatch, Rules/ZoneMatch) on the playtest map (Config/Maps/Playtest
-- .zoneMatch). Runs in the DEV place while Workspace has the attribute set (workspace:SetAttribute("Playtest", true))
-- and the map is built: one live zone moving between the map's spots every MoveEvery seconds (the next one marked
-- Warning seconds before), a soldier alone in it, alive and on their feet, scoring PointsPerSecond, two or more
-- contesting it; timed matches with a results pause, then scores reset and everyone respawns; everyone an enemy
-- (Workspace's FreeForAll attribute, Rules/Teams); each life spawned at the map's spawn point farthest from the
-- others and clear of the zone, protected for a moment (src/server/Damage.protect). The marker models carry the state
-- as attributes; src/client/ZoneMarker colours them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.ZoneMatch)
local DevCfg = require(Shared.Config.DevTools)
local Map = require(Shared.Config.Maps.Playtest)
local Rules = require(Shared.Rules.ZoneMatch)
local Damage = require(script.Parent.Damage)
local Ragdoll = require(script.Parent.Ragdoll)

local ZoneMatch = {}

local ATTRIBUTE = "Playtest"
local MK = Cfg.Marker
local spots: { { number } } = Map.zoneMatch.spots
local spawns: { { number } } = Map.zoneMatch.spawns

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

local function ground(x: number, z: number): number
	local hit = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), terrainOnly)
	return if hit then hit.Position.Y else 0
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function piece(model: Model, name: string, size: Vector3, cf: CFrame, color: { number }, transparency: number)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = rgb(color)
	p.Transparency = transparency
	p.Parent = model
end

-- the ring of blocks on the ground round (0, 0) (each block at its own ground height) and, for the live zone, the post
local function marker(name: string, parent: Instance, withPost: boolean, transparency: number): Model
	local model = Instance.new("Model")
	model.Name = name
	local n, r = MK.Segments, Cfg.Radius
	local len = 2 * math.pi * r / n + 0.2
	for i = 0, n - 1 do
		local a = i / n * 2 * math.pi
		local cf = CFrame.new(r * math.cos(a), MK.RingHeight / 2, r * math.sin(a)) * CFrame.Angles(0, -a, 0)
		piece(model, "Ring", Vector3.new(MK.RingWidth, MK.RingHeight, len), cf, MK.Colors.Free, transparency)
	end
	if withPost then
		local w, h = MK.PostWidth, MK.PostHeight
		piece(model, "Post", Vector3.new(w, h, w), CFrame.new(0, h / 2, 0), MK.Colors.Post, 0)
		local f = MK.Pennant
		piece(
			model,
			"Pennant",
			Vector3.new(f[1], f[2], f[3]),
			CFrame.new(w / 2 + f[1] / 2, h - f[2] / 2, 0),
			MK.Colors.Free,
			0
		)
	end
	model.WorldPivot = CFrame.new()
	model.Parent = parent
	return model
end

-- moves a marker onto spot `i`: centred there, each ring block down on the ground under it
local function moveTo(model: Model, i: number)
	local x, z = spots[i][1], spots[i][2]
	local y = ground(x, z)
	model:PivotTo(CFrame.new(x, y, z))
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name == "Ring" then
			local at = p.Position
			p.Position = Vector3.new(at.X, ground(at.X, at.Z) + MK.RingHeight / 2, at.Z)
		end
	end
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
local spot: number = 1

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
	local pos = Vector3.new(x, ground(x, z) + 3.2, z)
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

local function join(player: Player)
	player:SetAttribute(Cfg.ScoreAttribute, 0)
	local function spawned(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait() -- after Roblox has stood it on a spawn
		spawnAt(player)
	end
	player.CharacterAdded:Connect(spawned)
	if player.Character then
		task.spawn(spawned, player.Character)
	end
end

local function setSpot(i: number)
	spot = i
	moveTo(zone, i)
	zone:SetAttribute("Spot", i)
	zone:SetAttribute("MoveAt", workspace:GetServerTimeNow() + Cfg.MoveEvery)
	zone:SetAttribute("NextSpot", nil)
	nextZone:PivotTo(CFrame.new(0, -500, 0))
end

local function run(root: Instance)
	zone = marker(Cfg.MarkerName, root, true, 0)
	nextZone = marker(Cfg.NextMarkerName, root, false, MK.NextTransparency)
	local random = Random.new()
	while true do
		-- a match
		for _, p in Players:GetPlayers() do
			p:SetAttribute(Cfg.ScoreAttribute, 0)
		end
		setSpot(Rules.nextSpot(nil, #spots, random:NextNumber()))
		local endsAt = workspace:GetServerTimeNow() + Cfg.MatchSeconds
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
					and Rules.inside(r.Position.X, r.Position.Y - 3, r.Position.Z, centre.X, centre.Y, centre.Z, Cfg)
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
				end
			end
		end
		-- the results
		local scores = {}
		for _, p in Players:GetPlayers() do
			scores[p.UserId] = (p:GetAttribute(Cfg.ScoreAttribute) :: number?) or 0
		end
		local ranking = Rules.ranking(scores)
		zone:SetAttribute("Phase", "Results")
		zone:SetAttribute("State", "Free")
		zone:SetAttribute("Holder", nil)
		zone:SetAttribute("NextSpot", nil)
		zone:SetAttribute("Winner", ranking[1])
		zone:SetAttribute("EndsAt", workspace:GetServerTimeNow() + Cfg.ResultsSeconds)
		task.wait(Cfg.ResultsSeconds)
		for _, p in Players:GetPlayers() do
			task.spawn(function()
				p:LoadCharacter()
			end)
		end
	end
end

function ZoneMatch.start()
	if game.PlaceId ~= DevCfg.DevPlaceId or workspace:GetAttribute(ATTRIBUTE) ~= true then
		return
	end
	local root = workspace:FindFirstChild(Map.name)
	if not root then
		warn(`[ZoneMatch] the attribute is set but the map isn't built: Greybox.build("{Map.name}")`)
		return
	end
	workspace:SetAttribute(Cfg.FreeForAllAttribute, true)
	Players.PlayerAdded:Connect(join)
	for _, p in Players:GetPlayers() do
		join(p)
	end
	task.spawn(run, root)
end

return ZoneMatch
