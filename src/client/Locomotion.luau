--!strict
-- Plays the soldier's movement animations on the local character (replaces Roblox's default Animate script;
-- src/character/Animate calls attach). Tracks played here replicate to every other player.
-- Ground: idle / walk / sprint picked by horizontal speed, played at the Config cycle length and scaled to the speed.
-- Air: jump on take-off, fall loop while airborne, a landing after a real drop. Tools: the stock arm-out hold.
-- Numbers and ids: Config/Locomotion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Locomotion)

local Locomotion = {}

local GROUND = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Landed] = true,
}

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
	for _, name in { "idle", "walk", "sprint", "fall", "climb", "toolnone" } do
		tracks[name].Looped = true
	end
	tracks.jump.Looped = false
	tracks.land.Looped = false

	-- the one base track playing (ground cycle, jump, fall or climb)
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

	local airSince: number? = nil
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			airSince = os.clock()
			play("jump", Cfg.AirFade)
		elseif new == Enum.HumanoidStateType.Freefall then
			airSince = airSince or os.clock()
			if current ~= "jump" then
				play("fall", Cfg.AirFade)
			end
		elseif new == Enum.HumanoidStateType.Landed then
			if airSince and os.clock() - airSince >= Cfg.LandMinAir then
				tracks.land:Play(0.05)
				tracks.land:AdjustWeight(if horizontalSpeed() > Cfg.IdleBelow then Cfg.LandWeightMoving else 1, 0)
			end
			airSince = nil
		elseif new == Enum.HumanoidStateType.Climbing then
			play("climb", Cfg.Fade)
		elseif new == Enum.HumanoidStateType.Dead then
			for _, t in tracks do
				t:Stop(0.1)
			end
			current = nil
		end
	end)
	tracks.jump.Stopped:Connect(function()
		if current == "jump" then
			current = nil
			if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
				play("fall", Cfg.AirFade)
			end
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
		if GROUND[state] then
			local speed = horizontalSpeed()
			local name = if speed < Cfg.IdleBelow then "idle" elseif speed > Cfg.SprintAbove then "sprint" else "walk"
			play(name, Cfg.Fade)
			local a = Cfg.Animations[name]
			if a.speed and a.keyed and a.cycle then
				local pace = math.clamp(speed / a.speed, Cfg.PlaybackMin, Cfg.PlaybackMax)
				tracks[name]:AdjustSpeed(pace * a.keyed / a.cycle)
			end
		elseif state == Enum.HumanoidStateType.Climbing then
			local climb = Cfg.Animations.climb
			tracks.climb:AdjustSpeed(root.AssemblyLinearVelocity.Y / (climb.speed or 1))
		end
	end)
	character.Destroying:Connect(function()
		step:Disconnect()
	end)
end

return Locomotion
