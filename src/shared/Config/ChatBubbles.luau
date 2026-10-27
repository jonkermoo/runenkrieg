--!strict
-- The chat bubbles over players' heads (src/client/ChatBubbles; user 2026-10-27: at night "the text bubbles are way
-- too bright and its hard to read. make it normal"). Bubbles are drawn in the 3D view, so the night's exposure lift
-- (Config/Environment Light.night.exposure) brightened them too: white past the Bloom threshold, washed-out text.
-- The client darkens these colours by the same exposure so a bubble looks the same at any time of day.
-- Colours 0-255 (Roblox's own bubble look), transparency 0-1. Data only.

local ChatBubbles = {
	background = { 250, 250, 250 },
	text = { 57, 59, 61 },
	transparency = 0.1,
}

return table.freeze(ChatBubbles)
