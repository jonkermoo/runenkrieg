--!strict
-- The game's own chat (UI overhaul, user 2026-10-30: "build our own simple chat panel underneath the map that works
-- similarily to robloxs. we will have a server, team, and global chat. make sure the features on roblox's chat panel
-- carries over"): src/client/Chat draws it top left under the sketch map's place, src/server/Chat keeps the team and
-- whisper channels and carries Global between servers, Rules/Chat reads what was typed. Server, Team and whispers go
-- through Roblox's TextChatService (its filtering, chat settings and bubbles); Global is filtered for broadcast and
-- sent on through MessagingService. Colours: Config/Palette UI.Grimoire. Data only.

local Chat = {
	MaxLength = 200, -- characters a line may have (Roblox's own limit)
	CounterFrom = 150, -- the characters-left counter shows from this many on
	History = 200, -- lines kept, oldest dropped (kept through deaths)
	FadeAfter = 25, -- seconds a line stays up in the quiet view, then it fades out
	FadeTime = 1.5,
	QuietTransparency = 0.25, -- a fresh line's words in the quiet view
	-- the channels (user 2026-11-03: "make chat just team, server, global"; no All tab, Team first): the view tabs left
	-- to right, each also the channel a line is sent to (Tab cycles them; the first is where you start), each one's
	-- word on a line and its colour (Palette UI.Grimoire.Chat). Whispers and system lines show in every tab.
	Views = { "Team", "Server", "Global" },
	Send = { "Team", "Server", "Global" },
	-- TextChatService channel names: Roblox's general one is the server channel; ours are made by src/server/Chat
	ServerChannel = "RBXGeneral",
	SystemChannel = "RBXSystem",
	TeamPrefix = "Team_", -- + the team's kit
	WhisperPrefix = "Whisper_", -- + the two user ids, lower first
	Folder = "RunenkriegChannels", -- under TextChatService
	-- Global: the MessagingService topic, a sender's wait between lines, the server tag shown on lines from elsewhere
	Global = { topic = "RunenkriegGlobalChat", cooldown = 2, tagLength = 4 },
	WhisperCooldown = 0.5, -- seconds between asking the server for whisper channels
	-- the panel: top left, under the sketch map's place. Its corner `x`, `y` in reference pixels at an 800-pixel-tall
	-- screen (moved with the screen's height, clamped by `scale`, as the map is); everything else in screen pixels, not
	-- scaled, as Roblox's own chat (user 2026-11-02: "make the text in the chat smaller? it should match the size of what
	-- roblox's wouldve been": its ChatWindowConfiguration.TextSize, 14)
	Panel = {
		x = 16,
		y = 168, -- under the in-play sketch map (Config/SketchMap.Hud: 10 + 486 x 295 / 1024, plus 18)
		width = 360,
		height = 230,
		tabs = 22, -- the tab row's height
		bar = 32, -- the input bar's height
		pad = 8,
		gap = 2, -- between lines
		textSize = 14,
		tagSize = 12, -- the channel word on a line
		tabSize = 15, -- the chosen tab; the others are smaller
		tabSizeOff = 12,
		hintSize = 12,
		-- the hide toggle under the panel (user 2026-10-31: "can we also make the chat hideable"): a faint word, its
		-- gap below the panel's wash; hidden, only it stays, with a red mark once a line comes in
		toggle = { gap = 4, height = 16, fade = 0.35 },
		washTransparency = 0.45,
		scale = { min = 0.65, max = 1.25 },
	},
	Help = {
		"/t, /s, /g message: send once to Team, Server or Global",
		"/c team (server, global): change the channel you type to; Tab cycles it",
		"/w name message: whisper; /r message: answer the last whisper",
		"/mute name, /unmute name: hide or show someone's lines",
	},
}

return table.freeze(Chat)
