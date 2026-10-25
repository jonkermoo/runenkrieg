--!strict
-- Procedural ear and tail motion (Config/Species.Motion; user 2026-10-18: "procedural motion"). Every client moves
-- every soldier's (and dev dummy's) species joints (src/server/Species: Motor6Ds named EarL / EarR on the Head; the tail's bones Tail1..)
-- itself, through each joint's Transform, so nothing replicates: ears only drift (user 2026-10-25: twitching, lying back
-- and flattening poked them out through the helmet holes); a tail sways, lifts as its soldier runs and swings
-- against sideways motion, and hangs limp once dead. Characters beyond Motion.Range from the camera hold still.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Species)
local DevTools = require(Shared.Config.DevTools)
local Rule = require(Shared.Rules.Species)

local SpeciesMotion = {}

local M = Cfg.Motion
local DEG = math.rad(1)

-- one ear's eased angles
type Ear = { motor: Motor6D, side: number, seed: number, x: number, y: number }
-- a tail bone: its rest turn in the Torso's axes (the angles are the Torso's, turned into the bone's own frame)
type Seg = { bone: Bone, rest: CFrame, x: number, y: number }
type State = {
	ears: { Ear },
	tail: { Seg },
	motion: number,
	torso: BasePart?,
	humanoid: Humanoid?,
	wornEars: Instance?, -- the Ears / Tail models these joints came from (gathered again when they change)
	wornTail: Instance?,
}
local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any

-- The character's joints, gathered again whenever its worn ears or tail change (a respawn or a re-dress).
local function stateOf(character: Model): State?
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
	-- the joints replicate after their models: until all of them are here, gather again next frame (Studio round 2:
	-- an early, empty gather was kept and that soldier never moved)
	local wantTail = kind and kind.tail and kind.tailBones or 0
	if (wornEars and #fresh.ears < 2) or (wornTail and #fresh.tail < wantTail) then
		states[character] = nil
		return nil
	end
	states[character] = fresh
	return fresh
end

local function step(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	local characters: { Instance } = CollectionService:GetTagged(DevTools.Dummies.Tag)
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	for _, c in characters do
		local character: Model? = if c:IsA("Model") then c else nil
		local s = character and stateOf(character)
		local torso = s and s.torso
		if not character or not s or not torso then
			continue
		end
		if (torso.Position - eye).Magnitude > M.Range then
			continue
		end
		local humanoid = s.humanoid
		local dead = humanoid == nil or humanoid.Health <= 0
		-- the body's own motion in the Torso's frame (forward = -Z)
		local v = torso.CFrame:VectorToObjectSpace(torso.AssemblyLinearVelocity)
		local forward, sideways = -v.Z, v.X
		local E = M.Ear
		for _, ear in s.ears do
			local x, y = Rule.earAngles(now, ear.side, ear.seed, s.motion, E)
			ear.x = Rule.ease(ear.x, x, E.follow, dt)
			ear.y = Rule.ease(ear.y, y, E.follow, dt)
			ear.motor.Transform = CFrame.Angles(ear.x * DEG, ear.y * DEG, 0)
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
