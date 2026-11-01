--!strict
-- Target dummies for manual tests (Config/DevTools.Dummies; spawned from src/client/DevTargetMenu through
-- src/server/DevTools): soldiers in a team's kit and species, with or without the helmet, standing, walking back and forth or
-- strafing side to side. src/server/Damage hurts anything with the dummy tag like a player's soldier, so they take real
-- shots, staff hits and blasts, get knocked and ragdolled, show the health faces (src/server/Bodies) and lose helmets.
-- They have no client of their own, so the server throws their bodies (as src/client/Ragdoll does for a player) and
-- stands them up again. A hit shows a readout over the head (Rules/DevActions.readout; also printed). A dead dummy lies
-- for Config/Metrics.Combat.RespawnDelay and comes back where it was put.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local DamageCfg = require(Shared.Config.Damage)
local Loco = require(Shared.Config.Locomotion)
local Anims = require(Shared.Rules.MovementSet).animations(Loco) -- the movement set in play
local Metrics = require(Shared.Config.Metrics)
local RagdollCfg = require(Shared.Config.Ragdoll)
local RagdollRules = require(Shared.Rules.Ragdoll)
local U = require(Shared.Config.Uniforms)
local Rules = require(Shared.Rules.DevActions)
local Helmets = require(script.Parent.Helmets)
local Ragdoll = require(script.Parent.Ragdoll)
local Showcase = require(script.Parent.Showcase)

local DevDummies = {}

local D = Cfg.Dummies

export type Spec = { kit: string, helmet: boolean, move: string, at: CFrame }

local specs: { [Model]: Spec } = setmetatable({}, { __mode = "k" }) :: any
-- a knock not yet matched with a health change (the readout shows them together)
local pending: { [Model]: string } = setmetatable({}, { __mode = "k" }) :: any
local count = 0

local function folder(): Folder
	local f = workspace:FindFirstChild(D.Folder) :: Folder?
	if not f then
		local made = Instance.new("Folder")
		made.Name = D.Folder
		made.Parent = workspace
		f = made
	end
	return f :: Folder
end

local function readout(m: Model, text: string)
	print(`[DevDummies] {m.Name}: {text}`)
	local head = m:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local R = D.Readout
	local gui = head:FindFirstChild("Readout") :: BillboardGui?
	if not gui then
		local g = Instance.new("BillboardGui")
		g.Name = "Readout"
		g.Size = UDim2.fromOffset(R.width, R.tall)
		g.StudsOffset = Vector3.new(0, R.height, 0)
		g.AlwaysOnTop = true
		g.MaxDistance = R.range
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextSize = R.size
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = R.stroke
		t.Parent = g
		g.Parent = head
		gui = g
	end
	local g = gui :: BillboardGui
	local label = g:FindFirstChild("Text") :: TextLabel
	label.Text = text
	g.Enabled = true
	local seq = ((g:GetAttribute("Seq") :: number?) or 0) + 1
	g:SetAttribute("Seq", seq)
	task.delay(R.show, function()
		if g.Parent and g:GetAttribute("Seq") == seq then
			g.Enabled = false
		end
	end)
end

-- every loose part's physics on the server: loosened joints split the body into new assemblies, which Roblox hands to
-- the nearest player (Studio round 2: dead dummies stood upright, owned by the player, so the server never threw them)
local function own(m: Model)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d:SetNetworkOwner(nil)
			end)
		end
	end
end

-- the body thrown along `direction` (flat; it tumbles that way), held limp, tipped over if it still stands
local function throw(m: Model, humanoid: Humanoid, knock: { [string]: number }, direction: Vector3, scale: number)
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = m:FindFirstChild("Torso") :: BasePart?
	if not root or not torso or humanoid.Health <= 0 then
		return -- (a dead body: src/server/Ragdoll throws it itself)
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else -root.CFrame.LookVector
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	local velocity = (dir * knock.push + Vector3.yAxis * (knock.lift - (knock.drop or 0))) * scale
	local axis = Vector3.new(0, 1, 0):Cross(dir)
	-- held for Tip.hold s, as src/server/Ragdoll does for a dead body (Studio, staff round 1: set once, a living
	-- body going limp lost most of it, so every blast throw came out alike)
	local spin = axis * knock.tumble * scale
	task.spawn(function()
		local stopAt = os.clock() + RagdollCfg.Tip.hold
		repeat
			root.AssemblyLinearVelocity = velocity
			root.AssemblyAngularVelocity = spin
			task.wait()
		until os.clock() >= stopAt or not root.Parent
	end)
	local T = RagdollCfg.Tip
	task.spawn(function()
		local t0 = os.clock()
		task.wait(T.after)
		while torso.Parent and m:GetAttribute("Ragdolled") == true and os.clock() - t0 < T.window do
			if torso.CFrame.UpVector.Y > T.upright then
				torso.AssemblyAngularVelocity += axis * T.spin
				torso.AssemblyLinearVelocity += dir * T.push
			end
			task.wait(T.every)
		end
	end)
end

-- the Humanoid's own tip-over states off: a server-owned soldier only goes down through src/server/Ragdoll
local function steady(humanoid: Humanoid)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
end

-- each soldier's get-up tracks, loaded on first use (a plain table, dropped with the Humanoid: KNOWN_TRAPS 64 tracks)
local getUps: { [Humanoid]: { [string]: AnimationTrack } } = {}
local function getUpTrack(humanoid: Humanoid, way: string): AnimationTrack
	local set = getUps[humanoid]
	if not set then
		set = {}
		getUps[humanoid] = set
		humanoid.Destroying:Connect(function()
			getUps[humanoid] = nil
		end)
		-- knocked again while getting up: stopped
		local m = humanoid.Parent :: Model
		m:GetAttributeChangedSignal("Ragdolled"):Connect(function()
			if m:GetAttribute("Ragdolled") == true then
				for _, t in getUps[humanoid] or {} do
					t:Stop(0)
				end
			end
		end)
	end
	local track = set[way]
	if not track then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. (RagdollCfg.GetUp :: any)[way].id
		track = (animator :: Animator):LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false
		set[way] = track
	end
	return track
end

-- up again once src/server/Ragdoll clears "Ragdolled" (the joints back): stood upright on its feet where it lies, facing
-- the way it lay, its physics on the server again (the body is one assembly once more), then GettingUp
-- (Config/Ragdoll.Stand; a GettingUp from flat on the ground alone left server-owned bodies lying or half up)
local function getUp(m: Model, humanoid: Humanoid)
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = m:FindFirstChild("Torso") :: BasePart?
	if not root or not torso or humanoid.Health <= 0 then
		return
	end
	own(m)
	local S = RagdollCfg.Stand
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { m }
	-- getting up by the animation (src/server/Ragdoll "GetUp", Config/Ragdoll.GetUp): stood where it will stand, facing
	-- the way it rises (Rules/Ragdoll.getUpWay), the root on the ground (the animation lies the torso down there)
	local way = m:GetAttribute("GetUp")
	local g = if type(way) == "string" then (RagdollCfg.GetUp :: any)[way] else nil
	local cf = torso.CFrame
	local _, fx, fz = RagdollRules.getUpWay(
		{ x = cf.LookVector.X, y = cf.LookVector.Y, z = cf.LookVector.Z },
		{ x = cf.UpVector.X, y = cf.UpVector.Y, z = cf.UpVector.Z }
	)
	local look = Vector3.new(fx, 0, fz)
	local at = torso.Position + (if g then look * g.ahead else Vector3.zero)
	local hit = workspace:Raycast(at + Vector3.yAxis * 2, Vector3.new(0, -(S.probe + 2), 0), params)
	local leg = m:FindFirstChild("Left Leg") :: BasePart?
	local height = (if leg then leg.Size.Y else 2) + root.Size.Y / 2 + humanoid.HipHeight
	local y = if hit then hit.Position.Y + height + (if g then 0 else S.lift) else at.Y
	local pos = Vector3.new(at.X, y, at.Z)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(pos, pos + look)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	if g then
		getUpTrack(humanoid, way :: string):Play(RagdollCfg.GetUp.fade)
	end
end

-- (src/server/Bots: the bot soldiers' bodies are handled the same way)
DevDummies.own = own
DevDummies.throw = throw
DevDummies.steady = steady
DevDummies.getUp = getUp

-- the idle cycle, and the walk cycle while moving (at its game pace, scaled by the speed)
local function animate(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local function track(name: string): AnimationTrack
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. (Anims :: any)[name].id
		local t = (animator :: Animator):LoadAnimation(anim)
		t.Priority = Enum.AnimationPriority.Core
		t.Looped = true
		return t
	end
	local idle, walk = track("idle"), track("walk")
	local W = Anims.walk
	idle:Play(Loco.Fade)
	-- dead: still (Rules/Ragdoll.animates; the idle's breath kept a dead dummy's torso moving)
	humanoid.Died:Connect(function()
		idle:Stop(0.1)
		walk:Stop(0.1)
	end)
	humanoid.Running:Connect(function(speed)
		if not RagdollRules.animates(humanoid.Health) then
			return
		elseif speed > Loco.IdleBelow then
			if not walk.IsPlaying then
				walk:Play(Loco.Fade)
			end
			walk:AdjustSpeed(math.clamp(speed / W.speed, Loco.PlaybackMin, Loco.PlaybackMax) * W.keyed / W.cycle)
		elseif walk.IsPlaying then
			walk:Stop(Loco.Fade)
		end
	end)
end

-- back and forth between its two patrol points (Rules/DevActions.leg), waiting while knocked down
local function patrol(m: Model, humanoid: Humanoid, spec: Spec)
	if spec.move == "Stand" then
		return
	end
	task.spawn(function()
		local leg = 1
		while m.Parent and humanoid.Health > 0 do
			if m:GetAttribute("Ragdolled") == true then
				task.wait(D.Poll * 2)
				continue
			end
			local right, forward = Rules.leg(spec.move, leg, D.Patrol)
			local goal = spec.at * Vector3.new(right, 0, -forward)
			humanoid:MoveTo(goal)
			local t0 = os.clock()
			while m.Parent and humanoid.Health > 0 and m:GetAttribute("Ragdolled") ~= true do
				local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
				local off = if root then root.Position - goal else Vector3.zero
				if Vector3.new(off.X, 0, off.Z).Magnitude < D.Arrive or os.clock() - t0 > D.LegTimeout then
					break
				end
				task.wait(D.Poll)
			end
			leg = -leg
		end
	end)
end

local respawn: (m: Model) -> ()

-- A dummy per `spec`, or nil when there are already Config/DevTools.Dummies.Max.
function DevDummies.spawn(spec: Spec): Model?
	local f = folder()
	if #f:GetChildren() >= D.Max then
		return nil
	end
	local kit = U.Kits[spec.kit]
	if not kit then
		return nil
	end
	count += 1
	-- dressed in the kit by Bodies (uniform, helmet, pack, species: src/server/Kits)
	local m = Showcase.dummy(`Dummy {count} ({Rules.kitName(Cfg, spec.kit)})`, spec.at, f, spec.kit)
	specs[m] = spec
	if not spec.helmet then
		Helmets.dress(m, nil)
	end
	m:SetAttribute("Muted", nil)
	local function group(d: Instance)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Characters" -- (client debris passes through, as with players)
		end
	end
	for _, d in m:GetDescendants() do
		group(d)
	end
	m.DescendantAdded:Connect(group)
	local humanoid = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = DamageCfg.Health
	humanoid.Health = DamageCfg.Health
	humanoid.WalkSpeed = D.WalkSpeed
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false) -- soldiers never swim (src/client/Wading)
	steady(humanoid)
	humanoid.AutoRotate = spec.move ~= "Strafe"
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = false
	own(m)
	CollectionService:AddTag(m, D.Tag)

	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		local knock = pending[m]
		pending[m] = nil
		if health < last then
			readout(m, Rules.readout(last - health, knock, health))
		end
		last = health
	end)
	m:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if m:GetAttribute("Ragdolled") ~= true and humanoid.Health > 0 then
			getUp(m, humanoid)
		end
	end)
	humanoid.Died:Connect(function()
		own(m)
		task.wait() -- (a hit's own knock comes with its death: let it land first)
		if not Ragdoll.active(m) then
			Ragdoll.knock(m, DamageCfg.Knocks.Other, -root.CFrame.LookVector)
		end
		task.delay(Metrics.Combat.RespawnDelay, function()
			if m.Parent then
				respawn(m)
			end
		end)
	end)
	animate(humanoid)
	patrol(m, humanoid, spec)
	return m
end

respawn = function(m: Model)
	local spec = specs[m]
	m:Destroy()
	if spec then
		DevDummies.spawn(spec)
	end
end

-- Every dummy back to full health; dead ones come back now.
function DevDummies.heal()
	for _, m in folder():GetChildren() do
		local humanoid = m:IsA("Model") and m:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
		elseif m:IsA("Model") then
			respawn(m)
		end
	end
end

function DevDummies.clear()
	for _, m in folder():GetChildren() do
		m:Destroy()
	end
end

function DevDummies.start()
	Ragdoll.knocked.Event:Connect(function(m: Model, name: string, direction: Vector3, scale: number)
		local humanoid = m:FindFirstChildOfClass("Humanoid")
		if not specs[m] or not humanoid then
			return
		end
		own(m)
		throw(m, humanoid, RagdollCfg.Knocks[name] :: any, direction, scale)
		-- a knock with no damage shows on its own
		pending[m] = name
		local health = humanoid.Health
		task.delay(D.Readout.knockWait, function()
			if pending[m] == name then
				pending[m] = nil
				readout(m, Rules.readout(0, name, health))
			end
		end)
	end)
end

return DevDummies
