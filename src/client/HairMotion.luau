--!strict
-- Hair sway (Config/HairMotion; user 2026-10-20: "slight animation like the animal ears and tails", "not laggy").
-- Every client moves every near soldier's hair itself, as src/client/SpeciesMotion moves ears and tails: the worn
-- "Hair" model (src/server/Helmets) is skinned to a few bones (tools/hair/rig_hair.py), and each moving bone's
-- Transform swings it on a spring toward Rules/HairMotion's angles: a slight idle sway, trailing back on the move,
-- swinging against sidesteps and turns, a bounce with the stride, lifting when falling; less under a helmet; settled
-- and still once dead. Nothing replicates. Soldiers beyond Config.Range or off screen hold still, and at most
-- Config.PerFrame soldiers move per frame (the rest wait their turn and catch up with their own time step). Worn hairs
-- carry the tag Config.Tag (players' soldiers and dev dummies alike).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.HairMotion)
local Rule = require(Shared.Rules.HairMotion)

local HairMotion = {}

local DEG = math.rad(1)

-- a moving bone: its rest turn in the head's axes (the angles are the head's, turned into the bone's own frame), and
-- its two springs (back, right: angle and speed)
type Joint = { bone: Bone, info: Rule.Bone, rest: CFrame, b: number, bv: number, r: number, rv: number }
type State = {
	hair: Instance, -- the worn Hair model these bones came from (gathered again when it changes)
	head: BasePart,
	root: BasePart?,
	humanoid: Humanoid?,
	joints: { Joint },
	chain: number, -- the back chain's length
	seed: number,
	last: number, -- when it last moved (its own time step)
	yaw: number, -- the head's last heading (for the turn rate)
}
local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any

local function heading(cf: CFrame): number
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- The character's hair bones, gathered again whenever its worn Hair changes (a respawn, the helmet shot off).
local function stateOf(character: Model, now: number): State?
	local hair = character:FindFirstChild("Hair")
	local head = character:FindFirstChild("Head") :: BasePart?
	if not hair or not head then
		states[character] = nil
		return nil
	end
	local s = states[character]
	if s and s.hair == hair then
		return s
	end
	local joints: { Joint } = {}
	local chain = 0
	local wanted = hair:GetAttribute("Bones") -- how many moving bones the rig has (src/server/Helmets)
	for _, b in hair:GetDescendants() do
		if b:IsA("Bone") then
			local info = Rule.bone(b.Name)
			if info then
				if info.kind == "back" then
					chain = math.max(chain, info.index)
				end
				local rest = (head.CFrame:ToObjectSpace(b.WorldCFrame)).Rotation
				table.insert(joints, { bone = b, info = info, rest = rest, b = 0, bv = 0, r = 0, rv = 0 })
			end
		end
	end
	-- the bones replicate after their model: until all of them are here, gather again next frame (as SpeciesMotion)
	if type(wanted) == "number" and #joints < wanted then
		states[character] = nil
		return nil
	end
	local fresh: State = {
		hair = hair,
		head = head,
		root = character:FindFirstChild("HumanoidRootPart") :: BasePart?,
		humanoid = character:FindFirstChildOfClass("Humanoid"),
		joints = joints,
		chain = chain,
		seed = math.random(),
		last = now,
		yaw = heading(head.CFrame),
	}
	states[character] = fresh
	return fresh
end

local function move(character: Model, s: State, now: number)
	local dt = math.min(now - s.last, 0.25)
	s.last = now
	if dt <= 0 or #s.joints == 0 then
		return
	end
	local head = s.head
	local cf = head.CFrame
	local body = s.root or head
	local v = cf:VectorToObjectSpace(body.AssemblyLinearVelocity)
	local yaw = heading(cf)
	local dyaw = (yaw - s.yaw + math.pi) % (2 * math.pi) - math.pi
	s.yaw = yaw
	local humanoid = s.humanoid
	local dead = humanoid == nil or humanoid.Health <= 0
	local m: Rule.Motion = {
		forward = -v.Z,
		sideways = v.X,
		up = v.Y,
		turn = dyaw / dt,
		speed = Vector3.new(v.X, 0, v.Z).Magnitude,
	}
	local scale = if character:GetAttribute("HelmetOn") == true then Cfg.HelmetOn else 1
	for _, j in s.joints do
		local tb, tr = Rule.target(j.info, s.chain, now, m, s.seed, scale, dead, Cfg)
		j.b, j.bv = Rule.spring(j.b, j.bv, tb, dt, Cfg.MaxDeg, Cfg.Spring)
		j.r, j.rv = Rule.spring(j.r, j.rv, tr, dt, Cfg.MaxDeg, Cfg.Spring)
		-- in the head's axes: tip back = a turn about -X, tip to the right = about +Z (the bone hangs down)
		j.bone.Transform = j.rest:Inverse() * CFrame.Angles(-j.b * DEG, 0, j.r * DEG) * j.rest
	end
end

local near: { Model } = {}
local worn: { [Instance]: true } = {} -- the tagged Hair models

local function byWait(a: Model, b: Model): boolean
	local sa, sb = states[a], states[b]
	return (sa and sa.last or 0) < (sb and sb.last or 0)
end

local function step()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	table.clear(near)
	for hair in worn do
		local parent = hair.Parent
		local character = if parent and parent:IsA("Model") then parent else nil
		local s = character and stateOf(character, now)
		if not character or not s then
			continue
		end
		local at = s.head.Position
		if (at - eye).Magnitude > Cfg.Range then
			s.last = now -- held still: no catching up on a long-stale step when it comes back into range
			continue
		end
		local _, onScreen = camera:WorldToViewportPoint(at)
		if not onScreen then
			s.last = now
			continue
		end
		table.insert(near, character)
	end
	local n = #near
	if n == 0 then
		return
	end
	if n > Cfg.PerFrame then
		-- the ones waiting longest first
		table.sort(near, byWait)
	end
	for k = 1, math.min(n, Cfg.PerFrame) do
		local character = near[k]
		local s = states[character]
		if s then
			move(character, s, now)
		end
	end
end

function HairMotion.start()
	for _, h in CollectionService:GetTagged(Cfg.Tag) do
		worn[h] = true
	end
	CollectionService:GetInstanceAddedSignal(Cfg.Tag):Connect(function(h)
		worn[h] = true
	end)
	CollectionService:GetInstanceRemovedSignal(Cfg.Tag):Connect(function(h)
		worn[h] = nil
	end)
	-- after the Animator has posed the body this frame, before it is drawn (as SpeciesMotion)
	RunService.PreSimulation:Connect(step)
end

return HairMotion
