--!strict
-- The game's own chat panel (Config/Chat, Rules/Chat; channels: src/server/Chat; user 2026-10-30: "build our own simple
-- chat panel underneath the map that works similarily to robloxs ... server, team, and global chat"), top left under
-- the sketch map's place, in Field Grimoire's bare ink (Palette UI.Grimoire): the words in warm shades with a dark
-- edge, an ink wash only while in use. Roblox's chat window and input bar are off; its bubbles stay.
-- - Quiet: the newest lines, fading out FadeAfter seconds after they came; "Press / to chat".
-- - In use (the mouse over it, or typing): every line, the wash, the view tabs (All / Server / Team / Global, a red
--   mark on one with unread lines), the bar with the channel it sends to and, near the limit, the characters used.
-- - / starts typing, Enter sends, Esc leaves; Tab (in the bar) cycles the channel; Rules/Chat reads commands: /t /s /g
--   to send once, /c to change channel, /w name and /r to whisper, /mute and /unmute (here only), /help.
-- - Server lines go to Roblox's general channel, Team to the team's (src/server/Chat), whispers to a channel the server
--   opens for the two, Global to the server (filtered for broadcast, sent to every server).
-- Hidden while the title screen is up (src/client/Menus); shown over the loadout menu (its kit cards leave the left free).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Chat)
local Palette = require(Shared.Config.Palette)
local R = require(Shared.Rules.Chat)
local Net = require(Shared.Net)
local Ink = require(script.Parent.Ink)

local Chat = {}

local GR = (Palette.UI :: any).Grimoire
local P = Cfg.Panel
local FONT = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local function hex(c: { number }): string
	return rgb(c):ToHex()
end

type Line = { label: TextLabel, at: number, kind: string }

local function textLabel(parent: Instance, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = rgb(GR.text)
	l.TextStrokeColor3 = rgb(GR.shade)
	l.TextStrokeTransparency = 0.55
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.RichText = true
	l.Parent = parent
	return l
end

function Chat.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	for _, class in { "ChatWindowConfiguration", "ChatInputBarConfiguration" } do
		local config = TextChatService:FindFirstChild(class) or TextChatService:FindFirstChildOfClass(class :: any)
		if config then
			(config :: any).Enabled = false
		end
	end
	local event = Net.event("Chat")

	-- the panel
	local gui = Instance.new("ScreenGui")
	gui.Name = "Chat"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.BackgroundTransparency = 1
	root.Position = UDim2.fromOffset(P.x, P.y)
	root.Size = UDim2.fromOffset(P.width, P.height)
	root.Parent = gui
	local wash = Ink.slab(root)
	wash.Position = UDim2.fromOffset(-P.pad, -P.pad)
	wash.Size = UDim2.new(1, 2 * P.pad, 1, 2 * P.pad)
	wash.ImageTransparency = 1

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, P.tabs)
	tabs.Parent = root
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	tabLayout.Padding = UDim.new(0, 16)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabs

	local list = Instance.new("ScrollingFrame")
	list.Name = "Lines"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, P.tabs + 4)
	list.Size = UDim2.new(1, 0, 1, -(P.tabs + P.bar + 12))
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = rgb(GR.dim)
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, P.gap)
	layout.Parent = list

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.new(1, 0, 0, P.bar)
	bar.Parent = root
	local barInk = Ink.slab(bar)
	local tag = textLabel(bar, P.tagSize)
	tag.Position = UDim2.fromOffset(12, 0)
	tag.Size = UDim2.new(0, 64, 1, 0)
	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.ClearTextOnFocus = false
	box.FontFace = FONT
	box.TextSize = P.textSize
	box.TextColor3 = rgb(GR.text)
	box.PlaceholderColor3 = rgb(GR.key)
	box.PlaceholderText = "Press / to chat · Tab changes channel"
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Text = ""
	box.Position = UDim2.fromOffset(78, 0)
	box.Size = UDim2.new(1, -150, 1, 0)
	box.ClipsDescendants = true
	box.Parent = bar
	local counter = textLabel(bar, P.tagSize)
	counter.TextXAlignment = Enum.TextXAlignment.Right
	counter.TextColor3 = rgb(GR.key)
	counter.AnchorPoint = Vector2.new(1, 0)
	counter.Position = UDim2.new(1, -12, 0, 0)
	counter.Size = UDim2.new(0, 64, 1, 0)
	local hint = textLabel(root, P.hintSize)
	hint.Text = "Press / to chat"
	hint.TextColor3 = rgb(GR.key)
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 2, 1, -8)
	hint.Size = UDim2.new(1, 0, 0, P.hintSize + 4)

	-- the view tabs
	local view = "All"
	local unread: { [string]: boolean } = {}
	type Tab = { button: TextButton, mark: Frame }
	local tabButtons: { [string]: Tab } = {}
	local sendChannel = "Server"
	local function paintTag()
		tag.Text = sendChannel:upper()
		tag.TextColor3 = rgb(GR.Chat[sendChannel])
	end
	local refreshLines: () -> ()
	local function paintTabs()
		for name, t in tabButtons do
			local on = name == view
			t.button.TextSize = if on then P.tabSize else P.tabSizeOff
			t.button.TextTransparency = if on then 0 else 0.5
			t.mark.Visible = unread[name] == true and not on
		end
	end
	for i, name in Cfg.Views do
		local b = Instance.new("TextButton")
		b.Name = name
		b.AutoButtonColor = false
		b.BackgroundTransparency = 1
		b.FontFace = FONT
		b.Text = name
		b.TextColor3 = rgb(GR.text)
		b.TextStrokeColor3 = rgb(GR.shade)
		b.TextStrokeTransparency = 0.55
		b.AutomaticSize = Enum.AutomaticSize.X
		b.Size = UDim2.fromScale(0, 1)
		b.LayoutOrder = i
		b.Parent = tabs
		local mark = Instance.new("Frame")
		mark.BorderSizePixel = 0
		mark.BackgroundColor3 = rgb(GR.pencil)
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(1, 3, 0.5, -2)
		mark.Size = UDim2.fromOffset(6, 6)
		mark.Visible = false
		mark.Parent = b
		tabButtons[name] = { button = b, mark = mark }
		b.Activated:Connect(function()
			view = name
			unread[name] = nil
			if name ~= "All" then
				sendChannel = name
				paintTag()
			end
			paintTabs()
			refreshLines()
		end)
	end
	paintTag()
	paintTabs()

	-- the lines
	local lines: { Line } = {}
	local order = 0
	local stuckToBottom = true
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local bottom = list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y
		stuckToBottom = list.CanvasPosition.Y >= bottom - 4
	end)
	local function shows(kind: string): boolean
		return view == "All" or kind == view or kind == "Whisper" or kind == "System"
	end
	function refreshLines()
		for _, l in lines do
			l.label.Visible = shows(l.kind)
		end
	end
	local function add(kind: string, rich: string)
		order += 1
		local label = textLabel(list, P.textSize)
		label.TextWrapped = true
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.new(1, -8, 0, 0)
		label.LayoutOrder = order
		label.Text = rich
		label.Visible = shows(kind)
		table.insert(lines, { label = label, at = os.clock(), kind = kind })
		while #lines > Cfg.History do
			table.remove(lines, 1).label:Destroy()
		end
		if not shows(kind) then
			unread[kind] = true
			paintTabs()
		end
		if stuckToBottom then
			task.defer(function()
				list.CanvasPosition = Vector2.new(0, math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y))
			end)
		end
	end
	local function system(text: string)
		add("System", `<font color="#{hex(GR.Chat.System)}">{R.escape(text)}</font>`)
	end
	local function nameOf(userId: number, fallback: string): string
		local p = Players:GetPlayerByUserId(userId)
		local kit = p and p.Character and p.Character:GetAttribute("Kit")
		local colour = type(kit) == "string" and GR.Name[kit]
		local name = R.escape(if p then p.DisplayName else fallback)
		return if colour then `<font color="#{hex(colour)}">{name}</font>` else name
	end
	local function line(kind: string, word: string, who: string, text: string)
		add(kind, `<font size="{P.tagSize}" color="#{hex(GR.Chat[kind] or GR.text)}">{word}</font>  {who}: {text}`)
	end

	-- the channels
	local muted: { [number]: boolean } = {}
	local lastWhisperFrom: number? = nil
	local whisperChannels: { [number]: string } = {}
	local pending: { [number]: { string } } = {}
	local folder = TextChatService:WaitForChild(Cfg.Folder, 30)
	local function teamChannel(): TextChannel?
		if not folder then
			return nil
		end
		for _, c in folder:GetChildren() do
			if c:IsA("TextChannel") and R.channelOf(c.Name, Cfg) == "Team" and c:FindFirstChild(player.Name) then
				return c
			end
		end
		return nil
	end
	local function findPlayer(name: string): Player?
		local n = name:lower()
		local partial: Player? = nil
		for _, p in Players:GetPlayers() do
			if p.Name:lower() == n or p.DisplayName:lower() == n then
				return p
			end
			if not partial and (p.Name:lower():sub(1, #n) == n or p.DisplayName:lower():sub(1, #n) == n) then
				partial = p
			end
		end
		return partial
	end
	local function sendOn(channel: TextChannel?, text: string)
		if not channel then
			system("That channel isn't open yet.")
			return
		end
		task.spawn(function()
			pcall(function()
				channel:SendAsync(text)
			end)
		end)
	end
	local function sendTo(channel: string, text: string)
		if channel == "Server" then
			local channels = TextChatService:FindFirstChild("TextChannels")
			sendOn(channels and channels:FindFirstChild(Cfg.ServerChannel) :: TextChannel?, text)
		elseif channel == "Team" then
			sendOn(teamChannel(), text)
		elseif channel == "Global" then
			event:FireServer("Global", text)
		end
	end
	local function whisper(target: Player, text: string)
		local name = whisperChannels[target.UserId]
		local c = name and folder and folder:FindFirstChild(name) :: TextChannel?
		if c then
			sendOn(c, text)
			return
		end
		pending[target.UserId] = pending[target.UserId] or {}
		table.insert(pending[target.UserId], text)
		event:FireServer("Whisper", target.UserId)
	end
	local function submit(raw: string)
		local cmd = R.parse(raw)
		local text = R.clip(cmd.text or "", Cfg.MaxLength)
		if cmd.kind == "send" then
			sendTo(cmd.channel or sendChannel, text)
		elseif cmd.kind == "switch" then
			sendChannel = cmd.channel :: string
			paintTag()
		elseif cmd.kind == "whisper" or cmd.kind == "reply" then
			local target = if cmd.kind == "reply"
				then (lastWhisperFrom and Players:GetPlayerByUserId(lastWhisperFrom))
				else findPlayer(cmd.name :: string)
			if not target then
				system(
					if cmd.kind == "reply"
						then "Nobody has whispered to you yet."
						else `Nobody called {cmd.name} is here.`
				)
			elseif text == "" then
				system(`Type /w {target.Name} and your message.`)
			else
				whisper(target, text)
			end
		elseif cmd.kind == "mute" or cmd.kind == "unmute" then
			local target = findPlayer(cmd.name :: string)
			if not target then
				system(`Nobody called {cmd.name} is here.`)
			else
				muted[target.UserId] = if cmd.kind == "mute" then true else nil
				system(
					if cmd.kind == "mute" then `{target.DisplayName} is muted.` else `{target.DisplayName} is unmuted.`
				)
			end
		elseif cmd.kind == "help" then
			for _, h in Cfg.Help do
				system(h)
			end
		elseif cmd.kind == "unknown" then
			system(`No command /{cmd.command}. /help lists them.`)
		end
	end

	TextChatService.MessageReceived:Connect(function(msg: TextChatMessage)
		local channel = msg.TextChannel
		local kind = channel and R.channelOf(channel.Name, Cfg)
		local source = msg.TextSource
		if not source or kind == "System" then
			system(msg.Text)
			return
		end
		if not kind or muted[source.UserId] then
			return
		end
		if kind == "Whisper" then
			local a, b = (channel :: TextChannel).Name:match("_(%d+)_(%d+)$")
			local other = if tonumber(a) == player.UserId then tonumber(b) else tonumber(a)
			if source.UserId == player.UserId then
				local p = other and Players:GetPlayerByUserId(other)
				line("Whisper", "TO", nameOf(other or 0, if p then p.Name else "?"), msg.Text)
			else
				lastWhisperFrom = source.UserId
				line("Whisper", "FROM", nameOf(source.UserId, source.Name), msg.Text)
			end
			return
		end
		line(kind, kind:upper(), nameOf(source.UserId, source.Name), msg.Text)
	end)
	local myServer = string.sub(game.JobId, 1, Cfg.Global.tagLength)
	event.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == "Global" and type(a) == "table" then
			if muted[a.u] then
				return
			end
			local word = if a.s ~= myServer and a.s ~= "" then `GLOBAL · {R.escape(tostring(a.s))}` else "GLOBAL"
			local colour = type(a.k) == "string" and GR.Name[a.k]
			local who = R.escape(tostring(a.n))
			line("Global", word, if colour then `<font color="#{hex(colour)}">{who}</font>` else who, R.escape(a.t))
		elseif kind == "Whisper" then
			local queued = pending[a]
			pending[a] = nil
			if not b then
				local p = Players:GetPlayerByUserId(a)
				system(`You can't whisper to {if p then p.DisplayName else "them"}.`)
				return
			end
			whisperChannels[a] = b
			local c = folder and folder:WaitForChild(b, 5) :: TextChannel?
			for _, text in queued or {} do
				sendOn(c, text)
			end
		elseif kind == "Notice" and type(a) == "string" then
			system(a)
		end
	end)

	-- typing
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local t = box.Text
		if t:find("\t") then
			box.Text = (t:gsub("\t", ""))
			sendChannel = R.cycle(sendChannel, Cfg.Send)
			paintTag()
			return
		end
		local clipped = R.clip(t, Cfg.MaxLength)
		if clipped ~= t then
			box.Text = clipped
			return
		end
		local n = utf8.len(t) or #t
		counter.Text = if n >= Cfg.CounterFrom then `{n} / {Cfg.MaxLength}` else ""
	end)
	box.FocusLost:Connect(function(enter)
		if enter then
			local t = box.Text
			box.Text = ""
			submit(t)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.Slash or box:IsFocused() or not gui.Enabled then
			return
		end
		box:CaptureFocus()
		task.defer(function()
			if box.Text == "/" then
				box.Text = ""
			end
		end)
	end)
	local hovering = false
	root.MouseEnter:Connect(function()
		hovering = true
	end)
	root.MouseLeave:Connect(function()
		hovering = false
	end)

	-- each frame: hidden under the menus; in use or quiet; the lines fading by age
	local menus = { "TitleScreen" } -- (the kit-card loadout leaves the left side free: chat while respawning)
	RunService.RenderStepped:Connect(function()
		local h = gui.AbsoluteSize.Y
		if h > 0 then
			scale.Scale = math.clamp(h / 800, P.scale.min, P.scale.max)
		end
		local inMenu = false
		for _, n in menus do
			local g = playerGui:FindFirstChild(n) :: ScreenGui?
			if g and g.Enabled then
				inMenu = true
			end
		end
		gui.Enabled = not inMenu
		local using = hovering or box:IsFocused()
		wash.ImageTransparency = if using then P.washTransparency else 1
		tabs.Visible = using
		bar.Visible = using
		barInk.Visible = using
		hint.Visible = not using
		list.ScrollBarImageTransparency = if using then 0.4 else 1
		local now = os.clock()
		for _, l in lines do
			local t = 0
			if not using then
				local age = now - l.at
				t = if age < Cfg.FadeAfter
					then Cfg.QuietTransparency
					else math.min(1, Cfg.QuietTransparency + (age - Cfg.FadeAfter) / Cfg.FadeTime)
			end
			l.label.TextTransparency = t
			l.label.TextStrokeTransparency = 0.55 + 0.45 * t
		end
	end)
	gui.Parent = playerGui
end

return Chat
