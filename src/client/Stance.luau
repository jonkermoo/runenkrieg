--!strict
-- The soldier's stance controls (keys and hold / toggle modes are player settings, src/client/Settings; speeds from
-- Config/Metrics.Movement):
-- - hold Shift to sprint (or press it once: the "Toggle" sprint mode, off again on the next press, a crouch, or
--   stopping after moving), unlimited stamina (user 2026-10-11), only while moving forward relative to the camera
--   (user reference video: strafing or backing up with Shift stays a walk; Config/Locomotion.SprintCone);
-- - hold right mouse to aim down the sights while a weapon is in the hands (or press it once: the "Toggle" aim mode,
--   off again on the next press, a sprint, a fall or putting the weapon away); never while sprinting (Shift wins), and not
--   until a reload or a load has finished (src/client/GunFx "Reloading"; aiming cuts a single load short,
--   src/client/Firing), so the sights never come up over the loading arms;
-- - C toggles crouch (or is held: the "Hold" crouch mode) (moderate, from the user's reference video); sprinting or jumping stands you up. Crouched, the
--   camera comes down with the body (Humanoid.CameraOffset follows the torso's drop; src/client/WeaponCamera too).
-- - healing someone (the "Healing" attribute, src/server/Healing): crouched at crouch speed, no sprint or aim;
-- - dragging a teammate (the "Dragging" attribute, src/server/Dragging): crouched at Config/Dragging.Speed, no sprint
--   or aim;
-- - a staff cast (src/client/StaffAttack) scales the walk speed by the character's "SpeedScale" attribute (local:
--   the charge and the recoil slow you, Config/Spells.Staff) and blocks sprinting while "Casting" is set.
-- Sets the local character's Humanoid.WalkSpeed (the client owns its character's physics) and the "Sprinting" /
-- "Aiming" / "Crouching" attributes that the animations, the camera and the weapon code read (local only; the
-- animations they choose replicate).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion)
local Dev = require(Shared.Config.DevTools)
local DragCfg = require(Shared.Config.Dragging)
local M = require(Shared.Config.Metrics)
local W = require(Shared.Config.Weapons)
local CameraRules = require(Shared.Rules.Camera)
local Held = require(script.Parent.Held)
local Settings = require(script.Parent.Settings)

local Stance = {}

function Stance.start()
	local player = Players.LocalPlayer
	local sprintHeld, aimHeld, crouched = false, false, false
	local sprintMoved = false -- a toggled sprint has moved since it was switched on (stopping then ends it)

	local cone = math.cos(math.rad(Cfg.SprintCone))
	-- moving within the cone around where the camera looks (flat), or standing still (Shift down, about to go)
	local function forward(humanoid: Humanoid): boolean
		local move = humanoid.MoveDirection
		if move.Magnitude < 0.1 then
			return true
		end
		local look = workspace.CurrentCamera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		return flat.Magnitude > 1e-3 and flat.Unit:Dot(move.Unit) >= cone
	end

	local function apply()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid then
			return
		end
		-- ragdolled (src/client/Ragdoll): no control at all
		local limp = character:GetAttribute("Ragdolled") == true
		if sprintHeld and Settings.get("SprintMode") == "Toggle" then
			if humanoid.MoveDirection.Magnitude >= Cfg.ToggleSprintMoving then
				sprintMoved = true
			elseif sprintMoved then
				sprintHeld = false -- stopped: a toggled sprint ends
			end
		end
		-- healing someone (src/server/Healing sets "Healing"): crouched at crouch speed, no sprint, no aim
		local healing = character:GetAttribute("Healing") ~= nil
		local dragging = character:GetAttribute("Dragging") == true -- (src/server/Dragging) slow, no sprint, no aim
		local sprinting = sprintHeld
			and forward(humanoid)
			and character:GetAttribute("Casting") ~= true
			and not limp
			and not healing
			and not dragging
		if sprinting then
			crouched = false -- a sprint stands you up
		end
		local low = crouched or healing or dragging
		-- only an item with an aim hold can be aimed (the staff has no sights)
		local weapon = Held.weapon(character)
		if aimHeld and Settings.get("AimMode") == "Toggle" and (sprinting or limp or not weapon) then
			aimHeld = false -- a toggled aim ends with a sprint, a fall or the weapon put away
		end
		local aiming = aimHeld
			and not sprinting
			and character:GetAttribute("Blocked") ~= true -- the gun folded in (src/client/Tuck)
			and not limp
			and not healing
			and not dragging
			and weapon ~= nil
			and W[weapon.name].holds.aim ~= nil
			and character:GetAttribute("Reloading") ~= true
		local speed = if dragging
			then DragCfg.Speed
			elseif sprinting then M.Movement.SprintSpeed
			elseif low then M.Movement.CrouchSpeed
			elseif aiming then M.Movement.AimWalkSpeed
			else M.Movement.WalkSpeed
		-- the staff's slows (1 when unset), and the dev admin panel's speed multiplier (src/client/DevAdminMenu; 1 when
		-- unset)
		local scale = character:GetAttribute("SpeedScale")
		speed *= if type(scale) == "number" then scale else 1
		humanoid.WalkSpeed = speed * ((player:GetAttribute(Dev.Admin.Attribute) :: number?) or 1)
		character:SetAttribute("Sprinting", sprinting)
		character:SetAttribute("Aiming", aiming)
		character:SetAttribute("Crouching", low)
	end

	local function held(flag: (boolean) -> ()): (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
		return function(_, state)
			if state == Enum.UserInputState.Begin then
				flag(true)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				flag(false)
			end
			apply()
			return Enum.ContextActionResult.Pass
		end
	end
	local function sprint(on: boolean)
		if Settings.get("SprintMode") ~= "Toggle" then
			sprintHeld = on
		elseif on then
			sprintHeld, sprintMoved = not sprintHeld, false
		end
	end
	local function aim(on: boolean)
		if Settings.get("AimMode") ~= "Toggle" then
			aimHeld = on
		elseif on then
			-- toggled; pressed during a load (which it stops, src/client/Firing) it always means aim once it's done
			local character = player.Character
			local loading = character ~= nil and character:GetAttribute("Reloading") == true
			aimHeld = loading or not aimHeld
		end
	end
	local function crouch(on: boolean)
		if Settings.get("CrouchMode") == "Hold" then
			crouched = on
		elseif on then
			crouched = not crouched
		end
		if crouched and Settings.get("SprintMode") == "Toggle" then
			sprintHeld = false -- crouching ends a toggled sprint
		end
	end
	-- (re)bound to the player's keys whenever one changes
	local function bindAll()
		ContextActionService:BindAction("Sprint", held(sprint), false, Settings.key("Key_Sprint"))
		ContextActionService:BindAction("Aim", held(aim), false, Settings.key("Key_Aim"))
		ContextActionService:BindAction("Crouch", held(crouch), false, Settings.key("Key_Crouch"))
	end
	bindAll()
	for _, k in { "Key_Sprint", "Key_Aim", "Key_Crouch" } do
		Settings.changed(k, bindAll)
	end
	for _, k in { "AimMode", "SprintMode", "CrouchMode" } do
		Settings.changed(k, function()
			sprintHeld, aimHeld, crouched = false, false, false
			apply()
		end)
	end

	local function hook(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		crouched = false
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping and crouched then
				crouched = false -- a jump stands you up
				apply()
			end
		end)
		apply()
		-- equipping or putting away a weapon starts or ends aiming while the button stays held
		character.ChildAdded:Connect(apply)
		character.ChildRemoved:Connect(apply)
		character:GetAttributeChangedSignal("SpeedScale"):Connect(apply)
		character:GetAttributeChangedSignal("Casting"):Connect(apply)
		character:GetAttributeChangedSignal("Ragdolled"):Connect(apply)
		character:GetAttributeChangedSignal("Healing"):Connect(apply)
		character:GetAttributeChangedSignal("Dragging"):Connect(apply)
		character:GetAttributeChangedSignal("Reloading"):Connect(apply) -- the aim held through a reload comes up after it
	end
	player.CharacterAdded:Connect(hook)
	player:GetAttributeChangedSignal(Dev.Admin.Attribute):Connect(apply)
	if player.Character then
		task.spawn(hook, player.Character)
	end
	-- the direction changes without any key event (turning the camera, letting go of W)
	-- crouched, the camera comes down with the torso (on a spring, so it starts and stops gently; the drop is read
	-- from the animated body)
	local drop, dropSpeed = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		if sprintHeld then
			apply()
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local torso = character and character:FindFirstChild("Torso") :: BasePart?
		if humanoid and root and torso then
			local want = if crouched then math.min(0, torso.Position.Y - root.Position.Y) else 0
			drop, dropSpeed = CameraRules.spring(drop, dropSpeed, want, Cfg.CrouchCameraSpring, dt)
			humanoid.CameraOffset = Vector3.new(0, drop, 0)
		end
	end)
end

return Stance
