--!strict
-- The global sway layer (docs/HOLD_AND_CAMERA_RULES.md §3, numbers in Config/Sway). One motion state on the local
-- client, fed by its sources and read by the first-person viewmodel (src/client/Viewmodel) and the camera
-- (src/client/WeaponCamera). Local only: others see the third-person animations.
-- Sources: steps (the stride phase runs continuously at the pace of the walk / sprint / crouch cycle playing, and the
-- Footstep markers only nudge it toward the feet, so the gun and the view land with the feet without ever jumping:
-- a phase reset at each marker jerked the gun whenever the pace changed, e.g. into and out of a sprint), breath, look lag (the gun trails the view), strafe (the gun cants toward the side it
-- moves), jump (a kick at takeoff, the gun trailing the vertical speed in the air) and landing (a dip). Scaled by Master, the held item's class weight and, while aiming, the Aim shares.
-- Sway.viewmodel() is a small turn of the viewmodel about Config/Sway.Pivot (camera space); Sway.camera(view) a small
-- turn of the camera itself. Recoil (Sway.kick, src/client/Firing; Config/Firing.Recoil) kicks the gun up, aside and
-- back and the view up, on springs. Charging a staff spell (Sway.shake, Config/Sway.Charge) shakes the view and the
-- staff more and more. Later sources (explosions, damage) add here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Sway)
local Fire = require(Shared.Config.Firing)
local Loco = require(Shared.Config.Locomotion)
local W = require(Shared.Config.Weapons)
local Held = require(script.Parent.Held)

local Sway = {}

-- after the camera has turned with the mouse (src/client/WeaponCamera input), before it is placed
Sway.Priority = Enum.RenderPriority.Input.Value + 2

local WALK = "rbxassetid://" .. Loco.Animations.walk.id
local SPRINT = "rbxassetid://" .. Loco.Animations.sprint.id
local CROUCH = "rbxassetid://" .. Loco.Animations.crouchWalk.id
local TAU = 2 * math.pi

local viewmodel = CFrame.identity
local camera = { pitch = 0, yaw = 0, roll = 0 }
local shakeWant, shakeLevel = 0, 0

function Sway.viewmodel(): CFrame
	return viewmodel
end

-- the camera's own turn for a view ("First", "Aim")
function Sway.camera(view: string?): CFrame
	local share = view and Cfg.Camera.View[view] or 0
	return CFrame.Angles(math.rad(camera.pitch * share), math.rad(camera.yaw * share), math.rad(camera.roll * share))
end

-- The charge shake's level, 0..1 (src/client/StaffAttack sets it every frame while charging; 0 when not).
function Sway.shake(level: number)
	shakeWant = math.clamp(level, 0, 1)
end

type Spring = { x: number, v: number }

local function spring(): Spring
	return { x = 0, v = 0 }
end

-- a damped spring toward `target` (substeps keep it stable at low frame rates)
local function pull(s: Spring, target: number, stiffness: number, damping: number, dt: number)
	local n = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / n
	for _ = 1, n do
		s.v += (stiffness * (target - s.x) - damping * s.v) * h
		s.x += s.v * h
	end
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- recoil: an impulse on each spring (peaks near the Config amplitude), worked off by the render step
local recoil = { pitch = spring(), yaw = spring(), back = spring(), camera = spring() }
function Sway.kick(scale: number?)
	local R = Fire.Recoil
	local k = math.sqrt(R.stiffness) * (scale or 1)
	recoil.pitch.v += R.pitch * k
	recoil.yaw.v += (math.random() * 2 - 1) * R.yaw * k
	recoil.back.v += R.back * k
	recoil.camera.v += R.camera * k
end

function Sway.start()
	local player = Players.LocalPlayer
	-- the stride: phase 0 = left foot down, 0.5 = right foot down; it advances at the playing cycle's rate (one
	-- cycle = one stride) and a marker leaves a correction that is worked off gradually
	local phase, rate, correction, nudge = 0, 1, 0, 0
	local cycles: { AnimationTrack } = {}
	-- the speed the step sway follows: a Roblox character stops dead, so the sway eases out instead of following the
	-- speed (following it snapped the sights back to the centre the moment you stopped, user 2026-10-11)
	local pace = 0
	local paceS = spring()
	local breathT = 0
	local lastYaw: number?, lastPitch: number? = nil, nil
	local lagYaw, lagPitch, lagRoll = spring(), spring(), spring()
	local strafeRoll, strafeShift = spring(), spring()
	local landing = spring()
	local jump = spring()
	local lastVy = 0

	local function attach(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		local animator = humanoid and humanoid:WaitForChild("Animator", 10) :: Animator?
		if not humanoid or not animator then
			return
		end
		local hooked: { [AnimationTrack]: boolean } = setmetatable({}, { __mode = "k" }) :: any
		local function hook(track: AnimationTrack)
			local id = track.Animation and track.Animation.AnimationId
			if (id == WALK or id == SPRINT or id == CROUCH) and not hooked[track] then
				hooked[track] = true
				table.insert(cycles, track)
				track:GetMarkerReachedSignal("Footstep"):Connect(function(side)
					if track.WeightCurrent < 0.5 then
						return
					end
					local want = if side == "Left" then 0 else 0.5
					correction = (want - phase + 0.5) % 1 - 0.5 -- the shortest way round
				end)
			end
		end
		animator.AnimationPlayed:Connect(hook)
		for _, t in animator:GetPlayingAnimationTracks() do
			hook(t)
		end
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping then
				local J = Cfg.Jump
				jump.v -= J.kick * math.sqrt(J.stiffness) -- an impulse: the gun dips about `kick` degrees as the body leaves
			elseif new == Enum.HumanoidStateType.Landed then
				local L = Cfg.Landing
				local dip = math.min(math.abs(lastVy) * L.pitch, L.max)
				landing.v -= dip * math.sqrt(L.stiffness) -- an impulse: peaks near `dip` degrees
			end
		end)
	end
	player.CharacterAdded:Connect(attach)
	if player.Character then
		task.spawn(attach, player.Character)
	end

	RunService:BindToRenderStep("Sway", Sway.Priority, function(dt)
		dt = math.min(dt, 0.1)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local cam = workspace.CurrentCamera
		if not character or not humanoid or not root or humanoid.Health <= 0 then
			viewmodel, camera.pitch, camera.yaw, camera.roll = CFrame.identity, 0, 0, 0
			shakeLevel = 0
			return
		end
		local weapon = Held.weapon(character)
		local class = weapon and (W[weapon.name] :: any).class
		local weight = class and Cfg.Classes[class] or 1
		local aiming = character:GetAttribute("Aiming") == true
		local A = Cfg.Aim
		local function share(k: string): number
			return if aiming then (A :: any)[k] else 1
		end
		local m = Cfg.Master

		-- steps
		local vel = root.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local S = Cfg.Stride
		local want = if grounded and speed > 0.75 then speed else 0
		-- a critically damped spring toward the speed: its rise starts at zero slope, so the sway eases in (a plain
		-- exponential follow jumped to full rise speed on the first frame); 2.15 / omega is its 63% time, as 1 / rate is
		local omega = 2.15 * (if want > paceS.x then S.Fade else S.Return)
		pull(paceS, want, omega * omega, 2 * omega, dt)
		pace = math.max(paceS.x, 0)
		-- the pace of the cycle playing most (walk, sprint or crouch walk)
		local best: AnimationTrack? = nil
		for _, t in cycles do
			if t.IsPlaying and t.Length > 0 and (not best or t.WeightCurrent > best.WeightCurrent) then
				best = t
			end
		end
		if best then
			rate += (best.Speed / best.Length - rate) * (1 - math.exp(-S.RateEase * dt))
		end
		-- the catch-up runs as an extra rate, eased in and capped, so the stride's speed never jumps
		local cap = S.NudgeMax * math.abs(rate)
		local aim = math.clamp(correction * S.Settle, -cap, cap)
		nudge += (aim - nudge) * (1 - math.exp(-S.NudgeEase * dt))
		local fix = nudge * dt
		if fix * correction > 0 and math.abs(fix) > math.abs(correction) then
			fix = correction -- never past the feet
		end
		correction -= fix
		-- stopping, the stride slows to a halt as the sway settles: a little follow-through, no swing in place
		local going = math.clamp(pace / S.Halt, 0, 1)
		phase = (phase + rate * dt * going + fix) % 1
		local g = math.clamp((pace - S.WalkSpeed) / (S.SprintSpeed - S.WalkSpeed), 0, 1)
		local size = math.min(pace / S.WalkSpeed, 1)
		local side = lerp(S.walk.side, S.sprint.side, g) * math.sin(TAU * phase) * size
		local down = -lerp(S.walk.down, S.sprint.down, g) * math.cos(2 * TAU * phase) * size
		local sroll = lerp(S.walk.roll, S.sprint.roll, g) * math.sin(TAU * phase) * size

		-- breath
		local B = Cfg.Breath
		breathT += dt
		local bPitch = B.pitch * math.sin(TAU * breathT / B.period)
		local bYaw = B.yaw * math.sin(math.pi * breathT / B.period)

		-- look lag: the camera's turn rate this frame
		local look = cam.CFrame.LookVector
		local yaw = math.deg(math.atan2(-look.X, -look.Z))
		local pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
		local yawRate, pitchRate = 0, 0
		if lastYaw and lastPitch and dt > 0 then
			yawRate = ((yaw - lastYaw + 180) % 360 - 180) / dt
			pitchRate = (pitch - lastPitch) / dt
		end
		lastYaw, lastPitch = yaw, pitch
		local L = Cfg.LookLag
		pull(lagYaw, math.clamp(-L.gain * yawRate, -L.max, L.max), L.stiffness, L.damping, dt)
		pull(lagPitch, math.clamp(-L.gain * pitchRate, -L.max, L.max), L.stiffness, L.damping, dt)
		pull(lagRoll, math.clamp(L.roll * yawRate, -L.max, L.max), L.stiffness, L.damping, dt)

		-- strafe: sideways speed in the view's frame, as a share of walk speed
		local lateral = math.clamp(cam.CFrame:VectorToObjectSpace(vel).X / S.WalkSpeed, -1, 1)
		local St = Cfg.Strafe
		pull(strafeRoll, -St.roll * lateral, St.stiffness, St.damping, dt)
		pull(strafeShift, St.shift * lateral, St.stiffness, St.damping, dt)

		-- jump: in the air the gun trails the vertical speed (back to rest on the ground)
		local J = Cfg.Jump
		pull(jump, if grounded then 0 else math.clamp(-J.gain * vel.Y, -J.max, J.max), J.stiffness, J.damping, dt)

		-- landing
		local Ld = Cfg.Landing
		pull(landing, 0, Ld.stiffness, Ld.damping, dt)
		lastVy = vel.Y

		local R = Fire.Recoil
		for _, sp in recoil do
			pull(sp, 0, R.stiffness, R.damping, dt)
		end

		-- the charge shake: smooth noise per axis, its size following the charge level
		local Ch = Cfg.Charge
		shakeLevel += (shakeWant - shakeLevel) * (1 - math.exp(-Ch.ease * dt))
		local amp = shakeLevel ^ Ch.grow * m
		local nt = breathT * Ch.rate
		local function wander(seed: number): number
			return math.noise(nt, seed) * 2 -- math.noise stays within about +-0.5
		end
		local sx, sy, sz = wander(1.7) * amp, wander(5.3) * amp, wander(9.1) * amp

		local w = weight * m
		local turnPitch = (down * share("down") + bPitch * share("breath")) * w
			+ lagPitch.x * share("lag") * w
			+ landing.x * share("landing") * m
			+ jump.x * share("jump") * m
		turnPitch += recoil.pitch.x
		local turnYaw = (side * share("side") + bYaw * share("breath") + lagYaw.x * share("lag")) * w + recoil.yaw.x
		local turnRoll = (sroll * share("roll") + lagRoll.x * share("lag")) * w + strafeRoll.x * share("strafe") * m
		local lift = landing.x * Ld.drop * share("landing") + jump.x * J.drop * share("jump")
		local shift = Vector3.new(strafeShift.x * share("strafe"), lift, 0) * m + Vector3.new(0, 0, recoil.back.x)
		local pivot = Vector3.new(table.unpack(Cfg.Pivot))
		local V = Ch.viewmodel
		turnPitch += sx * V.pitch
		turnYaw += sy * V.yaw
		turnRoll += sz * V.roll
		viewmodel = CFrame.new(pivot + shift)
			* CFrame.Angles(math.rad(turnPitch), math.rad(turnYaw), math.rad(turnRoll))
			* CFrame.new(-pivot)

		-- the camera's own small bob at the steps
		local C = Cfg.Camera
		local cw = if aiming
			then C.aim
			else { pitch = lerp(C.walk.pitch, C.sprint.pitch, g), roll = lerp(C.walk.roll, C.sprint.roll, g) }
		local CC = Ch.camera
		camera.pitch = -cw.pitch * math.cos(2 * TAU * phase) * size * m + recoil.camera.x + sx * CC.pitch
		camera.yaw = sy * CC.yaw
		camera.roll = cw.roll * math.sin(TAU * phase) * size * m + sz * CC.roll
	end)
end

return Sway
