--!strict
-- Plays the soldier's movement animations on the local character (replaces Roblox's default Animate script;
-- src/character/Animate calls attach). Tracks played here replicate to every other player.
-- Idle / walk / sprint picked by horizontal speed, played at the Config cycle length and scaled to the speed. No air
-- animations (user 2026-10-11): jumping or falling keeps the current cycle.
-- A weapon in the hands plays its hold over the cycle (Config/Weapons holds, Action priority): ready standing and
-- walking, carry while sprinting, aim while aiming down the sights. The hold is written to the character's "Hold"
-- attribute (local) for the look tilt and the camera. Other tools: the stock arm-out hold.
-- Numbers and ids: Config/Locomotion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion)
local W = require(Shared.Config.Weapons)
local Held = require(script.Parent.Held)

local Locomotion = {}

function Locomotion.attach(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator

	local tracks: { [string]: AnimationTrack } = {}
	for name, a in Cfg.Animations do
		local anim = Instance.new("Animation")
		anim.Name = name
		anim.AnimationId = "rbxassetid://" .. a.id
		tracks[name] = animator:LoadAnimation(anim)
	end
	tracks.idle.Priority = Enum.AnimationPriority.Idle
	tracks.toolnone.Priority = Enum.AnimationPriority.Action
	for _, t in tracks do
		t.Looped = true
	end

	local holds: { [string]: { [string]: AnimationTrack } } = {}

	-- the one base track playing (idle, walk, sprint or climb)
	local current: string? = nil
	local function play(name: string, fade: number)
		if current == name then
			return
		end
		if current then
			tracks[current]:Stop(fade)
		end
		tracks[name]:Play(fade)
		current = name
	end

	local function horizontalSpeed(): number
		local v = root.AssemblyLinearVelocity
		return Vector3.new(v.X, 0, v.Z).Magnitude
	end

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Dead then
			for _, t in tracks do
				t:Stop(0.1)
			end
			for _, set in holds do
				for _, t in set do
					t:Stop(0.1)
				end
			end
			current = nil
		end
	end)

	-- weapon holds, loaded per weapon on first equip
	local function holdTracks(name: string): { [string]: AnimationTrack }
		if not holds[name] then
			holds[name] = {}
			for hold, id in W[name].holds do
				local anim = Instance.new("Animation")
				anim.Name = hold
				anim.AnimationId = "rbxassetid://" .. id
				local t = animator:LoadAnimation(anim)
				t.Priority = Enum.AnimationPriority.Action
				t.Looped = true
				holds[name][hold] = t
			end
		end
		return holds[name]
	end
	-- the one upper-body track playing over the cycle (a weapon hold or the stock tool hold)
	local upper: AnimationTrack? = nil
	local function hold(track: AnimationTrack?)
		if upper == track then
			return
		end
		if upper then
			upper:Stop(Cfg.HoldFade)
		end
		if track then
			track:Play(Cfg.HoldFade)
		end
		upper = track
	end

	character.ChildAdded:Connect(function(child)
		-- join the gun to the torso at once (the server does too, a moment later), or it drops for a frame
		local weapon = child:IsA("Tool") and Held.weapon(character)
		local torso = character:FindFirstChild("Torso") :: BasePart?
		if weapon and torso then
			weapon.hold.Part0 = torso
		end
	end)

	local step = RunService.Heartbeat:Connect(function()
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Dead then
			return
		elseif state == Enum.HumanoidStateType.Climbing then
			play("climb", Cfg.Fade)
			local climb = Cfg.Animations.climb
			tracks.climb:AdjustSpeed(root.AssemblyLinearVelocity.Y / (climb.speed or 1))
		else -- on the ground or in the air: the cycle for the horizontal speed
			local speed = horizontalSpeed()
			local name = if speed < Cfg.IdleBelow then "idle" elseif speed > Cfg.SprintAbove then "sprint" else "walk"
			play(name, Cfg.Fade)
			local a = Cfg.Animations[name]
			if a.speed and a.keyed and a.cycle then
				local pace = math.clamp(speed / a.speed, Cfg.PlaybackMin, Cfg.PlaybackMax)
				tracks[name]:AdjustSpeed(pace * a.keyed / a.cycle)
			end
		end
		local weapon = Held.weapon(character)
		local holding = if not weapon
			then nil
			elseif character:GetAttribute("Aiming") then "aim"
			elseif current == "sprint" then "carry"
			else "ready"
		character:SetAttribute("Hold", holding)
		if weapon and holding then
			hold(holdTracks(weapon.name)[holding])
		else
			hold(if character:FindFirstChildOfClass("Tool") then tracks.toolnone else nil)
		end
	end)
	character.Destroying:Connect(function()
		step:Disconnect()
	end)
end

return Locomotion
