--!strict
-- The camera while knocked down (Config/Camera.Down; user 2026-11-01: "when knocked down in first person, your
-- character is able to freely see through everything"). Lying on the ground, Roblox's first-person camera sits half a
-- stud behind the head along the view, so looking up put it under the ground, and nothing keeps it out of walls. While
-- the local soldier is "Ragdolled" or getting up ("GetUp"), after every other camera step (Roblox's, src/client/
-- WeaponCamera, the shakes) a sphere is swept from the head out to where the camera was put, and the camera stops short
-- of whatever it hits (Rules/Camera.downReach). A head sunk into the ground starts from just over the surface.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local D = require(Shared.Config.Camera).Down
local Rules = require(Shared.Rules.Camera)

local DownCamera = {}

-- after Roblox's camera (Camera), WeaponCamera and LookTilt (+1), the artillery (+2) and the shakes (+5, +6)
DownCamera.Priority = Enum.RenderPriority.Camera.Value + 7

function DownCamera.start()
	local player = Players.LocalPlayer
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true -- (grass blades, effects and other see-through bits don't count)
	RunService:BindToRenderStep("DownCamera", DownCamera.Priority, function()
		local character = player.Character
		local camera = workspace.CurrentCamera
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if
			not character
			or not camera
			or not head
			or (character:GetAttribute("Ragdolled") ~= true and character:GetAttribute("GetUp") == nil)
		then
			return
		end
		params.FilterDescendantsInstances = { character }
		-- from the head; on or sunk into the ground, from `lift` over its surface (a sweep starting inside the ground
		-- never hits it)
		local origin = head.Position
		local ground = workspace:Raycast(origin + Vector3.yAxis * D.probe, Vector3.yAxis * -(D.probe + D.lift), params)
		if ground then
			origin = ground.Position + ground.Normal * D.lift
		end
		local cf = camera.CFrame
		local out = cf.Position - origin
		local want = out.Magnitude
		if want < 1e-3 then
			return
		end
		local dir = out / want
		local hit = workspace:Spherecast(origin, D.radius, out, params)
		local reach = Rules.downReach(want, if hit then hit.Distance else nil, D.gap)
		if reach < want or origin ~= head.Position then
			camera.CFrame = cf.Rotation + (origin + dir * reach)
		end
	end)
end

return DownCamera
