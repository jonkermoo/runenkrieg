--!strict
-- Client-side fracture debris for broken building sections (Net "SectionBroken"). Visual only:
-- local parts, never replicated, in the "Debris" collision group (never collides with characters). They fly until at
-- rest (Config.Destruction.Debris.Rest), then freeze where they lie, and stay until `lifetime`; past maxLive the oldest
-- go first. A frozen chunk wakes and falls again when what it may lie on goes (another chunk, a broken section), so
-- nothing is left floating. maxLive and lifetime are scaled by the player's Debris setting (Config/Settings.DebrisLevels,
-- Rules/Settings.debris). How a piece goes (its `m`, Config/Damage.Blast.Destroy): crumpled chunks drop near where they
-- were, a piece that lost its support only drops, glass shatters outward, and a pulverised piece ("dust") leaves a puff
-- of dust and a few shards that are gone in seconds.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local D = require(Shared.Config.Destruction)
local Net = require(Shared.Net)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Destruction)
local SettingsCfg = require(Shared.Config.Settings)
local SettingsRules = require(Shared.Rules.Settings)
local Settings = require(script.Parent.Settings)

local DebrisClient = {}

type Chunk = { part: BasePart, flying: number, still: number }

local live: { BasePart } = {} -- oldest first
local moving: { [BasePart]: Chunk } = {} -- flying, not yet at rest
local frozen: { [BasePart]: boolean } = {}
local gone: { { at: Vector3, radius: number } } = {} -- what went this frame (frozen chunks near it wake)
local container: Folder

-- something at `at` (`radius` its bounding radius) went: chunks frozen on it wake next frame
local function went(at: Vector3, radius: number)
	table.insert(gone, { at = at, radius = radius })
end

local function wake(p: BasePart)
	frozen[p] = nil
	p.Anchored = false
	moving[p] = { part = p, flying = 0, still = 0 }
end

-- `push`: how hard it is thrown from `origin` (Config/Destruction.Debris.Push; 0: it only drops, nudged to a side).
-- `brief`: a pulverised piece's shard, gone in seconds: never frozen and no part of the maxLive count.
local function spawnChunk(
	cf: CFrame,
	size: Vector3,
	color: Color3,
	transparency: number,
	origin: Vector3,
	lifetime: number,
	maxLive: number,
	push: number,
	brief: boolean?
)
	while not brief and #live >= maxLive do
		table.remove(live, 1):Destroy()
	end
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = transparency < 0.2
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = transparency
	p.Size = size
	p.CFrame = cf
	p.CollisionGroup = "Debris"
	p.Parent = container
	if push <= 0 then
		local a, n, s = math.random() * 2 * math.pi, D.Debris.fallNudge * math.random(), D.Debris.fallSpin
		p.AssemblyLinearVelocity = Vector3.new(math.cos(a) * n, 0, math.sin(a) * n)
		p.AssemblyAngularVelocity =
			Vector3.new((math.random() * 2 - 1) * s, (math.random() * 2 - 1) * s, (math.random() * 2 - 1) * s)
	else
		local away = cf.Position - origin
		local dist = math.max(away.Magnitude, 1)
		local speed = math.clamp(40 / dist, 0.5, 1) * math.random(18, 34)
		p.AssemblyLinearVelocity = (away.Unit * speed + Vector3.new(0, math.random(8, 22), 0)) * push
		p.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
	end
	if not brief then
		table.insert(live, p)
		moving[p] = { part = p, flying = 0, still = 0 }
	end
	p.Destroying:Connect(function()
		local i = table.find(live, p)
		if i then
			table.remove(live, i)
		end
		moving[p] = nil
		frozen[p] = nil
		went(p.Position, p.Size.Magnitude / 2)
	end)
	Debris:AddItem(p, lifetime)
end

-- Split a piece into up to `max` chunks along its two longest axes.
local function fracture(
	cf: CFrame,
	size: Vector3,
	color: Color3,
	t: number,
	origin: Vector3,
	max: number,
	lifetime: number,
	maxLive: number,
	push: number
)
	local axes = { { "X", size.X }, { "Y", size.Y }, { "Z", size.Z } }
	table.sort(axes, function(a, b)
		return a[2] > b[2]
	end)
	local n1 = math.clamp(math.floor(axes[1][2] / 2.5), 1, max)
	local n2 = math.clamp(math.floor(axes[2][2] / 2.5), 1, math.max(1, max // n1))
	local counts = { X = 1, Y = 1, Z = 1 }
	counts[axes[1][1]] = n1
	counts[axes[2][1]] = n2
	local cs = Vector3.new(size.X / counts.X, size.Y / counts.Y, size.Z / counts.Z)
	for i = 0, counts.X - 1 do
		for j = 0, counts.Y - 1 do
			for k = 0, counts.Z - 1 do
				local off = Vector3.new(
					(i + 0.5) * cs.X - size.X / 2,
					(j + 0.5) * cs.Y - size.Y / 2,
					(k + 0.5) * cs.Z - size.Z / 2
				)
				-- slightly shrink so chunks don't start interpenetrating
				spawnChunk(cf * CFrame.new(off), cs * 0.92, color, t, origin, lifetime, maxLive, push)
			end
		end
	end
end

-- a pulverised piece (Debris.Dust): a few small shards thrown hard and soon gone, and puffs of dust along it; `puffs` is
-- how many this break may still show. Returns the puffs left.
local function pulverise(
	cf: CFrame,
	size: Vector3,
	color: Color3,
	origin: Vector3,
	maxLive: number,
	puffs: number
): number
	local U = D.Debris.Dust
	local shard = Vector3.new(math.min(size.X, U.shard), math.min(size.Y, U.shard), math.min(size.Z, U.shard))
	for _ = 1, U.shards do
		local off =
			Vector3.new((math.random() - 0.5) * size.X, (math.random() - 0.5) * size.Y, (math.random() - 0.5) * size.Z)
		spawnChunk(cf * CFrame.new(off), shard, color, 0, origin, U.shardLife, maxLive, D.Debris.Push.dust, true)
	end
	local long = math.max(size.X, size.Y, size.Z)
	local n = math.min(math.clamp(math.floor(long / U.puffEvery), 1, 3), puffs)
	local axis = if long == size.X then Vector3.xAxis elseif long == size.Y then Vector3.yAxis else Vector3.zAxis
	local dust = color:Lerp(Color3.fromRGB(table.unpack(Palette.Buildings.Dust)), U.tint)
	local s = math.min(math.min(size.X, size.Y, size.Z) + long / n, U.puffMax / U.puffSize) * U.puffSize
	for i = 1, n do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = dust
		p.Transparency = U.alpha
		p.Size = Vector3.one * s
		local at = cf * (axis * long * ((i - 0.5) / n - 0.5))
		p.CFrame = CFrame.new(at) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		p.Parent = container
		TweenService:Create(
			p,
			TweenInfo.new(U.puffTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = p.Size * U.grow, Transparency = 1 }
		):Play()
		Debris:AddItem(p, U.puffTime)
	end
	return puffs - n
end

-- every `Rest.every` s: flying chunks at rest freeze; frozen chunks near anything that went wake
local function step(dt: number)
	local R = D.Debris.Rest
	for p, c in moving do
		c.flying += dt
		local freeze, letGo
		c.still, freeze, letGo = Rules.rested(
			p.AssemblyLinearVelocity.Magnitude,
			p.AssemblyAngularVelocity.Magnitude,
			c.still,
			c.flying,
			dt,
			R
		)
		if freeze then
			moving[p] = nil
			frozen[p] = true
			p.Anchored = true
		elseif letGo then
			moving[p] = nil -- (left to the physics engine: it sleeps once it stops)
		end
	end
	if #gone > 0 then
		local list = gone
		gone = {}
		local margin = D.Debris.wakeMargin
		for p in frozen do
			local at = p.Position
			for _, g in list do
				local o = at - g.at
				if Rules.leanedOn(o.X, o.Y, o.Z, g.radius, margin) then
					wake(p)
					break
				end
			end
		end
	end
end

function DebrisClient.start()
	container = Instance.new("Folder")
	container.Name = "ClientDebris"
	container.Parent = workspace
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= D.Debris.Rest.every then
			step(acc)
			acc = 0
		end
	end)
	-- any section gone (broken, swapped for its Remains, collapsed): what lay on it falls
	CollectionService:GetInstanceRemovedSignal(D.SectionTag):Connect(function(m)
		if m:IsA("Model") then
			local ok, cf, size = pcall(m.GetBoundingBox, m)
			if ok then
				went(cf.Position, size.Magnitude / 2)
			end
		end
	end)
	-- pieces: { cf, size, color, t, m? } (m: nil crumpled, "fall" lost its support, "dust" pulverised)
	Net.event("SectionBroken").OnClientEvent:Connect(function(pieces: { any }, origin: Vector3)
		local per = D.Debris.chunksPerSection
		local Push = D.Debris.Push
		local puffs = D.Debris.Dust.maxPuffs
		local maxLive, lifetime = SettingsRules.debris(
			(SettingsCfg.DebrisLevels :: any)[Settings.get("Debris")],
			D.Debris.maxLive,
			D.Debris.lifetime
		)
		-- one lifetime for the batch: a heap goes at once, not chunk by chunk from under the rest
		lifetime += math.random() * 1.5
		for _, piece in pieces do
			-- the section went: whatever lay on it falls
			went(piece.cf.Position, piece.size.Magnitude / 2)
			if piece.m == "dust" and piece.t <= 0.1 then
				puffs = pulverise(piece.cf, piece.size, piece.color, origin, maxLive, puffs)
			elseif piece.t > 0.1 then
				-- glass: more, smaller shards
				local push = if piece.m == "fall" then 0 else Push.glass
				fracture(piece.cf, piece.size, piece.color, piece.t, origin, 9, lifetime, maxLive, push)
			else
				local push = if piece.m == "fall" then 0 else Push.crumple
				fracture(piece.cf, piece.size, piece.color, piece.t, origin, per, lifetime, maxLive, push)
			end
		end
	end)
end

return DebrisClient
