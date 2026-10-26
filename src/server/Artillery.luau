--!strict
-- Artillery on the server (docs/MILESTONES.md A2; Config/Artillery, Rules/Artillery): places the guns (the dev menu,
-- and players' shovels: src/server/Build stands them), mans them, lays them and flies their shells.
-- - A gun is a copy of its library model (ReplicatedStorage.Assets.Weapons.Shared.Artillery), anchored, painted
--   (Config/Palette.Artillery), its pivot moved to gun space (found from the Bore disc at rest), standing in the
--   Workspace folder Config/Artillery.Folder. Its attributes: "Gun" (the Config/Artillery.Guns key), "Traverse",
--   "Elevation" (degrees), "FiredAt", "ReadyAt" (server time), "Gunner" (UserId). Every client poses the moving parts
--   from these (src/client/Artillery); the server moves only a turning mount (crewTurns: its gunner stands on it) and,
--   swinging the whole gun, its pivot. The gunner is welded to what they stand on.
-- - E (its ProximityPrompt) mans it: the gunner stands welded at the crew spot, platform-standing, weapons put away,
--   until they leave (Net "Artillery" "Leave"), die or go.
-- - "Aim" sets the wanted yaw and elevation; the gun works toward them at its rates (Rules/Artillery.lay).
-- - "Fire", loaded: the gunner braces (the howitzer charges up), the gun's `charge` s later the shell leaves the muzzle with the gun's lay plus scatter, flies the plain parabola (stepped
--   casts, so nothing thin is passed through) and goes off where it hits: Damage.blast with its charge and fragments,
--   every client shows it (Net "ArtilleryBlast").
-- - Every blast wears the guns down (Damage.onBlast; Config/Artillery.Hits): a direct hit on a gun takes a lot, one on
--   its pit, mound or the ground round it little. Its HP ("HP") falls through the Config/Artillery.Wreck stages
--   ("Stage"): scorched, then unusable ("Broken": its gunner thrown off, the prompt gone, the barrel knocked down, the
--   howitzer's crystal dead), leaning and sinking more each stage; at 0 a wreck that stays.
-- - A dug-in gun's pit is lined with trench dirt slabs (Config/Artillery.Slabs, the trench kit: src/server/Trenches),
--   laid rough, in the Workspace folder Config/Artillery.PitFolder, gone with the gun.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Artillery)
local Net = require(Shared.Net)
local Damage = require(script.Parent.Damage)
local Ground = require(script.Parent.Ground)
local Trenches = require(script.Parent.Trenches)
local TrenchCfg = require(Shared.Config.Build).Trench

local Artillery = {}

type State = {
	model: Model,
	key: string,
	gun: Cfg.Gun,
	prompt: ProximityPrompt,
	lay: Rules.Lay,
	want: { yaw: number, elevation: number },
	gunner: Player?,
	mannedAt: number,
	conns: { RBXScriptConnection },
	sent: number, -- when the lay was last written out
	aimed: number, -- when the gunner's last aim was taken
	crewAt: number, -- the traverse the mount was last turned to here
	mountRest: { [BasePart]: CFrame }, -- a turning mount's parts at rest, in gun space (crewTurns: posed here too)
	weld: WeldConstraint?, -- the gunner held on the gun
	bracing: boolean, -- a shot on its way (the gunner bracing)
	hp: number,
	stage: number, -- its Config/Artillery.Wreck stage (0: unhurt)
	broken: boolean, -- past Wreck.unusable: nobody can man it
	colors: { [BasePart]: Color3 }, -- as painted
	holes: number, -- shell holes punched in it so far (Wreck.holes)
	upright: CFrame?, -- its pivot before it first leaned
	lean: number, -- which way it leans (radians round its up axis)
	pit: Model?, -- its pit's slabs
}

local guns: { [Model]: State } = {}
local random = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function folder(): Folder
	local f = workspace:FindFirstChild(Cfg.Folder)
	if not f then
		f = Instance.new("Folder")
		f.Name = Cfg.Folder
		f.Parent = workspace
	end
	return f :: Folder
end

local function library(asset: string): Model
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, sub in { "Weapons", "Shared", "Artillery", asset } do
		f = f and f:FindFirstChild(sub)
	end
	assert(f and f:IsA("Model"), `artillery model {asset} is not in ReplicatedStorage.Assets (run the Library sync)`)
	return f :: Model
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- a mesh's team colour by the role its name ends in (Palette.Artillery.Roles: MountTrim, CarriageFittings, ...)
local function roleColor(name: string, team: string): { number }?
	local art = Palette.Artillery
	for _, role in art.Roles do
		if #name > #role and string.sub(name, -#role) == role then
			return (art.Team[team] :: any)[role]
		end
	end
	return nil
end

-- the team's paint on the painted parts, its accent colours on the accent pieces, the rest by mesh name; the runes and
-- the crystal glow
local function paint(model: Model, team: string)
	local art = Palette.Artillery
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Material = Enum.Material.SmoothPlastic
			d.Color = rgb(
				if table.find(art.Painted, d.Name)
					then art.Paint[team]
					else roleColor(d.Name, team) or (art :: any)[d.Name] or art.Barrel
			)
			if table.find(art.Glowing, d.Name) then
				d.Material = Enum.Material.Neon
			end
		end
	end
end

local function part(model: Model, name: string): BasePart
	local p = model:FindFirstChild(name, true)
	assert(p and p:IsA("BasePart"), `artillery model {model.Name} has no part {name}`)
	return p :: BasePart
end

-- gun space on the model as it lies: level, looking from the barrel to its muzzle, the origin found back from the Bore
-- disc (its centre sits `boreCentre` behind the muzzle face)
local function gunSpace(model: Model, gun: Cfg.Gun): CFrame
	local bore = part(model, "Bore")
	local barrel = part(model, "Barrel")
	local f = bore.Position - barrel.Position
	local rot = CFrame.Angles(0, math.rad(Rules.yawOf(f.X, f.Z)), 0)
	local m = gun.muzzle
	local origin = bore.Position - rot:VectorToWorldSpace(Vector3.new(m[1], m[2], m[3] + gun.boreCentre))
	return CFrame.new(origin) * rot
end

-- where the gunner's root stands: the crew spot, on whatever is under it, facing along the gun
local function crewSpot(s: State, character: Model): CFrame?
	-- (on the mount, the spot turns with its traverse)
	local pivot = s.model:GetPivot()
	if s.gun.crewTurns then
		pivot *= CFrame.Angles(0, math.rad(s.lay.traverse), 0)
	end
	local c = s.gun.crew
	local above = pivot:PointToWorldSpace(Vector3.new(c[1], 20, c[2]))
	local leg = character:FindFirstChild("Left Leg") :: BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not leg or not root then
		return nil
	end
	local floor: number
	if s.gun.crewY then
		floor = pivot:PointToWorldSpace(Vector3.new(c[1], s.gun.crewY, c[2])).Y
	else
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, s.model }
		local hit = workspace:Raycast(above, Vector3.new(0, -60, 0), params)
		if not hit then
			return nil
		end
		floor = hit.Position.Y
	end
	local y = floor + leg.Size.Y + root.Size.Y / 2
	local at = Vector3.new(above.X, y, above.Z)
	return CFrame.lookAt(at, at + pivot.LookVector)
end

local function leave(s: State)
	local player = s.gunner
	for _, c in s.conns do
		c:Disconnect()
	end
	s.conns = {}
	s.gunner = nil
	if s.weld then
		s.weld:Destroy()
		s.weld = nil
	end
	s.model:SetAttribute("Gunner", nil)
	s.prompt.Enabled = not s.broken
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = false
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
end

local function man(s: State, player: Player)
	if s.gunner or s.broken then
		return
	end
	for _, other in guns do
		if other.gunner == player then
			return
		end
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local spot = crewSpot(s, character)
	if not spot then
		return
	end
	humanoid:UnequipTools()
	-- held on the part of the gun they stand on (user 2026-10-21: "when turning, the player starts twitching on the
	-- gun": the server re-placed an anchored root 20 times a second while every client turns the gun smoothly), so on
	-- every client they ride the gun exactly as it's drawn
	root.CFrame = spot
	local holder = if s.gun.crewTurns then part(s.model, s.gun.mount[1]) else part(s.model, s.gun.base)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "ArtilleryGunner"
	weld.Part0 = root
	weld.Part1 = holder
	weld.Parent = root
	s.weld = weld
	root.Anchored = false
	-- and platform-standing (user 2026-10-22: "the field cannon is unoperable. the character starts tweaking out with
	-- the cannon. it only fixes when you have fly on": the dev Fly platform-stands): held by the weld, the humanoid
	-- still tried to stand and walk on the ground under it, fighting the gun
	humanoid.PlatformStand = true
	s.gunner = player
	s.mannedAt = os.clock()
	s.want = { yaw = s.lay.yaw + s.lay.traverse, elevation = s.lay.elevation }
	s.model:SetAttribute("Gunner", player.UserId)
	s.prompt.Enabled = false
	table.insert(
		s.conns,
		humanoid.Died:Connect(function()
			leave(s)
		end)
	)
	table.insert(
		s.conns,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(workspace) then
				leave(s)
			end
		end)
	)
	-- no weapon in the hands while on the gun
	table.insert(
		s.conns,
		character.ChildAdded:Connect(function(c)
			if c:IsA("Tool") then
				task.defer(function()
					humanoid:UnequipTools()
				end)
			end
		end)
	)
end

-- the shell's flight from `origin` at `velocity`, stepped against the world; goes off where it hits
local function fly(s: State, origin: Vector3, velocity: Vector3, by: Model?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { s.model }
	params.IgnoreWater = false
	params.CollisionGroup = "Default" -- the out-of-bounds walls stop only characters
	local g = s.gun.gravity -- (its own: slow shells, same ranges)
	local t = 0
	local prev = origin
	local key, gun = s.key, s.gun
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		local x, y, z = Rules.at(t, origin.X, origin.Y, origin.Z, velocity.X, velocity.Y, velocity.Z, g)
		local p = Vector3.new(x, y, z)
		local hit = workspace:Raycast(prev, p - prev, params)
		if hit then
			conn:Disconnect()
			local at = hit.Position + hit.Normal * 0.3
			Damage.blast(at, gun.kg, by, { fragments = gun.fragments, craterScale = gun.craterScale })
			Net.event("ArtilleryBlast"):FireAllClients(at, key)
		elseif t > Cfg.MaxFlight then
			conn:Disconnect()
		end
		prev = p
	end)
end

local function fire(s: State)
	local player = s.gunner
	local character = player and player.Character
	local t = now()
	local ready = s.model:GetAttribute("ReadyAt") :: number?
	if not character or s.broken or (ready and t < ready) then
		return
	end
	local gun = s.gun
	local r = {}
	for i = 1, 6 do
		r[i] = random:NextNumber()
	end
	local dYaw, dElev, speed = Rules.scatter(gun.scatter, r)
	local mx, my, mz, dx, dy, dz = Rules.muzzle(gun, s.lay.traverse + dYaw, s.lay.elevation + dElev)
	local pivot = s.model:GetPivot()
	local origin = pivot:PointToWorldSpace(Vector3.new(mx, my, mz))
	local velocity = pivot:VectorToWorldSpace(Vector3.new(dx, dy, dz)) * gun.speed * speed
	s.model:SetAttribute("FiredAt", t)
	s.model:SetAttribute("ReadyAt", t + gun.reload)
	Net.event("ArtilleryShot"):FireAllClients(s.model, origin, velocity)
	fly(s, origin, velocity, character)
end

local function pitFolder(): Folder
	local f = workspace:FindFirstChild(Cfg.PitFolder)
	if not f then
		f = Instance.new("Folder")
		f.Name = Cfg.PitFolder
		f.Parent = workspace
	end
	return f :: Folder
end

-- The ground's height over the pit's centre (flat ground) `along` the ramp's way out and `across` it, as Ground.pit
-- leaves it (`lean`: studs out per stud up of its walls)
local function surface(d: any, lean: number, along: number, across: number): number
	local r = math.sqrt(along * along + across * across)
	local top = d.radius + d.depth * lean
	local z = 0
	if r <= d.radius then
		z = -d.depth
	elseif r <= top then
		z = -d.depth + (r - d.radius) / lean
	elseif r <= top + d.rim then
		z = d.rimHeight * (1 - math.abs(r - top - d.rim / 2) / (d.rim / 2))
	end
	if d.ramp and along > 0 and along <= d.radius + d.ramp.length then
		local side = math.max(across - d.ramp.width / 2, 0)
		local lane = -d.depth + d.depth * math.clamp((along - d.radius) / d.ramp.length, 0, 1) + side / lean
		z = math.min(z, lane)
	end
	return z
end

-- Lines a gun's pit (centre `at` on the ground, the ramp out along `back`) with rough trench dirt slabs
-- (Config/Artillery.Slabs; the trench kit, src/server/Trenches): uneven rows round its leaning wall, the ramp's sides
-- where they're deep, a few loose floor pieces off the gun's bed. Rolled from where it stands, so the same every time.
local function slabs(at: Vector3, d: any, back: Vector3): Model?
	local kit, offsets = Trenches.pieceKit()
	if not kit then
		return nil
	end
	local S = Cfg.Slabs
	local rng = Random.new(math.floor(at.X) * 7919 + math.floor(at.Z) * 104729)
	local lean = 1 / math.tan(math.rad(d.wall))
	local up = Vector3.yAxis
	local side = back:Cross(up).Unit -- across the ramp
	local holder = Instance.new("Model")
	holder.Name = "Pit"
	local function place(name: string, cf: CFrame, stretch: number, k: number)
		local src = kit:FindFirstChild(name)
		local off = offsets[name]
		if not (src and src:IsA("BasePart") and off) then
			return
		end
		local p = src:Clone()
		p.Size = Vector3.new(src.Size.X * stretch, src.Size.Y * k, src.Size.Z * k)
		p.CFrame = cf * CFrame.new(off.Position.X * stretch, off.Position.Y * k, off.Position.Z * k) * off.Rotation
		p.Color = Trenches.pieceColor(name)
		p.Material = Enum.Material.SmoothPlastic
		local base = not (string.find(name, "Chunks") or string.find(name, "Planks"))
		p.Anchored = true
		p.CanCollide = base
		p.CanQuery = base
		p.CanTouch = false
		p.Parent = holder
	end
	local function jitter(range: number): number
		return rng:NextNumber(-range, range)
	end
	-- a wall slab with its foot's start at `foot`, leaning back out along `out` (flat), `length` along it from there,
	-- `height` up its slope, turned off true by `yaw` and `roll`; `heap`: a trench parapet behind its top
	local function slab(
		foot: Vector3,
		out: Vector3,
		length: number,
		height: number,
		yaw: number,
		roll: number,
		heap: boolean
	)
		local cf = CFrame.fromMatrix(foot, up:Cross(out), up, out) * CFrame.Angles(0, yaw, roll)
		local stretch = length / TrenchCfg.pieces.segment
		local n = S.walls[rng:NextInteger(1, #S.walls)]
		for _, suffix in { "", "Chunks", "Planks", "PlanksDark" } do
			place(`Wall{n}{suffix}`, cf, stretch, height / TrenchCfg.depth)
		end
		if heap then
			place(`Wall{n}Parapet`, cf * CFrame.new(0, height - TrenchCfg.depth, 0), stretch, 1)
		end
	end
	-- round the wall, the ramp's mouth left open
	local a = S.mouth
	while a < 2 * math.pi - S.mouth - S.turn[1] do
		local step = rng:NextNumber(S.turn[1], S.turn[2])
		local m = a + step / 2
		local out = back * math.cos(m) + side * math.sin(m)
		local x = up:Cross(out)
		for row = 0, S.rows - 1 do
			if rng:NextNumber() >= S.gap then
				local h0 = math.max(row * S.rowStep + rng:NextNumber(-S.shift, S.shift * 0.75), 0)
				local r = d.radius + h0 * lean + rng:NextNumber(-S.shift * 0.6, S.shift * 0.4)
				local length = 2 * r * math.tan(step / 2) + rng:NextNumber(S.extra[1], S.extra[2])
				local foot = at + out * r + up * (h0 - d.depth) - x * (length / 2)
				local height = rng:NextNumber(S.height[1], S.height[2])
				local heap = row == S.rows - 1 and rng:NextNumber() < S.parapet
				slab(foot, out, length, height, jitter(S.jitter[1]), jitter(S.jitter[2]), heap)
			end
		end
		a += step
	end
	-- the ramp's sides, where they stand high enough
	if d.ramp then
		local w = d.ramp.width / 2
		local pitch = math.atan(d.depth / d.ramp.length)
		local y = d.radius + 1
		while y < d.radius + d.ramp.length do
			local length = rng:NextNumber(S.rampLength[1], S.rampLength[2])
			local mid = y + length / 2
			local floor = surface(d, lean, mid, 0)
			local height = surface(d, lean, mid, w + S.rampHeight * lean + 2) - floor
			for _, sx in { -1, 1 } do
				if rng:NextNumber() >= S.rampGap and height >= S.rampMin then
					local out = side * sx
					local forward = up:Cross(out):Dot(back) > 0
					local along = if forward then y else y + length
					local foot = at + back * along + out * (w + jitter(0.3)) + up * surface(d, lean, along, 0)
					local roll = if forward then pitch else -pitch
					slab(foot, out, length, math.min(height, S.rampHeight), jitter(S.jitter[1] * 0.5), roll, false)
				end
			end
			y += length * rng:NextNumber(0.85, 1.05)
		end
	end
	-- a few loose floor pieces, none under the bed
	local n = S.floorGrid
	local segment = TrenchCfg.pieces.segment
	for i = 1, n do
		for j = 1, n do
			local u, v = (i - (n + 1) / 2) * S.floorStep, (j - (n + 1) / 2) * S.floorStep
			local r = math.sqrt(u * u + v * v)
			if rng:NextNumber() >= S.floorGap and r > S.floorStep * 1.2 and r < d.radius - S.floorStep / 2 then
				local centre = at + back * u + side * v + up * (0.05 - d.depth)
				local turn = rng:NextNumber(-S.floorTurn, S.floorTurn) + rng:NextInteger(0, 1) * math.pi / 2
				local cf = CFrame.fromMatrix(centre, up:Cross(back), up, back)
					* CFrame.Angles(0, turn, 0)
					* CFrame.new(-segment / 2, 0, 0)
				local f = rng:NextInteger(1, TrenchCfg.pieces.floors)
				place(`Floor{f}`, cf, 1, 1)
				place(`Floor{f}Chunks`, cf, 1, 1)
			end
		end
	end
	holder.Parent = pitFolder()
	return holder
end

-- Digs a gun in at `at` (its Config `dig`; user 2026-10-21: "when you build the howitzer, it will be slightly
-- underground to give it cover (even when spawned, it should naturally destroy the terrain and be more burrowed)"):
-- the pit carved to a level mud floor `depth` under the ground, an earth rim thrown up round it and a ramp down into it
-- behind the gun (`back`, flat; Ground.pit), its walls lined with trench slabs (`slabs`). Returns the floor and the slabs.
local function dig(at: Vector3, d: any, back: Vector3): (Vector3, Model?)
	local ramp = d.ramp and { dir = back, width = d.ramp.width, length = d.ramp.length }
	local out = Ground.pit(at, d.radius, d.depth, d.rim, d.rimHeight, ramp, d.wall)
	Net.event("GroundDug"):FireAllClients(at, out)
	local pit = if d.slabs and d.wall then slabs(at, d, back) else nil
	return at - Vector3.new(0, d.depth, 0), pit
end

-- a copy of a gun's library model, painted (`paint`: a Config/Palette.Artillery.Paint key, nil: Config/Artillery.Paint),
-- its pivot in gun space
local function copyOf(gun: Cfg.Gun, key: string, paintKey: string?): Model
	local model = library(gun.asset):Clone()
	model.Name = key
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- clients pose it whole
	paint(model, if paintKey and Palette.Artillery.Paint[paintKey] then paintKey else Cfg.Paint)
	local base = part(model, gun.base)
	model.PrimaryPart = base
	base.PivotOffset = base.CFrame:ToObjectSpace(gunSpace(model, gun))
	return model
end

-- A gun being built (src/server/Build; Config/Artillery.Assembly): a copy of it in `paint`, nothing to stand on, shoot or
-- touch, posed by Artillery.assemble. Not a gun (no "Gun", nobody mans it).
function Artillery.parts(key: string, paintKey: string?): Model?
	local gun = Cfg.Guns[key]
	if not gun then
		return nil
	end
	local model = copyOf(gun, key, paintKey)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	return model
end

-- each built gun's parts at rest in gun space (Artillery.parts copies, before they are posed), the quarter each appears
-- at (Config/Artillery.Assembly; nil: never while built) and the stage of the gun that moves it (1 mount ... 4 breech)
type Built = {
	rest: { [BasePart]: CFrame },
	at: { [BasePart]: number },
	moves: { [BasePart]: number },
	alpha: { [BasePart]: number }, -- its own transparency
}
local built: { [Model]: Built } = setmetatable({}, { __mode = "k" }) :: any

local function builtOf(model: Model, gun: Cfg.Gun): Built
	local got = built[model]
	if got then
		return got
	end
	local pivot = model:GetPivot()
	local b: Built = { rest = {}, at = {}, moves = {}, alpha = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			b.rest[d] = pivot:ToObjectSpace(d.CFrame)
			b.alpha[d] = d.Transparency
			-- its group: the longest name it starts with (BarrelRunes with Barrel)
			local length = 0
			for _, g in gun.assembly do
				for _, name in g.names do
					if #name > length and string.sub(d.Name, 1, #name) == name then
						b.at[d], length = g.at, #name
					end
				end
			end
			for i, names in { gun.mount, gun.cradle, gun.barrel, gun.breech } do
				if table.find(names, d.Name) then
					b.moves[d] = i
				end
			end
		end
	end
	built[model] = b
	return b
end

-- Poses a gun being built (Artillery.parts) standing at `at` with `quarters` of Config/Artillery.Assembly.quarters
-- done: each group in place once its quarter is done, unseen before; the barrel at the gun's lowest lay.
function Artillery.assemble(model: Model, key: string, at: CFrame, quarters: number)
	local gun = Cfg.Guns[key]
	if not gun then
		return
	end
	local b = builtOf(model, gun)
	local t = gun.trunnion
	local trunnion = CFrame.new(t[1], t[2], t[3])
	local lay = trunnion
		* CFrame.Angles(math.rad(math.clamp(0, gun.elevation[1], gun.elevation[2])), 0, 0)
		* trunnion:Inverse()
	for p, rest in b.rest do
		-- (user 2026-10-26: "the runes shouldn't be active until the cannon is built": nothing glows while built)
		local shown = b.at[p] ~= nil and b.at[p] <= quarters and not table.find(Palette.Artillery.Glowing, p.Name)
		p.Transparency = if shown then b.alpha[p] else 1
		p.CFrame = at * (if (b.moves[p] or 0) >= 2 then lay * rest else rest)
	end
end

-- The earth block a placed gun stands on (Config/Artillery.Ground): under its footprint in gun space, from the ground
-- (the pivot) down, part of the gun
local function standOn(model: Model)
	local G = Cfg.Ground
	local pivot = model:GetPivot()
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local half = d.Size / 2
			for _, c in
				{
					Vector3.new(1, 1, 1),
					Vector3.new(1, 1, -1),
					Vector3.new(1, -1, 1),
					Vector3.new(-1, 1, 1),
					Vector3.new(1, -1, -1),
					Vector3.new(-1, 1, -1),
					Vector3.new(-1, -1, 1),
					Vector3.new(-1, -1, -1),
				}
			do
				local l = pivot:PointToObjectSpace(d.CFrame:PointToWorldSpace(half * c))
				lo, hi = lo:Min(l), hi:Max(l)
			end
		end
	end
	local p = Instance.new("Part")
	p.Name = "Ground"
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = true, true, false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Color = rgb((Palette.Terrain :: any)[G.color])
	p.Size = Vector3.new(hi.X - lo.X + 2 * G.pad, G.depth, hi.Z - lo.Z + 2 * G.pad)
	p.CFrame = pivot * CFrame.new((lo.X + hi.X) / 2, -G.depth / 2 - 0.02, (lo.Z + hi.Z) / 2)
	p.Parent = model
end

-- Places a gun (a Config/Artillery.Guns key) at `at`, its muzzle toward `look` (flattened); a gun with `dig` is dug in.
-- `opts`: `paint` (a Config/Palette.Artillery.Paint key: a player-built gun in its team's paint); `dug`: its pit is
-- already carved round `at` (src/server/Build digs a built gun's pit stage by stage), only its slabs laid here.
function Artillery.place(key: string, at: Vector3, look: Vector3, opts: { paint: string?, dug: boolean? }?): Model?
	local gun = Cfg.Guns[key]
	if not gun then
		return nil
	end
	local model = copyOf(gun, key, opts and opts.paint)
	local base = model.PrimaryPart :: BasePart
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local pit: Model? = nil
	if gun.dig and opts and opts.dug then
		local d = gun.dig
		pit = if d.slabs and d.wall then slabs(at, d, -flat.Unit) else nil
		at -= Vector3.new(0, d.depth, 0)
	elseif gun.dig then
		at, pit = dig(at, gun.dig, -flat.Unit)
	end
	model:PivotTo(CFrame.lookAt(at, at + flat.Unit))
	standOn(model)
	model:SetAttribute("Gun", key)
	model:SetAttribute("Traverse", 0)
	local low = math.max(gun.elevation[1], 0) -- the lowest it lays (a mortar never lies flat)
	model:SetAttribute("Elevation", low)
	model:SetAttribute("HP", gun.hp)
	model:SetAttribute("Stage", 0)
	local colors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			colors[d] = d.Color
		end
	end

	local spot = Instance.new("Attachment")
	spot.Name = "Crew"
	spot.Parent = base
	spot.WorldPosition = model:GetPivot():PointToWorldSpace(Vector3.new(gun.crew[1], 3, gun.crew[2]))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Man the gun"
	prompt.ObjectText = gun.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = gun.prompt
	prompt.RequiresLineOfSight = false
	prompt.Parent = spot
	model.Parent = folder()

	local yaw = Rules.yawOf(flat.X, flat.Z)
	local s: State = {
		model = model,
		key = key,
		gun = gun,
		prompt = prompt,
		lay = { yaw = yaw, traverse = 0, elevation = low },
		want = { yaw = yaw, elevation = low },
		gunner = nil,
		mannedAt = 0,
		conns = {},
		sent = 0,
		aimed = 0,
		crewAt = 0,
		mountRest = {},
		weld = nil,
		bracing = false,
		hp = gun.hp,
		stage = 0,
		broken = false,
		colors = colors,
		holes = 0,
		upright = nil,
		lean = random:NextNumber(0, 2 * math.pi),
		pit = pit,
	}
	if gun.crewTurns then
		local pivot = model:GetPivot()
		for _, name in gun.mount do
			local p = model:FindFirstChild(name, true)
			if p and p:IsA("BasePart") then
				s.mountRest[p] = pivot:ToObjectSpace(p.CFrame)
			end
		end
	end
	guns[model] = s
	prompt.Triggered:Connect(function(player)
		man(s, player)
	end)
	model.Destroying:Connect(function()
		if s.gunner then
			leave(s)
		end
		if s.pit then
			s.pit:Destroy()
		end
		guns[model] = nil
	end)
	return model
end

-- Removes every gun.
function Artillery.clear()
	for model in guns do
		model:Destroy()
	end
end

-- a turning mount (the howitzer's, its gunner standing on it) posed here as well at its traverse, so the server's gunner
-- and its step stand where every client draws them
local function turnMount(s: State)
	s.crewAt = s.lay.traverse
	local frame = s.model:GetPivot() * CFrame.Angles(0, math.rad(s.lay.traverse), 0)
	for p, rest in s.mountRest do
		p.CFrame = frame * rest
	end
end

-- the Damage folder a gun's holes go in (src/client/Artillery carries each with the part named by its "On")
local function damageFolder(model: Model): Folder
	local f = model:FindFirstChild("Damage")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Damage"
		f.Parent = model
	end
	return f :: Folder
end

local function bare(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	parent: Instance,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = parent
	return p
end

-- One shell hole punched into the gun where a ray from round it meets one of its `wreckParts`: a dark disc in the
-- surface and a ring of torn metal flaps bent out round it, in that part's own colour gone dark
local function punch(s: State)
	local W = Cfg.Wreck
	local gun = s.gun
	local targets = {}
	for _, name in gun.wreckParts do
		local p = s.model:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			table.insert(targets, p)
		end
	end
	if #targets == 0 then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = targets
	local cf, size = s.model:GetBoundingBox()
	local reach = size.Magnitude
	for _ = 1, 8 do
		local inside = Vector3.new(
			random:NextNumber(-0.4, 0.4) * size.X,
			random:NextNumber(-0.2, 0.4) * size.Y,
			random:NextNumber(-0.4, 0.4) * size.Z
		)
		local into = cf:PointToWorldSpace(inside)
		local from = into + random:NextUnitVector() * reach
		local hit = workspace:Raycast(from, (into - from).Unit * reach * 1.5, params)
		if hit and hit.Instance:IsA("BasePart") then
			local on = hit.Instance :: BasePart
			local d = random:NextNumber(gun.holeSize[1], gun.holeSize[2])
			local face = CFrame.lookAt(hit.Position, hit.Position + hit.Normal)
			local holes = damageFolder(s.model)
			local dark = on.Color:Lerp(rgb(Palette.Artillery.Scorched), 0.6)
			local disc = face * CFrame.Angles(0, math.rad(90), 0)
			local parts = {
				bare(
					"Hole",
					Vector3.new(W.holeDepth, d, d),
					disc,
					rgb(Palette.Artillery.Hole),
					holes,
					Enum.PartType.Cylinder
				),
			}
			for k = 1, W.petals do
				local a = 2 * math.pi * (k + random:NextNumber(-0.25, 0.25)) / W.petals
				local flap = face
					* CFrame.Angles(0, 0, a)
					* CFrame.new(0, d * 0.45, 0)
					* CFrame.Angles(math.rad(-random:NextNumber(25, 55)), 0, 0)
					* CFrame.new(0, d * 0.15, -0.02)
				table.insert(parts, bare("Flap", Vector3.new(d * 0.3, d * 0.35, W.holeDepth), flap, dark, holes))
			end
			for _, p in parts do
				p:SetAttribute("On", on.Name)
				p:SetAttribute("Offset", on.CFrame:ToObjectSpace(p.CFrame))
			end
			return
		end
	end
end

-- the accent pieces of `roles` (Palette.Artillery.Roles) blown off: each hidden, a loose copy tumbling away
local function blowOff(s: State, roles: { string })
	local D = Cfg.Wreck.debris
	local centre = s.model:GetPivot().Position
	for _, d in s.model:GetDescendants() do
		if not d:IsA("BasePart") or d.Transparency >= 1 then
			continue
		end
		for _, role in roles do
			if #d.Name > #role and string.sub(d.Name, -#role) == role then
				local loose = d:Clone()
				loose.Anchored = false
				loose.CanCollide, loose.CanQuery, loose.CanTouch = true, false, false
				loose.CollisionGroup = "Debris"
				loose.Parent = workspace
				local out = (d.Position - centre) * Vector3.new(1, 0, 1)
				local dir = (if out.Magnitude > 1e-3 then out.Unit else random:NextUnitVector())
					+ Vector3.new(0, 1.2, 0)
				loose.AssemblyLinearVelocity = dir.Unit * random:NextNumber(D.speed[1], D.speed[2])
				loose.AssemblyAngularVelocity = random:NextUnitVector() * D.spin
				Debris:AddItem(loose, D.life)
				d.Transparency = 1
				break
			end
		end
	end
end

-- A gun's look at its Wreck stage: scorched toward Palette.Artillery.Scorched, holed and stripped of its accents
-- (Wreck.holes, Wreck.lose), knocked out of action from Wreck.unusable, its glow dead from Wreck.dark, leaning and sunk
-- (Config/Artillery.Wreck).
local function wreck(s: State)
	local W = Cfg.Wreck
	local art = Palette.Artillery
	local stage = s.stage
	local broken = stage >= W.unusable
	local dark = stage >= W.dark
	local scorched, dead = rgb(art.Scorched), rgb(art.Dead)
	for _ = s.holes + 1, W.holes[stage] or 0 do
		punch(s)
	end
	s.holes = math.max(s.holes, W.holes[stage] or 0)
	blowOff(s, W.lose[stage] or {})
	if dark then
		s.model:SetAttribute("Dead", true)
	end
	for p, c in s.colors do
		if dark and table.find(art.Glowing, p.Name) then
			p.Color = dead
			p.Material = Enum.Material.SmoothPlastic
		else
			p.Color = c:Lerp(scorched, W.scorch[stage] or 0)
		end
	end
	if broken and not s.broken then
		s.broken = true
		s.model:SetAttribute("Broken", true)
		if s.gunner then
			leave(s)
		end
		s.prompt.Enabled = false
		-- the barrel knocked down to its lowest lay and round a little
		local gun = s.gun
		local knock = math.min(W.knock, gun.traverse)
		s.lay = {
			yaw = s.lay.yaw,
			traverse = math.clamp(s.lay.traverse + random:NextNumber(-knock, knock), -gun.traverse, gun.traverse),
			elevation = gun.elevation[1],
		}
		s.want = { yaw = s.lay.yaw + s.lay.traverse, elevation = s.lay.elevation }
		s.model:SetAttribute("Traverse", math.round(s.lay.traverse * 100) / 100)
		s.model:SetAttribute("Elevation", s.lay.elevation)
		if gun.crewTurns then
			turnMount(s)
		end
	end
	local tilt, sink = W.tilt[stage] or 0, W.sink[stage] or 0
	if tilt > 0 or sink > 0 then
		s.upright = s.upright or s.model:GetPivot()
		local axis = Vector3.new(math.cos(s.lean), 0, math.sin(s.lean))
		s.model:PivotTo(CFrame.new(0, -sink, 0) * (s.upright :: CFrame) * CFrame.fromAxisAngle(axis, math.rad(tilt)))
	end
end

-- A blast at `position` (Damage.onBlast; `structure`: what set it off, a Config/Artillery.Hits key, nil: by its `kg`)
-- wears each gun down by how far it is from the gun's box (Config/Artillery.Hits).
local function blast(position: Vector3, kg: number, structure: string?)
	local H = Cfg.Hits
	local src = Rules.hitSource(structure, kg, H)
	for model, s in guns do
		if s.hp <= 0 then
			continue
		end
		local cf, size = model:GetBoundingBox()
		local function off(c: CFrame, sz: Vector3): number
			local l = c:PointToObjectSpace(position)
			return Vector3.new(
				math.max(math.abs(l.X) - sz.X / 2, 0),
				math.max(math.abs(l.Y) - sz.Y / 2, 0),
				math.max(math.abs(l.Z) - sz.Z / 2, 0)
			).Magnitude
		end
		local d = off(cf, size)
		-- its platform: a flat pad round its foot that counts as the gun (Config `platform`)
		-- (from the top of the earth it stands on, Config/Artillery.Ground)
		local pf = s.gun.platform
		local ground = model:FindFirstChild("Ground")
		if pf and ground and ground:IsA("BasePart") then
			local top = ground.CFrame * CFrame.new(0, (ground.Size.Y + pf.thick) / 2, 0)
			d = math.min(d, off(top, Vector3.new(ground.Size.X + 2 * pf.pad, pf.thick, ground.Size.Z + 2 * pf.pad)))
		end
		local amount = Rules.gunHit(d, src, H.direct)
		if amount > 0 then
			s.hp = math.max(s.hp - amount, 0)
			model:SetAttribute("HP", math.round(s.hp * 10) / 10)
			local stage = Rules.wreckStage(s.hp, s.gun.hp, Cfg.Wreck.at)
			if stage ~= s.stage then
				s.stage = stage
				model:SetAttribute("Stage", stage)
				wreck(s)
			end
		end
	end
end

local function stateOf(player: Player): State?
	for _, s in guns do
		if s.gunner == player then
			return s
		end
	end
	return nil
end

function Artillery.start()
	Damage.onBlast(blast)
	Net.event("Artillery").OnServerEvent:Connect(function(player: Player, kind: any, a: any, b: any)
		local s = stateOf(player)
		if not s then
			return
		end
		if kind == "Aim" then
			local t = os.clock()
			-- at most Aim.rate a second (a little slack for the network bunching them)
			if Rules.aimOk(a, b) and t - s.aimed >= 0.5 / Cfg.Aim.rate then
				s.aimed = t
				s.want = { yaw = Rules.wrap(a), elevation = b }
			end
		elseif kind == "Fire" then
			-- the gunner braces first, the shot goes a moment later (user 2026-10-20: "play that first then fire, a slight
			-- delay in the shots makes it feel real"); "BraceAt" says when, for the gunner's brace
			local ready = s.model:GetAttribute("ReadyAt") :: number?
			if s.bracing or (ready and now() < ready) then
				return
			end
			s.bracing = true
			s.model:SetAttribute("BraceAt", now())
			local gunner = s.gunner
			task.delay(s.gun.charge, function()
				s.bracing = false
				if s.gunner == gunner and guns[s.model] then
					fire(s)
				end
			end)
		elseif kind == "Leave" then
			if os.clock() - s.mannedAt >= Cfg.LeaveAfter then
				leave(s)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local s = stateOf(player)
		if s then
			leave(s)
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		for model, s in guns do
			if not s.gunner then
				continue
			end
			s.lay = Rules.lay(s.lay, s.want.yaw, s.want.elevation, s.gun, dt)
			if t - s.sent < 1 / Cfg.Send then
				continue
			end
			s.sent = t
			model:SetAttribute("Traverse", math.round(s.lay.traverse * 100) / 100)
			model:SetAttribute("Elevation", math.round(s.lay.elevation * 100) / 100)
			local pivot = model:GetPivot()
			local yaw = math.rad(s.lay.yaw)
			local _, current = pivot:ToOrientation()
			local turned = math.abs(Rules.wrap(math.deg(current - yaw))) > 0.01
			if turned then
				model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, yaw, 0))
			end
			-- a turning mount (the howitzer's, its gunner standing on it) is turned here as well, so the server's gunner
			-- and its step stand where every client draws them
			if s.gun.crewTurns and math.abs(s.lay.traverse - s.crewAt) > 0.05 then
				turnMount(s)
			end
		end
	end)
end

return Artillery
