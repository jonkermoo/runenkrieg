--!strict
-- Dragging a downed teammate (Config/Dragging, Rules/Dragging; src/server/Dragging decides and pulls the body). The
-- knocked-down, living teammate (the same "Kit": Rules/Teams) in reach nearest your look gets a "[G] Drag" prompt; the
-- Drag key (Config/Settings Key_Drag) asks the server to start, and again to let go. While the server's "Dragging"
-- attribute is on the local soldier: no jumping, the pull animation looping over the walk legs (tracks played here
-- replicate to everyone); the slow walk and no sprint are src/client/Stance's, facing the body src/client/BodyTurn's.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Dragging)
local DevCfg = require(Shared.Config.DevTools)
local Palette = require(Shared.Config.Palette)
local Net = require(Shared.Net)
local Teams = require(Shared.Rules.Teams)
local Settings = require(script.Parent.Settings)

local Dragging = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function root(m: Model?): BasePart?
	return m and m:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The downed, living teammate in Range nearest the camera's look (within PickCone degrees), not already dragged.
local function pick(me: Model): Model?
	local mine = root(me)
	if not mine then
		return nil
	end
	local cam = workspace.CurrentCamera.CFrame
	local best, bestDot = nil, math.cos(math.rad(Cfg.PickCone))
	local function consider(m: Instance?)
		if not m or m == me or not m:IsA("Model") or not m:IsDescendantOf(workspace) then
			return
		end
		local h = m:FindFirstChildOfClass("Humanoid")
		local r = root(m)
		if
			not h
			or not r
			or h.Health <= 0
			or m:GetAttribute("Ragdolled") ~= true
			or m:GetAttribute("Dragged") == true
			or not Teams.same(me:GetAttribute("Kit"), m:GetAttribute("Kit"))
			or (r.Position - mine.Position).Magnitude > Cfg.Range
		then
			return
		end
		local to = r.Position - cam.Position
		local dot = if to.Magnitude > 1e-3 then cam.LookVector:Dot(to.Unit) else -1
		if dot >= bestDot then
			best, bestDot = m, dot
		end
	end
	for _, p in Players:GetPlayers() do
		consider(p.Character)
	end
	for _, m in CollectionService:GetTagged(DevCfg.Dummies.Tag) do
		consider(m)
	end
	return best
end

local function prompt(): BillboardGui
	local P = Cfg.Prompt
	local gui = Instance.new("BillboardGui")
	gui.Name = "DragPrompt"
	gui.Size = UDim2.fromOffset(P.Size[1], P.Size[2])
	gui.StudsOffsetWorldSpace = Vector3.new(0, P.Above, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	local t = Instance.new("TextLabel")
	t.Name = "Text"
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
	return gui
end

function Dragging.start()
	local player = Players.LocalPlayer
	local gui = prompt()
	local label = gui:FindFirstChild("Text") :: TextLabel
	gui.Parent = player:WaitForChild("PlayerGui")
	local target: Model? = nil

	local function hook(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		local animator = humanoid:WaitForChild("Animator") :: Animator
		local pull: AnimationTrack? = nil
		if Cfg.Animation.id ~= 0 then
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. Cfg.Animation.id
			pull = animator:LoadAnimation(a) -- (preloaded: a first play shows no frozen pose)
		end
		character:GetAttributeChangedSignal("Dragging"):Connect(function()
			local on = character:GetAttribute("Dragging") == true
			-- no jumping while dragging (src/client/Jump's own cooldown switches the state, so the jump is zeroed instead)
			if on then
				humanoid:SetAttribute("DragJumpPower", humanoid.JumpPower)
				humanoid:SetAttribute("DragJumpHeight", humanoid.JumpHeight)
				humanoid.JumpPower, humanoid.JumpHeight = 0, 0
			else
				local power, height = humanoid:GetAttribute("DragJumpPower"), humanoid:GetAttribute("DragJumpHeight")
				if type(power) == "number" and type(height) == "number" then
					humanoid.JumpPower, humanoid.JumpHeight = power, height
				end
			end
			if pull then
				if on then
					pull:Play(Cfg.Fade)
				else
					pull:Stop(Cfg.Fade)
				end
			end
		end)
	end
	player.CharacterAdded:Connect(hook)
	if player.Character then
		task.spawn(hook, player.Character)
	end

	local function drag(_, state: Enum.UserInputState): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local character = player.Character
		if character and character:GetAttribute("Dragging") == true then
			Net.event("Drag"):FireServer("Stop")
		elseif target then
			Net.event("Drag"):FireServer("Start", target)
		else
			return Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Sink
	end
	local function bind()
		ContextActionService:BindAction("Drag", drag, false, Settings.key("Key_Drag"))
	end
	bind()
	Settings.changed("Key_Drag", bind)

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local free = character
			and character:GetAttribute("Dragging") ~= true
			and character:GetAttribute("Ragdolled") ~= true
			and character:GetAttribute("Healing") == nil
		target = if character and free then pick(character) else nil
		gui.Adornee = target and target:FindFirstChild("Torso") :: BasePart?
		gui.Enabled = gui.Adornee ~= nil
		label.Text = `[{Settings.get("Key_Drag")}] {Cfg.Prompt.Text}`
	end)
end

return Dragging
