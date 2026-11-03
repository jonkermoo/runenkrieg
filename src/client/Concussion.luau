--!strict
-- Concussion and shell shock on the own view (Config/Concussion, Rules/Concussion): a near blast (every blast shown:
-- src/client/Vfx/Blast calls Concussion.near, when its sound gets here), a blast's throw survived and a helmet knocked
-- off (src/server/Concussion sends Net "Concussed"). The picture: blur, a greyer, dimmer picture, dark edges, the view
-- tilted and wobbling, the head thrown by a helmet hit, all fading out, with a pressure thump (near blasts) or a clang
-- (the helmet). The ears, only for a big charge close by (Config/Concussion.Ears: a howitzer shell): a high ring and
-- every other sound muffled (the highs first) and coming back. A second one restarts the picture at the stronger of
-- the two, never adds up; a second ring stops the first. The "ShellShock" setting scales it (0: off); the blur also follows "ScreenBlur". The HUD stays
-- on top. Ends at death and on a new soldier. (The slower get-up is the server's: src/server/Ragdoll.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Concussion)
local AudioCfg = require(Shared.Config.Audio)
local DamageCfg = require(Shared.Config.Damage)
local Rules = require(Shared.Rules.Concussion)
local BlastRules = require(Shared.Rules.Blast)
local Net = require(Shared.Net)
local Audio = require(script.Parent.Audio)
local Settings = require(script.Parent.Settings)

local Concussion = {}

local blur: BlurEffect? = nil
local grade: ColorCorrectionEffect? = nil
local ring: Sound? = nil
local thump: Sound? = nil
local clangs: { Sound } = {}
local edges: ScreenGui? = nil
local frame: RBXScriptConnection? = nil
local state: Rules.State? = nil
local shape: Rules.Shape? = nil
local ears: Rules.State? = nil -- (the ring and the muffle, on their own timing: Config/Concussion.Ears)
local earShape: Rules.Shape? = nil
local snapPitch, snapYaw, side = 0, 0, 1
local life = 0 -- (a near blast still on its way when the soldier died or respawned is dropped)

local function intensity(): number
	return math.clamp((tonumber(Settings.get("ShellShock")) or 100) / 100, 0, 1)
end

local function alive(): BasePart?
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if head and humanoid and humanoid.Health > 0 then
		return head
	end
	return nil
end

local function stop()
	if frame then
		frame:Disconnect()
		frame = nil
		RunService:UnbindFromRenderStep("Concussion")
	end
	state, shape = nil, nil
	ears, earShape = nil, nil
	if blur then
		blur.Enabled = false
	end
	if grade then
		grade.Enabled = false
	end
	if ring then
		ring:Stop()
	end
	if edges then
		edges.Enabled = false
	end
	Audio.duck(1)
	Audio.muffle(0, 0, 0)
end

local function sound(name: string, id: number): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. id
	s.Volume = 0
	s.Parent = SoundService -- (flat, outside the muffled group)
	return s
end

local function edge(parent: Instance, rotation: number, size: UDim2, position: UDim2)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Size, f.Position = size, position
	f.Parent = parent
	local g = Instance.new("UIGradient")
	g.Rotation = rotation -- (dark at the screen's edge, clear inwards)
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = f
end

-- made once and kept (a Sound made when needed plays late)
local function build()
	if blur then
		return
	end
	local camera = workspace.CurrentCamera
	local b = Instance.new("BlurEffect")
	b.Name = "Concussion"
	b.Size = 0
	b.Enabled = false
	b.Parent = camera
	blur = b
	local g = Instance.new("ColorCorrectionEffect")
	g.Name = "Concussion"
	g.Enabled = false
	g.Parent = camera
	grade = g
	ring = sound("ConcussionRing", Cfg.Ring.id) -- (one long take, never looped: a loop's seam is heard)
	thump = sound("ConcussionThump", Cfg.Thump.id)
	for i, id in Cfg.Clang.ids do
		clangs[i] = sound("ConcussionClang", id)
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Concussion"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -10 -- (under the HUD)
	gui.Enabled = false
	local d = Cfg.Vignette.size
	edge(gui, 90, UDim2.fromScale(1, d), UDim2.fromScale(0, 0)) -- top
	edge(gui, 270, UDim2.fromScale(1, d), UDim2.fromScale(0, 1 - d)) -- bottom
	edge(gui, 0, UDim2.fromScale(d, 1), UDim2.fromScale(0, 0)) -- left
	edge(gui, 180, UDim2.fromScale(d, 1), UDim2.fromScale(1 - d, 0)) -- right
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	edges = gui
end

local function step()
	local st, s = state, shape
	if not st or not s then
		return
	end
	local now = os.clock()
	local e = now - st.at
	local f = Rules.held(e, s.hold, s.duration, Cfg.Fade)
	local fr = Rules.held(e, s.hold, s.ringFor, Cfg.RingFade)
	local er, m = 0, 0
	local et, es = ears, earShape
	if et and es then
		local ee = now - et.at
		er = Rules.held(ee, es.hold, es.ringFor, Cfg.RingFade)
		m = Rules.muffle(ee, es, Cfg.Muffle.attack)
	end
	if f <= 0 and fr <= 0 and er <= 0 and m <= 0 then
		stop()
		return
	end
	local k = intensity()
	local camera = workspace.CurrentCamera
	local b, g, r, v = blur :: BlurEffect, grade :: ColorCorrectionEffect, ring :: Sound, edges :: ScreenGui
	if camera and b.Parent ~= camera then
		b.Parent, g.Parent = camera, camera -- (a new camera)
	end
	b.Size = s.blur * fr * k -- (on the ring's timing: as loud as it would be, as blurred)
	b.Enabled = Settings.get("ScreenBlur") ~= "Off" and b.Size > Cfg.Shown.blur
	local flash = s.flash * Rules.kick(e, Cfg.Flash.time)
	g.Saturation = s.saturation * f * k
	g.Brightness = (s.brightness * f + flash) * k
	local dark = s.vignette * f * k
	v.Enabled = dark > Cfg.Shown.vignette
	if v.Enabled then
		for _, child in v:GetChildren() do
			(child :: Frame).BackgroundTransparency = 1 - dark
		end
	end
	r.Volume = if es then es.ring * er * k * Audio.volume() else 0
	if er <= 0 and r.IsPlaying then
		r:Stop()
	end
	local depth = m * k
	local M = Cfg.Muffle
	Audio.muffle(-M.high * depth, -M.mid * depth, M.low * depth)
	Audio.duck(if es and es.muffle > 0 then 1 + (es.duck - 1) * (m / es.muffle) * k else 1)
end

-- after the camera is placed: the head snap, the tilt and the dizzy wobble
local function view()
	local st, s = state, shape
	if not st or not s then
		return
	end
	local e = os.clock() - st.at
	local k = intensity()
	local f = Rules.held(e, s.hold, s.duration, Cfg.Fade) * k
	local kick = Rules.kick(e, Cfg.Snap.time) * s.snap * k
	local w = 2 * math.pi * Cfg.Sway.rate * e
	local W = Cfg.Sway
	local pitch = snapPitch * kick + s.sway * W.pitch.size * f * math.sin(w * W.pitch.rate + W.pitch.phase)
	local yaw = snapYaw * kick + s.sway * W.yaw.size * f * math.sin(w * W.yaw.rate + W.yaw.phase)
	local roll = side * s.tilt * f + s.sway * f * math.sin(w)
	if pitch ~= 0 or yaw ~= 0 or roll ~= 0 then
		local camera = workspace.CurrentCamera
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
	end
end

-- Shows a concussion of `strength` (0..1) and `kind` from now, over whatever was showing (the stronger of the two).
-- `from`: the way a helmet hit travelled (the head is thrown along it); `heard`: a near blast's thump; `rung`: it rings
-- the ears and muffles them too (Config/Concussion.Ears).
function Concussion.show(strength: number, kind: Rules.Kind, from: Vector3?, heard: boolean?, rung: boolean?)
	if not alive() then
		return
	end
	local now = os.clock()
	local st = Rules.add(state, strength, kind, now, Cfg)
	local k = intensity()
	build()
	if heard and strength >= Cfg.Thump.from then
		local t = thump :: Sound
		t.Volume = Cfg.Thump.volume * math.min(strength / Cfg.Thump.full, 1) * k * Audio.volume()
		t.TimePosition = 0
		t:Play()
	end
	if kind == "Helmet" and #clangs > 0 then
		local c = clangs[math.random(#clangs)]
		c.Volume = Cfg.Clang.volume * Audio.volume()
		c.TimePosition = 0
		c:Play()
	end
	if rung then
		local es = Rules.shape(strength, kind, Cfg)
		if es.ringFor > 0 or es.muffle > 0 then
			ears, earShape = { at = now, strength = strength, kind = kind }, es
			-- a new one over a ring still going: the old one stops, the new one starts from the top
			local r = ring :: Sound
			r.PlaybackSpeed = es.pitch
			r:Stop()
			r.TimePosition = 0
			r:Play()
		end
	end
	local s = st and Rules.shape(st.strength, st.kind, Cfg)
	if st and s and (s.duration > 0 or s.ringFor > 0) then
		state, shape = st, s
		side = if math.random() < 0.5 then -1 else 1
		snapPitch, snapYaw = 0, 0
		local camera = workspace.CurrentCamera
		if from and camera and from.Magnitude > 0 then
			-- thrown along the shot: hit from the front, the head goes back (looks up); from the left, it turns right
			local l = camera.CFrame:VectorToObjectSpace(from.Unit)
			snapPitch, snapYaw = math.clamp(l.Z, -1, 1), -math.clamp(l.X, -1, 1)
			if math.abs(snapPitch) + math.abs(snapYaw) < Cfg.Snap.crown then
				snapPitch = 1 -- (straight down on the crown: a nod back all the same)
			end
		end
		(grade :: ColorCorrectionEffect).Enabled = true
	end
	if not state then
		return -- (nothing showing: the ears go with a picture)
	end
	if not frame then
		frame = RunService.RenderStepped:Connect(step)
		RunService:BindToRenderStep("Concussion", Enum.RenderPriority.Camera.Value + 6, view)
	end
	step()
end

-- A blast of `kg` of TNT at `at` (every blast shown, src/client/Vfx/Blast): felt by its overpressure at the own head
-- (Config/Concussion.Near), once its sound gets here; a big one close by rings the ears too (Config/Concussion.Ears).
function Concussion.near(at: Vector3, kg: number)
	local head = alive()
	if not head or kg <= 0 then
		return
	end
	local d = (head.Position - at).Magnitude
	local strength = Rules.near(BlastRules.kpa(d, kg, DamageCfg.Blast), Cfg.Near)
	if strength <= 0 then
		return
	end
	local rung = Rules.ears(kg, d, Cfg.Ears)
	local mine = life
	task.delay(d / AudioCfg.Heard.speed, function()
		if life == mine then
			Concussion.show(strength, "Blast", nil, true, rung)
		end
	end)
end

function Concussion.start()
	Net.event("Concussed").OnClientEvent:Connect(function(strength: number, kind: any, from: any)
		if type(strength) == "number" and (kind == "Blast" or kind == "Helmet") then
			Concussion.show(strength, kind, if typeof(from) == "Vector3" then from else nil)
		end
	end)
	local function spawned(character: Model)
		life += 1
		stop()
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				life += 1
				stop()
			end)
		end
	end
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(spawned)
	if player.Character then
		task.spawn(spawned, player.Character)
	end
end

return Concussion
