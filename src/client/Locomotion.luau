--!strict
-- Plays the soldier's movement animations on the local character (replaces Roblox's default Animate script;
-- src/character/Animate calls attach). Tracks played here replicate to every other player.
-- Idle / walk / sprint picked by horizontal speed (crouch idle / crouch walk while the "Crouching" attribute is set),
-- played at the Config cycle length and scaled to the speed. In the air (user 2026-10-18): the take-off after a jump,
-- then the tuck until landing; the landing plays once over the ground cycle (Config/Locomotion.Air). Crouched, a
-- weapon plays its crouch holds (crouchReady / crouchWalk / crouchAim).
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
local MovementSet = require(Shared.Rules.MovementSet)
local Anims = MovementSet.animations(Cfg) -- the movement set in play (Config/Locomotion.Set)
local W = require(Shared.Config.Weapons)
local ShovelCfg = require(Shared.Config.Shovel)
local Spells = require(Shared.Config.Spells)
local SpellRules = require(Shared.Rules.Spells)
local Held = require(script.Parent.Held)
local Net = require(Shared.Net)
local SoundFx = require(script.Parent.SoundFx)

local Locomotion = {}

function Locomotion.attach(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator

	local tracks: { [string]: AnimationTrack } = {}
	for name, a in Anims do
		local anim = Instance.new("Animation")
		anim.Name = name
		anim.AnimationId = "rbxassetid://" .. a.id
		tracks[name] = animator:LoadAnimation(anim)
	end
	tracks.idle.Priority = Enum.AnimationPriority.Idle
	tracks.toolnone.Priority = Enum.AnimationPriority.Action
	for name, t in tracks do
		t.Looped = name ~= "jump" and name ~= "land" -- the take-off and the landing play once
	end
	local Air = Cfg.Air

	local holds: { [string]: { [string]: AnimationTrack } } = {}

	-- the one base track playing (idle, walk, sprint or climb)
	local current: string? = nil
	-- the stepping cycles: switching between them carries the stride across (every one starts on the left foot's
	-- contact), so the legs blend between matching poses instead of jumping to the start of a new stride
	local STEPPING = { walk = true, sprint = true, crouchWalk = true }
	local function play(name: string, fade: number)
		if current == name then
			return
		end
		local from = current and tracks[current]
		local phase = if from
				and STEPPING[current]
				and STEPPING[name]
				and from.Length > 0
			then from.TimePosition / from.Length
			else nil
		if from then
			from:Stop(fade)
		end
		local track = tracks[name]
		track:Play(fade)
		if phase and track.Length > 0 then
			track.TimePosition = phase * track.Length
		end
		current = name
	end

	local function horizontalSpeed(): number
		local v = root.AssemblyLinearVelocity
		return Vector3.new(v.X, 0, v.Z).Magnitude
	end

	-- in the air: when the soldier left the ground (nil on it) and whether by a jump
	local airborneAt: number? = nil
	local jumped = false
	local ground: string? = nil -- the last ground cycle: the weapon hold keeps it through a jump

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall then
			if not airborneAt then
				airborneAt = os.clock()
			end
			if new == Enum.HumanoidStateType.Jumping then
				jumped = true
				tracks.land:Stop(Air.JumpFade)
			end
		elseif new == Enum.HumanoidStateType.Landed then
			-- the landing, over the ground cycle the step below crossfades back to; lighter on the move
			if airborneAt and os.clock() - airborneAt >= Air.LandMinAir then
				local moving = horizontalSpeed() >= Cfg.IdleBelow
				tracks.land:Play(Air.LandFade, if moving then Air.LandWeightMoving else Air.LandWeight)
			end
			airborneAt, jumped = nil, false
		else
			airborneAt, jumped = nil, false
		end
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

	local swinging: AnimationTrack? = nil -- the shovel's swing looping (src/client/Shovel "Digging")
	-- the swing playing, or none; "Swinging" (local) while one plays, so the soldier stands (src/client/Stance)
	local function swingWith(track: AnimationTrack?)
		swinging = track
		character:SetAttribute("Swinging", if track then true else nil)
	end

	-- weapon holds, loaded per weapon on first equip
	local function holdTracks(name: string): { [string]: AnimationTrack }
		if not holds[name] then
			holds[name] = {}
			for hold, id in MovementSet.holds(Cfg, name, W[name].holds) do
				local anim = Instance.new("Animation")
				anim.Name = hold
				anim.AnimationId = "rbxassetid://" .. id
				local t = animator:LoadAnimation(anim)
				-- the equip is a one shot over the hold that will follow it; the staff's charge too (its time is set from
				-- the hold time, below)
				local once = hold == "equip"
					or hold == "unequip"
					or hold == "charge"
					or hold == "airCharge"
					or hold == "chargeTwo"
					or hold == "airChargeTwo"
					or hold == "pin"
				-- a grenade's throw: a one shot over its wind-up (src/client/Grenades "ThrownAt"); the shovel's dig the same
				-- over its hold (src/client/Shovel "DugAt"), and a gun's butt stroke (src/client/Melee "StruckAt")
				-- the shovel's swings loop over the hold while the fire key is held (src/client/Shovel "Digging")
				local swing = hold == "dig" or hold == "chip"
				local over = hold == "throw" or hold == "strike"
				t.Priority = if over or swing
					then Enum.AnimationPriority.Action3
					elseif once then Enum.AnimationPriority.Action2
					else Enum.AnimationPriority.Action
				t.Looped = not once and not over
				holds[name][hold] = t
				if swing then
					-- its sound now: the swinger's own at once, everyone else's through the server (src/client/Shovel)
					local function sound(kind: string)
						SoundFx.play(ShovelCfg.Sounds[kind], root)
						Net.event("Dug"):FireServer(kind)
					end
					t:GetMarkerReachedSignal("Strike"):Connect(function()
						if t == swinging then
							character:SetAttribute("DugMode", if hold == "chip" then "Destroy" else "Build")
							character:SetAttribute("DugAt", os.clock())
							sound(if hold == "chip" then "Chip" else "Dig")
						end
					end)
					t:GetMarkerReachedSignal("Rest"):Connect(function()
						if t == swinging and hold == "dig" then
							sound("Toss") -- (the dig's rest is the toss)
						end
						-- let go (or switched mode): settle to the ready from here (the other mode starts next step)
						local want = if hold == "chip" then "Destroy" else "Build"
						if t == swinging and character:GetAttribute("Digging") ~= want then
							t:Stop(ShovelCfg.Leave)
							swingWith(nil)
						end
					end)
				end
			end
		end
		return holds[name]
	end
	-- the one upper-body track playing over the cycle (a weapon hold or the stock tool hold)
	local upper: AnimationTrack? = nil
	local charging: AnimationTrack? = nil -- the staff's charge while it plays
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

	-- putting a weapon away (Config/Locomotion.Stow): its unequip plays on the body (the server keeps a copy in the
	-- hands for it, told by Net "Stow") and the viewmodel's ("Stowing" names the weapon; src/client/Viewmodel,
	-- src/client/WeaponCamera wait for it to end); knocked into a ragdoll it just goes (src/client/Ragdoll)
	local stowTrack: AnimationTrack? = nil
	local function endStow()
		if stowTrack and stowTrack.IsPlaying then
			stowTrack:Stop(0.1)
		end
		stowTrack = nil
		character:SetAttribute("Stowing", nil)
	end

	-- something taken out while a weapon is still going over the shoulder (user 2026-10-25: "an animation has to finish
	-- (fully putting gun back) before they can do anything else"): back into the backpack, and drawn once it's away
	local waiting: Tool? = nil
	local bouncing: { [Instance]: boolean } = {}

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and character:GetAttribute("Stowing") ~= nil and backpack then
			waiting = child
			bouncing[child] = true
			task.defer(function()
				if child.Parent == character then
					child.Parent = backpack
				end
				bouncing[child] = nil
			end)
			return
		end
		-- join the gun to the torso at once (the server does too, a moment later), or it drops for a frame
		local weapon = child:IsA("Tool") and Held.weapon(character)
		local torso = character:FindFirstChild("Torso") :: BasePart?
		if weapon and torso then
			endStow() -- drawn again while being put away
			weapon.hold.Part0 = torso
			-- drawn from the sling: the equip plays once over the hold; the viewmodel starts its own from this moment
			character:SetAttribute("EquippedAt", os.clock())
			holdTracks(weapon.name).equip:Play(0.05)
			local sounds = W[weapon.name].sounds
			SoundFx.play(sounds and sounds.Equip, torso) -- (the staff's swish)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		local name = child:IsA("Tool") and child:GetAttribute("Weapon")
		if
			bouncing[child]
			or type(name) ~= "string"
			or not W[name]
			or humanoid.Health <= 0
			or character:GetAttribute("Ragdolled") == true
		then
			return
		end
		local track = holdTracks(name).unequip
		if not track then
			return -- no unequip animation: straight onto the back, as before
		end
		Net.event("Stow"):FireServer()
		local at = os.clock()
		character:SetAttribute("Stowing", name)
		character:SetAttribute("StowedAt", at)
		track:Play(0.1)
		stowTrack = track
		local sounds = W[name].sounds
		SoundFx.play(sounds and sounds.Unequip, root)
		task.delay(Cfg.Stow.time, function()
			if character:GetAttribute("StowedAt") == at and character:GetAttribute("Stowing") == name then
				endStow()
				-- away: what was taken out meanwhile comes out now
				local next = waiting
				waiting = nil
				if
					next
					and next.Parent == backpack
					and humanoid.Health > 0
					and character:GetAttribute("Ragdolled") ~= true
					and character:GetAttribute("Healing") == nil
					and not character:FindFirstChildOfClass("Tool")
				then
					humanoid:EquipTool(next)
				end
			end
		end)
	end)

	-- the moving holds keep step with the cycle they ride on (same keyed length, so the same phase)
	local CYCLE = { walk = "walk", carry = "sprint", crouchWalk = "crouchWalk" }
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

	local thrown: number? = nil -- the last grenade throw played ("ThrownAt")
	local struck: number? = nil -- the last butt stroke played ("StruckAt")
	local striking: AnimationTrack? = nil -- the butt stroke while it plays (stopped if that gun is put away)
	local pinned: number? = nil -- the last pin pull played ("PinAt")
	local pinning: AnimationTrack? = nil -- the grenade's pin pull and throw while they play (stopped if cancelled)
	local throwing: AnimationTrack? = nil
	local step = RunService.Heartbeat:Connect(function()
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Dead then
			return
		elseif state == Enum.HumanoidStateType.Climbing then
			play("climb", Cfg.Fade)
			local climb = Anims.climb
			tracks.climb:AdjustSpeed(root.AssemblyLinearVelocity.Y / (climb.speed or 1))
		elseif character:GetAttribute("Floating") == true then
			-- floating with the staff aimed (src/client/StaffAttack): the float cycle; landing crossfades back
			play("float", Cfg.Fade)
		elseif
			airborneAt
			and (state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall)
			and (jumped or os.clock() - airborneAt >= Air.FallDelay)
		then
			-- in the air: the take-off once after a jump, then the tuck
			if current ~= "jump" and current ~= "fall" then
				play(if jumped then "jump" else "fall", if jumped then Air.JumpFade else Air.FallFade)
			elseif current == "jump" and not tracks.jump.IsPlaying then
				play("fall", Air.FallFade)
			end
		else -- on the ground (or just stepped off it): the cycle for the horizontal speed
			local speed = horizontalSpeed()
			local crouching = character:GetAttribute("Crouching") == true
			local name = if crouching
				then (if speed < Cfg.IdleBelow then "crouchIdle" else "crouchWalk")
				elseif speed < Cfg.IdleBelow then "idle"
				elseif speed > Cfg.SprintAbove then "sprint"
				else "walk"
			play(name, Cfg.Fade)
			ground = name
			local a = Anims[name]
			if a.speed and a.keyed and a.cycle then
				local pace = math.clamp(speed / a.speed, Cfg.PlaybackMin, Cfg.PlaybackMax)
				tracks[name]:AdjustSpeed(pace * a.keyed / a.cycle)
			end
		end
		-- a grenade's pin pull or throw cancelled (another weapon drawn before it left the hand: src/client/Grenades)
		if pinning and pinning.IsPlaying and character:GetAttribute("Winding") ~= true then
			pinning:Stop(0.1)
		end
		if throwing and throwing.IsPlaying and character:GetAttribute("ThrownAt") == nil then
			throwing:Stop(0.1)
		end
		local weapon = Held.weapon(character)
		-- in the air the hold stays on the ground cycle's (a sprinting jump keeps the carry)
		local base = if current == "jump" or current == "fall" then ground else current
		local holding = if not weapon
			then nil
			elseif character:GetAttribute("Winding") == true and W[weapon.name].holds.windup then "windup"
			elseif character:GetAttribute("Blocked") == true and base ~= "sprint" then "tuck" -- (src/client/Tuck)
			elseif character:GetAttribute("Aiming") then "aim"
			elseif base == "sprint" then "carry"
			else "ready"
		character:SetAttribute("Hold", holding)
		if weapon and holding then
			-- standing still: the ready hold; walking: the walking hold (sprinting: carry already swings)
			local set = holdTracks(weapon.name)
			local pick = holding
			if holding == "windup" then
				pick = "windup" -- a grenade drawn back (src/client/Grenades), standing or crouched
			elseif base == "crouchIdle" or base == "crouchWalk" then -- crouched: the holds for the hunched torso
				pick = if holding == "aim"
					then "crouchAim"
					elseif holding == "tuck" then "crouchTuck"
					elseif base == "crouchWalk" then "crouchWalk"
					else "crouchReady"
			elseif holding == "ready" and base == "walk" then
				pick = "walk"
			elseif holding == "aim" and character:GetAttribute("TwoHands") == true and set.aimTwo then
				pick = "aimTwo" -- the staff: the left hand joined (src/client/StaffAttack)
			end
			-- a hold the item doesn't have (the staff has no run or crouch holds yet) plays its ready
			local track = set[pick] or set.ready
			hold(track)
			if CYCLE[pick] and set[pick] then
				keepStep(pick, track)
			end
			-- a grenade's pin pulled and thrown (src/client/Grenades marks the moments): each plays once over the hold
			local pinAt = character:GetAttribute("PinAt")
			if type(pinAt) == "number" and pinAt ~= pinned then
				pinned = pinAt
				if set.pin then
					set.pin:Play(0.05)
					pinning = set.pin
				end
			end
			local at = character:GetAttribute("ThrownAt")
			if type(at) == "number" and at ~= thrown then
				thrown = at
				if set.throw then
					set.throw:Play(0.05)
					throwing = set.throw
				end
			end
			-- the shovel held swinging (src/client/Shovel "Digging", the mode): its swing loops over the hold, blending up
			-- from the ready, the dig in Build, the chip in Destroy; let go, it stops at its "Rest" marker (above)
			if swinging and (not swinging.IsPlaying or (swinging ~= set.dig and swinging ~= set.chip)) then
				swinging:Stop(0.1) -- (put away)
				swingWith(nil)
			end
			local digging = character:GetAttribute("Digging")
			local swing = if digging == "Destroy" then set.chip elseif digging == "Build" then set.dig else nil
			if swing and not swinging then
				swing:Play(ShovelCfg.Enter)
				swingWith(swing)
			end
			-- a gun's butt stroke (src/client/Melee marks the moment): played once over the hold
			local struckAt = character:GetAttribute("StruckAt")
			if type(struckAt) == "number" and struckAt ~= struck then
				struck = struckAt
				if set.strike then
					set.strike:Play(0.05)
					striking = set.strike
				end
			end
			if striking and striking.IsPlaying and set.strike ~= striking then
				striking:Stop(0.1) -- another weapon drawn
			end
			-- the staff's charge: posed at how long the cast has been held (then its ready shake on a loop); floating, the
			-- one leaning back
			-- with both hands already on the staff when it started (src/client/StaffAttack "ChargeTwo"), the two-handed one
			local held = character:GetAttribute("CastHeld")
			local two = character:GetAttribute("ChargeTwo") == true
			local charge = if character:GetAttribute("Floating") == true and set.airCharge
				then (if two and set.airChargeTwo then set.airChargeTwo else set.airCharge)
				else (if two and set.chargeTwo then set.chargeTwo else set.charge)
			if charging and charging ~= charge then
				charging:Stop(Cfg.Fade)
				charging = nil
			end
			if charge and type(held) == "number" and character:GetAttribute("Casting") == true then
				if not charge.IsPlaying then
					charge:Play(Cfg.HoldFade)
				end
				charge:AdjustSpeed(0)
				local t = SpellRules.chargeTime(Spells.Stages, Spells.Staff.ChargeLoop, held)
				charge.TimePosition = math.min(t, math.max(charge.Length - 0.01, 0))
				charging = charge
			elseif charging then
				charging:Stop(0.1)
				charging = nil
			end
		else
			if striking and striking.IsPlaying then
				striking:Stop(0.1) -- put away
			end
			if swinging then
				swinging:Stop(0.1) -- the shovel put away
				swingWith(nil)
			end
			hold(if character:FindFirstChildOfClass("Tool") then tracks.toolnone else nil)
			if charging then
				charging:Stop(0.1)
				charging = nil
			end
		end
	end)
	character.Destroying:Connect(function()
		step:Disconnect()
	end)
end

return Locomotion
