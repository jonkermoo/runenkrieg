--!strict
-- What a chat line typed into the game's own chat means (Config/Chat; src/client/Chat sends it, src/server/Chat keeps
-- the channels). Pure: strings and tables only.
--   Chat.parse(text) -> Command: { kind = "none" } | { kind = "send", channel: string?, text } (channel nil: the one
--     the bar is on) | { kind = "switch", channel } | { kind = "whisper", name, text } | { kind = "reply", text } |
--     { kind = "mute" | "unmute", name } | { kind = "help" } | { kind = "unknown", command }
--   Chat.clip(text, max) -> string: at most `max` characters (whole UTF-8 characters)
--   Chat.escape(text) -> string: safe to show in a RichText label
--   Chat.channelOf(name, cfg) -> "Server" | "Team" | "Whisper" | "System" | nil: a TextChatService channel's kind
--   Chat.teamChannel(kit, cfg), Chat.whisperChannel(a, b, cfg) -> string: the channel names
--   Chat.cycle(channel, list) -> string: the next channel in `list` after `channel`

local Chat = {}

export type Command = {
	kind: string,
	channel: string?,
	text: string?,
	name: string?,
	command: string?,
}

local SEND = {
	t = "Team",
	team = "Team",
	s = "Server",
	server = "Server",
	all = "Server",
	g = "Global",
	global = "Global",
}

local function trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Chat.parse(raw: string): Command
	local text = trim(raw:gsub("[\t\r\n]", " "))
	if text == "" then
		return { kind = "none" }
	end
	if text:sub(1, 1) ~= "/" then
		return { kind = "send", text = text }
	end
	local word, rest = text:match("^/(%S+)%s*(.*)$")
	if not word then
		return { kind = "none" }
	end
	word = word:lower()
	rest = trim(rest or "")
	if SEND[word] then
		if rest == "" then
			return { kind = "switch", channel = SEND[word] }
		end
		return { kind = "send", channel = SEND[word], text = rest }
	end
	if word == "c" or word == "channel" then
		local to = SEND[rest:lower()]
		return if to then { kind = "switch", channel = to } else { kind = "unknown", command = word }
	end
	if word == "w" or word == "whisper" then
		local name, msg = rest:match("^(%S+)%s*(.*)$")
		if not name then
			return { kind = "unknown", command = word }
		end
		name = name:gsub("^@", "")
		return { kind = "whisper", name = name, text = trim(msg or "") }
	end
	if word == "r" or word == "reply" then
		return { kind = "reply", text = rest }
	end
	if word == "mute" or word == "unmute" then
		if rest == "" then
			return { kind = "unknown", command = word }
		end
		return { kind = word, name = (rest:gsub("^@", "")) }
	end
	if word == "help" or word == "?" then
		return { kind = "help" }
	end
	return { kind = "unknown", command = word }
end

function Chat.clip(text: string, max: number): string
	if utf8.len(text) == nil then
		-- not valid UTF-8: count bytes
		return text:sub(1, max)
	end
	local n = 0
	for at in utf8.codes(text) do
		n += 1
		if n > max then
			return text:sub(1, at - 1)
		end
	end
	return text
end

function Chat.escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

function Chat.channelOf(name: string, cfg: any): string?
	if name == cfg.ServerChannel then
		return "Server"
	elseif name == cfg.SystemChannel then
		return "System"
	elseif name:sub(1, #cfg.TeamPrefix) == cfg.TeamPrefix then
		return "Team"
	elseif name:sub(1, #cfg.WhisperPrefix) == cfg.WhisperPrefix then
		return "Whisper"
	end
	return nil
end

function Chat.teamChannel(kit: string, cfg: any): string
	return cfg.TeamPrefix .. kit
end

function Chat.whisperChannel(a: number, b: number, cfg: any): string
	return `{cfg.WhisperPrefix}{math.min(a, b)}_{math.max(a, b)}`
end

function Chat.cycle(channel: string, list: { string }): string
	local i = table.find(list, channel) or 0
	return list[i % #list + 1]
end

return Chat
