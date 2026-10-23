--!strict
-- The camera shake (Config/CameraShake, Rules/CameraShake; user 2026-10-22: "also make camera shake according to
-- explosions"): kicks added up, each dying away, applied after the camera has been placed.
-- - kick(at, size, reach): a kick of `size` degrees at `at`, falling off to nothing `reach` studs away (the guns' shot);
-- - blast(at, kg): an explosion of `kg` of TNT (src/client/Vfx/Blast.play calls it once for every explosion shown).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.CameraShake)
local Rules = require(Shared.Rules.CameraShake)

local CameraShake = {}

local kicks: { { at: number, size: number } } = {}
local shaking = false

local function step()
	local now = os.clock()
	local sx, sy = 0, 0
	for i = #kicks, 1, -1 do
		local k = kicks[i]
		local t = now - k.at
		local a = Rules.decay(k.size, t, Cfg.time)
		if a then
			sx += a * math.sin(t * Cfg.speed * 1.3)
			sy += a * math.cos(t * Cfg.speed)
		else
			table.remove(kicks, i)
		end
	end
	if #kicks == 0 then
		shaking = false
		RunService:UnbindFromRenderStep("CameraShake")
		return
	end
	local cam = workspace.CurrentCamera
	cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(sy), math.rad(sx), 0)
end

local function add(size: number)
	if size <= 0 then
		return
	end
	table.insert(kicks, { at = os.clock(), size = size })
	if shaking then
		return
	end
	shaking = true
	RunService:BindToRenderStep("CameraShake", Enum.RenderPriority.Camera.Value + 5, step)
end

local function distance(at: Vector3): number
	return (workspace.CurrentCamera.CFrame.Position - at).Magnitude
end

function CameraShake.kick(at: Vector3, size: number, reach: number)
	add(Rules.falloff(size, reach, distance(at)))
end

function CameraShake.blast(at: Vector3, kg: number)
	add(Rules.blast(kg, distance(at), Cfg.Blast))
end

return CameraShake
