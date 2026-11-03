--!strict
-- The chat bubbles over players' heads (src/client/ChatBubbles; user 2026-10-27: at night "the text bubbles are way
-- too bright and its hard to read. make it normal"). Bubbles are drawn in the 3D view, so the night's exposure lift
-- (Config/Environment Light.night.exposure) brightened them too: white past the Bloom threshold, washed-out text.
-- The client darkens these colours by the same exposure so a bubble looks the same at any time of day.
-- Colours 0-255 (Roblox's own bubble look), transparency 0-1. Data only.
-- Where they show (user 2026-11-03: "speech bubbles should appear only when ur near players (like usual) ... make it
-- also float a little bit above your head. its super high up"): Roblox lifts a player's bubble over the top of
-- everything in the character, the rifle slung on the back too, so the client draws them itself on a marker `lift`
-- studs over the head's centre (its tail just clears a name over the head), only for speakers within `range` studs
-- of the camera (Roblox's own 100), shrunk to a dot past `minimize`.

local ChatBubbles = {
	background = { 250, 250, 250 },
	text = { 57, 59, 61 },
	transparency = 0.1,
	range = 100,
	minimize = 40,
	lift = 1,
	anchor = "ChatBubbleAnchors", -- the client's folder of markers in the workspace
	anchorSize = 0.05, -- studs: a marker (invisible; too small to show)
}

return table.freeze(ChatBubbles)
