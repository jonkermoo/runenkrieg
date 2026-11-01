--!strict
-- Concussion on the own view (src/server/Concussion decides and sends Net "Concussed"; Config/Concussion,
-- Rules/Concussion): a blur and a greyer, dimmer picture, a high ring, every other sound ducked for a moment, all fading
-- out over the concussion's duration. The blur is off with the "ScreenBlur" setting. Ends at death and on a new soldier.
-- (The slower get-up is the server's: src/server/Ragdoll.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Concussion)
local Rules = require(Shared.Rules.Concussion)
local Net = require(Shared.Net)
local Audio = require(script.Parent.Audio)
local Settings = require(script.Parent.Settings)

local Concussion = {}

local blur: BlurEffect? = nil
local grade: ColorCorrectionEffect? = nil
local ring: Sound? = nil
local frame: RBXScriptConnection? = nil
local at, shape = 0, nil :: Rules.Shape?

local function stop()
	if frame then
		frame:Disconnect()
		frame = nil
	end
	shape = nil
	if blur then
		blur.Enabled = false
	end
	if grade then
		grade.Enabled = false
	end
	if ring then
		ring:Stop()
	end
	Audio.duck(1)
end

local function step()
	local s = shape
	if not s then
		return
	end
	local elapsed = os.clock() - at
	local f = Rules.fade(elapsed, s.duration, Cfg.Fade)
	if f <= 0 then
		stop()
		return
	end
	local camera = workspace.CurrentCamera
	local b, g, r = blur :: BlurEffect, grade :: ColorCorrectionEffect, ring :: Sound
	if camera and b.Parent ~= camera then
		b.Parent, g.Parent = camera, camera -- (a new camera)
	end
	b.Size = s.blur * f
	b.Enabled = Settings.get("ScreenBlur") ~= "Off" and b.Size > 0.05
	g.Saturation, g.Brightness = s.saturation * f, s.brightness * f
	r.Volume = s.ring * Rules.fade(elapsed, s.duration, Cfg.RingFade) * Audio.volume()
	Audio.duck(Rules.duck(elapsed, s.duck, s.duckFor, Cfg.Recover))
end

-- Shows a concussion of `strength` (0..1) from now, over whatever was showing.
function Concussion.show(strength: number)
	local s = Rules.shape(strength, Cfg)
	if s.duration <= 0 then
		return
	end
	if not blur then
		local b = Instance.new("BlurEffect")
		b.Name = "Concussion"
		b.Size = 0
		b.Enabled = false
		b.Parent = workspace.CurrentCamera
		blur = b
		local g = Instance.new("ColorCorrectionEffect")
		g.Name = "Concussion"
		g.Enabled = false
		g.Parent = workspace.CurrentCamera
		grade = g
		local r = Instance.new("Sound")
		r.Name = "ConcussionRing"
		r.SoundId = "rbxassetid://" .. Cfg.Ring.id
		r.PlaybackSpeed = Cfg.Ring.speed
		r.Volume = 0
		r.Parent = SoundService -- (flat, outside the ducked group)
		ring = r
	end
	at, shape = os.clock(), s
	local g, r = grade :: ColorCorrectionEffect, ring :: Sound
	g.Enabled = true
	r.TimePosition = 0
	r:Play()
	if not frame then
		frame = RunService.RenderStepped:Connect(step)
	end
	step()
end

function Concussion.start()
	Net.event("Concussed").OnClientEvent:Connect(function(strength: number)
		if type(strength) == "number" then
			Concussion.show(strength)
		end
	end)
	local function spawned(character: Model)
		stop()
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(stop)
		end
	end
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(spawned)
	if player.Character then
		task.spawn(spawned, player.Character)
	end
end

return Concussion
