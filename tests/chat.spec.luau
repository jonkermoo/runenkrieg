--!strict
local R = require("../src/shared/Rules/Chat")
local Cfg = require("../src/shared/Config/Chat")

return {
	["plain words go to the bar's channel"] = function()
		local c = R.parse("  push the farm  ")
		assert(c.kind == "send" and c.channel == nil and c.text == "push the farm", c.kind)
		assert(R.parse("").kind == "none", "empty")
		assert(R.parse("   ").kind == "none", "spaces")
	end,
	["/t /s /g send once; alone they switch the channel"] = function()
		local t = R.parse("/t smoke the ford")
		assert(t.kind == "send" and t.channel == "Team" and t.text == "smoke the ford", "team")
		assert(R.parse("/team hi").channel == "Team", "/team")
		assert(R.parse("/S hi").channel == "Server", "upper case")
		assert(R.parse("/g gg").channel == "Global", "global")
		local sw = R.parse("/g")
		assert(sw.kind == "switch" and sw.channel == "Global", "switch")
		local c = R.parse("/c team")
		assert(c.kind == "switch" and c.channel == "Team", "/c team")
		assert(R.parse("/c nowhere").kind == "unknown", "/c with no such channel")
	end,
	["whispers, replies, mutes, help"] = function()
		local w = R.parse("/w @Arturo_V drop me a med pack")
		assert(w.kind == "whisper" and w.name == "Arturo_V" and w.text == "drop me a med pack", "whisper")
		assert(R.parse("/whisper Ottokar").text == "", "whisper with no words yet")
		assert(R.parse("/w").kind == "unknown", "whisper to nobody")
		local r = R.parse("/r on my way")
		assert(r.kind == "reply" and r.text == "on my way", "reply")
		local m = R.parse("/mute Ottokar")
		assert(m.kind == "mute" and m.name == "Ottokar", "mute")
		assert(R.parse("/unmute @Ottokar").name == "Ottokar", "unmute")
		assert(R.parse("/mute").kind == "unknown", "mute nobody")
		assert(R.parse("/help").kind == "help" and R.parse("/?").kind == "help", "help")
		assert(R.parse("/dance").kind == "unknown" and R.parse("/dance").command == "dance", "unknown")
	end,
	["tabs and new lines in the box become spaces"] = function()
		assert(R.parse("a\tb\nc").text == "a b c", R.parse("a\tb\nc").text)
	end,
	["lines are clipped by characters, not bytes"] = function()
		assert(R.clip("hello", 3) == "hel", "ascii")
		assert(R.clip("ääää", 2) == "ää", "two-byte characters")
		assert(R.clip("short", Cfg.MaxLength) == "short", "under the limit")
	end,
	["rich text is escaped"] = function()
		assert(
			R.escape("<b>\"x\" & 'y'</b>") == "&lt;b&gt;&quot;x&quot; &amp; &apos;y&apos;&lt;/b&gt;",
			R.escape("<b>")
		)
	end,
	["channel names and kinds"] = function()
		assert(R.channelOf(Cfg.ServerChannel, Cfg) == "Server", "server")
		assert(R.channelOf(Cfg.SystemChannel, Cfg) == "System", "system")
		assert(R.channelOf(R.teamChannel("uniform2", Cfg), Cfg) == "Team", "team")
		local w = R.whisperChannel(9, 3, Cfg)
		assert(w == R.whisperChannel(3, 9, Cfg), "the same channel either way round")
		assert(R.channelOf(w, Cfg) == "Whisper", "whisper")
		assert(R.channelOf("Something", Cfg) == nil, "other")
	end,
	["Tab cycles the send channels"] = function()
		assert(R.cycle("Server", Cfg.Send) == "Team", "server -> team")
		assert(R.cycle("Global", Cfg.Send) == "Server", "wraps")
		assert(R.cycle("Nowhere", Cfg.Send) == Cfg.Send[1], "unknown starts at the first")
	end,
}
