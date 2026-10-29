--!strict
-- The frontline match, Normal mode (user 2026-10-27: "a standard 5 stage territory push between 2 sides"): two of the
-- teams, drawn at random each match, hold the West and East ends of the map's sector chain (Config/Maps/*.sectors:
-- S1 the West HQ, S5 the East HQ). Each side can only attack the sector next to its front, so the line moves both
-- ways; capturing the enemy HQ wins. No tickets (docs/GDD.md). Rules/Frontline is the maths, src/server/Frontline
-- runs it.
local Frontline = {
	-- A sector's control runs from 1 (West holds it) to -1 (East holds it). The holder loses it at 0 (it goes neutral);
	-- the other side takes it at its own end. Soldiers in the zone push it by their lead over the other side's.
	-- seconds for one soldier to take an enemy sector all the way (neutral at the half)
	CaptureSeconds = 20,
	-- a bigger lead pushes faster, up to this many soldiers' worth (user's GDD: "rate scales with the player advantage")
	MaxAdvantage = 3,
	-- seconds for a sector left empty (or out of reach) to drift from neutral back to its holder's end
	DrainSeconds = 20,
	-- Momentum (user 2026-10-27: "momentum, but there is a reasonable cap"): once the front has gone `after` seconds
	-- without a capture, captures go `perMinute` faster for each minute more, up to `max` times; any capture resets it
	Momentum = { after = 180, perMinute = 0.25, max = 2 },
	-- the match's start: waiting until each side has this many players, then the countdown (captures don't count yet)
	MinPerSide = 1,
	CountdownSeconds = 10,
	-- a Defend award (Config/Classes.Earn): a kill with the killer or the victim within the sector's radius plus this
	-- of its point, while the enemy is attacking that sector of the killer's side
	DefendReach = 20,
	-- who's in a zone: alive, on their feet, within the sector's radius across the ground and this far above or below
	-- the ground at its point
	Height = 8,
	Tick = 0.2, -- seconds between the server's zone checks
	ResultsSeconds = 10, -- the winner shown, then a new match
	SpawnLift = 3.2, -- a spawned root this far over the ground (standing)
	SpawnWait = 10, -- seconds a new character's root is waited for
	FeetBelowRoot = 3, -- a soldier's feet this far under the root (what counts as in the zone: Height round them)
	GroundRay = { top = 300, depth = 600 }, -- the ground found by a ray this high, this long, down on terrain only
	-- replicated state (read by src/client/ModeHud): a Folder in Workspace with the match's attributes (Phase "Waiting"
	-- / "Countdown" / "Playing" / "Results", PhaseEndsAt (server time, for the countdown and results), Winner (a
	-- side), Momentum (the capture speed's multiplier), West and East (each side's team, Config/Uniforms.Teams)) and one
	-- child Folder per sector (Index, Owner, Control, and the West / East soldiers in its zone)
	FolderName = "Frontline",
	-- on Workspace while a match runs: the two teams playing, "west,east" (Rules/Frontline.pairText); kept teams and the
	-- loadout menu's team cards use only these (src/server/Deploy)
	TeamsAttribute = "MatchTeams",
}

return table.freeze(Frontline)
