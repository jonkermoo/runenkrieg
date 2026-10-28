--!strict
-- The camera while a weapon is in the hands (Config/Camera):
-- - a gun (user 2026-10-20): first person at the eye or over the right shoulder, stepped by the mouse wheel
--   (Config/Camera.Gun, Rules/Camera.wheel; the mouse locked to the centre, no cursor; a hollow circle in third person,
--   src/client/Crosshair); right mouse aims down the sights (src/client/Stance), always first person with a narrower
--   view, gliding back out to the distance chosen when it ends. Every distance change follows a spring. The body's
--   facing is src/client/BodyTurn's (third person: the head turns first, the body catches up);
-- - drawing a weapon glides the camera in from wherever Roblox's camera was; inside the head the body hides and the
--   viewmodel (src/client/Viewmodel) shows, at once; putting the weapon away stays at the eye while it goes over the
--   shoulder ("Stowing", src/client/Locomotion), then glides back out to where Roblox's camera was at the zoom it had
--   (Config/Camera.LeaveBlend), the body solid again as soon as the camera leaves the head, and hands it back;
-- - the body is never seen through (user 2026-10-25), except as a wall pushes the camera in toward the head;
-- - the whole body stays hidden from the player while inside: the viewmodel shows the first-person holds;
-- - ragdolled ("Ragdolled", src/client/Ragdoll): the body isn't turned with the view and the eye rides the head;
-- - the staff (user 2026-10-21): the gun's camera, wheel, shoulder view and crosshair, but aiming stays in the view it
--   is in (Config/Camera.AimInPlace): over the shoulder it is "ThirdAim" with a narrower view. (The old staff-only
--   orbit, Config/Camera.ThirdPersonClasses, Rules/Camera.target / shoulder, now has no class: centred behind the head
--   at a fixed distance, over the right shoulder while firing.) Walls stop the camera (a swept sphere);
-- - the shovel (Config/Camera.FreeClasses, user 2026-10-24): none of this, Roblox's own camera stays as with empty
--   hands, held no nearer than FreeMinZoom.
-- Writes the view to the character's "CameraMode" attribute (local): "First", "Aim", "Third" or "ThirdAim" (a gun
-- over the shoulder is "Third", "First" nearer); "CameraInside" (the viewmodel is on: first person only) and
-- "Handover" (1 once the camera is inside the head: the viewmodel shows).
-- Player settings (src/client/Settings): the look sensitivities and Invert Y scale the mouse turn, the field of view
-- sets the hip view and narrows the aimed ones by the same ratio (Rules/Settings). While the settings menu is open
-- (the Player's "MenuOpen", src/client/SettingsMenu) the mouse is free and the view doesn't turn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Camera)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Camera)
local SettingsRules = require(Shared.Rules.Settings)
local Settings = require(script.Parent.Settings)
local Held = require(script.Parent.Held)
local LookTilt = require(script.Parent.LookTilt)
local Sway = require(script.Parent.Sway)

local WeaponCamera = {}

-- set by start(): the view chosen now, a manned gun's hold on the camera, its view handed back (WeaponCamera.view)
local viewNow: () -> (number, number, number) = function()
	return 0, 1, 1
end
local manned = false
local handBackTo: (number, number) -> () = function() end

local HEAD = Vector3.new(0, 1.5, 0) -- head centre above the root (R6)
local ROBLOX_MIN = 0.5 -- StarterPlayer.CameraMinZoomDistance: Roblox's first person

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- the hip field of view (the player's setting) and an aimed one at it (Rules/Settings.aimFov)
local function hipFov(): number
	return Settings.get("FieldOfView") :: number
end
local function aimedFov(base: number): number
	return SettingsRules.aimFov(hipFov(), Cfg.Fov, base)
end

local function ease(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

-- whether the weapon in the hands gets the third-person-only camera (Config/Camera.ThirdPersonClasses)
local function thirdPerson(weapon: Held.Weapon?): boolean
	local spec = weapon and (W :: any)[weapon.name]
	return Rules.thirdPerson(Cfg.ThirdPersonClasses, spec and spec.class)
end

-- whether a weapon (by name) keeps Roblox's own camera (Config/Camera.FreeClasses: the shovel)
local function free(name: any): boolean
	local spec = type(name) == "string" and (W :: any)[name]
	return Rules.thirdPerson(Cfg.FreeClasses, spec and spec.class)
end

-- the nearest Roblox's camera may come: further out with a free-camera weapon in the hands
local function minZoom(character: Model?): number
	local weapon = Held.weapon(character)
	return if weapon and free(weapon.name) then Cfg.FreeMinZoom else ROBLOX_MIN
end

-- whether the weapon in the hands aims where the view is, not always in first person (the staff)
local function inPlace(weapon: Held.Weapon?): boolean
	local spec = weapon and (W :: any)[weapon.name]
	return Rules.thirdPerson(Cfg.AimInPlace, spec and spec.class)
end

function WeaponCamera.start()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local active = false
	local zoom = 0 -- Roblox's camera distance when the weapon came out (handed back when it goes away)
	local yaw, pitch = 0, 0 -- degrees
	-- drawing the weapon: the camera eases in from where Roblox's camera was (relative to the root)
	local from: Vector3? = nil
	local blend = 1
	-- putting it away: the glide back out (from where the camera was, relative to the root; 0..1)
	local leaving = false
	local leaveFrom = Vector3.zero
	local leaveT = 0
	local pinned = false -- the zoom handed back is held for a moment (finish)
	-- the staff's third person (Config/Camera.Staff): the eased distance (0: at the eye), the shoulder blend (0 centred
	-- .. 1 over the right shoulder), the last click
	local third = false
	local fresh = false -- just drawn: set the view once the weapon is known
	local current, shoulder = 0, 0
	local currentSpeed = 0 -- the distance's spring velocity
	local clicked = -math.huge
	-- a gun's chosen distance (0: first person; Config/Camera.Gun)
	local gunZoom = 0
	local G = Cfg.Gun
	local S = Cfg.Staff
	local sweep = RaycastParams.new()
	sweep.FilterType = Enum.RaycastFilterType.Exclude
	sweep.RespectCanCollide = true

	local function parts(): (Model?, Humanoid?, BasePart?)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return character, humanoid, root
	end

	-- the whole body (with what it wears and holds) at one local transparency, the head (with its face and hats) at
	-- its own; others always see it whole
	local function show(character: Model, body: number, head: number?)
		-- seen through, only the outer model shows (user 2026-10-18): under a helmet the hair, the head and the species
		-- ears (user 2026-10-21: they showed through it aiming in) are hidden whenever the head is faded at all, so they
		-- never show through the see-through helmet (src/server/Helmets)
		local helmeted = character:GetAttribute("HelmetOn") == true
		local hair = character:FindFirstChild("Hair")
		for _, d in character:GetDescendants() do
			if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
				local part = if d:IsA("Decal") then d.Parent else d
				local onHead = part ~= nil
					and (
						part.Name == "Head"
						or part.Name == "FaceCard"
						or part:FindFirstAncestorOfClass("Accessory") ~= nil
						or part:FindFirstAncestor("Ears") ~= nil -- species ears (src/server/Species)
					)
				local t = if onHead and head then head else body
				local inside = part ~= nil
					and (
						part.Name == "Head"
						or part.Name == "FaceCard"
						or (hair ~= nil and part:IsDescendantOf(hair))
						or part:FindFirstAncestor("Ears") ~= nil
					)
				if helmeted and inside and t > 0 then
					t = 1
				end
				(d :: any).LocalTransparencyModifier = t
			end
		end
	end

	local function enter()
		active, leaving = true, false
		local _, _, root = parts()
		-- remember Roblox's zoom, and glide in from where its camera was
		zoom = (camera.CFrame.Position - camera.Focus.Position).Magnitude
		gunZoom = Rules.drawn(G, zoom)
		if root then
			from, blend = camera.CFrame.Position - root.Position, 0
		end
		local look = camera.CFrame.LookVector
		yaw = math.deg(math.atan2(-look.X, -look.Z))
		pitch = math.clamp(math.deg(math.asin(look.Y)), -Cfg.PitchLimit, Cfg.PitchLimit)
		camera.CameraType = Enum.CameraType.Scriptable
		fresh, shoulder, clicked = true, 0, -math.huge
	end

	-- hands Roblox's camera back (at once, or at the end of the glide out)
	local function finish(character: Model?, _humanoid: Humanoid?)
		active, leaving = false, false
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = hipFov()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		if character then
			character:SetAttribute("CameraMode", nil)
			character:SetAttribute("CameraInside", nil)
			character:SetAttribute("Handover", nil)
			show(character, 0)
		end
		-- hand the zoom back: Roblox's camera has no zoom setter, so pin its range for a frame
		local d = math.clamp(zoom, minZoom(character), Cfg.FreeMaxZoom)
		player.CameraMinZoomDistance, player.CameraMaxZoomDistance = d, d
		pinned = true
		task.delay(0.1, function()
			pinned = false
			player.CameraMinZoomDistance, player.CameraMaxZoomDistance = minZoom(player.Character), Cfg.FreeMaxZoom
		end)
	end

	-- the weapon is away: glide back out from the eye (user 2026-10-14: "smoothly go back to where my camera was");
	-- dead, at once
	local function leave(character: Model?, humanoid: Humanoid?)
		local _, _, root = parts()
		if not character or not humanoid or humanoid.Health <= 0 or not root then
			finish(character, humanoid)
			return
		end
		active, leaving = false, true
		leaveFrom, leaveT = camera.CFrame.Position - root.Position, 0
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		character:SetAttribute("CameraMode", nil)
		character:SetAttribute("CameraInside", nil)
		character:SetAttribute("Handover", nil)
	end

	viewNow = function()
		if active or leaving then
			return gunZoom, G.FirstBelow, G.MaxZoom
		end
		return (camera.CFrame.Position - camera.Focus.Position).Magnitude, G.FirstBelow, Cfg.FreeMaxZoom
	end
	handBackTo = function(distance: number, max: number)
		local character = player.Character
		zoom = if distance <= 0 then ROBLOX_MIN else distance / max * Cfg.FreeMaxZoom
		finish(character, character and character:FindFirstChildOfClass("Humanoid"))
	end

	-- the staff in third person: a click brings the shoulder view for a moment
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and active and Settings.pressed("Key_Fire", input) then
			clicked = os.clock()
		end
	end)
	-- a gun: the wheel steps between first person and the shoulder view (the zoom handed back when it goes away)
	UserInputService.InputChanged:Connect(function(input, processed)
		if
			processed
			or not active
			or third
			or input.UserInputType ~= Enum.UserInputType.MouseWheel
			or player:GetAttribute("MenuOpen") == true
		then
			return
		end
		gunZoom = Rules.wheel(G, gunZoom, input.Position.Z)
		zoom = if gunZoom > 0 then gunZoom else ROBLOX_MIN
	end)

	-- the camera from `origin` (the head) out to `goal`, stopped by walls: a sphere swept between them (world space);
	-- and whether a wall stopped it
	local function blocked(character: Model, origin: Vector3, goal: Vector3): (Vector3, boolean)
		local span = goal - origin
		if span.Magnitude < 1e-3 then
			return goal, false
		end
		sweep.FilterDescendantsInstances = { character, camera }
		local hit = workspace:Spherecast(origin, S.Radius, span, sweep)
		return if hit then origin + span.Unit * hit.Distance else goal, hit ~= nil
	end

	-- before the look tilt: turn with the mouse, face the body
	RunService:BindToRenderStep("WeaponCameraInput", Enum.RenderPriority.Input.Value + 1, function()
		local character, humanoid, root = parts()
		-- a weapon in the hands, one going over the shoulder (src/client/Locomotion "Stowing") or the last grenade's throw
		-- playing out after it left the hand (src/client/Grenades "Throwing"); not the shovel (Config/Camera.FreeClasses:
		-- Roblox's camera stays, held out at FreeMinZoom)
		if manned then
			-- on a machine gun (src/client/Artillery): its camera
			active, leaving = false, false
			return
		end
		local held = Held.weapon(character)
		local stowing = character and character:GetAttribute("Stowing")
		local want = character
			and humanoid
			and root
			and humanoid.Health > 0
			and (
				(held ~= nil and not free(held.name))
				or (stowing ~= nil and not free(stowing))
				or character:GetAttribute("Throwing") == true
			)
		if not active and not leaving and not pinned then
			local near = minZoom(character)
			if player.CameraMinZoomDistance ~= near then
				player.CameraMinZoomDistance = near
			end
		end
		if want and not active then
			enter()
		elseif not want and active then
			leave(character, humanoid)
		end
		if leaving and (not character or not humanoid or humanoid.Health <= 0) then
			finish(character, humanoid)
		end
		if not active or not character or not humanoid or not root then
			return
		end
		local weapon = Held.weapon(character)
		if weapon then -- (putting it away, "Stowing": the view it had stays)
			local wants = thirdPerson(weapon)
			if fresh or wants ~= third then
				third = wants
				if fresh then
					current, currentSpeed = if third then S.Distance else gunZoom, 0
				end
				fresh = false
			end
		end
		local aiming = character:GetAttribute("Aiming") == true
		if player:GetAttribute("MenuOpen") == true then
			-- the settings menu: a free cursor, the view held
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			local delta = UserInputService:GetMouseDelta()
			local sx, sy = SettingsRules.look(
				Cfg.Sensitivity * (if aiming then Cfg.AimSensitivity else 1),
				Settings.get(if aiming then "AimSensitivity" else "HipSensitivity") :: number,
				Settings.get("InvertY") == "On"
			)
			yaw -= delta.X * sx
			pitch = math.clamp(pitch - delta.Y * sy, -Cfg.PitchLimit, Cfg.PitchLimit)
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false -- no cursor or crosshair (user 2026-10-12)
		end
		camera.CFrame = CFrame.new(camera.CFrame.Position) * CFrame.fromOrientation(math.rad(pitch), math.rad(yaw), 0)
		-- (the body turns toward the view in src/client/BodyTurn)
		-- a gun is "Third" as soon as it heads out over the shoulder (the chosen distance, not the moving one, so the mode
		-- never flickers while the spring settles)
		character:SetAttribute(
			"CameraMode",
			if third then (if aiming then "ThirdAim" else "Third") else Rules.gunView(gunZoom, aiming, inPlace(weapon))
		)
	end)

	-- after the look tilt has posed the gun: place the camera
	RunService:BindToRenderStep("WeaponCameraPlace", LookTilt.Priority + 1, function(dt)
		local character, humanoid0, root = parts()
		if manned then
			return
		end
		if leaving and character and root then
			-- the glide back out: to where Roblox's camera sits at the zoom it had, looking the same way, the body
			-- fading back in as the camera leaves the head
			leaveT = math.min(1, leaveT + dt / Cfg.LeaveBlend)
			local rotation = CFrame.fromOrientation(math.rad(pitch), math.rad(yaw), 0)
			local head = root.Position + HEAD
			local d = math.clamp(zoom, minZoom(character), Cfg.FreeMaxZoom)
			local rel = leaveFrom:Lerp(head - rotation.LookVector * d - root.Position, smooth(leaveT))
			camera.CFrame = CFrame.new(root.Position + rel) * rotation
			camera.Focus = CFrame.new(head)
			camera.FieldOfView += (hipFov() - camera.FieldOfView) * (1 - math.exp(-Cfg.Ease * dt))
			-- no fade (user 2026-10-25: only a wall in the camera's way sees through the body): hidden while the camera is
			-- still inside the head, solid from there out
			local near = (camera.CFrame.Position - head).Magnitude
			show(character, if near < Cfg.Handover.near then 1 else 0)
			if leaveT >= 1 then
				finish(character, humanoid0)
			end
			return
		end
		local weapon = character and Held.weapon(character)
		local stowing = character ~= nil
			and (character:GetAttribute("Stowing") ~= nil or character:GetAttribute("Throwing") == true)
		if not active or not character or not root or not (weapon or stowing) then
			return
		end
		local view = character:GetAttribute("CameraMode")
		local rotation = CFrame.fromOrientation(math.rad(pitch), math.rad(yaw), 0)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local head = root.Position + HEAD + (if humanoid then humanoid.CameraOffset else Vector3.zero) -- lower crouched
		-- a steady eye on the upright body (lowered when crouched), not the animated head: the sprint's lean threw the
		-- head, and the camera with it, ~0.7 studs forward going into a sprint. The view's motion is the sway layer's
		-- small step bob (Sway.camera), as in the user's reference
		local eye = HEAD + Vector3.new(Cfg.Eye[1], Cfg.Eye[2], 0)
		local target = CFrame.new(root.Position + eye + (if humanoid then humanoid.CameraOffset else Vector3.zero))
			* CFrame.fromOrientation(0, math.rad(yaw), 0)
			* Vector3.new(0, 0, Cfg.Eye[3])
		local rel = target - root.Position
		local headPart = character:FindFirstChild("Head") :: BasePart?
		local ragdolled = character:GetAttribute("Ragdolled") == true and headPart ~= nil
		if ragdolled and headPart then
			rel = headPart.Position - root.Position -- down: the eye goes with the tumbling head
		end
		-- out behind the head to the distance (the staff's fixed one, over the shoulder while firing; a gun's chosen one,
		-- always over the shoulder, first person while aiming), on a spring; near the eye it blends from the eye to the
		-- head centre, so going in or out is one smooth move
		local aiming = character:GetAttribute("Aiming") == true
		local want = if third then Rules.target(S, aiming) else Rules.gunTarget(gunZoom, aiming, inPlace(weapon))
		current, currentSpeed = Rules.spring(current, currentSpeed, want, if third then S.ZoomEase else G.Spring, dt)
		if current < 0.02 and want <= 0 then
			current, currentSpeed = 0, 0
		end
		current = math.max(current, 0)
		local walled = false -- a wall stopped the camera short this frame (the only time the body is seen through)
		local firing = Rules.shoulder(S, aiming, character:GetAttribute("Casting") == true, os.clock() - clicked)
		local side = if want > 0 and (not third or firing) then 1 else 0
		shoulder += (side - shoulder) * ease(S.ShoulderEase, dt)
		if current > 0 then
			local over = if third then S.Shoulder else G.Shoulder
			local k = math.clamp(current / (if third then S.EyeBlend else G.EyeBlend), 0, 1)
			local pivot = if ragdolled and headPart then headPart.Position - root.Position else head - root.Position
			local base = rel:Lerp(pivot, k)
			local out = rotation.RightVector * (over[1] * shoulder * k)
				+ Vector3.yAxis * (over[2] * shoulder * k)
				- rotation.LookVector * current
			local at
			at, walled = blocked(character, root.Position + base, root.Position + base + out)
			rel = at - root.Position
		end
		-- drawn just now: a short glide in from where Roblox's camera was, as long as the first-person aim-in
		if from and blend < 1 then
			blend = math.min(1, blend + dt / Cfg.AimBlend)
			rel = from:Lerp(rel, smooth(blend))
		end
		camera.CFrame = CFrame.new(root.Position + rel) * rotation * Sway.camera(view) -- its small step bob
		camera.Focus = CFrame.new(head)
		local fov = if view == "Aim"
			then aimedFov(Cfg.AimFov)
			elseif view == "ThirdAim" then aimedFov(S.AimFov)
			else hipFov()
		local rate = if view == "Aim" or view == "ThirdAim" then Cfg.AimEase else Cfg.Ease
		camera.FieldOfView += (fov - camera.FieldOfView) * ease(rate, dt)

		-- the body is solid (user 2026-10-25: "the transparency thing should only happen when a wall is blocking the
		-- camera ... remove it everywhere else (zooming in manually, unequipping weapons, staff, etc)"): it fades only
		-- as a wall pushes the camera in toward the head
		local near = (camera.CFrame.Position - head).Magnitude
		if third then
			-- the staff's third person: no viewmodel
			character:SetAttribute("CameraInside", false)
			character:SetAttribute("Handover", 0)
			local close = math.clamp((S.Fade.far - near) / (S.Fade.far - S.Fade.near), 0, 1)
			show(character, if walled then close else 0)
			return
		end
		-- a gun: in first person the body is hidden and the viewmodel shown at once when the camera gets inside the head
		-- (Handover.near), no fade either way; it stays hidden until the viewmodel is on screen (it says so the frame
		-- after it shows), and is solid till then
		local GF = G.Fade
		local close = if walled then math.clamp((GF.far - near) / (GF.far - GF.near), 0, 1) else 0
		local outside = view == "Third" or view == "ThirdAim"
		local inside = not outside and near < Cfg.Handover.near
		character:SetAttribute("CameraInside", not outside)
		character:SetAttribute("Handover", if inside then 1 else 0)
		local body = if inside and character:GetAttribute("ViewmodelShown") == true then 1 else close
		-- Roblox's camera fades the body too when it thinks the camera is near the head: ours is written every frame
		show(character, math.floor(body * GF.Steps + 0.5) / GF.Steps)
	end)

	-- nothing in the hands: Roblox's camera at the chosen field of view too
	camera.FieldOfView = hipFov()
	Settings.changed("FieldOfView", function(v)
		if not active and not leaving then
			camera.FieldOfView = v
		end
	end)
end

-- The view chosen now, for a camera that takes over (the MG nest's gun, src/client/Artillery): its distance (0 first
-- person), the distance under which it is first person, its furthest
function WeaponCamera.view(): (number, number, number)
	return viewNow()
end

-- A machine gun's camera holds the view while it is manned (src/client/Artillery): nothing here moves the camera
function WeaponCamera.manning(on: boolean)
	manned = on
end

-- Getting off a machine gun: Roblox's camera back at the same share of the way out as `distance` of `max` (0: first
-- person)
function WeaponCamera.handBack(distance: number, max: number)
	handBackTo(distance, max)
end

return WeaponCamera
