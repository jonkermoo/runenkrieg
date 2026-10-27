--!strict
-- The server's game mode (user 2026-10-27: "an admin panel for switching game modes"; src/server/Modes, Rules/Modes),
-- switched from the admin panel's "Server" rows (Net "DevAction" "Mode"). Only the live mode's map has spawns, a match
-- and zones; the other map stays standing, reached by the dev teleports. `openAdmin`: everyone in a Studio test or the
-- DEV place gets the admin panel (Config/DevTools); in the other modes only Config/DevTools.AllowedUserIds do.
local Modes = {
	Attribute = "Mode", -- on Workspace: the live mode's key (set by the server; a place saved with it starts in it)
	-- the zone match's old switch (workspace:SetAttribute("Playtest", true)): a place saved with it starts in FFA
	Legacy = { attribute = "Playtest", mode = "FFA" },
	Default = "Admin",
	List = { "Admin", "FFA", "Normal" }, -- the panel's order
	Defs = {
		-- the sandbox: spawn on Map 1 with nothing running
		Admin = { name = "Admin server", map = "Map1", ready = true, openAdmin = true },
		-- the zone-capture free-for-all on the playtest map (src/server/ZoneMatch)
		FFA = { name = "FFA", map = "Playtest", ready = true, openAdmin = false },
		-- the finished game's frontline mode on Map 1: not built yet, can't be switched to
		Normal = { name = "Normal", map = "Map1", ready = false, openAdmin = false },
	},
}

return table.freeze(Modes)
