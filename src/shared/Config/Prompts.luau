--!strict
-- The game's own interaction prompt, "field note" (user 2026-10-27, options page, picked F): in place of Roblox's
-- ProximityPrompt look on every prompt (doors, the guns). A pin on the thing itself; on the prompt E would use, a thin
-- line up to its words (the key on a light cap, the object in small capitals, the action) with an underline that fills
-- while the key is held; every other prompt in reach shows only its pin. A prompt that can't be used stays, dimmed,
-- with a red reason. Drawn by src/client/Prompts (layout src/shared/ui/Prompt.json, colours Config/Palette.UI.Prompt;
-- which prompt shows what: Rules/Prompts). Data only.

local Prompts = {
	-- the CollectionService tag the server gives every prompt it makes (Style Custom): the client draws pins for these
	Tag = "Prompt",
	-- attributes on a prompt: why it can't be used (a key of `Reasons`; the server also turns it off), and the UserId
	-- of the player using it (it isn't drawn for them: the gunner on their own gun)
	BlockedAttr = "Blocked",
	UserAttr = "PromptUser",
	Reasons = { InUse = "In use", Broken = "Broken" },

	-- how far out the pins show, as a share of each prompt's own reach, and how many at most (the nearest)
	FarReach = 2,
	MaxPins = 8,
	-- how often the client looks for prompts around the player (s)
	Check = 0.1,
	-- the billboards come this far toward the camera from the thing (studs), so a pin on a door isn't half in it
	Toward = 0.4,

	-- doors (src/server/Doors): reach, studs
	Door = { reach = 9 },
}

return table.freeze(Prompts)
