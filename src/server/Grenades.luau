--!strict
-- Thrown grenades on the server (docs/MILESTONES.md G1; Config/Grenades, Rules/Grenade). The client says where it
-- looks (Net "GrenadeThrow", src/client/Grenades); the server checks the soldier holds a grenade with some left and
-- isn't throwing faster than Config/Grenades.Cooldown, then throws one from its own view of the head, along that look,
-- exactly as the client's arc preview drew it (Rules/Grenade.launch). The Tool's "Count" attribute says how many are
-- left (src/server/Armory gives Config/Grenades.Carried a life); the last one thrown empties the hand.
-- In flight it is a small bouncing ball (Config/Grenades.Body) carrying the model; it passes through soldiers (its own
-- collision group), so it can't hit the thrower or be caught. The Mills's pin stays behind and its lever flies off.
-- Config/Grenades.Fuse seconds after the throw it goes off: Damage.blast with the real charge, its fragments, trees
-- only stripped and shaken (user 2026-10-18), and every client shows the explosion (Net "GrenadeBlast").

local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Grenades)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Grenade)
local Net = require(Shared.Net)
local Armory = require(script.Parent.Armory)
local Damage = require(script.Parent.Damage)

local Grenades = {}

local GROUP = "Grenades"

-- The hand it leaves from (Rules/Grenade.hand): as the client's camera would put it, looking along `look`; never
-- past a wall between the head and the hand (Rules/Grenade.clearShare; src/client/Grenades draws from the same point).
function Grenades.hand(character: Model, head: Vector3, look: Vector3): Vector3
	local x, y, z = Rules.hand(head.X, head.Y, head.Z, look.X, look.Y, look.Z, Cfg.Throw.from)
	local line = Vector3.new(x, y, z) - head
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(head, line, params)
	return head + line * Rules.clearShare(line.Magnitude, hit and hit.Distance, Cfg.Throw.gap)
end

local function held(character: Model): (Tool?, string?)
	local tool = character:FindFirstChildOfClass("Tool")
	local name = tool and tool:GetAttribute("Weapon")
	if tool and type(name) == "string" and W[name] and W[name].class == "Grenade" and Cfg.Types[name] then
		return tool, name
	end
	return nil, nil
end

local function goOff(position: Vector3, name: string, by: Model?)
	local t = Cfg.Types[name]
	Damage.blast(position, t.kg, by, { fell = false, fragments = t.fragments })
	Net.event("GrenadeBlast"):FireAllClients(position, t.kg)
end

local function throw(character: Model, name: string, origin: Vector3, velocity: Vector3)
	local B = Cfg.Body
	local ball = Instance.new("Part")
	ball.Name = "Grenade"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * B.size
	ball.Transparency = 1
	ball.CustomPhysicalProperties = PhysicalProperties.new(B.density, B.friction, B.elasticity)
	ball.CollisionGroup = GROUP
	ball.CanQuery, ball.CanTouch = false, false
	ball.CFrame = CFrame.lookAlong(origin, velocity)

	local model = Armory.build(name)
	model.Name = "Thrown_" .. name
	local gun = model.PrimaryPart :: BasePart
	model:PivotTo(ball.CFrame)
	local weld = Instance.new("Weld")
	weld.Part0, weld.Part1 = ball, gun
	weld.Parent = ball
	ball.Parent = model
	model.Parent = workspace

	-- the pin stays in the hand; the lever flies off (the striker is free)
	local pin = model:FindFirstChild("Pin")
	if pin then
		pin:Destroy()
	end
	local lever = model:FindFirstChild("Lever") :: BasePart?
	if lever then
		local w = lever:FindFirstChildOfClass("Weld")
		if w then
			w:Destroy()
		end
		lever.Parent = workspace
		lever.Massless = false
		local L = B.lever
		lever.AssemblyLinearVelocity = velocity * L.carry + Vector3.yAxis * L.pop
		lever.AssemblyAngularVelocity = Vector3.new(L.spin, 0, L.spin / 2)
		Debris:AddItem(lever, L.life)
	end

	ball:SetNetworkOwner(nil) -- the server's physics: no client moves it
	ball.AssemblyLinearVelocity = velocity
	ball.AssemblyAngularVelocity = Vector3.new(Cfg.Throw.spin, 0, Cfg.Throw.spin * 0.5)

	-- each frame: swept from where it was (a fast throw never passes through thin ground or a wall: it's put back on
	-- the near side and bounced), and on the ground it thuds (`land`) then rolls to a stop (`roll`)
	local radius = B.size / 2
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	params.CollisionGroup = GROUP -- what it can touch (not soldiers)
	local last = ball.Position
	local landed = false
	local step = RunService.Heartbeat:Connect(function(dt)
		local p, v = ball.Position, ball.AssemblyLinearVelocity
		local move = p - last
		if move.Magnitude > 1e-3 then
			local hit = workspace:Raycast(last, move + move.Unit * radius, params)
			if hit then
				local n = hit.Normal
				local into = v:Dot(n)
				if into < 0 then
					v -= n * into * (1 + B.elasticity)
				end
				ball.CFrame = CFrame.new(hit.Position + n * radius)
				ball.AssemblyLinearVelocity = v
				p = ball.Position
			end
		end
		if workspace:Raycast(p, Vector3.yAxis * -(radius + B.probe), params) then
			local keep = if landed then math.exp(-B.roll * dt) else B.land
			landed = true
			ball.AssemblyLinearVelocity = Vector3.new(v.X * keep, v.Y, v.Z * keep)
			ball.AssemblyAngularVelocity *= keep
		end
		last = ball.Position
	end)

	task.delay(Cfg.Fuse, function()
		step:Disconnect()
		if not ball.Parent then
			return
		end
		local at = ball.Position + Vector3.yAxis * B.lift
		model:Destroy()
		goOff(at, name, character)
	end)
end

function Grenades.start()
	if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
		PhysicsService:RegisterCollisionGroup(GROUP)
	end
	for _, other in { GROUP, "Characters", "Debris", "Viewmodel" } do
		if PhysicsService:IsCollisionGroupRegistered(other) then
			PhysicsService:CollisionGroupSetCollidable(GROUP, other, false)
		end
	end

	local last: { [Player]: number } = {}
	Net.event("GrenadeThrow").OnServerEvent:Connect(function(player: Player, direction: any)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if not character or not humanoid or humanoid.Health <= 0 or not head or typeof(direction) ~= "Vector3" then
			return
		end
		local tool, name = held(character)
		local count = tool and tool:GetAttribute("Count")
		if not tool or not name or type(count) ~= "number" or count < 1 then
			return
		end
		local now = os.clock()
		if now - (last[player] or -math.huge) < Cfg.Cooldown then
			return
		end
		local d = direction :: Vector3
		local origin = Grenades.hand(character, head.Position, if d.Magnitude > 1e-3 then d else Vector3.zAxis)
		if not Rules.throwOk(d.X, d.Y, d.Z, (origin - head.Position).Magnitude, Cfg.Throw.reach) then
			return
		end
		last[player] = now
		count -= 1
		tool:SetAttribute("Count", count)
		tool.Name = Armory.label(name, count)
		local vx, vy, vz = Rules.launch(d.X, d.Y, d.Z, Cfg.Throw.loft, Cfg.Types[name].speed)
		throw(character, name, origin, Vector3.new(vx, vy, vz))
		if count <= 0 then
			tool:Destroy() -- the last one thrown: an empty hand
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
end

return Grenades
