--!strict
-- The game's own chat on the server (Config/Chat, Rules/Chat; the panel is src/client/Chat):
-- - a Team channel per team (TextChatService, under Config/Chat.Folder), each player in the one of the kit they play
--   (their soldier's "Kit", else the kit they spawn in next: src/server/Kits), moved when it changes;
-- - whisper channels made on request for two players, where Roblox lets those two chat (CanUsersDirectChatAsync);
-- - Global: a line from a player who may chat is filtered for broadcast (TextService) and published on MessagingService;
--   every server hands what arrives to its players who may chat. Without MessagingService (a Studio test) it stays
--   on this server.
-- Server chat is Roblox's own general channel; TextChatService filters Server, Team and whispers itself.

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Chat)
local U = require(Shared.Config.Uniforms)
local R = require(Shared.Rules.Chat)
local Net = require(Shared.Net)
local Kits = require(script.Parent.Kits)

local ChatServer = {}

local folder: Folder
local teamOf: { [Player]: string } = {}
local canChat: { [Player]: boolean } = {}
local lastGlobal: { [Player]: number } = {}
local lastWhisper: { [Player]: number } = {}
local event: RemoteEvent

local function channel(name: string): TextChannel
	local c = folder:FindFirstChild(name) :: TextChannel?
	if not c then
		local made = Instance.new("TextChannel")
		made.Name = name
		made.Parent = folder
		c = made
	end
	return c :: TextChannel
end

-- puts `player` in the Team channel of the kit they play now
local function placeTeam(player: Player)
	local character = player.Character
	local kit = character and character:GetAttribute("Kit")
	if type(kit) ~= "string" then
		kit = Kits.next(player)
	end
	if teamOf[player] == kit then
		return
	end
	local old = teamOf[player]
	teamOf[player] = kit
	if old then
		local oc = folder:FindFirstChild(R.teamChannel(old, Cfg))
		local source = oc and oc:FindFirstChild(player.Name)
		if source then
			source:Destroy()
		end
	end
	pcall(function()
		channel(R.teamChannel(kit, Cfg)):AddUserAsync(player.UserId)
	end)
end

local function notice(player: Player, text: string)
	event:FireClient(player, "Notice", text)
end

local function deliverGlobal(line: any)
	for p, ok in canChat do
		if ok and p.Parent then
			event:FireClient(p, "Global", line)
		end
	end
end

local function sendGlobal(player: Player, raw: any)
	if type(raw) ~= "string" or not canChat[player] then
		return
	end
	local now = os.clock()
	if now - (lastGlobal[player] or -math.huge) < Cfg.Global.cooldown then
		notice(player, "Wait a moment before sending to Global again.")
		return
	end
	lastGlobal[player] = now
	local text = R.clip(R.parse(raw).text or "", Cfg.MaxLength)
	if text == "" then
		return
	end
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(filtered) ~= "string" then
		notice(player, "Your message couldn't be sent.")
		return
	end
	local character = player.Character
	local kit = character and character:GetAttribute("Kit") or teamOf[player]
	local line = {
		u = player.UserId,
		n = player.DisplayName,
		k = if type(kit) == "string" then kit else nil,
		t = filtered,
		s = string.sub(game.JobId, 1, Cfg.Global.tagLength),
	}
	local sent = pcall(function()
		MessagingService:PublishAsync(Cfg.Global.topic, line)
	end)
	if not sent then
		deliverGlobal(line)
	end
end

local function openWhisper(player: Player, userId: any)
	if type(userId) ~= "number" then
		return
	end
	local now = os.clock()
	if now - (lastWhisper[player] or -math.huge) < Cfg.WhisperCooldown then
		return
	end
	lastWhisper[player] = now
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player then
		event:FireClient(player, "Whisper", userId, nil)
		return
	end
	local ok, allowed = pcall(function()
		return TextChatService:CanUsersDirectChatAsync(player.UserId, { target.UserId })
	end)
	if not ok or type(allowed) ~= "table" or #allowed == 0 then
		event:FireClient(player, "Whisper", userId, nil)
		return
	end
	local name = R.whisperChannel(player.UserId, target.UserId, Cfg)
	local existing = folder:FindFirstChild(name)
	local c = channel(name)
	if not existing then
		pcall(function()
			c:AddUserAsync(player.UserId)
			c:AddUserAsync(target.UserId)
		end)
	end
	event:FireClient(player, "Whisper", userId, name)
end

local function joined(player: Player)
	task.spawn(function()
		local ok, may = pcall(function()
			return TextChatService:CanUserChatAsync(player.UserId)
		end)
		canChat[player] = ok and may == true
	end)
	placeTeam(player)
	player.CharacterAdded:Connect(function(character)
		placeTeam(player)
		character:GetAttributeChangedSignal("Kit"):Connect(function()
			placeTeam(player)
		end)
	end)
end

function ChatServer.start()
	folder = Instance.new("Folder")
	folder.Name = Cfg.Folder
	folder.Parent = TextChatService
	for _, kit in U.Teams do
		channel(R.teamChannel(kit, Cfg))
	end
	event = Net.event("Chat")
	event.OnServerEvent:Connect(function(player, kind, value)
		if kind == "Global" then
			sendGlobal(player, value)
		elseif kind == "Whisper" then
			openWhisper(player, value)
		end
	end)
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(Cfg.Global.topic, function(message)
				local line = message.Data
				if type(line) == "table" and type(line.t) == "string" then
					deliverGlobal(line)
				end
			end)
		end)
	end)
	Players.PlayerAdded:Connect(joined)
	for _, p in Players:GetPlayers() do
		joined(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		teamOf[p], canChat[p], lastGlobal[p], lastWhisper[p] = nil, nil, nil, nil
		-- the whisper channels this player was in go with them
		for _, c in folder:GetChildren() do
			local a, b = c.Name:match("_(%d+)_(%d+)$")
			if R.channelOf(c.Name, Cfg) == "Whisper" and (tonumber(a) == p.UserId or tonumber(b) == p.UserId) then
				c:Destroy()
			end
		end
	end)
end

return ChatServer
