--!strict
-- The camera while a weapon is in the hands (Config/Camera, Metrics.Camera; user 2026-10-11):
-- - equipping locks it over the right shoulder, the body turning with it (mouse locked to the centre);
-- - the mouse wheel steps to first person (forward) or a free third-person orbit (back; the body turns to where it
--   walks, the wheel zooms, and zooming in past the nearest hands back to the shoulder);
-- - aiming down the sights (src/client/Stance) is first person.
-- In first person (and aiming) the camera is the eye; the player's own body arms and weapon are hidden and the
-- viewmodel shows the first-person holds instead (src/client/Viewmodel).
-- Putting the weapon away hands the camera back to Roblox's own. Writes the mode to the character's "CameraMode"
-- attribute (local): "First", "Shoulder", "Free" or "Aim".

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

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function WeaponCamera.start()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local active = false
	local mode = Cfg.DefaultMode
	local yaw, pitch = 0, 0 -- degrees
	local distance = Cfg.FreeDistance
	-- moving between modes: the camera eases from where it was (relative to the root) to the new spot
	local from: Vector3? = nil
	local blend = 1
	local last = Vector3.zero
	local lastView: any = nil
	local shown = ""
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.RespectCanCollide = true

	local function parts(): (Model?, Humanoid?, BasePart?)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return character, humanoid, root
	end

	-- What the camera hides from the local player (others always see the whole soldier): in first person and aiming,
	-- the head with whatever it wears, the arms and the weapon (the viewmodel shows the first-person ones).
	local function hide(character: Model, view: string)
		local inside = view == "First" or view == "Aim"
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				local hidden = inside
					and (
						d.Name == "Head"
						or d.Name == "Left Arm"
						or d.Name == "Right Arm"
						or d:FindFirstAncestorOfClass("Accessory") ~= nil
						or d:FindFirstAncestorOfClass("Tool") ~= nil
					)
				d.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end

	local function enter()
		active = true
		mode = Cfg.DefaultMode
		local _, _, root = parts()
		if root then -- ease in from where Roblox's camera was
			last = camera.CFrame.Position - root.Position
			lastView = nil
		end
		local look = camera.CFrame.LookVector
		yaw = math.deg(math.atan2(-look.X, -look.Z))
		pitch = math.clamp(math.deg(math.asin(look.Y)), -Cfg.PitchLimit, Cfg.PitchLimit)
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local function leave(character: Model?, humanoid: Humanoid?)
		active = false
		shown = ""
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = Cfg.Fov
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if humanoid then
			humanoid.AutoRotate = true
		end
		if character then
			character:SetAttribute("CameraMode", nil)
			hide(character, "")
		end
	end

	-- wheel: forward toward first person, back toward the free orbit
	ContextActionService:BindActionAtPriority("WeaponCameraZoom", function(_, state, input)
		if not active or state ~= Enum.UserInputState.Change then
			return Enum.ContextActionResult.Pass
		end
		local i = table.find(Cfg.Modes, mode) or 2
		if input.Position.Z > 0 then
			if mode == "Free" then
				distance -= Cfg.FreeStep
				if distance < Cfg.FreeMin then
					distance = Cfg.FreeDistance
					mode = "Shoulder"
				end
			else
				mode = Cfg.Modes[math.max(1, i - 1)]
			end
		elseif mode == "Free" then
			distance = math.min(distance + Cfg.FreeStep, Cfg.FreeMax)
		else
			mode = Cfg.Modes[math.min(#Cfg.Modes, i + 1)]
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
		local facing = aiming or mode ~= "Free"
		humanoid.AutoRotate = not facing
		if facing then
			root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, math.rad(yaw), 0)
		end
		character:SetAttribute("CameraMode", if aiming then "Aim" else mode)
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
		local head = root.Position + HEAD
		ray.FilterDescendantsInstances = { character }
		-- a point `offset` from `origin`, stopped short of anything solid in between
		local function clear(origin: Vector3, offset: Vector3): Vector3
			local hit = workspace:Raycast(origin, offset, ray)
			if hit then
				return hit.Position - offset.Unit * Cfg.CollisionMargin
			end
			return origin + offset
		end
		local torso = root.CFrame
			* (root:FindFirstChild("RootJoint") :: Motor6D).C0
			* (root:FindFirstChild("RootJoint") :: Motor6D).Transform
			* (root:FindFirstChild("RootJoint") :: Motor6D).C1:Inverse()

		local target: Vector3
		if view == "Aim" or view == "First" then
			local neck = (character:FindFirstChild("Torso") :: BasePart):FindFirstChild("Neck") :: Motor6D
			target = (torso * neck.C0 * neck.Transform * neck.C1:Inverse()) * v3(Cfg.Eye)
		elseif view == "Free" then
			target = clear(head, rotation:VectorToWorldSpace(Vector3.new(0, 0, distance)))
		else
			local o = M.Camera.ShoulderOffset
			local shoulder =
				clear(head, CFrame.fromOrientation(0, math.rad(yaw), 0):VectorToWorldSpace(Vector3.new(o.X, o.Y, o.Z)))
			target = clear(shoulder, rotation:VectorToWorldSpace(Vector3.new(0, 0, M.Camera.Distance)))
		end
		-- on a change of view, ease from the last spot (relative to the root), then follow exactly
		if view ~= lastView then
			from, blend, lastView = last, 0, view
		end
		local rel = target - root.Position
		if from and blend < 1 then
			blend = math.min(1, blend + dt * Cfg.Ease / 3)
			rel = from:Lerp(rel, smooth(blend))
		end
		last = rel
		camera.CFrame = CFrame.new(root.Position + rel) * rotation * Sway.camera(view) -- its small step bob
		camera.Focus = CFrame.new(head)
		local fov = if view == "Aim" then Cfg.AimFov else Cfg.Fov
		camera.FieldOfView += (fov - camera.FieldOfView) * (1 - math.exp(-Cfg.Ease * dt))
		-- Roblox's camera fades the whole body while the camera is near the head, so this is held every frame there
		local inside = view == "Aim" or view == "First"
		if view ~= shown or inside then
			hide(character, view)
			shown = view
		end
	end)
end

return WeaponCamera
