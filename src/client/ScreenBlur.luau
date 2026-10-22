--!strict
-- The short screen blur when a bullet passes close (src/client/ShotAudio) or something blows up nearby (every blast
-- shown through src/client/Vfx/Blast). Config/ScreenBlur, Rules/ScreenBlur: strength by distance and size, eased in and
-- out, hits building up but never past the cap. One BlurEffect in the camera, made on the first hit; off with the
-- "ScreenBlur" setting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Audio)
local Cfg = require(Shared.Config.ScreenBlur)
local R = require(Shared.Rules.ScreenBlur)
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

-- A bullet passing `off` studs from the camera, `delay` seconds from now (when it gets there).
function ScreenBlur.pass(off: number, delay: number?)
	local s = R.pass(off, A.Heard.pass.radius, Cfg.Pass.peak, Cfg.Pass.curve)
	if s <= 0 then
		return
	end
	if delay and delay > 0 then
		task.delay(delay, hit, s)
	else
		hit(s)
	end
end

-- A blast at `position` with a fireball `fireball` studs across.
function ScreenBlur.blast(position: Vector3, fireball: number)
	local camera = workspace.CurrentCamera
	if camera then
		hit(R.blast((camera.CFrame.Position - position).Magnitude, fireball, Cfg.Blast))
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
