--!strict
-- The full ragdoll of the local R6 character (Config/Ragdoll; user 2026-10-13: "lose complete control (full ragdoll,
-- limbs go limp with realistic constraints)", knockback by cause). Ragdoll.knock(character, knock, direction, scale)
-- throws the body: every joint goes loose on a ball socket limited like a person's (its swing cone along the limb,
-- KNOWN_TRAPS), each limb gets a collider so it rests on the ground, whatever was held is put away, the
-- Humanoid goes to the Physics state (no walking, jumping or standing) and the character's "Ragdolled" attribute is
-- set: the camera rides the head and the stance and weapon code take no input (src/client/WeaponCamera, Stance,
-- StaffAttack, Firing). Once the body has settled it gets up after the knock's `getUp` seconds. The client owns its
-- character's physics, so the fall replicates; the loose limbs are local for now.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Ragdoll)

local Ragdoll = {}

-- each joint's rest direction in the torso's axes: the limbs hang down, the head stands up
local ALONG = {
	["Left Shoulder"] = Vector3.new(0, -1, 0),
	["Right Shoulder"] = Vector3.new(0, -1, 0),
	["Left Hip"] = Vector3.new(0, -1, 0),
	["Right Hip"] = Vector3.new(0, -1, 0),
	Neck = Vector3.new(0, 1, 0),
}
local LIMBS = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local down: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

function Ragdoll.active(character: Model): boolean
	return down[character] == true
end

-- Knocks the character down: `knock` a Config/Ragdoll.Knocks entry, `direction` the way it's thrown (flat; it also
-- tumbles that way), `scale` the caller's factor on the push (default 1).
function Ragdoll.knock(character: Model, knock: { [string]: number }, direction: Vector3, scale: number?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local torso = character:FindFirstChild("Torso") :: BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not torso or not root or down[character] or humanoid.Health <= 0 then
		return
	end
	down[character] = true
	character:SetAttribute("Ragdolled", true)
	local k = scale or 1
	local made: { Instance } = {}
	local loose: { Motor6D } = {}
	for name, j in Cfg.Joints do
		local m = torso:FindFirstChild(name) :: Motor6D?
		local p0, p1 = m and m.Part0, m and m.Part1
		if m and p0 and p1 then
			-- the cone is round the attachments' X axis: along the limb (KNOWN_TRAPS)
			local function frame(at: Vector3): CFrame
				return CFrame.fromMatrix(at, ALONG[name], Vector3.new(0, 0, -1))
			end
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.CFrame, a1.CFrame = frame(m.C0.Position), frame(m.C1.Position)
			a0.Parent, a1.Parent = p0, p1
			local b = Instance.new("BallSocketConstraint")
			b.Attachment0, b.Attachment1 = a0, a1
			b.LimitsEnabled = true
			b.UpperAngle = j.swing
			b.TwistLimitsEnabled = true
			b.TwistLowerAngle, b.TwistUpperAngle = -j.twist, j.twist
			b.Restitution = 0
			b.Parent = p0
			table.insert(made, a0)
			table.insert(made, a1)
			table.insert(made, b)
			m.Enabled = false
			table.insert(loose, m)
		end
	end
	-- R6 limbs don't collide: a collider inside each, kept off the torso so they don't fight it
	for _, name in LIMBS do
		local limb = character:FindFirstChild(name) :: BasePart?
		if limb then
			local c = Instance.new("Part")
			c.Name = "RagdollCollider"
			c.Size = limb.Size * Vector3.new(0.7, 0.85, 0.7)
			c.Transparency = 1
			c.CanCollide, c.CanQuery, c.CanTouch = true, false, false
			c.Massless = true
			c.CollisionGroup = limb.CollisionGroup
			c.CFrame = limb.CFrame
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = limb, c
			w.Parent = c
			local n = Instance.new("NoCollisionConstraint")
			n.Part0, n.Part1 = c, torso
			n.Parent = c
			c.Parent = limb
			table.insert(made, c)
		end
	end
	-- whatever was in the hands is put away (user 2026-10-13: "make ragdolling unequip whatever you had"): a slung
	-- weapon rides on the body again
	humanoid:UnequipTools()

	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else -root.CFrame.LookVector
	root.AssemblyLinearVelocity = (dir * knock.push + Vector3.yAxis * knock.lift) * k
	-- tumble the way it's thrown: about the horizontal axis across the push
	local up = Vector3.new(0, 1, 0)
	root.AssemblyAngularVelocity = up:Cross(dir) * knock.tumble * k

	local function getUp()
		for _, m in loose do
			m.Enabled = true
		end
		for _, i in made do
			i:Destroy()
		end
		down[character] = nil
		character:SetAttribute("Ragdolled", nil)
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
	-- down until the body settles, then up after the knock's getUp
	task.spawn(function()
		local t0 = os.clock()
		while character.Parent and os.clock() - t0 < Cfg.maxDown do
			task.wait()
			local settled = os.clock() - t0 >= Cfg.minDown and torso.AssemblyLinearVelocity.Magnitude < Cfg.still
			if settled then
				break
			end
		end
		task.wait(knock.getUp)
		getUp()
	end)
end

return Ragdoll
