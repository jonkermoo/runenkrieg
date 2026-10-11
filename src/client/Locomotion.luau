--!strict
-- Plays the soldier's movement animations on the local character (replaces Roblox's default Animate script;
-- src/character/Animate calls attach). Tracks played here replicate to every other player.
-- Idle / walk / sprint picked by horizontal speed, played at the Config cycle length and scaled to the speed. No air
-- animations (user 2026-10-11): jumping or falling keeps the current cycle.
-- A weapon in the hands plays its hold over the cycle (Config/Weapons holds, Action priority): ready standing, walk
-- walking and carry sprinting (both kept in step with the legs), aim while aiming down the sights; drawing it plays
-- the equip once on top. The hold is written to the character's "Hold"
-- attribute (local) for the look tilt and the camera. Other tools: the stock arm-out hold.
-- Numbers and ids: Config/Locomotion.

local Players = game:GetService("Players")
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
				-- the equip is a one shot over the hold that will follow it
				t.Priority = if hold == "equip" then Enum.AnimationPriority.Action2 else Enum.AnimationPriority.Action
				t.Looped = hold ~= "equip"
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

	-- load a weapon's holds as soon as it is carried, so drawing it (the equip) plays from its first frame
	local backpack = (Players.LocalPlayer :: Player):FindFirstChildOfClass("Backpack")
	local function carried(child: Instance)
		local name = child:IsA("Tool") and child:GetAttribute("Weapon")
		if type(name) == "string" and W[name] then
			holdTracks(name)
		end
	end
	if backpack then
		backpack.ChildAdded:Connect(carried)
		for _, c in backpack:GetChildren() do
			carried(c)
		end
	end

	character.ChildAdded:Connect(function(child)
		-- join the gun to the torso at once (the server does too, a moment later), or it drops for a frame
		local weapon = child:IsA("Tool") and Held.weapon(character)
		local torso = character:FindFirstChild("Torso") :: BasePart?
		if weapon and torso then
			weapon.hold.Part0 = torso
			-- drawn from the sling: the equip plays once over the hold; the viewmodel starts its own from this moment
			character:SetAttribute("EquippedAt", os.clock())
			holdTracks(weapon.name).equip:Play(0.05)
		end
	end)

	-- the moving holds keep step with the cycle they ride on (same keyed length, so the same phase)
	local CYCLE = { walk = "walk", carry = "sprint" }
	local function keepStep(state: string, track: AnimationTrack)
		local base = tracks[CYCLE[state]]
		if not base or not base.IsPlaying or base.Length <= 0 or track.Length <= 0 then
			return
		end
		local want = base.TimePosition / base.Length * track.Length
		local off = math.abs(track.TimePosition - want)
		if math.min(off, track.Length - off) > 0.03 then
			track.TimePosition = want
		end
		track:AdjustSpeed(base.Speed)
	end

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
			-- standing still: the ready hold; walking: the walking hold (sprinting: carry already swings)
			local set = holdTracks(weapon.name)
			local pick = if holding == "ready" and current == "walk" then "walk" else holding
			hold(set[pick])
			if CYCLE[pick] then
				keepStep(pick, set[pick])
			end
		else
			hold(if character:FindFirstChildOfClass("Tool") then tracks.toolnone else nil)
		end
	end)
	character.Destroying:Connect(function()
		step:Disconnect()
	end)
end

return Locomotion
