--!strict
-- Spent cases and belt links thrown off a gun (Config/Cases; user 2026-10-29: "can you add shell case droppings and
-- sounds?"): a copy of the gun's own part, flung from where it leaves the gun, tumbling down on real gravity, a clink
-- for its kind where it first lands, a bounce or two, a round case rolling on a little, then lying on what it landed
-- on until it goes. Seen and heard by everyone, each client its own. Flown here, not by Roblox physics: a part this
-- small fell straight through terrain and never touched it (user 2026-10-29: "casings just fall through terrains
-- though and i never hear the sound"), so each frame casts its path ahead and stops it on the first thing in the way.
-- drop(template, at, push, sound, skip) throws one; preload() loads the clinks.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Cases)
local SoundFx = require(script.Parent.SoundFx)

local CaseDrop = {}

type Piece = {
	part: BasePart,
	v: Vector3, -- studs/s
	w: Vector3, -- its tumble, rad/s
	sound: string?,
	params: RaycastParams,
	bounces: number,
	-- rolling on the ground once down (a round case): along `dir` at `speed` studs/s on the surface of normal `n`
	roll: { dir: Vector3, speed: number, n: Vector3 }?,
}

local folder: Folder? = nil
local lastClink = 0
local flying: { Piece } = {}
local stepping: RBXScriptConnection? = nil

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

-- laid down on the surface at `at` (normal `n`): its long side along the ground the way it was heading, its thinnest
-- half above it
local function lie(p: Piece, at: Vector3, n: Vector3)
	local part = p.part
	local along = part.CFrame.LookVector - n * part.CFrame.LookVector:Dot(n)
	if along.Magnitude < 1e-3 then
		along = part.CFrame.RightVector - n * part.CFrame.RightVector:Dot(n)
	end
	local size = part.Size
	local lift = math.min(size.X, size.Y) / 2
	part.CFrame = CFrame.lookAt(at + n * lift, at + n * lift + along.Unit, n)
		* CFrame.Angles(0, 0, math.random() * math.pi * 2)
end

-- one frame of a roll: on round its long side, slowing, kept on the ground; off an edge it flies again
local function roll(p: Piece, dt: number): boolean
	local part, r = p.part, p.roll :: { dir: Vector3, speed: number, n: Vector3 }
	local kind = p.sound and Cfg.Sounds[p.sound]
	r.speed -= (kind and kind.rollSlow or 0) * dt
	if r.speed <= 0 then
		return false
	end
	local radius = math.min(part.Size.X, part.Size.Y) / 2
	local dist = r.speed * dt
	local ahead = part.Position + r.dir * dist
	local ground = workspace:Raycast(ahead + r.n * Cfg.rollReach, -r.n * (Cfg.rollReach + radius * 2), p.params)
	if not ground then
		p.roll, p.v, p.bounces = nil, r.dir * r.speed, Cfg.bounces
		return true
	end
	local turn = CFrame.fromAxisAngle(r.n:Cross(r.dir).Unit, dist / radius)
	part.CFrame = CFrame.new(ground.Position + ground.Normal * radius) * turn * part.CFrame.Rotation
	r.n = ground.Normal
	return true
end

-- one frame of flight: true while it still flies (or rolls)
local function fly(p: Piece, dt: number): boolean
	local part = p.part
	if not part.Parent then
		return false
	end
	if p.roll then
		return roll(p, dt)
	end
	local from = part.Position
	p.v -= Vector3.new(0, Cfg.gravity * dt, 0)
	local step = p.v * dt
	local hit = workspace:Raycast(from, step, p.params)
	if not hit then
		part.CFrame = CFrame.new(from + step) * CFrame.Angles(p.w.X * dt, p.w.Y * dt, p.w.Z * dt) * part.CFrame.Rotation
		return true
	end
	if hit.Material == Enum.Material.Water then
		part:Destroy() -- (sunk without a sound)
		return false
	end
	local n = hit.Normal
	if p.bounces == 0 then
		clink(p.sound, hit.Position)
	end
	p.bounces += 1
	local v = (p.v - n * 2 * p.v:Dot(n)) * Cfg.bounce
	if p.bounces > Cfg.bounces or v.Magnitude < Cfg.settle then
		lie(p, hit.Position, n)
		local kind = p.sound and Cfg.Sounds[p.sound]
		if kind and kind.roll then
			-- across its long side, the way it was going (either way if straight down)
			local dir = n:Cross(part.CFrame.LookVector)
			if dir.Magnitude < 1e-3 then
				return false
			end
			dir = dir.Unit * (if p.v:Dot(dir) < 0 then -1 else 1)
			p.roll = { dir = dir, speed = kind.roll * (Cfg.rollLeast + (1 - Cfg.rollLeast) * math.random()), n = n }
			return true
		end
		return false
	end
	p.v, p.w = v, p.w * Cfg.bounce
	part.CFrame = CFrame.new(hit.Position + n * 0.05) * part.CFrame.Rotation
	return true
end

local function step(dt: number)
	local i = 1
	while i <= #flying do
		if fly(flying[i], dt) then
			i += 1
		else
			flying[i] = flying[#flying]
			flying[#flying] = nil
		end
	end
	if #flying == 0 and stepping then
		stepping:Disconnect()
		stepping = nil
	end
end

-- A copy of `template` thrown from `at` (its place and turn in the world) at `push` (studs/s, world), clinking as
-- `sound` (Config/Cases.Sounds) where it first lands; `skip`: what it passes through (the gun it came off)
function CaseDrop.drop(template: BasePart, at: CFrame, push: Vector3, sound: string?, skip: Instance?)
	local copy = template:Clone()
	copy:ClearAllChildren()
	copy.Transparency, copy.LocalTransparencyModifier = 0, 0
	copy.Anchored, copy.CanCollide, copy.CanQuery, copy.CanTouch = true, false, false, false
	copy.CFrame = at
	copy.Parent = fx()
	local kind = sound and Cfg.Sounds[sound]
	Debris:AddItem(copy, kind and kind.life or Cfg.life)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if skip then { fx(), skip } else { fx() }
	params.CollisionGroup = "Debris" -- (through characters, as other debris)
	params.RespectCanCollide = true
	params.IgnoreWater = false
	table.insert(flying, {
		part = copy,
		v = push,
		w = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * Cfg.spin,
		sound = sound,
		params = params,
		bounces = 0,
	})
	if not stepping then
		stepping = RunService.Heartbeat:Connect(step)
	end
end

function CaseDrop.preload()
	local all = {}
	for kind, s in Cfg.Sounds do
		all[kind] = s.variants
	end
	SoundFx.preload(all)
end

return CaseDrop
