--!strict
-- The short screen blur when a bullet passes close (src/client/ShotAudio) or something blows up nearby (every blast
-- shown through src/client/Vfx/Blast), measured from the own soldier's head in any view. Config/ScreenBlur, Rules/ScreenBlur: strength by distance and size, eased in and
-- out, hits building up but never past the cap. One BlurEffect in the camera, made on the first hit; off with the
-- "ScreenBlur" setting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Audio)
local Cfg = require(Shared.Config.ScreenBlur)
local R = require(Shared.Rules.ScreenBlur)
local ShotRules = require(Shared.Rules.ShotAudio)
local Settings = require(script.Parent.Settings)

local ScreenBlur = {}

local effect: BlurEffect? = nil
local level, shown, holdUntil = 0, 0, 0

local function on(): boolean
	return Settings.get("ScreenBlur") ~= "Off"
end

local function frame(dt: number)
	local camera = workspace.CurrentCamera
	local blur = effect :: BlurEffect
	if level <= 0 and shown <= 0 then
		blur.Enabled = false
		return
	end
	level, shown = R.step(level, shown, dt, os.clock() < holdUntil, Cfg.Rise, Cfg.Fall, Cfg.Floor)
	blur.Size = shown * Cfg.MaxSize
	blur.Enabled = shown > 0
	if camera and blur.Parent ~= camera then
		blur.Parent = camera -- a new camera
	end
end

local function hit(strength: number)
	if strength <= 0 or not on() then
		return
	end
	if not effect then
		local blur = Instance.new("BlurEffect")
		blur.Name = "ScreenBlur"
		blur.Size = 0
		blur.Enabled = false
		blur.Parent = workspace.CurrentCamera
		effect = blur
		RunService.RenderStepped:Connect(frame)
	end
	level = R.add(level, strength, Cfg.Stack, Cfg.Cap)
	holdUntil = os.clock() + Cfg.Hold
end

-- Where the blur is measured from: the own soldier's head, so first and third person blur alike (user 2026-11-01: "can
-- we apply blur settings to third person too"; the third-person camera sits well behind the soldier); the camera with
-- no soldier.
local function at(): Vector3?
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if head then
		return head.Position
	end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position
end

local function point(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

-- A shot from `origin` whose bullets (or pellets) ended at `hits`, flying `bullet` studs a second: the nearest one
-- passing the head blurs as it gets there.
function ScreenBlur.shot(origin: Vector3, hits: { Vector3 }, bullet: number)
	local from = at()
	if not from then
		return
	end
	local P = A.Heard.pass
	local best: ShotRules.Pass? = nil
	for _, h in hits do
		local p = ShotRules.pass(point(origin), point(h), point(from), P.radius, P.clear)
		if p and (not best or p.off < best.off) then
			best = p
		end
	end
	if not best then
		return
	end
	local s = R.pass(best.off, P.radius, Cfg.Pass.peak, Cfg.Pass.curve)
	if s <= 0 then
		return
	end
	local delay = best.along / bullet
	if delay > 0 then
		task.delay(delay, hit, s)
	else
		hit(s)
	end
end

-- A blast at `position` with a fireball `fireball` studs across.
function ScreenBlur.blast(position: Vector3, fireball: number)
	local from = at()
	if from then
		hit(R.blast((from - position).Magnitude, fireball, Cfg.Blast))
	end
end

Settings.changed("ScreenBlur", function(value)
	if value == "Off" then
		level, shown = 0, 0
		if effect then
			effect.Enabled = false
		end
	end
end)

return ScreenBlur
