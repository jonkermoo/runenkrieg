--!strict
-- The camera while a weapon is in the hands (Config/Camera; user 2026-10-12: no third-person shoulder camera, a weapon
-- in the hands is always first person):
-- - first person at the eye, the body turning with it (mouse locked to the centre, no cursor or crosshair); right
--   mouse aims down the sights (src/client/Stance), still first person with a narrower view;
-- - drawing a weapon glides the camera in from wherever Roblox's camera was, the body fading out as the viewmodel
--   (src/client/Viewmodel) fades in near the eye, the head first so it never fills the view; putting the weapon away
--   hands Roblox's camera back at the zoom it had;
-- - the whole body stays hidden from the player while inside: the viewmodel shows the first-person holds;
-- - ragdolled ("Ragdolled", src/client/Ragdoll): the body isn't turned with the view and the eye rides the head.
-- Writes the view to the character's "CameraMode" attribute (local): "First" or "Aim"; "CameraInside" (the viewmodel
-- is on) and "Handover" (0..1, how far the viewmodel has faded in).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Camera)
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

function WeaponCamera.start()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local active = false
	local zoom = 0 -- Roblox's camera distance when the weapon came out (handed back when it goes away)
	local yaw, pitch = 0, 0 -- degrees
	-- drawing the weapon: the camera eases in from where Roblox's camera was (relative to the root)
	local from: Vector3? = nil
	local blend = 1

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
		active = true
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
	end

	local function leave(character: Model?, humanoid: Humanoid?)
		active = false
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

	-- before the look tilt: turn with the mouse, face the body
	RunService:BindToRenderStep("WeaponCameraInput", Enum.RenderPriority.Input.Value + 1, function()
		local character, humanoid, root = parts()
		local want = character and humanoid and root and humanoid.Health > 0 and Held.weapon(character) ~= nil
		if want and not active then
			enter()
		elseif not want and active then
			leave(character, humanoid)
		end
		if not active or not character or not humanoid or not root then
			return
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
		character:SetAttribute("CameraMode", if aiming then "Aim" else "First")
	end)

	-- after the look tilt has posed the gun: place the camera
	RunService:BindToRenderStep("WeaponCameraPlace", LookTilt.Priority + 1, function(dt)
		local character, _, root = parts()
		local weapon = character and Held.weapon(character)
		if not active or not character or not root or not weapon then
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
		-- drawn just now: a short glide in from where Roblox's camera was, as long as the first-person aim-in
		local rel = target - root.Position
		local headPart = character:FindFirstChild("Head") :: BasePart?
		if character:GetAttribute("Ragdolled") == true and headPart then
			rel = headPart.Position - root.Position -- down: the eye goes with the tumbling head
		end
		if from and blend < 1 then
			blend = math.min(1, blend + dt / Cfg.AimBlend)
			rel = from:Lerp(rel, smooth(blend))
		end
		camera.CFrame = CFrame.new(root.Position + rel) * rotation * Sway.camera(view) -- its small step bob
		camera.Focus = CFrame.new(head)
		local fov = if view == "Aim" then Cfg.AimFov else Cfg.Fov
		local ease = if view == "Aim" then Cfg.AimEase else Cfg.Ease
		camera.FieldOfView += (fov - camera.FieldOfView) * (1 - math.exp(-ease * dt))

		-- the body fades as the camera nears it; over the last stretch to the eye the viewmodel fades in while the body
		-- fades out, the head first
		local near = (camera.CFrame.Position - head).Magnitude
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
