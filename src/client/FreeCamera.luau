--!strict
-- Roblox's own camera (empty hands, the shovel: src/client/WeaponCamera hands it back) through soldiers (user
-- 2026-11-04: "sometimes cameras gets stuck in a teammates head in third person"; Config/Camera.Through). Roblox's
-- camera already looks past every player's body, but bots aren't players: when a soldier is the first thing between
-- the head and the camera, the camera goes back out to the zoom the player chose, stopped by
-- anything but soldiers (Config/Collision.Camera). Runs just after Roblox's camera, before the shake and the other
-- camera steps.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Camera)
local CollisionCfg = require(Shared.Config.Collision)
local CollisionRules = require(Shared.Rules.Collision)
local Rules = require(Shared.Rules.Camera)

local FreeCamera = {}

local T = Cfg.Through
local FADE_FROM = 2 -- Roblox fades the body in nearer than this (its TransparencyController)

function FreeCamera.start()
	local player = Players.LocalPlayer
	local any = RaycastParams.new()
	any.FilterType = Enum.RaycastFilterType.Exclude
	any.RespectCanCollide = true
	local sweep = RaycastParams.new()
	sweep.FilterType = Enum.RaycastFilterType.Exclude
	sweep.RespectCanCollide = true
	sweep.CollisionGroup = CollisionCfg.Camera

	-- the zoom the player chose: Roblox's camera keeps it to itself (its CameraModule shows nothing), so it is where
	-- the camera sat the last time nothing pulled it in
	local want: number? = nil

	RunService:BindToRenderStep("FreeCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			not camera
			or not character
			or not humanoid
			or camera.CameraType ~= Enum.CameraType.Custom
			or camera.CameraSubject ~= humanoid
			or character:GetAttribute("CameraMode") ~= nil
		then
			return
		end
		local focus = camera.Focus.Position
		local at = (camera.CFrame.Position - focus).Magnitude
		local dir = -camera.CFrame.LookVector
		any.FilterDescendantsInstances = { character, camera }
		local first = workspace:Spherecast(focus, T.radius, dir * math.max(at, want or 0), any)
		if first == nil or first.Distance > at + T.slack then
			want = at -- nothing pulled it in: the zoom chosen
			return
		end
		if want == nil or not CollisionRules.isSoldier(first.Instance.CollisionGroup, CollisionCfg) then
			return -- a wall: Roblox's own stop
		end
		sweep.FilterDescendantsInstances = { character, camera }
		local wall = workspace:Spherecast(focus, T.radius, dir * want, sweep)
		local out = Rules.through(at, want, wall and wall.Distance, true, T.gap, T.slack)
		if not out then
			return
		end
		camera.CFrame = camera.CFrame.Rotation + (focus - camera.CFrame.LookVector * out)
		if at < FADE_FROM and out >= FADE_FROM then
			-- Roblox faded the body for the near camera it chose; it is out again
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") and d.LocalTransparencyModifier > 0 then
					d.LocalTransparencyModifier = 0
				end
			end
		end
	end)
end

return FreeCamera
