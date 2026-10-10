--!strict
-- Player settings: options and defaults. Stored as Player attributes "Setting_<Key>" (src/client/Settings).
-- Per session for now; saving goes into the player profile
-- when persistence lands (roadmap 4.2), so there is only one save system.

local Settings = {
	Options = {
		GrassQuality = {
			label = "Grass",
			values = { "Off", "Low", "Medium", "High" }, -- Config/Foliage.Levels
			default = "Medium",
			defaultTouch = "Low", -- phones/tablets
		},
	},
	Order = { "GrassQuality" },
}

return table.freeze(Settings)
