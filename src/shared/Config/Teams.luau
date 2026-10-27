--!strict
-- Kept teams (user 2026-10-27: "add a change team button (only if it's balanced)"; Rules/Teams, src/server/Deploy). In
-- a mode that keeps teams (Config/Modes `teams`: Normal; or any mode while the admin panel's switch is on) a player joins
-- the smallest team and keeps it every life; the loadout menu's team cards (src/client/Menus) move them, and changing
-- team resets their match points (Config/Classes.Start). In the other modes (Admin, FFA) the team is rolled each life.
local Teams = {
	-- the server's size (user 2026-10-27: "the game will be max 100 players"): each team has room for this over the
	-- number of teams (Config/Uniforms.Teams), rounded up
	MaxPlayers = 100,
	-- after a change, the team joined may be at most this many soldiers bigger than the one left: 1 = only to a smaller
	-- team (user 2026-10-27)
	Gap = 1,
	-- on Workspace: the admin panel's test switch that keeps teams (and shows the team cards) in any mode
	DevAttribute = "DevTeams",
}

return table.freeze(Teams)
