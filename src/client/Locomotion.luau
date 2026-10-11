--!strict
-- Plays the soldier's movement animations on the local character (replaces Roblox's default Animate script;
-- src/character/Animate calls attach). Tracks played here replicate to every other player.
-- Idle / walk / sprint picked by horizontal speed, played at the Config cycle length and scaled to the speed. No air
-- animations (user 2026-10-11): jumping or falling keeps the current cycle. Tools: the stock arm-out hold.
-- Numbers and ids: Config/Locomotion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Locomotion)

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
			current = nil
		end
	end)

	local function onChild(child: Instance, added: boolean)
		if child:IsA("Tool") then
			if added then
				tracks.toolnone:Play(0.1)
			elseif not character:FindFirstChildOfClass("Tool") then
				tracks.toolnone:Stop(0.1)
			end
		end
	end
	character.ChildAdded:Connect(function(c)
		onChild(c, true)
	end)
	character.ChildRemoved:Connect(function(c)
		onChild(c, false)
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
	end)
	character.Destroying:Connect(function()
		step:Disconnect()
	end)
end

return Locomotion
