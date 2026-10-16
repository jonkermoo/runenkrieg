--!strict
-- The camera while a weapon is in the hands (Config/Camera; user 2026-10-12: no third-person shoulder camera, a weapon
-- in the hands is always first person, except the staff: user 2026-10-16, below):
-- - first person at the eye, the body turning with it (mouse locked to the centre, no cursor or crosshair); right
--   mouse aims down the sights (src/client/Stance), still first person with a narrower view;
-- - drawing a weapon glides the camera in from wherever Roblox's camera was, the body fading out as the viewmodel
--   (src/client/Viewmodel) fades in near the eye, the head first so it never fills the view; putting the weapon away
--   stays at the eye while it goes over the shoulder ("Stowing", src/client/Locomotion), then glides back out to
--   where Roblox's camera was at the zoom it had, the body fading back in (Config/Camera.LeaveBlend), and hands it
--   back;
-- - the whole body stays hidden from the player while inside: the viewmodel shows the first-person holds;
-- - ragdolled ("Ragdolled", src/client/Ragdoll): the body isn't turned with the view and the eye rides the head;
-- - the staff (Config/Camera.ThirdPersonClasses, Rules/Camera): third person only, orbiting behind the head at a fixed
--   distance (Staff.Distance, no zooming), the mouse still locked and the body turning with the view, no crosshair.
--   Centred behind the head, over the right shoulder while firing (aiming, charging, a moment after a click); aiming
--   comes in closer with a narrower view. Walls stop the camera (a swept sphere).
-- Writes the view to the character's "CameraMode" attribute (local): "First", "Aim", "Third" or "ThirdAim";
-- "CameraInside" (the viewmodel is on: first person only) and "Handover" (0..1, how far the viewmodel has faded in).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Camera)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Camera)
local Held = require(script.Parent.Held)
local LookTilt = require(script.Parent.LookTilt)
local Sway = require(script.Parent.Sway)

local WeaponCamera = {}

local HEAD = Vector3.new(0, 1.5, 0) -- head centre above the root (R6)
local ROBLOX_MIN = 0.5 -- StarterPlayer.CameraMinZoomDistance: Roblox's first person

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function ease(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

-- whether the weapon in the hands gets the third-person camera (the staff)
local function thirdPerson(weapon: Held.Weapon?): boolean
	local spec = weapon and (W :: any)[weapon.name]
	return Rules.thirdPerson(Cfg.ThirdPersonClasses, spec and spec.class)
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
	-- the staff's third person (Config/Camera.Staff): the eased distance (0: at the eye), the shoulder blend (0 centred
	-- .. 1 over the right shoulder), the last click
	local third = false
	local fresh = false -- just drawn: set the view once the weapon is known
	local current, shoulder = 0, 0
	local clicked = -math.huge
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
		for _, d in character:GetDescendants() do
			if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
				local part = if d:IsA("Decal") then d.Parent else d
				local onHead = part ~= nil
					and (
						part.Name == "Head"
						or part.Name == "FaceCard"
						or part:FindFirstAncestorOfClass("Accessory") ~= nil
					)
				local t = if onHead and head then head else body;
				(d :: any).LocalTransparencyModifier = t
			end
		end
	end

	local function enter()
		active, leaving = true, false
		local _, _, root = parts()
		-- remember Roblox's zoom, and glide in from where its camera was
		zoom = (camera.CFrame.Position - camera.Focus.Position).Magnitude
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
	local function finish(character: Model?, humanoid: Humanoid?)
		active, leaving = false, false
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = Cfg.Fov
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		if humanoid then
			humanoid.AutoRotate = true
		end
		if character then
			character:SetAttribute("CameraMode", nil)
			character:SetAttribute("CameraInside", nil)
			character:SetAttribute("Handover", nil)
			show(character, 0)
		end
		-- hand the zoom back: Roblox's camera has no zoom setter, so pin its range for a frame
		local d = math.clamp(zoom, ROBLOX_MIN, Cfg.FreeMaxZoom)
		player.CameraMinZoomDistance, player.CameraMaxZoomDistance = d, d
		task.delay(0.1, function()
			player.CameraMinZoomDistance, player.CameraMaxZoomDistance = ROBLOX_MIN, Cfg.FreeMaxZoom
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
		humanoid.AutoRotate = true
		character:SetAttribute("CameraMode", nil)
		character:SetAttribute("CameraInside", nil)
		character:SetAttribute("Handover", nil)
	end

	-- the staff in third person: a click brings the shoulder view for a moment
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and active and input.UserInputType == Enum.UserInputType.MouseButton1 then
			clicked = os.clock()
		end
	end)

	-- the camera from `origin` (the head) out to `goal`, stopped by walls: a sphere swept between them (world space)
	local function blocked(character: Model, origin: Vector3, goal: Vector3): Vector3
		local span = goal - origin
		if span.Magnitude < 1e-3 then
			return goal
		end
		sweep.FilterDescendantsInstances = { character, camera }
		local hit = workspace:Spherecast(origin, S.Radius, span, sweep)
		return if hit then origin + span.Unit * hit.Distance else goal
	end

	-- before the look tilt: turn with the mouse, face the body
	RunService:BindToRenderStep("WeaponCameraInput", Enum.RenderPriority.Input.Value + 1, function()
		local character, humanoid, root = parts()
		-- a weapon in the hands, or one going over the shoulder (src/client/Locomotion "Stowing")
		local want = character
			and humanoid
			and root
			and humanoid.Health > 0
			and (Held.weapon(character) ~= nil or character:GetAttribute("Stowing") ~= nil)
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
					current = if third then S.Distance else 0
				end
				fresh = false
			end
		end
		local aiming = character:GetAttribute("Aiming") == true
		local delta = UserInputService:GetMouseDelta()
		local sens = Cfg.Sensitivity * (if aiming then Cfg.AimSensitivity else 1)
		yaw -= delta.X * sens
		pitch = math.clamp(pitch - delta.Y * sens, -Cfg.PitchLimit, Cfg.PitchLimit)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false -- no cursor or crosshair (user 2026-10-12)
		camera.CFrame = CFrame.new(camera.CFrame.Position) * CFrame.fromOrientation(math.rad(pitch), math.rad(yaw), 0)
		humanoid.AutoRotate = false
		if character:GetAttribute("Ragdolled") ~= true then -- a ragdoll tumbles freely
			root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, math.rad(yaw), 0)
		end
		character:SetAttribute(
			"CameraMode",
			if third then (if aiming then "ThirdAim" else "Third") else if aiming then "Aim" else "First"
		)
	end)

	-- after the look tilt has posed the gun: place the camera
	RunService:BindToRenderStep("WeaponCameraPlace", LookTilt.Priority + 1, function(dt)
		local character, humanoid0, root = parts()
		if leaving and character and root then
			-- the glide back out: to where Roblox's camera sits at the zoom it had, looking the same way, the body
			-- fading back in as the camera leaves the head
			leaveT = math.min(1, leaveT + dt / Cfg.LeaveBlend)
			local rotation = CFrame.fromOrientation(math.rad(pitch), math.rad(yaw), 0)
			local head = root.Position + HEAD
			local d = math.clamp(zoom, ROBLOX_MIN, Cfg.FreeMaxZoom)
			local rel = leaveFrom:Lerp(head - rotation.LookVector * d - root.Position, smooth(leaveT))
			camera.CFrame = CFrame.new(root.Position + rel) * rotation
			camera.Focus = CFrame.new(head)
			camera.FieldOfView += (Cfg.Fov - camera.FieldOfView) * (1 - math.exp(-Cfg.Ease * dt))
			-- (as the glide in: hidden near the eye, the head last to show)
			local near = (camera.CFrame.Position - head).Magnitude
			local H = Cfg.Handover
			local body = math.max(
				math.clamp((Cfg.FadeFar - near) / (Cfg.FadeFar - Cfg.FadeNear), 0, 1) * Cfg.FadeMax,
				math.clamp((H.far - near) / (H.far - H.near), 0, 1)
			)
			show(character, body, math.max(body, math.clamp((H.headFar - near) / (H.headFar - H.headNear), 0, 1)))
			if leaveT >= 1 then
				finish(character, humanoid0)
			end
			return
		end
		local weapon = character and Held.weapon(character)
		local stowing = character ~= nil and character:GetAttribute("Stowing") ~= nil
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
		-- the staff's third person: out behind the head to the eased distance, over the shoulder while firing; near the
		-- eye (coming from a gun) it blends from the eye to the head centre, so the switch is one smooth move
		local aiming = character:GetAttribute("Aiming") == true
		local want = if third then Rules.target(S, aiming) else 0
		current += (want - current) * ease(S.ZoomEase, dt)
		if want <= 0 and current < 0.02 then
			current = 0
		end
		local firing = Rules.shoulder(S, aiming, character:GetAttribute("Casting") == true, os.clock() - clicked)
		local side = if third and want > 0 and firing then 1 else 0
		shoulder += (side - shoulder) * ease(S.ShoulderEase, dt)
		if current > 0 then
			local k = math.clamp(current / S.EyeBlend, 0, 1)
			local pivot = if ragdolled and headPart then headPart.Position - root.Position else head - root.Position
			local base = rel:Lerp(pivot, k)
			local out = rotation.RightVector * (S.Shoulder[1] * shoulder * k)
				+ Vector3.yAxis * (S.Shoulder[2] * shoulder * k)
				- rotation.LookVector * current
			rel = blocked(character, root.Position + base, root.Position + base + out) - root.Position
		end
		-- drawn just now: a short glide in from where Roblox's camera was, as long as the first-person aim-in
		if from and blend < 1 then
			blend = math.min(1, blend + dt / Cfg.AimBlend)
			rel = from:Lerp(rel, smooth(blend))
		end
		camera.CFrame = CFrame.new(root.Position + rel) * rotation * Sway.camera(view) -- its small step bob
		camera.Focus = CFrame.new(head)
		local fov = if view == "Aim" then Cfg.AimFov elseif view == "ThirdAim" then S.AimFov else Cfg.Fov
		local rate = if view == "Aim" or view == "ThirdAim" then Cfg.AimEase else Cfg.Ease
		camera.FieldOfView += (fov - camera.FieldOfView) * ease(rate, dt)

		-- the body fades as the camera nears it; over the last stretch to the eye the viewmodel fades in while the body
		-- fades out, the head first
		local near = (camera.CFrame.Position - head).Magnitude
		if view == "Third" or view == "ThirdAim" then
			-- third person: no viewmodel; the whole body fades only once the camera is right at the head
			character:SetAttribute("CameraInside", false)
			character:SetAttribute("Handover", 0)
			show(character, math.clamp((S.Fade.far - near) / (S.Fade.far - S.Fade.near), 0, 1))
			return
		end
		local t = math.clamp((Cfg.FadeFar - near) / (Cfg.FadeFar - Cfg.FadeNear), 0, 1)
		local H = Cfg.Handover
		local handover = math.clamp((H.far - near) / (H.far - H.near), 0, 1)
		character:SetAttribute("CameraInside", true)
		character:SetAttribute("Handover", handover)
		-- fully gone only once the viewmodel is on screen (it says so the frame after it shows)
		local covered = if character:GetAttribute("ViewmodelShown") == true then 1 else Cfg.FadeMax
		local body = math.max(math.floor(t * Cfg.FadeMax * 20 + 0.5) / 20, handover * covered)
		local headFade = math.max(body, math.clamp((H.headFar - near) / (H.headFar - H.headNear), 0, 1))
		-- Roblox's camera fades the body too when it thinks the camera is near the head: ours is written every frame
		show(character, body, headFade)
	end)
end

return WeaponCamera
