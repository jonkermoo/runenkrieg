--!strict
-- A bolt rifle's action as pure state (M11; Config/Firing, Config/Weapons ammo / action). The client predicts with
-- it and the server decides with it (src/client/Firing, src/server/Firing); times are plain numbers (seconds).
-- - fire: needs a live round in the chamber and nothing else going on; leaves the spent case in the chamber;
-- - bolt (worked by hand after a shot): throws out what is in the chamber and feeds the next round, if any;
-- - reload: an en-bloc clip (Carcano) goes in only when the magazine is empty; a stripper clip (Gewehr, SMLE) goes in
--   whole into an empty magazine. Either way the bolt closes on a round if the chamber was empty.
-- - single rounds (user 2026-10-13: a clip only fits an empty magazine): a stripper-clip rifle with rounds left loads
--   them one by one through the open action ("load"): the bolt opens (throwing out what is in the chamber, a live
--   round too: it is lost), a round goes in every `singleRound` seconds until the magazine is full or the player
--   clicks (stopLoad: the round in the hand still goes in), then the bolt closes on a round. Each round counts once
--   it is in (loadedBy).
-- - the bolt stays open on an empty rifle (user 2026-10-12): working it with nothing left to feed stops it pulled
--   back (the action takes only until the bolt is open); the reload then starts from the open bolt and closes it.
-- - put away mid-action (user 2026-10-12): the action's time left is kept (pause); drawn again, it plays out after
--   the draw (resume), so stowing a rifle never skips a bolt or a reload.
-- - loose shells (a pump shotgun, clip "Loose"; user 2026-10-13): R always loads one at a time, through the loading
--   port, the action left shut: what is in the chamber stays (a fired hull still needs the pump). If the chamber was
--   empty (the action held open), it closes on a shell at the end. The pump is worked like a bolt.
-- A full rifle: one round chambered and a full clip in the magazine (Gewehr 5 + 1, Carcano 6 + 1; Config/Firing.RifleClip).

local Firing = {}

export type Gun = {
	capacity: number, -- rounds one clip holds
	clip: string, -- "Enbloc" | "Stripper" | "Loose" (shells one at a time, the action left shut)
	boltTime: number,
	reloadTime: number,
	fireTime: number,
	openAt: number, -- share of the bolt cycle at which the bolt is fully back (Config/Firing.BoltCycle.back)
	reloadOpenAt: number, -- share of the reload at which the bolt is open (Config/Firing.ReloadCycle.back)
	-- single rounds (Config/Firing.Single): seconds to open the bolt, per round, to close it
	singleOpen: number,
	singleRound: number,
	singleClose: number,
}

-- loading single rounds: started at `start`, room for `room`; `rounds` is how many go in (nil: until full or told to
-- stop); `elapsed` holds the time done while the rifle is put away
export type Load = {
	start: number,
	room: number,
	rounds: number?,
	open: number,
	round: number,
	close: number,
	elapsed: number?,
}

export type State = {
	magazine: number,
	chambered: boolean, -- a live round in the chamber
	spent: boolean, -- a fired case in the chamber
	open: boolean, -- the bolt held open on an empty rifle
	busyUntil: number,
	paused: number, -- seconds of an action left when the rifle was put away
	load: Load?, -- single rounds going in
}

function Firing.new(gun: Gun): State
	return { magazine = gun.capacity, chambered = true, spent = false, open = false, busyUntil = 0, paused = 0 }
end

local function idle(s: State, now: number, slack: number?): boolean
	return now + (slack or 0) >= s.busyUntil
end

local function loadEnd(l: Load): number
	return l.start + l.open + (l.rounds or l.room) * l.round + l.close
end

-- Rounds of a single load already in the magazine at `now` (each counts once it is pushed in).
function Firing.loadedBy(s: State, now: number): number
	local l = s.load
	if not l then
		return 0
	end
	local at = if l.elapsed then l.start + l.elapsed else now
	local k = math.floor((at - l.start - l.open) / l.round)
	return math.clamp(k, 0, l.rounds or l.room)
end

-- A single load that has ended: its rounds join the magazine and the bolt has closed on one.
function Firing.settle(s: State, now: number)
	local l = s.load
	if not l or l.elapsed or now < loadEnd(l) then
		return
	end
	s.magazine += l.rounds or l.room
	s.load = nil
	if not s.chambered and not s.spent and s.magazine > 0 then -- (loose shells: a fired hull waits for the pump)
		s.magazine -= 1
		s.chambered = true
	end
end

-- Stop a single load (a click): the round in the hand still goes in, then the bolt closes. Returns how many go in.
function Firing.stopLoad(s: State, now: number): number?
	Firing.settle(s, now)
	local l = s.load
	if not l or l.rounds or l.elapsed then
		return nil
	end
	local done = now - l.start - l.open
	l.rounds = if done <= 0 then 0 else math.min(l.room, math.ceil(done / l.round))
	s.busyUntil = loadEnd(l)
	return l.rounds
end

-- What a press of the fire button does now: "Fire", "Bolt" (a case to throw out, or an empty chamber with rounds
-- left), "Open" (the bolt is held open: nothing happens), "Dry" (nothing to fire), "Load" (stop loading single
-- rounds) or "Busy".
function Firing.next(s: State, now: number): string
	Firing.settle(s, now)
	if s.load and not s.load.rounds and not s.load.elapsed then
		return "Load"
	elseif not idle(s, now) then
		return "Busy"
	elseif s.open then
		return "Open"
	elseif s.chambered then
		return "Fire"
	elseif s.spent or s.magazine > 0 then
		return "Bolt"
	end
	return "Dry"
end

function Firing.fire(s: State, gun: Gun, now: number, slack: number?): (boolean, string?)
	Firing.settle(s, now)
	if not idle(s, now, slack) then
		return false, "busy"
	elseif not s.chambered then
		return false, if s.spent then "bolt" else "empty"
	end
	s.chambered, s.spent = false, true
	s.busyUntil = now + gun.fireTime
	return true, nil
end

-- Returns ok, the reason it can't, and what came out of the chamber ("Casing", "Round" or nil).
function Firing.bolt(s: State, gun: Gun, now: number, slack: number?): (boolean, string?, string?)
	Firing.settle(s, now)
	if not idle(s, now, slack) then
		return false, "busy", nil
	elseif s.chambered then
		return false, "loaded", nil -- nothing to do (working it would throw a live round away)
	elseif s.open or (not s.spent and s.magazine == 0) then
		return false, "empty", nil
	end
	local out = if s.spent then "Casing" else nil
	s.spent = false
	if s.magazine > 0 then
		s.magazine -= 1
		s.chambered = true
		s.busyUntil = now + gun.boltTime
	else
		s.open = true -- nothing to feed: the bolt stays back
		s.busyUntil = now + gun.boltTime * gun.openAt
	end
	return true, nil, out
end

function Firing.canReload(s: State, gun: Gun): boolean
	if gun.clip == "Enbloc" then
		return s.magazine == 0
	end
	return s.magazine < gun.capacity
end

-- Returns ok, the reason it can't, what came out of the chamber when the bolt opened ("Casing", "Round": a live round
-- thrown out, or nil; loose shells: "Open" when the action was held open and closes at the end), and the kind: "Reload" (a clip) or "Load" (single rounds: a stripper-clip rifle with rounds
-- left).
function Firing.reload(s: State, gun: Gun, now: number, slack: number?): (boolean, string?, string?, string?)
	Firing.settle(s, now)
	if not idle(s, now, slack) then
		return false, "busy", nil, nil
	elseif not Firing.canReload(s, gun) then
		return false, if gun.clip == "Enbloc" then "not empty" else "full", nil, nil
	end
	local loose = gun.clip == "Loose"
	if loose or (gun.clip == "Stripper" and s.magazine > 0) then
		local out: string? = nil
		if loose then
			-- "Open": the action was held open and closes on a shell at the end (settle); the chamber is left alone
			out = if s.open then "Open" else nil
			s.open = false
		else
			out = if s.spent then "Casing" elseif s.chambered then "Round" else nil
			s.spent, s.chambered, s.open = false, false, false
		end
		local l: Load = {
			start = now,
			room = gun.capacity - s.magazine,
			rounds = nil,
			open = gun.singleOpen,
			round = gun.singleRound,
			close = gun.singleClose,
			elapsed = nil,
		}
		s.load = l
		s.busyUntil = loadEnd(l)
		return true, nil, out, "Load"
	end
	local out = if s.spent then "Casing" else nil
	local wasOpen = s.open
	s.spent, s.open = false, false
	s.magazine = gun.capacity
	if not s.chambered then
		s.magazine -= 1
		s.chambered = true
	end
	-- from an open bolt the reload starts with the clip (the bolt is already back)
	s.busyUntil = now + gun.reloadTime * (if wasOpen then 1 - gun.reloadOpenAt else 1)
	return true, nil, out, "Reload"
end

-- The rifle is put away: whatever action was under way stops where it is, its time left kept.
function Firing.pause(s: State, now: number)
	Firing.settle(s, now)
	local l = s.load
	if l and not l.elapsed then
		-- loading single rounds: the round in the hand still goes in (after the draw), then the bolt closes
		Firing.stopLoad(s, now)
		l.elapsed = now - l.start
	end
	s.paused = math.max(0, s.busyUntil - now)
	s.busyUntil = now
end

-- Drawn again: an interrupted action plays out its time left, starting `delay` seconds from now (after the draw).
-- Returns the seconds left that will play (0: nothing was interrupted).
function Firing.resume(s: State, now: number, delay: number): number
	local left = s.paused
	s.paused = 0
	if left > 0 then
		s.busyUntil = now + delay + left
	end
	local l = s.load
	if l and l.elapsed then
		l.start = now + delay - l.elapsed -- the load carries on where it stopped
		l.elapsed = nil
	end
	return left
end

function Firing.rounds(s: State): number
	return s.magazine + (if s.chambered then 1 else 0)
end

-- The magazine as it stands at `now`, single rounds pushed in so far included.
function Firing.magazineAt(s: State, now: number): number
	return s.magazine + Firing.loadedBy(s, now)
end

-- A shotgun's pattern (user 2026-10-13): `count` pellet directions in a cone `spread` degrees wide (half angle),
-- spread evenly over its area, from `seed` (the same on the shooter's client, the server and everyone's effects).
-- Returns { yaw, pitch } offsets in degrees from the barrel's line (yaw + to the right, pitch + up).
function Firing.pellets(seed: number, count: number, spread: number): { { number } }
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local function rand(): number -- Park-Miller: plain numbers, the same everywhere
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
	local out = {}
	for _ = 1, count do
		local r = spread * math.sqrt(rand())
		local a = 2 * math.pi * rand()
		table.insert(out, { r * math.cos(a), r * math.sin(a) })
	end
	return out
end

-- A shot's geometry as the server sees it: the muzzle reported `originDistance` studs from the shooter's head, a
-- direction of length `directionLength` (must be a unit vector).
function Firing.validShot(originDistance: number, directionLength: number, maxOrigin: number): (boolean, string?)
	if originDistance ~= originDistance or originDistance > maxOrigin then
		return false, "origin"
	elseif math.abs(directionLength - 1) > 1e-3 then
		return false, "direction"
	end
	return true, nil
end

return Firing
