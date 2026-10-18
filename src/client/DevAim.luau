--!strict
-- The aim point the dev test panels act at (DevTargetMenu, DevBlastMenu): what the middle of the screen looks at, within
-- Config/DevTools.AimReach (the server checks the reach again). Skips your own body, the camera's viewmodel and the
-- client-only grass and debris.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.DevTools)

local DevAim = {}

local SKIP = { "ClientGrass", "ClientGrassBlades", "ClientDebris" }

function DevAim.point(): Vector3?
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not camera or not character or not root then
		return nil
	end
	local ignore: { Instance } = { character, camera }
	for _, name in SKIP do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local size = camera.ViewportSize
	local ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	-- (the camera sits behind the body in third person: reach is measured from the body, as the server does)
	local reach = Cfg.AimReach + (camera.CFrame.Position - root.Position).Magnitude
	local hit = workspace:Raycast(ray.Origin, ray.Direction * reach, params)
	if not hit or (hit.Position - root.Position).Magnitude > Cfg.AimReach then
		return nil
	end
	return hit.Position
end

return DevAim
