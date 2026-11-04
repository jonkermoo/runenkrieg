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
	-- what a soldier in the zone counts for (user 2026-11-03: "make flag capture speed be scale to how many on the
	-- point to players (include AI count as half a player)"): a player 1, a bot this; the lead is the sides' weights
	BotWeight = 0.5,
	-- seconds for a sector left empty (or out of reach) to drift from neutral back to its holder's end
	DrainSeconds = 20,
	-- Momentum (user 2026-10-27: "momentum, but there is a reasonable cap"): once the front has gone `after` seconds
	-- without a capture, captures go `perMinute` faster for each minute more, up to `max` times; any capture resets it
	Momentum = { after = 180, perMinute = 0.25, max = 2 },
	-- the match's start: waiting until each side has this many players, then the countdown (captures don't count yet)
	MinPerSide = 1,
	-- (the pre-match cutscene and the spoken plan play over it: Config/Cutscenes.Pre's length, user 2026-11-02; was 10)
	CountdownSeconds = 19,
	-- a fresh server's first match (nothing played on it yet, user 2026-11-03): no flight, a short loading screen over
	-- this countdown, then into the game
	FreshCountdownSeconds = 8,
	-- a Defend award (Config/Classes.Earn): a kill with the killer or the victim within the sector's radius plus this
	-- of its point, while the enemy is attacking that sector of the killer's side
	DefendReach = 20,
	-- who's in a zone: alive, on their feet, within the sector's radius across the ground and this far above or below
	-- the ground at its point
	Height = 8,
	Tick = 0.2, -- seconds between the server's zone checks
	-- a match's end (user 2026-11-02, the match-end sequence; Config/Cutscenes): everyone frozen and the screen faded
	-- to the winner's colour, the after-action report on the battle table, the map vote on the board (src/server/
	-- MapVote; skipped with one map to offer), then the armory while the map is put back and moved to the pick: at
	-- least as long as the narrator's first part (its words at Cutscenes.Speech.wordsPerSecond) and until every
	-- player has streamed in the next map (Net "MapLoad"), at most `max`
	-- (the table's own length: Rules/Cutscenes.tableSeconds, until its replay and report are done)
	FadeSeconds = 3,
	VoteSeconds = 30, -- (the approved demo, user 2026-11-03: the countdown from 0:30; was 15)
	-- (`tour`: the black before the flight held at most this long while every player's camera tours it unseen, Net
	-- "MapTour")
	Loading = { least = 8, max = 60, tour = 15 },
	-- on the Frontline folder from a match's end to the next countdown's end: what the narrator speaks of, "<winner
	-- kit or none>,<the map just played>" (src/client/MatchCutscene)
	SpeechAttribute = "Speech",
	-- on the Frontline folder: the server time of the latest dip to black between scenes (Config/Cutscenes.Dip: the
	-- next phase starts there), and PhaseAt the server time the phase started
	DipAttribute = "DipAt",
	-- on the Frontline folder with DipAt: which dip it is ("Flight": Config/Cutscenes.FlightDip; none: Cutscenes.Dip)
	DipKindAttribute = "DipKind",
	SpawnLift = 3.2, -- a spawned root this far over the ground (standing)
	SpawnWait = 10, -- seconds a new character's root is waited for
	FeetBelowRoot = 3, -- a soldier's feet this far under the root (what counts as in the zone: Height round them)
	GroundRay = { top = 300, depth = 600 }, -- the ground found by a ray this high, this long, down on terrain only
	-- replicated state (read by src/client/ModeHud): a Folder in Workspace with the match's attributes (Phase "Waiting"
	-- / "Countdown" / "Playing" / "Fade" / "Table" / "Vote" / "Loading", PhaseEndsAt (server time), Winner (a
	-- side), Momentum (the capture speed's multiplier), West and East (each side's team, Config/Uniforms.Teams)) and one
	-- child Folder per sector (Index, Owner, Control, the West / East soldiers in its zone weighed by BotWeight, Rate)
	FolderName = "Frontline",
	-- the map's key in Config/Maps: the built map's model in Workspace has this name (src/dev/Greybox), not its `name`
	MapKey = "Map1",
	-- on Workspace: the key of the map the match is on now (src/shared/LiveMap; the vote's pick), MapKey until set
	MapAttribute = "MatchMap",
	-- on Workspace while a match runs: the two teams playing, "west,east" (Rules/Frontline.pairText); kept teams and the
	-- loadout menu's team cards use only these (src/server/Deploy)
	TeamsAttribute = "MatchTeams",
	-- one of the two teams every match, against either other at random (user 2026-11-01: "it should always be green OR
	-- brown vs gray"; only the campaign's final map mixes green and brown on one side): the grey team (Config/Uniforms)
	AlwaysTeam = "uniform1",

	-- Waves (user 2026-10-27: "I want respawning to be in waves"): one clock for both sides, a wave every `every` seconds
	-- from the countdown's end (the first wave). A dead soldier may deploy once `dead` seconds have passed
	-- (src/server/Deploy, Normal only) and stands in its side's wave line, frozen and protected, until the wave goes;
	-- then it can move and keeps the shield `shield` seconds more (user 2026-10-31: "a shield that remains for a bit even
	-- when you're unfrozen"), unless it attacks first.
	Waves = { every = 15, dead = 5, shield = 3 },
	-- The wave line (user 2026-10-31: "make sure spawns are lined up and they spawn in the general area of the flag"):
	-- `perRow` soldiers side by side `gap` apart, filled from the middle out, each row `rowGap` behind the last, facing
	-- the side's target sector. At a fought-over sector the line's front row stands `back` of the way from its point to
	-- the point behind it (Rules/Frontline.lineCentre): closer to the sector behind (user 2026-11-02: "spawns still need
	-- to be pushed back. it should be closer to the previous sector than the furthest sector they have"; was `edge` 90
	-- past the zone, before that 20 and 8). On Map 1 0.60-0.75 stay hidden and dry; 0.55 puts the S3 / S4 line in the
	-- river. At a side's own HQ sector the line is in its spawn zone (Config/Maps/Map1.spawnZones). A slot needs `clear`
	-- (across, high, deep) studs of open ground over dry terrain; a blocked one is skipped (up to `tries` slots).
	-- A soldier stands on the highest ground within `foot` studs of its slot's middle (on the slope no foot is buried;
	-- user 2026-11-01: "my body was in the ground"), its feet `lift` over it, its root at its own standing height
	-- (legs, root, hip height) over that.
	-- No natural trees on a line's ground at a fought-over sector, `treeClear` round it (Rules/Frontline.lineQuads).
	Line = {
		perRow = 8,
		gap = 4,
		rowGap = 5,
		back = 0.65,
		treeClear = 4,
		clear = { 3, 6, 3 },
		tries = 40,
		foot = 1,
		lift = 0.2,
		-- while held, every `recheck` seconds a soldier is lifted back over the ground if it rose more than `relift` under
		-- its feet (src/server/Frontline keepUp; user 2026-11-02: "plays spawn under the ground")
		recheck = 0.25,
		relift = 0.05,
	},
	-- the shield round a soldier in the wave line: a ball `size` studs across in its team's magic colour
	-- (Config/Palette.UI.Grimoire.Magic), `transparency` see-through, fading out over the last of the shield's time
	Shield = { size = 7, transparency = 0.75, name = "WaveShield" },
	-- Artillery locks (user 2026-11-02: "only unlock the rune for the team that gets pushed back to their last sector
	-- (all artys still only for engineers)"): a gun in `lastStand` is built only by a side holding `unlockAt` sectors or
	-- fewer (Rules/Frontline.held: the run from its end; it locks again once the side pushes out past that), and is told
	-- `why` otherwise; every other gun from a match's start, under its per-team cap (Config/Build.Pieces `teamCap`).
	-- `unlockAt` 2 (user 2026-11-03: "make field mortars unlock at the second to last sector, not the last sector"; its
	-- HQ and the one before, so on Map 1 and Lantern Meadows from the start, user: "Yes, from the start"); was 1. Was a
	-- level per sector lost (2026-10-31), then no locks (earlier 2026-11-02). Each side's held count is the Frontline
	-- folder's "<Side>" .. `HeldAttribute` (src/server/Build reads it; the bots count it from the sectors' owners).
	Artillery = {
		lastStand = { Howitzer = true },
		unlockAt = 2,
		why = "Unlocks while you hold only your last two sectors",
	},
	-- Reinforcements (user 2026-10-29: "'reinforcements' boost that gives extra battle points. only when there is a lot
	-- of mis match"): while the bigger side has at least `gap` more players AND `share` more, the smaller side's points
	-- are paid `times` over (src/server/Loadouts)
	Reinforcements = { gap = 3, share = 0.25, times = 1.5 },
	-- on the Frontline folder: the next wave's server time; the side reinforced (or nil); each side's sectors held from
	-- its end ("<Side>Held", Artillery above), spawn sector (an index, "<Side>Spawn") and its wave line's centre (a
	-- Vector3, "<Side>Line": no shells there, Config/Artillery.SpawnGuard). On a character: while it stands in the wave
	-- line.
	WaveAttribute = "WaveAt",
	HeldAttribute = "Held",
	RateAttribute = "Rate", -- each sector's: its control per second now (Rules/Frontline.rates; the admin readout)
	-- each sector's "<Side>" .. this: the side's soldiers in its zone by head, unweighed (the bots' planning reads it;
	-- "West" / "East" are weighed by BotWeight)
	HeadsSuffix = "Heads",
	ReinforcedAttribute = "Reinforced",
	SpawnAttribute = "Spawn",
	LineAttribute = "Line",
	HoldAttribute = "WaveHold",
}

return table.freeze(Frontline)
