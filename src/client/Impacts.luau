--!strict
-- What a bullet throws up where it lands (Config/Firing.Effects.Impacts; user 2026-10-17), local to each client: a dirt
-- puff on the ground, chips off stone, brick and anything else that stays put, splinters off a trunk, a splash on
-- water, and leaves falling where the line passes through a canopy (canopies let bullets through). Bits are anchored
-- parts moved here each frame: no physics, nothing replicated, never touched.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Firing)
local TreeCfg = require(Shared.Config.TreeSway)
local Trees = require(Shared.Rules.Trees)
local Net = require(Shared.Net)
local TreeSway = require(script.Parent.TreeSway)

local Impacts = {}

local I = Cfg.Effects.Impacts

type Bit = { part: BasePart, v: Vector3, spin: CFrame, gravity: number, drag: number, born: number, life: number }
local bits: { Bit } = {}
local folder: Folder? = nil

local DIRT = {
	[Enum.Material.Grass] = true,
	[Enum.Material.LeafyGrass] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true,
	[Enum.Material.Sand] = true,
}

local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Include
probe.FilterDescendantsInstances = { workspace.Terrain }
probe.IgnoreWater = false

local function container(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "ClientImpacts"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

local function spread(): Vector3
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2
end

-- `kind`'s bits at `at`, thrown out along `normal`, in `color`
local function burst(kind: any, at: Vector3, normal: Vector3, color: Color3)
	local now = os.clock()
	for _ = 1, kind.count do
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = color
		local s = kind.size * (0.7 + math.random() * 0.6)
		p.Size = if kind.long then Vector3.new(s, s, s * kind.long) else Vector3.new(s, s * 0.6, s)
		p.CFrame = CFrame.new(at + normal * 0.1)
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.Parent = container()
		local v = (normal + spread() * 0.6).Unit * kind.speed * (0.5 + math.random()) + Vector3.yAxis * kind.up
		table.insert(bits, {
			part = p,
			v = v,
			spin = CFrame.Angles(math.random() * 0.3, math.random() * 0.3, math.random() * 0.3),
			gravity = kind.gravity,
			drag = kind.drag,
			born = now,
			life = kind.life * (0.7 + math.random() * 0.6),
		})
	end
end

-- leaves from every standing canopy the line `from` -> `to` passes through
local function leaves(from: Vector3, to: Vector3)
	local line = to - from
	local length = line.Magnitude
	if length < 1 then
		return
	end
	local d = line / length
	local mid = (from + to) / 2
	for _, tree in CollectionService:GetTagged(TreeCfg.Tag) do
		local canopy = tree:FindFirstChild("Canopy") :: BasePart?
		if canopy then
			local half = canopy.Size * I.Leaf.canopyShare / 2
			if (canopy.Position - mid).Magnitude <= length / 2 + half.Magnitude then
				local o = canopy.CFrame:PointToObjectSpace(from)
				local v = canopy.CFrame:VectorToObjectSpace(d)
				local t = Trees.enterBox(o.X, o.Y, o.Z, v.X, v.Y, v.Z, length, half.X, half.Y, half.Z)
				if t then
					burst(I.Leaf, from + d * t, -d, canopy.Color)
				end
			end
		end
	end
end

-- `count` leaves falling at `at` in `color` (shedding canopies, src/client/TreeFall)
function Impacts.leaves(at: Vector3, color: Color3, count: number)
	for _ = 1, math.max(count // I.Leaf.count, 1) do
		burst(I.Leaf, at + spread() * I.Beam.scatter, -Vector3.yAxis, color)
	end
end

-- one bullet's line from `from` to where it landed (`hit`, the surface's `normal`, the `part` it hit)
function Impacts.shot(from: Vector3?, hit: Vector3, normal: Vector3?, part: Instance?)
	if from then
		leaves(from, hit)
	end
	if not normal or not part then
		return
	end
	if part == workspace.Terrain then
		local d = if from then (hit - from).Unit else -normal
		local r = workspace:Raycast(hit - d, d * 2, probe)
		local m = if r then r.Material else Enum.Material.Ground
		if m == Enum.Material.Water then
			-- (GetMaterialColor doesn't take Water: its colour is Terrain.WaterColor)
			burst(I.Splash, hit, Vector3.yAxis, workspace.Terrain.WaterColor)
		elseif DIRT[m] then
			burst(I.Dirt, hit, normal, workspace.Terrain:GetMaterialColor(m))
		else
			burst(I.Chip, hit, normal, workspace.Terrain:GetMaterialColor(m))
		end
	elseif part:IsA("BasePart") and part.Anchored and part.Transparency < 0.5 then
		local wood = part.Name == "Trunk" or part.Name == "Stump"
		burst(if wood then I.Splinter else I.Chip, hit, normal, part.Color)
	end
end

-- `kind`'s bits (Config/Firing.Effects.Impacts shape) thrown up out of the ground at `at`, in the ground's own colour
-- (the shovel's dig: src/client/Shovel)
function Impacts.dirt(at: Vector3, kind: any)
	local r = workspace:Raycast(at + Vector3.yAxis, Vector3.yAxis * -2, probe)
	local m = if r then r.Material else Enum.Material.Ground
	local color = if m == Enum.Material.Water
		then workspace.Terrain.WaterColor
		else workspace.Terrain:GetMaterialColor(if m == Enum.Material.Air then Enum.Material.Ground else m)
	burst(kind, at, Vector3.yAxis, color)
end

function Impacts.start()
	-- a staff beam through or near canopies (src/server/Trees.beam): a shake and leaves, scaled by the stage
	Net.event("LeavesHit").OnClientEvent:Connect(function(hits: any)
		if type(hits) ~= "table" then
			return
		end
		local B = I.Beam
		for _, h in hits do
			local tree, at, react = nil, nil, nil
			if type(h) == "table" then
				tree, at, react = h[1], h[2], h[3]
			end
			local canopy = typeof(tree) == "Instance" and tree:FindFirstChild("Canopy") :: BasePart?
			if canopy and typeof(at) == "Vector3" and type(react) == "number" then
				react = math.clamp(react, 0, B.maxReact)
				TreeSway.explode(at, B.radius, react * B.kick)
				Impacts.leaves(at, canopy.Color, math.max(math.floor(B.leaves * react), 1))
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if #bits == 0 then
			return
		end
		local now = os.clock()
		local parts, cframes = {}, {}
		for i = #bits, 1, -1 do
			local b = bits[i]
			if now - b.born >= b.life or not b.part.Parent then
				b.part:Destroy()
				table.remove(bits, i)
			else
				b.v = b.v * math.max(1 - b.drag * dt, 0) - Vector3.yAxis * b.gravity * dt
				table.insert(parts, b.part)
				table.insert(cframes, (b.part.CFrame + b.v * dt) * b.spin)
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return Impacts
