--!strict
-- Artillery on the server (docs/MILESTONES.md A2; Config/Artillery, Rules/Artillery): places the guns (dev menu for
-- now), mans them, lays them and flies their shells.
-- - A gun is a copy of its library model (ReplicatedStorage.Assets.Weapons.Shared.Artillery), anchored, painted
--   (Config/Palette.Artillery), its pivot moved to gun space (found from the Bore disc at rest), standing in the
--   Workspace folder Config/Artillery.Folder. Its attributes: "Gun" (the Config/Artillery.Guns key), "Traverse",
--   "Elevation" (degrees), "FiredAt", "ReadyAt" (server time), "Gunner" (UserId). The server never moves the moving
--   parts: every client poses them from these (src/client/Artillery). Swinging the whole gun turns its pivot here.
-- - E (its ProximityPrompt) mans it: the gunner stands anchored at the crew spot, weapons put away, until they leave
--   (Net "Artillery" "Leave"), die or go.
-- - "Aim" sets the wanted yaw and elevation; the gun works toward them at its rates (Rules/Artillery.lay).
-- - "Fire", loaded: the gunner braces (the howitzer charges up), the gun's `charge` s later the shell leaves the muzzle with the gun's lay plus scatter, flies the plain parabola (stepped
--   casts, so nothing thin is passed through) and goes off where it hits: Damage.blast with its charge and fragments,
--   every client shows it (Net "ArtilleryBlast").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Artillery)
local Net = require(Shared.Net)
local Damage = require(script.Parent.Damage)

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
	crewAt: number, -- the traverse the gunner was last placed for
	bracing: boolean, -- a shot on its way (the gunner bracing)
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

-- the team's paint on the painted parts, the rest by mesh name; the runes and the crystal glow
local function paint(model: Model, team: string)
	local art = Palette.Artillery
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Material = Enum.Material.SmoothPlastic
			d.Color =
				rgb(if table.find(art.Painted, d.Name) then art.Paint[team] else (art :: any)[d.Name] or art.Barrel)
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
	s.model:SetAttribute("Gunner", nil)
	s.prompt.Enabled = true
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = false
	end
end

local function man(s: State, player: Player)
	if s.gunner then
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
	root.Anchored = true
	root.CFrame = spot
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
			Damage.blast(at, gun.kg, by, { fragments = gun.fragments })
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
	if not character or (ready and t < ready) then
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

-- Digs a gun in at `at` (its Config `dig`; user 2026-10-21: "when you build the howitzer, it will be slightly
-- underground to give it cover (even when spawned, it should naturally destroy the terrain and be more burrowed)"):
-- an earth rim thrown up round it, the pit carved inside, a level mud floor `depth` under the ground. Returns the floor.
local function dig(at: Vector3, d: any): Vector3
	local t = workspace.Terrain
	local here = CFrame.new(at)
	t:FillCylinder(here * CFrame.new(0, d.rimHeight / 2, 0), d.rimHeight, d.radius + d.rim, Enum.Material.Ground)
	local top = d.rimHeight + 8
	t:FillCylinder(here * CFrame.new(0, (top - d.depth) / 2, 0), top + d.depth, d.radius, Enum.Material.Air)
	t:FillCylinder(here * CFrame.new(0, -d.depth - 1, 0), 2, d.radius, Enum.Material.Mud)
	return at - Vector3.new(0, d.depth, 0)
end

-- Places a gun (a Config/Artillery.Guns key) at `at`, its muzzle toward `look` (flattened); a gun with `dig` is dug in.
function Artillery.place(key: string, at: Vector3, look: Vector3): Model?
	local gun = Cfg.Guns[key]
	if not gun then
		return nil
	end
	local model = library(gun.asset):Clone()
	model.Name = key
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- clients pose it whole
	paint(model, Cfg.Paint)
	local base = part(model, gun.base)
	model.PrimaryPart = base
	base.PivotOffset = base.CFrame:ToObjectSpace(gunSpace(model, gun))
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	if gun.dig then
		at = dig(at, gun.dig)
	end
	model:PivotTo(CFrame.lookAt(at, at + flat.Unit))
	model:SetAttribute("Gun", key)
	model:SetAttribute("Traverse", 0)
	local low = math.max(gun.elevation[1], 0) -- the lowest it lays (a mortar never lies flat)
	model:SetAttribute("Elevation", low)

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
		bracing = false,
	}
	guns[model] = s
	prompt.Triggered:Connect(function(player)
		man(s, player)
	end)
	model.Destroying:Connect(function()
		if s.gunner then
			leave(s)
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

local function stateOf(player: Player): State?
	for _, s in guns do
		if s.gunner == player then
			return s
		end
	end
	return nil
end

function Artillery.start()
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
			-- the gunner turns with it (and with the mount, standing on it)
			if turned or (s.gun.crewTurns and math.abs(s.lay.traverse - s.crewAt) > 0.05) then
				s.crewAt = s.lay.traverse
				local character = s.gunner and s.gunner.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local spot = character and crewSpot(s, character)
				if root and spot then
					root.CFrame = spot
				end
			end
		end
	end)
end

return Artillery
