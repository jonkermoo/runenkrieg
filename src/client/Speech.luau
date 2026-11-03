--!strict
-- The narrator between matches (user 2026-11-02: "a TTS natural voice over with subtitles of a plan"; Config/Cutscenes
-- .Speech, Rules/Cutscenes): a queue of lines spoken one after another, each no earlier than its cue and never over
-- the line before; the subtitle in the bottom bar shows the line being spoken. A line with a recorded clip
-- (Config/NarratorClips: the woman's voice, user 2026-11-03) plays that piece of the one recorded sheet (an
-- AudioPlayer); any other line is Roblox's text-to-speech (AudioTextToSpeech). Both are wired to the device output.
-- A line that fails to load is still shown for as long as it would take.
--   Speech.queue(lines, t0): adds lines whose cues (`at`) count from os.clock() `t0`; they load at once.
--   Speech.stop(): ends the speech and clears the queue. Speech.busy() -> boolean: a line is playing or waiting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Cutscenes)
local Clips = require(Shared.Config.NarratorClips)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Cutscenes)

local Speech = {}

local S = Cfg.Speech
local GR = (Palette.UI :: any).Grimoire

type Item = {
	text: string,
	due: number,
	tts: AudioTextToSpeech?,
	clip: { number }?, -- (start, length) in the recorded sheet
	ready: boolean,
	gen: number,
}
local items: { Item } = {}
local runner: thread? = nil
local gui: ScreenGui? = nil
local label: TextLabel? = nil
local output: AudioDeviceOutput? = nil
local sheet: AudioPlayer? = nil
local gen = 0 -- (a stop makes lines still waiting to load drop themselves)

local function ensure()
	if gui then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "Speech"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = Cfg.DisplayOrder + 1
	local l = Instance.new("TextLabel")
	l.Name = "Subtitle"
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 1 - Cfg.Bars / 2)
	l.Size = UDim2.fromScale(0.8, Cfg.Bars * 0.9)
	l.TextWrapped = true
	l.TextScaled = false
	l.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold)
	l.TextColor3 = Color3.fromRGB(GR.text[1], GR.text[2], GR.text[3])
	l.Text = ""
	l.Parent = g
	local function size()
		l.TextSize = math.max(14, S.subtitle * g.AbsoluteSize.Y / 800)
	end
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(size)
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	size()
	local out = Instance.new("AudioDeviceOutput")
	out.Name = "NarratorOutput"
	out.Parent = g
	if Clips.asset ~= "" then
		local p = Instance.new("AudioPlayer")
		p.Name = "NarratorSheet"
		p.Asset = Clips.asset
		p.Volume = Clips.volume
		p.Parent = g
		local wire = Instance.new("Wire")
		wire.SourceInstance = p
		wire.TargetInstance = out
		wire.Parent = p
		sheet = p
	end
	gui, label, output = g, l, out
end

local function load(item: Item)
	if item.gen ~= gen then
		return
	end
	if item.clip and sheet then
		return -- (the sheet loads once, for every line)
	end
	local tts = Instance.new("AudioTextToSpeech")
	tts.Name = "Narrator"
	tts.Text = item.text
	tts.VoiceId = S.voice
	tts.AutoLocalize = false
	tts.Speed = S.speed
	tts.Pitch = S.pitch
	tts.Volume = S.volume
	tts.Parent = gui
	local wire = Instance.new("Wire")
	wire.SourceInstance = tts
	wire.TargetInstance = output
	wire.Parent = tts
	item.tts = tts
	task.spawn(function()
		local ok, status = pcall(function()
			return tts:LoadAsync()
		end)
		item.ready = ok and status == Enum.AssetFetchStatus.Success
	end)
end

local function run()
	while #items > 0 do
		local item = table.remove(items, 1) :: Item
		local wait = item.due - os.clock()
		if wait > 0 then
			task.wait(wait)
		end
		-- a moment for the voice to load, then speak it (or show it for as long as it would take)
		local t = os.clock()
		local clip, p = item.clip, sheet
		local function ready(): boolean
			return if clip and p then p.IsReady else item.ready
		end
		while not ready() and os.clock() - t < 1.5 do
			task.wait(0.05)
		end
		local tts = item.tts;
		(label :: TextLabel).Text = item.text
		if clip and p and p.IsReady then
			p.TimePosition = clip[1]
			p:Play()
			task.wait(clip[2])
			p:Stop()
		elseif tts and item.ready then
			local done = false
			local conn = tts.Ended:Connect(function()
				done = true
			end)
			tts:Play()
			local limit = os.clock() + math.max(tts.TimeLength, 1) + 2
			while not done and os.clock() < limit do
				task.wait(0.05)
			end
			conn:Disconnect()
		else
			task.wait(Rules.lineSeconds(item.text, S.wordsPerSecond, Clips.clips))
		end
		if tts then
			tts:Destroy()
		end
		(label :: TextLabel).Text = ""
		task.wait(S.gap)
	end
	runner = nil
end

function Speech.queue(lines: { Rules.Line }, t0: number)
	ensure()
	for k, l in lines do
		local item: Item =
			{ text = l.text, due = t0 + l.at, tts = nil, clip = Clips.clips[l.text], ready = false, gen = gen }
		table.insert(items, item)
		-- (the client may ask for 4 voices a second)
		task.delay((k - 1) * 0.3, load, item)
	end
	if not runner then
		runner = task.spawn(run)
	end
end

function Speech.stop()
	gen += 1
	if runner then
		task.cancel(runner :: thread)
		runner = nil
	end
	for _, item in items do
		if item.tts then
			item.tts:Destroy()
		end
	end
	table.clear(items)
	if sheet then
		sheet:Stop()
	end
	if gui then
		for _, c in (gui :: ScreenGui):GetChildren() do
			if c:IsA("AudioTextToSpeech") then
				c:Destroy()
			end
		end
		(label :: TextLabel).Text = ""
	end
end

function Speech.busy(): boolean
	return runner ~= nil
end

return Speech
