--!strict
-- The camera while a weapon is in the hands (Config/Camera, Metrics.Camera; user 2026-10-11):
-- - over the right shoulder at the selected zoom, the body turning with it (mouse locked to the centre). The wheel
--   zooms in and out over the same range Roblox's camera has; one step in from the nearest zoom is first person;
-- - equipping keeps the zoom Roblox's camera had (first person stays first person; from beyond the shoulder camera's
--   range it comes in to MaxZoom), putting the weapon away hands the same zoom back to Roblox's camera, whose range
--   goes a few studs further (FreeMaxZoom);
-- - aiming down the sights (src/client/Stance) is first person;
-- - first person (and aiming) hides the whole body from the player: the viewmodel shows the first-person holds
--   (src/client/Viewmodel). Out of first person the body fades translucent as the camera comes near it (zoomed in,
--   or pulled in by a wall), so it never blocks the view.
-- Writes the view to the character's "CameraMode" attribute (local): "First", "Shoulder" or "Aim".

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Camera)
local M = require(Shared.Config.Metrics)
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
	local zoom = 7 -- selected distance; 0 = first person
	local shownZoom = 7 -- eased toward `zoom`
	local yaw, pitch = 0, 0 -- degrees
	-- moving between first and third person: the camera eases from where it was (relative to the root)
	local from: Vector3? = nil
	local blend = 1
	local last = Vector3.zero
	local lastView: any = nil
	local fade = -1 -- body transparency last written (-1: not yet)
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.RespectCanCollide = true

	local function parts(): (Model?, Humanoid?, BasePart?)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return character, humanoid, root
	end

	-- the whole body (with what it wears and holds) at one local transparency; others always see it whole
	local function show(character: Model, transparency: number)
		if transparency == fade then
			return
		end
		fade = transparency
		for _, d in character:GetDescendants() do
			if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = transparency
			end
		end
	end

	local function enter()
		active = true
		local _, _, root = parts()
		-- keep the zoom Roblox's camera had
		local d = (camera.CFrame.Position - camera.Focus.Position).Magnitude
		zoom = if d < Cfg.FirstBelow then 0 else math.clamp(d, Cfg.MinZoom, Cfg.MaxZoom)
		shownZoom = zoom
		if root then -- ease in from where Roblox's camera was
			last = camera.CFrame.Position - root.Position
			lastView = nil
		end
		local look = camera.CFrame.LookVector
		yaw = math.deg(math.atan2(-look.X, -look.Z))
		pitch = math.clamp(math.deg(math.asin(look.Y)), -Cfg.PitchLimit, Cfg.PitchLimit)
		fade = -1
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local function leave(character: Model?, humanoid: Humanoid?)
		active = false
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = Cfg.Fov
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if humanoid then
			humanoid.AutoRotate = true
		end
		if character then
			character:SetAttribute("CameraMode", nil)
			fade = -1
			show(character, 0)
		end
		-- hand the zoom back: Roblox's camera has no zoom setter, so pin its range for a frame
		local d = if zoom <= 0 then ROBLOX_MIN else zoom
		player.CameraMinZoomDistance, player.CameraMaxZoomDistance = d, d
		task.delay(0.1, function()
			player.CameraMinZoomDistance, player.CameraMaxZoomDistance = ROBLOX_MIN, Cfg.FreeMaxZoom
		end)
	end

	-- wheel: in toward first person, out to MaxZoom
	ContextActionService:BindActionAtPriority("WeaponCameraZoom", function(_, state, input)
		if not active or state ~= Enum.UserInputState.Change then
			return Enum.ContextActionResult.Pass
		end
		if input.Position.Z > 0 then
			zoom = if zoom <= Cfg.MinZoom + 1e-3 then 0 else math.max(Cfg.MinZoom, zoom * Cfg.ZoomStep)
		else
			zoom = if zoom <= 0 then Cfg.MinZoom else math.min(Cfg.MaxZoom, zoom / Cfg.ZoomStep)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseWheel)

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
		camera.CFrame = CFrame.new(camera.CFrame.Position) * CFrame.fromOrientation(math.rad(pitch), math.rad(yaw), 0)
		humanoid.AutoRotate = false
		root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, math.rad(yaw), 0)
		character:SetAttribute("CameraMode", if aiming then "Aim" elseif zoom <= 0 then "First" else "Shoulder")
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
		ray.FilterDescendantsInstances = { character }
		-- a point `offset` from `origin`, stopped short of anything solid in between
		local function clear(origin: Vector3, offset: Vector3): Vector3
			local hit = workspace:Raycast(origin, offset, ray)
			if hit then
				return hit.Position - offset.Unit * Cfg.CollisionMargin
			end
			return origin + offset
		end

		local inside = view == "Aim" or view == "First"
		local target: Vector3
		if inside then
			-- a steady eye on the upright body (lowered when crouched), not the animated head: the sprint's lean threw
			-- the head, and the camera with it, ~0.7 studs forward going into a sprint. The view's motion is the sway
			-- layer's small step bob (Sway.camera), as in the user's reference
			local eye = HEAD + Vector3.new(Cfg.Eye[1], Cfg.Eye[2], 0)
			target = CFrame.new(root.Position + eye + (if humanoid then humanoid.CameraOffset else Vector3.zero))
				* CFrame.fromOrientation(0, math.rad(yaw), 0)
				* Vector3.new(0, 0, Cfg.Eye[3])
		else
			shownZoom += (math.max(zoom, Cfg.MinZoom) - shownZoom) * (1 - math.exp(-Cfg.Ease * dt))
			local o = M.Camera.ShoulderOffset
			local shoulder =
				clear(head, CFrame.fromOrientation(0, math.rad(yaw), 0):VectorToWorldSpace(Vector3.new(o.X, o.Y, o.Z)))
			target = clear(shoulder, rotation:VectorToWorldSpace(Vector3.new(0, 0, shownZoom)))
		end
		-- between first and third person (and into the sights): a short ease from the last spot, then exact
		if inside ~= (lastView == "Aim" or lastView == "First") or lastView == nil then
			from, blend = last, 0
		end
		lastView = view
		local rel = target - root.Position
		if from and blend < 1 then
			blend = math.min(1, blend + dt / Cfg.Blend)
			rel = from:Lerp(rel, smooth(blend))
		end
		last = rel
		camera.CFrame = CFrame.new(root.Position + rel) * rotation * Sway.camera(view) -- its small step bob
		camera.Focus = CFrame.new(head)
		local fov = if view == "Aim" then Cfg.AimFov else Cfg.Fov
		camera.FieldOfView += (fov - camera.FieldOfView) * (1 - math.exp(-Cfg.Ease * dt))

		-- the body: gone in first person, fading as the camera nears it otherwise
		local near = (camera.CFrame.Position - head).Magnitude
		local t = math.clamp((Cfg.FadeFar - near) / (Cfg.FadeFar - Cfg.FadeNear), 0, 1)
		local want = if inside then 1 else math.floor(t * Cfg.FadeMax * 20 + 0.5) / 20
		-- Roblox's camera fades the body too when it thinks the camera is near the head: hold ours every frame
		fade = -1
		show(character, want)
	end)
end

return WeaponCamera
