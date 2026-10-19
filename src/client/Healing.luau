--!strict
-- Healing others (H1; Config/Healing, Rules/Healing; src/server/Healing decides and heals). You never heal yourself:
-- the hurt soldier in reach nearest your look gets a prompt over the head ("[H] Bandage" below 70 health, "[H] Med
-- pack" from 70); the Heal key (Config/Settings Key_Heal) asks the server to start, and again to stop. While the
-- server's "Healing" attribute is on the local soldier: crouched at crouch speed (src/client/Stance), turned to face
-- the patient ("HealPatient"), playing the item's animations (the bandage wraps in circles; the med pack is torn open,
-- then pressed on). Tracks played here replicate to everyone.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Healing)
local DevCfg = require(Shared.Config.DevTools)
local Palette = require(Shared.Config.Palette)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.Healing)
local HealItems = require(Shared.HealItems)
local HealView = require(script.Parent.HealView)
local Settings = require(script.Parent.Settings)

local Healing = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function root(m: Model?): BasePart?
	return m and m:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The hurt soldier in Range nearest the camera's look (within PickCone degrees), and the item they'd get.
local function pick(me: Model): (Model?, string?)
	local mine = root(me)
	if not mine then
		return nil, nil
	end
	local cam = workspace.CurrentCamera.CFrame
	local best, bestKind, bestDot = nil, nil, math.cos(math.rad(Cfg.PickCone))
	local function consider(m: Instance?)
		if not m or m == me or not m:IsA("Model") or not m:IsDescendantOf(workspace) then
			return
		end
		local h = m:FindFirstChildOfClass("Humanoid")
		local r = root(m)
		local kind = h and Rules.kind(h.Health, h.MaxHealth, Cfg)
		if not h or not r or not kind or not Rules.inReach((r.Position - mine.Position).Magnitude, Cfg.Range) then
			return
		end
		local to = r.Position - cam.Position
		local dot = if to.Magnitude > 1e-3 then cam.LookVector:Dot(to.Unit) else -1
		if dot >= bestDot then
			best, bestKind, bestDot = m, kind, dot
		end
	end
	for _, p in Players:GetPlayers() do
		consider(p.Character)
	end
	for _, m in CollectionService:GetTagged(DevCfg.Dummies.Tag) do
		consider(m)
	end
	return best, bestKind
end

local function prompt(): (BillboardGui, TextLabel)
	local P = Cfg.Prompt
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealPrompt"
	gui.Size = UDim2.fromOffset(P.Size[1], P.Size[2])
	gui.StudsOffsetWorldSpace = Vector3.new(0, P.Above, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = rgb(Palette.UI.panel)
	t.BackgroundTransparency = P.Transparency
	t.TextColor3 = rgb(Palette.UI.text)
	t.Font = Enum.Font.GothamBold
	t.TextSize = P.TextSize
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(Palette.UI.outline)
	stroke.Thickness = Palette.UI.stroke
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = t
	t.Parent = gui
	return gui, t
end

function Healing.start()
	local player = Players.LocalPlayer
	local gui, label = prompt()
	gui.Parent = player:WaitForChild("PlayerGui")
	local target: Model? = nil

	local tracks: { [string]: AnimationTrack } = {}
	local animator: Animator? = nil
	local function track(name: string): AnimationTrack?
		local id = Cfg.Animations[name].id
		if not animator or id == 0 then
			return nil
		end
		if not tracks[name] then
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. id
			tracks[name] = animator:LoadAnimation(a)
		end
		return tracks[name]
	end
	local function stopTracks()
		for _, t in tracks do
			t:Stop(Cfg.Fade)
		end
	end

	local turn = 0 -- each heal's own token: a delayed press from an earlier heal never plays
	local function onHealing(character: Model)
		local kind = character:GetAttribute("Healing")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		stopTracks()
		turn += 1
		local token = turn
		if humanoid and kind == nil then
			humanoid.AutoRotate = true
		end
		if kind == nil then
			return
		end
		-- `name` after `delay` seconds, if this heal is still on
		local function later(delay: number, name: string)
			task.delay(math.max(delay - Cfg.Fade, 0), function()
				local t = track(name)
				if t and turn == token and character:GetAttribute("Healing") == kind then
					t:Play(Cfg.Fade)
				end
			end)
		end
		-- the grab from the pack, then the healing itself (the server's health rises from then: Rules.prep)
		later(0, "grab")
		if kind == "Bandage" then
			later(Cfg.Grab.time, "wrap")
		else
			later(Cfg.Grab.time, "open")
			later(Cfg.Grab.time + Cfg.Open.time, "press")
		end
	end

	local function hook(character: Model)
		tracks = {}
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		animator = humanoid:WaitForChild("Animator") :: Animator
		for name in Cfg.Animations do
			track(name) -- preloaded: a first play shows no frozen pose
		end
		character:GetAttributeChangedSignal("Healing"):Connect(function()
			onHealing(character)
		end)
	end
	player.CharacterAdded:Connect(hook)
	if player.Character then
		task.spawn(hook, player.Character)
	end

	local function heal(_, state: Enum.UserInputState): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local character = player.Character
		if character and character:GetAttribute("Healing") ~= nil then
			Net.event("Heal"):FireServer("Stop")
		elseif target then
			Net.event("Heal"):FireServer("Start", target)
		else
			return Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Sink
	end
	local function bind()
		ContextActionService:BindAction("Heal", heal, false, Settings.key("Key_Heal"))
	end
	bind()
	Settings.changed("Key_Heal", bind)

	-- every healer's unrolling strip, toward their left hand (bones don't replicate: each client draws them)
	RunService.RenderStepped:Connect(function()
		for _, p in Players:GetPlayers() do
			local c = p.Character
			if p == player and HealView.isFirst(c) then
				continue -- (in first person the body's item is hidden: src/client/HealView draws its own)
			end
			local at = c and c:GetAttribute("HealAt")
			local item = c and c:GetAttribute("Healing") == "Bandage" and c:FindFirstChild("HealItem")
			local hand = c and c:FindFirstChild("Left Arm") :: BasePart?
			if item and hand and type(at) == "number" then
				HealItems.strip(
					item :: Model,
					hand.CFrame * Vector3.new(0, -1, 0),
					HealItems.unrolled(workspace:GetServerTimeNow() - at)
				)
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local healing = character and character:GetAttribute("Healing") ~= nil
		local kind
		if character and not healing then
			target, kind = pick(character)
		else
			target = nil
		end
		gui.Adornee = target and target:FindFirstChild("Head") :: BasePart?
		gui.Enabled = gui.Adornee ~= nil
		if kind then
			label.Text = `[{Settings.get("Key_Heal")}] {Cfg.Prompt[kind]}`
		end
		-- healing: turn to face the patient
		local link = healing and character and character:FindFirstChild("HealPatient") :: ObjectValue?
		local patient = link and link.Value :: Model?
		local mine, theirs = root(character), root(patient)
		if healing and character then
			-- this module turns the healer to the patient, not the humanoid (src/client/WeaponCamera hands
			-- AutoRotate back when the weapon is put away)
			local hum = character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.AutoRotate = false
			end
		end
		-- (zoomed into first person the player turns themself: src/client/HealView)
		if mine and theirs and not HealView.isFirst(character) then
			local flat = Vector3.new(theirs.Position.X - mine.Position.X, 0, theirs.Position.Z - mine.Position.Z)
			if flat.Magnitude > 1e-3 then
				local want = CFrame.lookAt(mine.Position, mine.Position + flat)
				mine.CFrame = mine.CFrame:Lerp(want, 1 - math.exp(-Cfg.Turn * dt))
			end
		end
	end)
end

return Healing
