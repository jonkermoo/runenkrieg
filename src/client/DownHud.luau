--!strict
-- Staying down, on screen (Config/Ragdoll.DownHud; layout src/shared/ui/Prompt.json `down` and `mark`, colours
-- Config/Palette.UI.Prompt; user 2026-11-06: "give a hold space to stay down indicator or something when a player is
-- knocked"). The stay-down key itself is src/client/Ragdoll's (Net "StayDown"); this only shows it:
-- - knocked down and alive: a field-note tag low in the middle of the screen, the key, what holding it does, and the
--   seconds left (Rules/Ragdoll.downView): "up in 1.4s" while the get-up wait runs; held, "staying down" with the
--   underline full and draining over the stay-down time (Config/Ragdoll.StayDown.max); dragged, the break-free key.
-- - a marker over each knocked-down, living squad mate near (src/client/Squad; a red cross and DOWN, or HOLDING ON
--   while they hold the key, waiting for a medic or a drag), seen through walls; only your own squad's (user
--   2026-11-09), none while you are in no squad.
-- Off during the match cutscenes and while the admin panel hides the game HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Ragdoll)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Ragdoll)
local Spec = require(Shared.ui.Prompt) :: any
local DevCinematic = require(script.Parent.DevCinematic)
local MatchCutscene = require(script.Parent.MatchCutscene)
local Squad = require(script.Parent.Squad)
local Settings = require(script.Parent.Settings)

local DownHud = {}

local C = Palette.UI.Prompt :: any
local S = Spec.theme.scale
local D = Spec.down
local M = Spec.mark
local H = Cfg.DownHud
local STAY = (Enum.KeyCode :: any)[Cfg.StayDown.key] :: Enum.KeyCode
local FONT = Font.new(
	`rbxasset://fonts/families/{Spec.theme.fonts.body.family}.json`,
	(Enum.FontWeight :: any)[Spec.theme.fonts.body.weight]
)

local player = Players.LocalPlayer

local function rgb(name: string): Color3
	local c = C[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function scale(): number
	local camera = workspace.CurrentCamera
	local h = if camera then camera.ViewportSize.Y else S.referenceHeight
	return math.clamp(h / S.referenceHeight, S.min, S.max)
end

local function frame(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Parent = parent
	return f
end

local function label(parent: Instance, name: string, size: number, color: string, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Size = UDim2.new()
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = rgb(color)
	l.TextStrokeColor3 = rgb("shadow")
	l.TextStrokeTransparency = Spec.text.strokeTransparency
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

local function list(parent: Instance, horizontal: boolean, gap: number)
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
end

local function hudHidden(): boolean
	return MatchCutscene.playing() or DevCinematic.hidden(player, "Hud")
end

-- your own prompt ------------------------------------------------------------------------------------------------------

type Prompt = { gui: ScreenGui, set: (view: Rules.DownView, key: string) -> () }

local function newPrompt(): Prompt
	local gui = Instance.new("ScreenGui")
	gui.Name = "DownHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Enabled = false

	local T = Spec.tag
	local tag = frame(gui, "Tag")
	tag.AnchorPoint = Vector2.new(0.5, 1)
	tag.Position = UDim2.fromScale(D.at[1], D.at[2])
	-- (sized from the row each frame, not AutomaticSize: the underline's fill at full width fed back into an
	-- auto-sized tag and grew it past the screen in Studio)
	tag.Size = UDim2.fromOffset(D.width, 0)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = tag
	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, T.padBottom)
	pad.Parent = tag
	local row = frame(tag, "Row")
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Size = UDim2.new()
	list(row, true, T.gap)

	local cap = label(row, "Key", D.keyText, "keyText", 1)
	cap.AutomaticSize = Enum.AutomaticSize.X
	cap.Size = UDim2.fromOffset(0, D.keyHeight)
	cap.TextXAlignment = Enum.TextXAlignment.Center
	cap.TextStrokeTransparency = 1
	cap.BackgroundColor3 = rgb("key")
	cap.BackgroundTransparency = 0
	local capPad = Instance.new("UIPadding")
	capPad.PaddingLeft, capPad.PaddingRight = UDim.new(0, Spec.key.padX + 2), UDim.new(0, Spec.key.padX + 2)
	capPad.Parent = cap

	local words = frame(row, "Words")
	words.AutomaticSize = Enum.AutomaticSize.XY
	words.Size = UDim2.new()
	words.LayoutOrder = 2
	list(words, false, 0)
	local object = label(words, "Object", Spec.text.object, "object", 1)
	local action = label(words, "Action", Spec.text.action, "action", 2)
	local time = label(row, "Time", D.time, "action", 3)

	-- the underline the width of the tag, and its fill
	local line = frame(tag, "Line")
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.new(0, 0, 1, T.padBottom)
	line.Size = UDim2.new(1, 0, 0, T.line)
	line.BackgroundColor3 = rgb("line")
	line.BackgroundTransparency = T.lineTransparency
	local fill = frame(line, "Fill")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = rgb("fill")
	fill.BackgroundTransparency = 0

	local B = Spec.blocked
	return {
		gui = gui,
		set = function(view: Rules.DownView, key: string)
			uiScale.Scale = scale()
			cap.Text = string.upper(key)
			local s = view.state
			if s == "dragged" then
				object.Text = "BEING DRAGGED"
				action.Text = "Break free once you can stand"
			elseif s == "held" then
				object.Text = "STAYING DOWN"
				action.Text = "Waiting for a medic - let go to get up"
			else
				object.Text = "KNOCKED DOWN"
				action.Text = "Hold to stay down for a medic"
			end
			-- held: the key lit; otherwise dimmed, as a prompt not yet taken
			local lit = s == "held" or s == "dragged"
			cap.BackgroundTransparency = if lit then 0 else B.key * 0.5
			time.Text = if view.left == nil
				then ""
				elseif s == "rising" then string.format("up in %.1fs", view.left)
				else string.format("%ds", math.ceil(view.left))
			time.Visible = view.left ~= nil
			fill.Size = UDim2.fromScale(view.fill, 1)
			local k = uiScale.Scale
			local w, h = row.AbsoluteSize.X / k, row.AbsoluteSize.Y / k
			tag.Size = UDim2.fromOffset(math.max(D.width, w), h + T.padBottom)
		end,
	}
end

-- the teammates' markers ----------------------------------------------------------------------------------------------

type Mark = { gui: BillboardGui, word: TextLabel }

local function newMark(head: BasePart): Mark
	local gui = Instance.new("BillboardGui")
	gui.Name = "DownMark"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.StudsOffsetWorldSpace = Vector3.new(0, M.up, 0)
	gui.Size = UDim2.fromOffset(M.size, M.tall)
	local root = frame(gui, "Canvas")
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale()
	uiScale.Parent = root
	gui.Size = UDim2.fromOffset(M.size * uiScale.Scale, M.tall * uiScale.Scale)
	root.Size = UDim2.fromOffset(M.size, M.tall)

	-- the disc and its cross (two bars), drawn
	local disc = frame(root, "Disc")
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.fromScale(0.5, 0)
	disc.Size = UDim2.fromOffset(M.disc, M.disc)
	disc.BackgroundColor3 = rgb("key")
	disc.BackgroundTransparency = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = disc
	local ring = Instance.new("UIStroke")
	ring.Color = rgb("ring")
	ring.Thickness = Spec.pin.ring
	ring.Transparency = Spec.pin.ringTransparency
	ring.Parent = disc
	for i = 1, 2 do
		local bar = frame(disc, "Cross" .. i)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		local long = M.disc * 0.6
		bar.Size = if i == 1 then UDim2.fromOffset(long, M.bar) else UDim2.fromOffset(M.bar, long)
		bar.BackgroundColor3 = rgb("reason")
		bar.BackgroundTransparency = 0
	end

	local word = label(root, "Word", M.word, "action", 1)
	word.AnchorPoint = Vector2.new(0.5, 0)
	word.Position = UDim2.new(0.5, 0, 0, M.disc + 3)
	word.TextXAlignment = Enum.TextXAlignment.Center
	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, word = word }
end

local marks: { [Model]: Mark } = {}

local function clearMarks()
	for m, k in marks do
		k.gui:Destroy()
		marks[m] = nil
	end
end

-- the knocked-down, living squad mates to mark now, nearest first, at most H.maxMarks within H.range
local function wanted(): { [Model]: BasePart }
	local out: { [Model]: BasePart } = {}
	local mine = player.Character
	if not mine or hudHidden() then
		return out
	end
	local andMe = player:GetAttribute(H.selfAttribute) == true
	local eye = workspace.CurrentCamera.CFrame.Position
	local found: { { m: Model, head: BasePart, d: number } } = {}
	local function consider(m: Instance?)
		if not m or not m:IsA("Model") or not m:IsDescendantOf(workspace) then
			return
		end
		if m:GetAttribute("Ragdolled") ~= true then
			return
		end
		local h = m:FindFirstChildOfClass("Humanoid")
		local head = m:FindFirstChild("Head") :: BasePart?
		if not h or h.Health <= 0 or not head then
			return
		end
		local d = (head.Position - eye).Magnitude
		if d <= H.range then
			table.insert(found, { m = m, head = head, d = d })
		end
	end
	-- only your own squad mates (user 2026-11-09: "dont show the down status thing to everyone. only show it for
	-- your squad mates"): none while you are in no squad
	local key = Squad.key()
	if key then
		for _, e in Squad.everyone() do
			if e.key == key and not e.me then
				consider(e.model)
			end
		end
	end
	if andMe then
		consider(mine)
	end
	table.sort(found, function(a, b)
		return a.d < b.d
	end)
	for i = 1, math.min(#found, H.maxMarks) do
		out[found[i].m] = found[i].head
	end
	return out
end

local function refreshMarks()
	local want = wanted()
	for m, k in marks do
		if not want[m] or k.gui.Adornee ~= want[m] then
			k.gui:Destroy()
			marks[m] = nil
		end
	end
	for m, head in want do
		local k = marks[m] or newMark(head)
		marks[m] = k
		k.word.Text = if m:GetAttribute("StayDown") == true then "HOLDING ON" else "DOWN"
	end
end

function DownHud.start()
	local prompt = newPrompt()
	prompt.gui.Parent = player:WaitForChild("PlayerGui")
	local since = 0
	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local down = character ~= nil
			and humanoid ~= nil
			and humanoid.Health > 0
			and character:GetAttribute("Ragdolled") == true
			and not hudHidden()
		prompt.gui.Enabled = down
		if down and character then
			local dragged = character:GetAttribute("Dragged") == true
			-- the server's word, or the key as held here (the server hears it a moment later)
			local holding = character:GetAttribute("StayDown") == true
				or (UserInputService:IsKeyDown(STAY) and not UserInputService:GetFocusedTextBox())
			local upAt = character:GetAttribute(H.upAtAttribute)
			local view = Rules.downView(
				workspace:GetServerTimeNow(),
				if type(upAt) == "number" then upAt else nil,
				holding,
				dragged,
				Cfg.StayDown
			)
			local key = if dragged then Settings.key("Key_DragEscape").Name else Cfg.StayDown.key
			prompt.set(view, key)
		end
		since += dt
		if since >= H.rate then
			since = 0
			refreshMarks()
		end
	end)
	player.CharacterRemoving:Connect(clearMarks)
end

return DownHud
