--!strict
-- Spent cases and belt links thrown off a gun (Config/Cases; user 2026-10-29: "can you add shell case droppings and
-- sounds?"): a loose copy of the gun's own part, flung from where it leaves the gun, tumbling down on real gravity, a
-- clink for its kind where it first lands, gone after a while. Seen and heard by everyone, each client its own.
-- drop(template, at, push, sound) throws one; preload() loads the clinks.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Cases)
local SoundFx = require(script.Parent.SoundFx)

local CaseDrop = {}

local folder: Folder? = nil
local lastClink = 0

local function fx(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "CaseDrop"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

local function clink(kind: string?, at: Vector3)
	local s = kind and Cfg.Sounds[kind]
	local t = os.clock()
	if not s or t - lastClink < Cfg.gap then
		return
	end
	lastClink = t
	local e = s.variants[math.random(#s.variants)]
	SoundFx.play(e, at, nil, { pitch = s.pitch * (1 + (math.random() * 2 - 1) * s.spread) })
end

-- A copy of `template` thrown from `at` (its place and turn in the world) at `push` (studs/s, world), clinking as
-- `sound` (Config/Cases.Sounds) where it first lands; `skip`: what it doesn't land on (the gun it came off)
function CaseDrop.drop(template: BasePart, at: CFrame, push: Vector3, sound: string?, skip: Instance?)
	local copy = template:Clone()
	copy:ClearAllChildren()
	copy.Transparency, copy.LocalTransparencyModifier = 0, 0
	copy.Anchored, copy.CanCollide, copy.CanQuery, copy.CanTouch, copy.Massless = false, true, false, true, false
	copy.CollisionGroup = "Debris"
	copy.CFrame = at
	copy.Parent = fx()
	copy.AssemblyLinearVelocity = push
	copy.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		* 2
		* Cfg.spin
	local a = Instance.new("Attachment")
	a.Parent = copy
	local lift = Instance.new("VectorForce")
	lift.Attachment0 = a
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Force = Vector3.new(0, copy.AssemblyMass * (workspace.Gravity - Cfg.gravity), 0)
	lift.Parent = copy
	Debris:AddItem(lift, Cfg.flight)
	Debris:AddItem(copy, Cfg.life)
	local landed: RBXScriptConnection? = nil
	landed = copy.Touched:Connect(function(hit: BasePart)
		if hit:IsDescendantOf(fx()) or (skip and hit:IsDescendantOf(skip)) then
			return
		end
		(landed :: RBXScriptConnection):Disconnect()
		copy.CanTouch = false
		clink(sound, copy.Position)
	end)
end

function CaseDrop.preload()
	local all = {}
	for kind, s in Cfg.Sounds do
		all[kind] = s.variants
	end
	SoundFx.preload(all)
end

return CaseDrop
