--!strict
-- The global sway layer (docs/HOLD_AND_CAMERA_RULES.md §3, numbers in Config/Sway). One motion state on the local
-- client, fed by its sources and read by the first-person viewmodel (src/client/Viewmodel) and the camera
-- (src/client/WeaponCamera). Local only: others see the third-person animations.
-- Sources: steps (the stride phase runs continuously at the pace of the walk / sprint / crouch cycle playing, and the
-- Footstep markers only nudge it toward the feet, so the gun and the view land with the feet without ever jumping:
-- a phase reset at each marker jerked the gun whenever the pace changed, e.g. into and out of a sprint), breath, look lag (the gun trails the view), strafe (the gun cants toward the side it
-- moves) and landing (a dip). Scaled by Master, the held item's class weight and, while aiming, the Aim shares.
-- Sway.viewmodel() is a small turn of the viewmodel about Config/Sway.Pivot (camera space); Sway.camera(view) a small
-- turn of the camera itself. Later sources (recoil, explosions, damage) add here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Sway)
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
local camera = { pitch = 0, roll = 0 }

function Sway.viewmodel(): CFrame
	return viewmodel
end

-- the camera's own turn for a view ("First", "Aim", "Shoulder")
function Sway.camera(view: string?): CFrame
	local share = view and Cfg.Camera.View[view] or 0
	return CFrame.Angles(math.rad(camera.pitch * share), 0, math.rad(camera.roll * share))
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

function Sway.start()
	local player = Players.LocalPlayer
	-- the stride: phase 0 = left foot down, 0.5 = right foot down; it advances at the playing cycle's rate (one
	-- cycle = one stride) and a marker leaves a correction that is worked off gradually
	local phase, rate, correction = 0, 1, 0
	local cycles: { AnimationTrack } = {}
	local stride = 0 -- 0..1, fades in when walking on the ground
	local breathT = 0
	local lastYaw: number?, lastPitch: number? = nil, nil
	local lagYaw, lagPitch, lagRoll = spring(), spring(), spring()
	local strafeRoll, strafeShift = spring(), spring()
	local landing = spring()
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
			if new == Enum.HumanoidStateType.Landed then
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
			viewmodel, camera.pitch, camera.roll = CFrame.identity, 0, 0
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
		stride += ((if grounded and speed > 0.75 then 1 else 0) - stride) * (1 - math.exp(-S.Fade * dt))
		-- the pace of the cycle playing most (walk, sprint or crouch walk)
		local best: AnimationTrack? = nil
		for _, t in cycles do
			if t.IsPlaying and t.Length > 0 and (not best or t.WeightCurrent > best.WeightCurrent) then
				best = t
			end
		end
		if best then
			rate = best.Speed / best.Length
		end
		local fix = correction * math.min(1, S.Settle * dt)
		correction -= fix
		phase = (phase + rate * dt + fix) % 1
		local g = math.clamp((speed - S.WalkSpeed) / (S.SprintSpeed - S.WalkSpeed), 0, 1)
		local size = stride * math.min(speed / S.WalkSpeed, 1)
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

		-- landing
		local Ld = Cfg.Landing
		pull(landing, 0, Ld.stiffness, Ld.damping, dt)
		lastVy = vel.Y

		local w = weight * m
		local turnPitch = (down * share("down") + bPitch * share("breath")) * w
			+ lagPitch.x * share("lag") * w
			+ landing.x * share("landing") * m
		local turnYaw = (side * share("side") + bYaw * share("breath") + lagYaw.x * share("lag")) * w
		local turnRoll = (sroll * share("roll") + lagRoll.x * share("lag")) * w + strafeRoll.x * share("strafe") * m
		local shift = Vector3.new(strafeShift.x * share("strafe"), landing.x * Ld.drop * share("landing"), 0) * m
		local pivot = Vector3.new(table.unpack(Cfg.Pivot))
		viewmodel = CFrame.new(pivot + shift)
			* CFrame.Angles(math.rad(turnPitch), math.rad(turnYaw), math.rad(turnRoll))
			* CFrame.new(-pivot)

		-- the camera's own small bob at the steps
		local C = Cfg.Camera
		local cw = if aiming
			then C.aim
			else { pitch = lerp(C.walk.pitch, C.sprint.pitch, g), roll = lerp(C.walk.roll, C.sprint.roll, g) }
		camera.pitch = -cw.pitch * math.cos(2 * TAU * phase) * size * m
		camera.roll = cw.roll * math.sin(TAU * phase) * size * m
	end)
end

return Sway
