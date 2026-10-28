--!strict
-- The game's own interaction prompt, "field note" (Config/Prompts; layout src/shared/ui/Prompt.json; colours
-- Config/Palette.UI.Prompt; user 2026-10-27, options page, picked F), in place of Roblox's look on every prompt the
-- server tags (Style Custom). Roblox still picks the prompt the key will use and still takes the key; this draws:
-- - on that prompt: the pin, a thin line up to the tag (the key cap, the object over the action) and an underline
--   that fills while the key is held (hold prompts only)
-- - on a prompt in reach that can't be used, when no other is up: the same, dimmed, with the red reason
-- - on every other prompt near (Config/Prompts.FarReach, the nearest MaxPins): only its pin
-- Rules/Prompts decides which. One BillboardGui per drawn prompt, made when it shows and dropped when it goes.
--   Prompts.new(adornee) -> Mark { set(view), drop() }: the same look for anything else that asks for a key

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Prompts)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Prompts)
local Spec = require(Shared.ui.Prompt) :: any

local Prompts = {}

local C = Palette.UI.Prompt :: any
local S = Spec.theme.scale
local FONT = Font.new(
	`rbxasset://fonts/families/{Spec.theme.fonts.body.family}.json`,
	(Enum.FontWeight :: any)[Spec.theme.fonts.body.weight]
)

export type View = {
	key: string,
	object: string?,
	action: string,
	state: string, -- "near", "blocked" or "far" (Rules/Prompts.states)
	reason: string?,
	progress: number?, -- 0..1, the hold
}
export type Mark = { set: (view: View) -> (), drop: () -> () }

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

local function corner(parent: Instance, px: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if px then UDim.new(0, px) else UDim.new(0.5, 0)
	c.Parent = parent
end

function Prompts.new(adornee: Instance): Mark
	local W, H = Spec.canvas[1], Spec.canvas[2]
	local px, py = Spec.pin.at[1], Spec.pin.at[2]
	local gui = Instance.new("BillboardGui")
	gui.Name = "FieldNote"
	gui.Adornee = adornee
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = false
	gui.StudsOffset = Vector3.new(0, 0, Cfg.Toward)
	local ox, oy = Rules.offset(px, py, W, H)
	gui.SizeOffset = Vector2.new(ox, oy)

	local root = frame(gui, "Canvas")
	root.Size = UDim2.fromOffset(W, H)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root

	local pin = frame(root, "Pin")
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.fromOffset(px, py)
	pin.BackgroundColor3 = rgb("pin")
	corner(pin)
	local ring = Instance.new("UIStroke")
	ring.Color = rgb("ring")
	ring.Thickness = Spec.pin.ring
	ring.Transparency = Spec.pin.ringTransparency
	ring.Parent = pin

	-- the lead: a bar turned about its own centre (Roblox turns a frame about its centre, not its anchor), so its
	-- centre is set half way along
	local L = Spec.lead
	local a = math.rad(L.angle)
	local endX, endY = px + math.cos(a) * L.length, py + math.sin(a) * L.length
	local lead = frame(root, "Lead")
	lead.AnchorPoint = Vector2.new(0.5, 0.5)
	lead.Position = UDim2.fromOffset((px + endX) / 2, (py + endY) / 2)
	lead.Size = UDim2.fromOffset(L.length, L.thick)
	lead.Rotation = L.angle
	lead.BackgroundColor3 = rgb("lead")
	lead.BackgroundTransparency = L.transparency

	-- the tag, its bottom-left on the lead's end
	local T = Spec.tag
	local tag = frame(root, "Tag")
	tag.AnchorPoint = Vector2.new(0, 1)
	tag.Position = UDim2.fromOffset(endX, endY)
	tag.AutomaticSize = Enum.AutomaticSize.XY
	tag.Size = UDim2.new()
	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, T.padBottom)
	pad.Parent = tag
	local row = frame(tag, "Row")
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Size = UDim2.new()
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, T.gap)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row

	local K = Spec.key
	local cap = label(row, "Key", K.textSize, "keyText", 1)
	cap.AutomaticSize = Enum.AutomaticSize.X
	cap.Size = UDim2.fromOffset(0, K.height)
	cap.TextXAlignment = Enum.TextXAlignment.Center
	cap.TextStrokeTransparency = 1
	cap.BackgroundColor3 = rgb("key")
	cap.BackgroundTransparency = 0
	local capPad = Instance.new("UIPadding")
	capPad.PaddingLeft, capPad.PaddingRight = UDim.new(0, K.padX), UDim.new(0, K.padX)
	capPad.Parent = cap
	corner(cap, K.corner)

	local words = frame(row, "Words")
	words.AutomaticSize = Enum.AutomaticSize.XY
	words.Size = UDim2.new()
	words.LayoutOrder = 2
	local wordList = Instance.new("UIListLayout")
	wordList.SortOrder = Enum.SortOrder.LayoutOrder
	wordList.Parent = words
	local TX = Spec.text
	local object = label(words, "Object", TX.object, "object", 1)
	local action = label(words, "Action", TX.action, "action", 2)
	local reason = label(words, "Reason", TX.reason, "reason", 3)

	-- the underline under the whole tag, and its fill
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
	local F = Spec.far
	local mark: Mark
	mark = {
		set = function(view: View)
			local s = scale()
			uiScale.Scale = s
			gui.Size = UDim2.fromOffset(W * s, H * s)
			local far = view.state == "far"
			local blocked = view.state == "blocked"
			-- the near one in front of walls (as Roblox's was); the pins behind them
			gui.AlwaysOnTop = not far
			local size = if far then F.pin else Spec.pin.size
			pin.Size = UDim2.fromOffset(size, size)
			pin.BackgroundTransparency = if far then F.transparency else 0
			pin.BackgroundColor3 = rgb(if blocked then "reason" else "pin")
			lead.Visible = not far
			tag.Visible = not far
			if far then
				return
			end
			cap.Text = view.key
			cap.BackgroundTransparency = if blocked then B.key else 0
			cap.TextTransparency = if blocked then B.key else 0
			object.Text = string.upper(view.object or "")
			object.Visible = view.object ~= nil and view.object ~= ""
			action.Text = view.action
			action.TextTransparency = if blocked then B.action else 0
			reason.Text = string.upper(view.reason or "")
			reason.Visible = blocked and view.reason ~= nil
			fill.Size = UDim2.fromScale(if blocked then 0 else view.progress or 0, 1)
		end,
		drop = function()
			gui:Destroy()
		end,
	}
	gui.Parent = player:WaitForChild("PlayerGui")
	return mark
end

-- where a prompt is: its part, or its attachment
local function spot(prompt: ProximityPrompt): Vector3?
	local p = prompt.Parent
	if p and p:IsA("BasePart") then
		return p.Position
	elseif p and p:IsA("Attachment") then
		return p.WorldPosition
	end
	return nil
end

function Prompts.start()
	local shown: ProximityPrompt? = nil
	local heldAt: number? = nil
	local marks: { [ProximityPrompt]: Mark } = {}
	local states: { [ProximityPrompt]: string } = {}

	local function view(prompt: ProximityPrompt, state: string): View
		local blocked = prompt:GetAttribute(Cfg.BlockedAttr) :: string?
		return {
			key = prompt.KeyboardKeyCode.Name,
			object = prompt.ObjectText,
			action = prompt.ActionText,
			state = state,
			reason = if blocked then (Cfg.Reasons :: any)[blocked] or blocked else nil,
			progress = if prompt == shown and heldAt
				then Rules.progress(os.clock() - heldAt, prompt.HoldDuration)
				else 0,
		}
	end

	local function refresh()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local want: { [ProximityPrompt]: string } = {}
		if root then
			local seen: { Rules.Seen } = {}
			local byId: { [string]: ProximityPrompt } = {}
			local shownId: string? = nil
			for i, inst in CollectionService:GetTagged(Cfg.Tag) do
				if not inst:IsA("ProximityPrompt") or not inst:IsDescendantOf(workspace) then
					continue
				end
				local at = spot(inst)
				if not at then
					continue
				end
				local id = tostring(i)
				byId[id] = inst
				if inst == shown then
					shownId = id
				end
				local dist = (at - root.Position).Magnitude
				if dist > inst.MaxActivationDistance * Cfg.FarReach and inst ~= shown then
					continue
				end
				table.insert(seen, {
					id = id,
					dist = dist,
					reach = inst.MaxActivationDistance,
					enabled = inst.Enabled,
					blocked = inst:GetAttribute(Cfg.BlockedAttr) :: string?,
					mine = inst:GetAttribute(Cfg.UserAttr) == player.UserId,
				})
			end
			for id, state in Rules.states(seen, shownId, Cfg.FarReach, Cfg.MaxPins) do
				want[byId[id]] = state
			end
		end
		for prompt, mark in marks do
			if not want[prompt] then
				mark.drop()
				marks[prompt] = nil
				states[prompt] = nil
			end
		end
		for prompt, state in want do
			local mark = marks[prompt]
			if not mark then
				local p = prompt.Parent
				if not p then
					continue
				end
				mark = Prompts.new(p)
				marks[prompt] = mark
			end
			states[prompt] = state
			mark.set(view(prompt, state))
		end
	end

	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			shown = prompt
			heldAt = nil
			refresh()
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if prompt == shown then
			shown = nil
			heldAt = nil
			refresh()
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		if prompt == shown then
			heldAt = os.clock()
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		if prompt == shown then
			heldAt = nil
		end
	end)

	local since = 0
	RunService.RenderStepped:Connect(function(dt)
		since += dt
		if since >= Cfg.Check then
			since = 0
			refresh()
		elseif heldAt and shown and marks[shown] then
			marks[shown].set(view(shown, states[shown] or "near"))
		end
	end)
end

return Prompts
