--!strict
-- Player settings: options, defaults and the menu's tabs (src/client/Settings, src/client/SettingsMenu,
-- Rules/Settings). Stored as Player attributes "Setting_<Key>"; saved in the player profile (src/server/Profile).
-- Kinds: "choice" (one of `values`), "slider" (a number from min to max in `step`s, shown as `format`), "key" (a
-- KeyCode or mouse button name, rebound in the Keybinds tab). `defaultTouch`: the default on phones / tablets.
-- Data only.

local Settings = {
	Options = {
		-- Graphics. The preset row (Presets below) sets the four marked "preset" together.
		GrassQuality = {
			kind = "choice",
			label = "Grass",
			values = { "Off", "Low", "Medium", "High" }, -- Config/Foliage.Levels
			default = "Medium",
			defaultTouch = "Low",
		},
		Shadows = { kind = "choice", label = "Shadows", values = { "Off", "On" }, default = "On", defaultTouch = "Off" },
		TreeSway = {
			kind = "choice",
			label = "Tree sway",
			values = { "Off", "On" },
			default = "On",
			defaultTouch = "Off",
		},
		Debris = {
			kind = "choice",
			label = "Debris",
			values = { "Low", "Medium", "High" }, -- DebrisLevels below
			default = "Medium",
			defaultTouch = "Low",
		},
		FieldOfView = {
			kind = "slider",
			label = "Field of view",
			min = 60,
			max = 90, -- (user 2026-10-19; a saved wider view loads as 90: Rules/Settings.clean)
			step = 1,
			default = 70,
			format = "%d",
		},
		-- the short blur when a bullet passes close or something blows up nearby (Config/ScreenBlur; user 2026-10-22)
		ScreenBlur = { kind = "choice", label = "Screen blur", values = { "On", "Off" }, default = "On" },

		-- Controls. Sensitivities multiply Config/Camera.Sensitivity / AimSensitivity.
		HipSensitivity = {
			kind = "slider",
			label = "Sensitivity",
			min = 0.2,
			max = 3,
			step = 0.05,
			default = 1,
			format = "%.2fx",
		},
		AimSensitivity = {
			kind = "slider",
			label = "Aimed sensitivity",
			min = 0.2,
			max = 3,
			step = 0.05,
			default = 1,
			format = "%.2fx",
		},
		InvertY = { kind = "choice", label = "Invert Y", values = { "Off", "On" }, default = "Off" },
		-- aim down the sights while the aim key is held, or press once to aim and again to stop (user 2026-10-19)
		AimMode = { kind = "choice", label = "Aim", values = { "Hold", "Toggle" }, default = "Hold" },
		SprintMode = { kind = "choice", label = "Sprint", values = { "Hold", "Toggle" }, default = "Hold" },
		CrouchMode = { kind = "choice", label = "Crouch", values = { "Toggle", "Hold" }, default = "Toggle" },
		-- the hollow circle at the screen centre with a gun in third person (Config/Camera.Crosshair; user 2026-10-20)
		Crosshair = { kind = "choice", label = "Crosshair", values = { "On", "Off" }, default = "On" },

		-- Audio, in percent. Each sound group plays at Master x its own share (src/client/Audio).
		MasterVolume = {
			kind = "slider",
			label = "Master",
			min = 0,
			max = 100,
			step = 5,
			default = 100,
			format = "%d%%",
		},
		EffectsVolume = {
			kind = "slider",
			label = "Effects",
			min = 0,
			max = 100,
			step = 5,
			default = 100,
			format = "%d%%",
		},

		-- Keybinds: one key or mouse button each (Rules/Settings.rebind swaps a key already in use).
		Key_Fire = { kind = "key", label = "Fire", default = "MouseButton1" }, -- after a shot, the same click works the bolt
		Key_Aim = { kind = "key", label = "Aim", default = "MouseButton2" }, -- aim down the sights (a weapon in the hands)
		Key_Reload = { kind = "key", label = "Reload", default = "R" },
		Key_Sprint = { kind = "key", label = "Sprint", default = "LeftShift" },
		Key_Crouch = { kind = "key", label = "Crouch", default = "C" },
		Key_Heal = { kind = "key", label = "Heal", default = "H" }, -- heal the hurt soldier you look at (Config/Healing)
		Key_Settings = { kind = "key", label = "Settings menu", default = "P" }, -- opens this menu (frees the mouse)
	},

	-- The menu's tabs, in order, and the rows in each.
	Tabs = {
		{
			name = "Graphics",
			rows = { "Preset", "GrassQuality", "Shadows", "TreeSway", "Debris", "FieldOfView", "ScreenBlur" },
		},
		{
			name = "Controls",
			rows = {
				"HipSensitivity",
				"AimSensitivity",
				"InvertY",
				"AimMode",
				"SprintMode",
				"CrouchMode",
				"Crosshair",
			},
		},
		{ name = "Audio", rows = { "MasterVolume", "EffectsVolume" } },
		{
			name = "Keybinds",
			rows = { "Key_Fire", "Key_Aim", "Key_Reload", "Key_Sprint", "Key_Crouch", "Key_Heal", "Key_Settings" },
		},
	},

	-- The menu (src/client/SettingsMenu); its layout, sizes and fonts are the spec src/shared/ui/SettingsMenu.json.
	Menu = {
		DisplayOrder = 10, -- over the HUD
		CaptureGuard = 0.3, -- seconds after a key is bound in which its button's click is ignored
	},

	-- Graphics presets (user 2026-10-18): picking one sets these options; any other mix shows as "Custom".
	-- Beautiful is to be designed with the user; for now it is everything at its highest.
	PresetLabel = "Graphics",
	PresetOrder = { "Low", "Normal", "Beautiful" },
	Presets = {
		Low = { GrassQuality = "Low", Shadows = "Off", TreeSway = "Off", Debris = "Low" },
		Normal = { GrassQuality = "Medium", Shadows = "On", TreeSway = "On", Debris = "Medium" },
		Beautiful = { GrassQuality = "High", Shadows = "On", TreeSway = "On", Debris = "High" },
	},

	-- Client debris (src/client/Debris): shares of Config/Destruction.Debris maxLive and lifetime.
	DebrisLevels = {
		Low = { live = 0.25, lifetime = 0.25 },
		Medium = { live = 1, lifetime = 1 },
		High = { live = 2, lifetime = 2 },
	},

	-- Saving (src/server/Profile): the DataStore and its profile field, a player's saves accepted per second, and how
	-- often a changed profile is written while they play (seconds; also on leaving and on shutdown). The client sends
	-- its settings this long after the last change (seconds).
	Store = "Profile_v1",
	Field = "settings",
	SaveRate = 1,
	AutosaveEvery = 60,
	ShutdownWait = 3, -- seconds the server waits on shutdown for the last saves
	SendDelay = 2,
	MaxKeyName = 32, -- longest key name accepted from a client
}

return table.freeze(Settings)
