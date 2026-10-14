--!strict
-- The staff's attack (user 2026-10-13; numbers in Config/Spells.Staff, stages in Config/Spells.Stages, effects
-- Vfx/Zoltraak.begin). Visual only, on the caster's client for now: no damage, others see the animations, not the
-- spells.
-- - Not aiming, left click: a quick fire (stage 1) at once from the staff's head toward the crosshair, turned by the
--   first-person sway (it sways with the steps like a gun barrel) inside a cone (Rules/Spells.spread: wider walking).
-- - Aiming (right mouse): the first circle opens and is held ready; a click fires it, holding charges stages 2 and 3,
--   release fires the stage reached toward the crosshair. While aiming, shots chain: the next circle opens once the
--   cooldown is over. Letting go of aim while charging drops the cast.
-- - Each shot: a cooldown, and the walk slowed for as long (Cooldown / Slow per stage), standing still or not.
-- - Charging: the walk slows more and more and the camera shakes more and more (Sway.shake); once stage 3 is ready you
--   can't move or jump. Halfway to stage 3 the left hand joins the staff, until aiming ends ("TwoHands").
-- - A stage 3 shot knocks the caster back into a ragdoll (src/client/Ragdoll, Config/Ragdoll.Knocks.StaffRecoil): no
--   control until they get up, half a second after landing.
-- - In first person the caster's own cast starts at the first-person staff's head (aiming: Staff.Lead past it, the
--   staff on the circles' line), drawn smaller (Staff.ViewScale) and see-through while held (Staff.Veil, the older
--   circles more: Staff.OlderVeil); solid once fired.
-- - While charging (left click held, aiming), a flickering dashed laser runs from the cast to the crosshair
--   (Vfx/Pointer): the aim in first person, a warning for whoever it points at. It goes when the beam fires.
-- - Only with the staff drawn (and the staff always brings the first-person weapon camera, src/client/WeaponCamera).
-- - No firing or aiming while sprinting (src/client/Stance).
-- - In the air while aiming: floating (Staff.Float): carried slowly up to the jump's height above where it took off,
--   hovering; after Float.hover seconds it sinks, and dropping below the takeoff height knocks it down (ragdoll). The
--   float cycle plays and a charge leans back (src/client/Locomotion, "Floating"). Landing ends it at once.
-- - Mana (Config/Spells.Mana, Rules/Spells): each shot spends its stage's cost; a charge stops at the stage it can pay
--   for; nothing fires without enough, or while burnt out after a mega shot. Shown by src/client/ManaBar from the
--   character's "Mana", "ManaLocked", "ManaSmoulder", "ManaCost", "ManaDenied", "ManaRefilled" (local).
-- Writes local attributes on the character: "SpeedScale" (src/client/Stance), "Casting" (charging), "CastHeld" (how
-- long the charge has been held, for the charge animations), "TwoHands".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Spells)
local M = require(Shared.Config.Metrics)
local RagdollCfg = require(Shared.Config.Ragdoll)
local VfxCfg = require(Shared.Config.Vfx)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Spells)
local Held = require(script.Parent.Held)
local LookTilt = require(script.Parent.LookTilt)
local Ragdoll = require(script.Parent.Ragdoll)
local Sway = require(script.Parent.Sway)
local Vfx = require(script.Parent.Vfx)
local Zoltraak = require(script.Parent.Vfx.Zoltraak)

local StaffAttack = {}

local S = Cfg.Staff
local RANGE = 1000 -- how far the aim ray looks for what the crosshair is on
local HOLDS = {}
for i, s in Cfg.Stages do
	HOLDS[i] = s.hold
end
local LAST = #Cfg.Stages
-- when each stage's circle starts to open (its hold, less an assembling circle's lead): a charge with only so many
-- stages paid for stops short of the next one's
local OPENS = {}
for i, s in Cfg.Stages do
	OPENS[i] = s.hold - ((VfxCfg.Cast.Stages[i] :: any).lead or 0)
end
local rng = Random.new()

local function isStaff(weapon: Held.Weapon?): boolean
	return weapon ~= nil and W[weapon.name] ~= nil and W[weapon.name].class == "Staff"
end

-- the point under the crosshair (the screen centre: the mouse is locked there with a weapon drawn)
local function aimPoint(ignore: { Instance }): Vector3
	local cam = workspace.CurrentCamera
	local size = cam.ViewportSize
	local ray = cam:ViewportPointToRay(size.X / 2, size.Y / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(ray.Origin, ray.Direction * RANGE, params)
	return if hit then hit.Position else ray.Origin + ray.Direction * RANGE
end

-- the staff's head as the player sees it: the first-person viewmodel's while it shows, else the body's
local function head(character: Model, weapon: Held.Weapon): Attachment?
	local vm = workspace.CurrentCamera:FindFirstChild("Viewmodel")
	local shown = character:GetAttribute("ViewmodelShown") == true
	local gun = if vm and shown then vm:FindFirstChild("Gun") else weapon.gun
	return gun and gun:FindFirstChild("Muzzle") :: Attachment?
end

-- a direction turned at random inside a cone of `degrees` (half-angle)
local function cone(dir: Vector3, degrees: number): Vector3
	local cf = CFrame.lookAt(Vector3.zero, dir)
	local a = math.rad(degrees) * math.sqrt(rng:NextNumber())
	local spin = rng:NextNumber(0, 2 * math.pi)
	return (cf * CFrame.Angles(0, 0, spin) * CFrame.Angles(a, 0, 0)).LookVector
end

function StaffAttack.start()
	local player = Players.LocalPlayer
	local cast: Zoltraak.Cast? = nil -- the held cast (aiming), if any
	local pressedAt: number? = nil -- left click went down on it: charging
	local readyUntil = 0 -- the cooldown: no firing (and no new circle) before this
	local slowUntil, slowShare = 0, 1
	local twoHands = false
	local lockedHumanoid: Humanoid? = nil
	local scheme = (VfxCfg.Schemes :: any)[S.Scheme]
	local pointer = Vfx.Pointer.new(scheme.pointer, scheme.core)
	local mana = Rules.mana(Cfg.Mana)
	player.CharacterAdded:Connect(function()
		mana = Rules.mana(Cfg.Mana) -- a new life starts full
	end)
	-- a shot refused for want of mana: the bar flashes (src/client/ManaBar)
	local function denied(character: Model)
		character:SetAttribute("ManaDenied", os.clock())
	end
	-- how far the charge has got: it runs with the hold, but waits short of a stage the mana can't pay for yet and
	-- goes on from there once it can (counted up each frame, so it never jumps ahead when the mana comes in)
	local charged = 0
	local function chargeHeld(_now: number): number?
		return if pressedAt then charged else nil
	end
	local function chargeStep(dt: number)
		if pressedAt then
			charged = Rules.capHeld(OPENS, Rules.affordable(mana, Cfg.Mana), charged + dt)
		end
	end

	local function ignoreList(character: Model): { Instance }
		return { character, Vfx.Util.folder(), workspace.CurrentCamera }
	end

	-- where the held cast starts, looking at the crosshair: just past the staff's head as seen (the first-person
	-- staff points at the crosshair while aiming, so it runs through the circles' centres)
	local function aimTip(character: Model, weapon: Held.Weapon, ignore: { Instance }): CFrame?
		local cam = workspace.CurrentCamera
		local h = head(character, weapon)
		if not h then
			return nil
		end
		local to = aimPoint(ignore)
		local from = h.WorldPosition
		if character:GetAttribute("CameraInside") == true and (to - from).Magnitude > S.Lead then
			from += (to - from).Unit * S.Lead
		end
		if (to - from).Magnitude < 1 then
			return CFrame.lookAt(from, from + cam.CFrame.LookVector)
		end
		return CFrame.lookAt(from, to)
	end

	local function setLock(humanoid: Humanoid?)
		if lockedHumanoid == humanoid then
			return
		end
		if lockedHumanoid then
			lockedHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
		if humanoid then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
		lockedHumanoid = humanoid
	end

	local function drop()
		local c = cast
		if c then
			c.cancel()
		end
		cast, pressedAt = nil, nil
		pointer.hide()
	end

	-- the third-person recoils (the staff's Config/Weapons `fire`), loaded per character; first person kicks with Sway.kick
	local recoils: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any
	-- a recoil one shot on a rig: the character, or the first-person viewmodel (src/client/Viewmodel)
	local function recoil(rig: Instance?, name: string)
		local humanoid = rig and rig:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		local character = player.Character
		local weapon = character and Held.weapon(character)
		local id = weapon and (W[weapon.name].fire :: any)[name]
		if not animator or not id then
			return
		end
		local set = recoils[animator] or {}
		recoils[animator] = set
		local t = set[name]
		if not t then
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://" .. id
			t = animator:LoadAnimation(anim)
			t.Priority = Enum.AnimationPriority.Action3
			t.Looped = false
			set[name] = t
		end
		(t :: AnimationTrack):Play(0.05)
	end

	-- a shot's cost: the cooldown and the slow (Staff.Cooldown / Slow), the recoil (Sway.kick in first person, an
	-- animation on the body), and after stage 3 the fall
	local function spent(character: Model, stage: number, aimed: boolean)
		local now = os.clock()
		readyUntil = now + S.Cooldown[stage]
		slowUntil, slowShare = readyUntil, S.Slow[stage]
		Sway.kick(stage)
		if stage < LAST then
			local base = if stage == 1 then (if aimed then "quickAim" else "quick") else "medium"
			if aimed and twoHands then
				base = if stage == 1 then "quickTwo" else "mediumTwo"
			end
			recoil(character, base)
			if not aimed then
				-- first person: a brief flick through the cooldown (the shot has already left)
				recoil(workspace.CurrentCamera:FindFirstChild("Viewmodel"), "firstQuick")
			end
		end
		if stage == LAST then
			-- the recoil throws the caster back off the aim (a minor knock: up again soon after landing)
			Ragdoll.knock(character, RagdollCfg.Knocks.StaffRecoil, -workspace.CurrentCamera.CFrame.LookVector)
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local weapon = character and Held.weapon(character)
		if not character or not humanoid or humanoid.Health <= 0 or not weapon or not isStaff(weapon) then
			return
		end
		if os.clock() < readyUntil or character:GetAttribute("Sprinting") == true or Ragdoll.active(character) then
			return
		end
		local c = cast
		if character:GetAttribute("Aiming") == true then
			if c and not pressedAt then
				pressedAt = os.clock() -- charging from the held circle
				charged = 0
			elseif not c and Rules.affordable(mana, Cfg.Mana) < 1 then
				denied(character)
			end
			return
		end
		if Rules.affordable(mana, Cfg.Mana) < 1 then
			denied(character)
			return
		end
		-- the hip: a quick fire at once, along the staff's line inside the cone
		local h = head(character, weapon)
		if not h then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local v = if root then root.AssemblyLinearVelocity else Vector3.zero
		local walking = Vector3.new(v.X, 0, v.Z).Magnitude / M.Movement.WalkSpeed
		-- toward the crosshair, turned as the first-person staff sways (the sway's turn, in camera space)
		local from = h.WorldPosition
		local cam = workspace.CurrentCamera.CFrame
		local toAim = (aimPoint(ignoreList(character)) - from).Unit
		local swayed = cam:VectorToWorldSpace(Sway.viewmodel().Rotation * cam:VectorToObjectSpace(toAim))
		local dir = cone(swayed, Rules.spread(S.Hip, walking))
		local own = character:GetAttribute("CameraInside") == true -- drawn smaller for the eye, as the aimed casts
		local quick = Vfx.Zoltraak.begin(
			CFrame.lookAt(from, from + dir),
			HOLDS,
			S.Scheme,
			if own then S.ViewScale else 1,
			if own then S.ViewSpread else 1
		)
		quick.release(1, ignoreList(character))
		Rules.spend(mana, Cfg.Mana, 1, os.clock())
		spent(character, 1, false)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local c, p = cast, pressedAt
		local character = player.Character
		if not c or not p or not character then
			return
		end
		local held = chargeHeld(os.clock()) or 0
		cast, pressedAt = nil, nil
		if held >= S.TwoHands then
			twoHands = true -- released after the left hand joined: it stays on until aiming ends
		end
		local stage = math.min(Rules.firing(Cfg.Stages, Cfg.Built, held) or 1, Rules.affordable(mana, Cfg.Mana))
		if stage < 1 then
			c.cancel()
			denied(character)
			return
		end
		c.release(stage, ignoreList(character))
		Rules.spend(mana, Cfg.Mana, stage, os.clock())
		spent(character, stage, true)
	end)

	-- after the viewmodel has posed the staff (src/client/Viewmodel) and the camera is placed
	RunService:BindToRenderStep("StaffAttack", LookTilt.Priority + 3, function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local weapon = character and Held.weapon(character)
		local now = os.clock()
		-- mana refills whether the staff is out or not (a waiting charge goes on once it's in)
		if Rules.refill(mana, Cfg.Mana, now, math.min(dt, 0.1)) and character then
			character:SetAttribute("ManaRefilled", now) -- burnt out no more
		end
		chargeStep(math.min(dt, 0.1))
		if character then
			local B = Cfg.Mana.burnout
			character:SetAttribute("Mana", mana.value)
			character:SetAttribute("ManaLocked", mana.locked)
			character:SetAttribute("ManaSmoulder", mana.locked and now - mana.spentAt < B.delay)
		end
		if not character or not humanoid or humanoid.Health <= 0 or not weapon or not isStaff(weapon) then
			drop()
			twoHands = false
			Sway.shake(0)
			setLock(nil)
			if character then
				character:SetAttribute("SpeedScale", nil)
				character:SetAttribute("Casting", nil)
				character:SetAttribute("CastHeld", nil)
				character:SetAttribute("TwoHands", nil)
				character:SetAttribute("ManaCost", nil)
			end
			return
		end
		local w = weapon :: Held.Weapon
		local aiming = character:GetAttribute("Aiming") == true and not Ragdoll.active(character)
		if not aiming then
			drop()
			twoHands = false
		elseif not cast and now >= readyUntil and Rules.affordable(mana, Cfg.Mana) >= 1 then
			-- aiming, ready and with mana: a circle opens and is held, ready to fire (the chain's next one too)
			local ignore = ignoreList(character)
			local t = aimTip(character, w, ignore)
			if t then
				local own = character:GetAttribute("CameraInside") == true -- drawn smaller for the eye
				cast = Vfx.Zoltraak.begin(
					t,
					HOLDS,
					S.Scheme,
					if own then S.ViewScale else 1,
					if own then S.ViewSpread else 1
				)
			end
		end

		local held = chargeHeld(now)
		-- what the held cast would spend if fired now (the bar shows it)
		character:SetAttribute(
			"ManaCost",
			if cast then Cfg.Mana.cost[Rules.firing(Cfg.Stages, Cfg.Built, held or 0) or 1] else nil
		)
		-- a held cast follows the aim, its laser to the crosshair (none once the beam has fired, until the next circle)
		local c = cast
		if c then
			local ignore = ignoreList(character)
			local t = aimTip(character, w, ignore)
			if t then
				c.aim(t)
				-- the laser only while left click is held (user 2026-10-13)
				if held then
					pointer.set(t.Position, aimPoint(ignore))
				else
					pointer.hide()
				end
			end
			c.update(held or 0)
			c.veil(if character:GetAttribute("CameraInside") == true then S.Veil else 0, S.OlderVeil, S.StageVeils)
		else
			pointer.hide()
		end
		if held and held >= S.TwoHands then
			twoHands = true
		end

		-- the walk: the charge's slow, then the recoil's
		local scale = if held then Rules.chargeSpeed(Cfg.Stages, S.Charge, held) else 1
		if now < slowUntil then
			scale *= slowShare
		end
		character:SetAttribute("SpeedScale", scale)
		character:SetAttribute("Casting", held ~= nil)
		character:SetAttribute("CastHeld", held)
		character:SetAttribute("TwoHands", twoHands)
		Sway.shake(if held then Rules.charge(Cfg.Stages, held) else 0)
		setLock(if held and Rules.charge(Cfg.Stages, held) >= 1 then humanoid else nil)
	end)

	-- floating: gravity cancelled by a lift on the root (on top of the jump's own apex lift, src/client/Jump) and the
	-- body carried to the hover height, then sinking after Float.hover; falling below the takeoff height after floating
	-- knocks it down. Landing ends it at once.
	-- a root's VectorForce by name: src/client/Jump names its attachment like its force, so FindFirstChild can hand
	-- back the attachment (KNOWN_TRAPS)
	local function force(root: BasePart, name: string): VectorForce?
		for _, c in root:GetChildren() do
			if c:IsA("VectorForce") and c.Name == name then
				return c
			end
		end
		return nil
	end
	local level = 0 -- how far the float has eased in
	local takeoff: number? = nil -- the root's height when it last stood on the ground
	local floatedFor = 0 -- seconds floating this time in the air
	local floated = false -- floated at all this time in the air
	RunService.Heartbeat:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not humanoid or not root then
			return
		end
		local lift = force(root, "StaffFloat")
		if not lift then
			local att = Instance.new("Attachment")
			att.Name = "StaffFloatAttachment"
			att.Parent = root
			local f = Instance.new("VectorForce")
			f.Name = "StaffFloat"
			f.Attachment0 = att
			f.RelativeTo = Enum.ActuatorRelativeTo.World
			f.ApplyAtCenterOfMass = true
			f.Force = Vector3.zero
			f.Parent = root
			lift = f
		end
		local F = S.Float
		local state = humanoid:GetState()
		local limp = Ragdoll.active(character)
		local airborne = humanoid.FloorMaterial == Enum.Material.Air
			and state ~= Enum.HumanoidStateType.Climbing
			and state ~= Enum.HumanoidStateType.Swimming
		local y = root.Position.Y
		if not airborne or limp then
			-- standing (not already rising off the ground: the first frames of a jump still read as grounded)
			if not limp and math.abs(root.AssemblyLinearVelocity.Y) < 1 then
				takeoff = y
			end
			floatedFor, floated = 0, false
		end
		local floating = airborne
			and not limp
			and humanoid.Health > 0
			and isStaff(Held.weapon(character))
			and character:GetAttribute("Aiming") == true
		level = if floating then level + (1 - level) * (1 - math.exp(-F.ease * dt)) else 0
		character:SetAttribute("Floating", if floating then true else nil)
		local jump = force(root, "JumpFloat")
		local already = if jump then jump.Force.Y else 0
		local cancel = if floating then root.AssemblyMass * workspace.Gravity else 0
		(lift :: VectorForce).Force = Vector3.new(0, math.max(0, cancel - already), 0)
		local base = takeoff
		if floating and base then
			floated = true
			floatedFor += dt
			-- toward the hover height (bobbing), or sinking once it has floated long enough
			local want: number
			if floatedFor < F.hover then
				local top = base
					+ humanoid.JumpHeight
					+ F.extra
					+ F.bob * math.sin(2 * math.pi * F.bobRate * floatedFor)
				want = math.clamp((top - y) * F.follow, -F.rise, F.rise)
			else
				want = -F.descend
			end
			local v = root.AssemblyLinearVelocity
			-- never faster up than the slow rise (the jump's own push is taken over at once)
			local vy = math.min(v.Y, F.rise)
			vy += (want - vy) * (1 - math.exp(-F.follow * level * dt))
			root.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
		end
		-- dropped below where it took off from after floating (sinking, or letting go of aim over a drop): knocked down
		if floated and airborne and not limp and base and y < base - F.below then
			floated = false
			Ragdoll.knock(character, RagdollCfg.Knocks.FloatFall, -root.CFrame.LookVector)
		end
	end)

	player.CharacterRemoving:Connect(function()
		drop()
		twoHands = false
		Sway.shake(0)
		setLock(nil)
	end)
end

return StaffAttack
