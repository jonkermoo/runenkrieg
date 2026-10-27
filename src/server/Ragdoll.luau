--!strict
-- Knocks on the server (M12; Config/Ragdoll; user 2026-10-17: every knock looks the same for everyone). A ragdoll
-- knock loosens the joints here, so every player sees the limbs go limp: each R6 joint on a ball socket limited like a
-- person's (its swing cone along the limb, KNOWN_TRAPS), a collider in each limb, the weapon put away, the
-- character's "Ragdolled" attribute set. Net "Knock" goes to every client: the body's owner (its own client: it owns
-- the physics) throws it and holds the Physics state (src/client/Ragdoll). Once the body has settled it gets up after
-- the knock's `getUp` seconds, unless it is dead: a dead body stays limp, head on, until it is removed at respawn.
-- A dead body's physics belongs to the server (Studio round 3: a headshot kill stood upright, its owner's push ignored),
-- so whenever the server owns the body it throws it, and tips it over if it still stands, itself.
-- A body being dragged (src/server/Dragging, the "Dragged" attribute) doesn't get up until it is let go, or until it
-- breaks free (Ragdoll.served: only once its knock's own stand-up time is over; the drag doesn't stop that clock).
-- Players knock themselves through Net "KnockSelf" (Config/Ragdoll.SelfKnocks: the staff's recoil, the float fall).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Ragdoll)
local Net = require(Shared.Net)
local RagdollRules = require(Shared.Rules.Ragdoll)
local StaffNet = require(Shared.Rules.StaffNet)

local Ragdoll = {}

-- fired on the server with (character, knock, direction, scale) on every knock: src/server/DevDummies throws its target
-- dummies with it (they have no client of their own)
Ragdoll.knocked = Instance.new("BindableEvent")

-- each joint's rest direction in the torso's axes: the limbs hang down, the head stands up
local ALONG = {
	["Left Shoulder"] = Vector3.new(0, -1, 0),
	["Right Shoulder"] = Vector3.new(0, -1, 0),
	["Left Hip"] = Vector3.new(0, -1, 0),
	["Right Hip"] = Vector3.new(0, -1, 0),
	Neck = Vector3.new(0, 1, 0),
}
local LIMBS = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

-- a body that is down: what was made for it, the joints loosened, and the knock's latest start (a new knock while
-- down restarts the settle wait)
type Down = {
	made: { Instance },
	loose: { Motor6D },
	since: number,
	getUp: number,
	knockAt: number, -- the latest knock, and when the body settled after it (nil: not yet): the knock's own stand-up
	settledAt: number?, -- clock, which a drag doesn't stop (Ragdoll.served)
	root: BasePart?, -- the HumanoidRootPart and whether it collided before
	rootCollides: boolean,
}
local down: { [Model]: Down } = setmetatable({}, { __mode = "k" }) :: any

-- (the "Ragdolled" attribute too: a copy of this module required elsewhere, e.g. from Studio's command bar, sees it)
function Ragdoll.active(character: Model): boolean
	return down[character] ~= nil or character:GetAttribute("Ragdolled") == true
end

local function loosen(character: Model, torso: BasePart): Down
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
			a0.Name, a1.Name = "RagdollJoint", "RagdollJoint"
			a0.CFrame, a1.CFrame = frame(m.C0.Position), frame(m.C1.Position)
			a0.Parent, a1.Parent = p0, p1
			local b = Instance.new("BallSocketConstraint")
			b.Name = "RagdollJoint"
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
			c.Size = limb.Size * Vector3.new(Cfg.Collider[1], Cfg.Collider[2], Cfg.Collider[3])
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
	-- the invisible root box doesn't touch the ground while down (2-player test: it held a dead torso upright on its
	-- folded legs)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rootCollides = root ~= nil and root.CanCollide
	if root then
		root.CanCollide = false
	end
	local now = os.clock()
	return {
		made = made,
		loose = loose,
		since = now,
		getUp = 0,
		knockAt = now,
		root = root,
		rootCollides = rootCollides,
	}
end

-- the server's own throw of a body it owns (a dead one): as src/client/Ragdoll does for its own soldier. The death
-- that follows the knock (src/server/Damage) hands the body to the server some time later, so for Config/Ragdoll.Tip
-- `window` seconds it watches: once it owns the body and the death has settled (`settle` s after it; a throw at the
-- moment of death was lost, Studio round 8: bodies fell out of their own backs) it throws it, holding the throw for
-- `hold` s, and every `every` s after `after` it tips a body still standing (user 2026-10-17: "headshots dont ragdoll
-- with enough force to fall on the ground sometimes").
local function serverThrow(character: Model, knock: { [string]: number }, direction: Vector3, scale: number)
	-- the newest knock's throw wins: an older one still watching stops (Studio round 9: two throws fought)
	local seq = ((character:GetAttribute("KnockSeq") :: number?) or 0) + 1
	character:SetAttribute("KnockSeq", seq)
	task.defer(function()
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local torso = character:FindFirstChild("Torso") :: BasePart?
		if not root or not torso then
			return
		end
		local flat = Vector3.new(direction.X, 0, direction.Z)
		local dir = if flat.Magnitude > 1e-3 then flat.Unit else -root.CFrame.LookVector
		local axis = Vector3.new(0, 1, 0):Cross(dir)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local T = Cfg.Tip
		local t0 = os.clock()
		local diedAt: number? = nil
		local thrownAt: number? = nil
		local tipAt = t0 + T.after
		while
			root:IsDescendantOf(workspace)
			and os.clock() - t0 < T.window
			and character:GetAttribute("KnockSeq") == seq
		do
			local now = os.clock()
			if not diedAt and (not humanoid or humanoid.Health <= 0) then
				diedAt = now
			end
			if root:GetNetworkOwner() == nil then
				local settled = diedAt ~= nil and now - diedAt >= T.settle
				if (not thrownAt and settled) or (thrownAt and now - thrownAt < T.hold) then
					thrownAt = thrownAt or now
					local up = knock.lift - (knock.drop or 0)
					root.AssemblyLinearVelocity = (dir * knock.push + Vector3.new(0, 1, 0) * up) * scale
					root.AssemblyAngularVelocity = axis * knock.tumble * scale
					tipAt = math.max(tipAt, now + T.every)
				elseif thrownAt and now >= tipAt then
					tipAt = now + T.every
					if torso.CFrame.UpVector.Y > T.upright then
						torso.AssemblyAngularVelocity += axis * T.spin
						torso.AssemblyLinearVelocity += dir * T.push
					end
				end
			end
			task.wait()
		end
	end)
end

-- the joints back and what was made for the knock gone: the body gets up (src/client/Ragdoll for a player's own)
local function stand(character: Model, made: Down)
	for _, m in made.loose do
		m.Enabled = true
	end
	if made.root then
		made.root.CanCollide = made.rootCollides
	end
	for _, i in made.made do
		i:Destroy()
	end
	down[character] = nil
	character:SetAttribute("Ragdolled", nil)
end

-- Knocks `character` with the Config/Ragdoll.Knocks entry `name`, thrown along `direction` (flat; it also tumbles that
-- way), `scale` the caller's factor on the push (default 1), `damage` the health the hit took (a live soldier stays down
-- longer the more it took, Config/Ragdoll.ByDamage; nil: none).
function Ragdoll.knock(character: Model, name: string, direction: Vector3, scale: number?, damage: number?)
	local knock = Cfg.Knocks[name] :: any
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if not knock or not humanoid or not torso or not character.Parent then
		return
	end
	local k = scale or 1
	local getUp = RagdollRules.getUp(knock.getUp, damage, Cfg.ByDamage)
	local d = down[character]
	if d then
		-- already down: thrown again, and the settle wait starts over (the longer of the two get-up waits)
		d.since, d.getUp = os.clock(), math.max(d.getUp, getUp)
		d.knockAt, d.settledAt = d.since, nil
		Net.event("Knock"):FireAllClients(character, name, direction, k)
		Ragdoll.knocked:Fire(character, name, direction, k)
		serverThrow(character, knock, direction, k)
		return
	end
	local made = loosen(character, torso)
	made.getUp = getUp
	down[character] = made
	character:SetAttribute("Ragdolled", true)
	-- whatever was in the hands is put away (user 2026-10-13: "make ragdolling unequip whatever you had"): a slung
	-- weapon rides on the body again
	humanoid:UnequipTools()
	Net.event("Knock"):FireAllClients(character, name, direction, k)
	Ragdoll.knocked:Fire(character, name, direction, k)
	serverThrow(character, knock, direction, k)

	-- down until the body settles, then up after the knock's getUp; a dead body stays down
	task.spawn(function()
		while character.Parent do
			task.wait()
			if down[character] ~= made then
				return -- up already: broke free of a drag (Ragdoll.rise)
			end
			local now = os.clock()
			local dragged = character:GetAttribute("Dragged") == true
			local speed = torso.AssemblyLinearVelocity.Magnitude
			if not made.settledAt and RagdollRules.settled(now - made.knockAt, speed, dragged, Cfg) then
				made.settledAt = now
			end
			if dragged then
				made.since = now -- dragged (src/server/Dragging): not up until let go, then the wait starts over
			end
			if RagdollRules.settled(now - made.since, speed, false, Cfg) then
				local since = made.since
				task.wait(made.getUp)
				if down[character] ~= made then
					return
				end
				if made.since == since and character:GetAttribute("Dragged") ~= true then
					break -- (knocked again meanwhile: the wait starts over)
				end
			end
		end
		if not character.Parent or humanoid.Health <= 0 then
			return -- dead: limp for good
		end
		stand(character, made)
	end)
end

-- Whether a knocked-down `character` has been down its knock's own stand-up time (settled, then its get-up wait),
-- counting the time it was dragged: then it may break free of a drag (src/server/Dragging).
function Ragdoll.served(character: Model): boolean
	local d = down[character]
	return d ~= nil and RagdollRules.served(d.settledAt, d.getUp, os.clock())
end

-- Stands a living `character` that has served its time (Ragdoll.served) up now: it broke free of a drag (let go first).
function Ragdoll.rise(character: Model)
	local d = down[character]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if d and humanoid and humanoid.Health > 0 and Ragdoll.served(character) then
		stand(character, d)
	end
end

function Ragdoll.start()
	-- the player's own knocks (the staff's recoil, the float fall), rate limited
	local buckets: { [Player]: StaffNet.Bucket } = {}
	Net.event("KnockSelf").OnServerEvent:Connect(function(player, name, direction)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then
			return
		end
		if type(name) ~= "string" or not Cfg.SelfKnocks[name] or typeof(direction) ~= "Vector3" then
			return
		end
		local v = direction :: Vector3
		if not (StaffNet.finite(v.X) and StaffNet.finite(v.Y) and StaffNet.finite(v.Z)) then
			return
		end
		local now = os.clock()
		local b = buckets[player]
		if not b then
			b = { tokens = Cfg.SelfRate, at = now }
			buckets[player] = b
		end
		if not StaffNet.take(b, now, Cfg.SelfRate) then
			return
		end
		Ragdoll.knock(character, name, if v.Magnitude > 1e-3 then v.Unit else Vector3.zero)
	end)
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return Ragdoll
