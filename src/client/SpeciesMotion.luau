--!strict
-- Procedural ear and tail motion (Config/Species.Motion; user 2026-10-18: "procedural motion"). Every client moves
-- every soldier's species joints (src/server/Species: Motor6Ds named EarL / EarR on the Head; the tail's bones Tail1..)
-- itself, through each joint's Transform, so nothing replicates: ears drift and now and then one twitches, lie back
-- while sprinting and flatten when hit (flat for good once dead); a tail sways, lifts as its soldier runs and swings
-- against sideways motion, and hangs limp once dead. Characters beyond Motion.Range from the camera hold still.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Species)
local Rule = require(Shared.Rules.Species)

local SpeciesMotion = {}

local M = Cfg.Motion
local DEG = math.rad(1)

-- one ear's eased angles and twitch timing
type Ear = { motor: Motor6D, side: number, seed: number, x: number, y: number, z: number, twitchAt: number }
-- a tail bone: its rest turn in the Torso's axes (the angles are the Torso's, turned into the bone's own frame)
type Seg = { bone: Bone, rest: CFrame, x: number, y: number }
type State = {
	ears: { Ear },
	tail: { Seg },
	motion: number,
	hurtAt: number,
	health: number,
	torso: BasePart?,
	humanoid: Humanoid?,
	wornEars: Instance?, -- the Ears / Tail models these joints came from (gathered again when they change)
	wornTail: Instance?,
}
local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any

local function nextTwitch(now: number): number
	local g = M.Ear.twitchGap
	return now + g[1] + math.random() * (g[2] - g[1])
end

-- The character's joints, gathered again whenever its worn ears or tail change (a respawn or a re-dress).
local function stateOf(character: Model, now: number): State?
	local wornEars = character:FindFirstChild("Ears")
	local wornTail = character:FindFirstChild("Tail")
	if not wornEars and not wornTail then
		states[character] = nil
		return nil
	end
	local s = states[character]
	if s and s.wornEars == wornEars and s.wornTail == wornTail then
		return s
	end
	local kind = Cfg.Kinds[character:GetAttribute("Species") :: any]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local fresh: State = {
		ears = {},
		tail = {},
		motion = kind and kind.earMotion or 1,
		hurtAt = -math.huge,
		health = humanoid and humanoid.Health or 0,
		torso = character:FindFirstChild("Torso") :: BasePart?,
		humanoid = humanoid,
		wornEars = wornEars,
		wornTail = wornTail,
	}
	if wornEars then
		for _, m in wornEars:GetDescendants() do
			if m:IsA("Motor6D") and (m.Name == "EarL" or m.Name == "EarR") then
				table.insert(fresh.ears, {
					motor = m,
					side = if m.Name == "EarR" then 1 else -1,
					seed = math.random(),
					x = 0,
					y = 0,
					z = 0,
					twitchAt = nextTwitch(now),
				})
			end
		end
	end
	if wornTail then
		local byNumber: { [number]: Bone } = {}
		for _, b in wornTail:GetDescendants() do
			if b:IsA("Bone") then
				local n = Rule.segment(Rule.base(b.Name))
				if n then
					byNumber[n] = b
				end
			end
		end
		local torso = fresh.torso
		for n = 1, #byNumber do
			local bone = byNumber[n]
			local rest = if torso then (torso.CFrame:ToObjectSpace(bone.WorldCFrame)).Rotation else CFrame.identity
			table.insert(fresh.tail, { bone = bone, rest = rest, x = 0, y = 0 })
		end
	end
	states[character] = fresh
	return fresh
end

local function step(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local s = character and stateOf(character, now)
		local torso = s and s.torso
		if not character or not s or not torso then
			continue
		end
		if (torso.Position - eye).Magnitude > M.Range then
			continue
		end
		local humanoid = s.humanoid
		local health = humanoid and humanoid.Health or 0
		local dead = humanoid == nil or health <= 0
		if health < s.health then
			s.hurtAt = now
		end
		s.health = health
		-- the body's own motion in the Torso's frame (forward = -Z)
		local v = torso.CFrame:VectorToObjectSpace(torso.AssemblyLinearVelocity)
		local flatVel = Vector3.new(v.X, 0, v.Z)
		local forward, sideways = -v.Z, v.X
		local E = M.Ear
		local back = if not dead and flatVel.Magnitude > E.sprintSpeed then 1 else 0
		local flat = if dead then 1 else Rule.hurt(now - s.hurtAt, E.hurtTime)
		for _, ear in s.ears do
			if now > ear.twitchAt + E.twitchTime then
				ear.twitchAt = nextTwitch(now)
			end
			local twitch = if dead then 0 else Rule.twitch(now - ear.twitchAt, E.twitchTime)
			local x, y, z = Rule.earAngles(now, ear.side, ear.seed, s.motion, twitch, back, flat, E)
			-- a twitch snaps; everything else eases
			local rate = if twitch > 0 then E.twitchFollow else E.follow
			ear.x = Rule.ease(ear.x, x, rate, dt)
			ear.y = Rule.ease(ear.y, y, rate, dt)
			ear.z = Rule.ease(ear.z, z, rate, dt)
			ear.motor.Transform = CFrame.Angles(ear.x * DEG, ear.y * DEG, ear.z * DEG)
		end
		local T = M.Tail
		local n = #s.tail
		for i, seg in s.tail do
			local x, y = Rule.tailAngles(i, n, now, forward, sideways, if dead then 1 else 0, T)
			seg.x = Rule.ease(seg.x, x, T.follow, dt)
			seg.y = Rule.ease(seg.y, y, T.follow, dt)
			seg.bone.Transform = seg.rest:Inverse() * CFrame.Angles(seg.x * DEG, seg.y * DEG, 0) * seg.rest
		end
	end
end

function SpeciesMotion.start()
	-- after the Animator has posed the body this frame, before it is drawn
	RunService.PreSimulation:Connect(step)
end

return SpeciesMotion
