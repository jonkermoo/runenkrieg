--!strict
-- A bolt rifle's action as pure state (M11; Config/Firing, Config/Weapons ammo / action). The client predicts with
-- it and the server decides with it (src/client/Firing, src/server/Firing); times are plain numbers (seconds).
-- - fire: needs a live round in the chamber and nothing else going on; leaves the spent case in the chamber;
-- - bolt (worked by hand after a shot): throws out what is in the chamber and feeds the next round, if any;
-- - reload: an en-bloc clip (Carcano) goes in only when the magazine is empty; a stripper clip (Gewehr) tops the
--   magazine up to capacity. Either way the bolt closes on a round if the chamber was empty.
-- - the bolt stays open on an empty rifle (user 2026-10-12): working it with nothing left to feed stops it pulled
--   back (the action takes only until the bolt is open); the reload then starts from the open bolt and closes it.
-- - put away mid-action (user 2026-10-12): the action's time left is kept (pause); drawn again, it plays out after
--   the draw (resume), so stowing a rifle never skips a bolt or a reload.
-- A full rifle: one round chambered and a full clip in the magazine (Gewehr 5 + 1, Carcano 6 + 1; Config/Firing.RifleClip).

local Firing = {}

export type Gun = {
	capacity: number, -- rounds one clip holds
	clip: string, -- "Enbloc" | "Stripper"
	boltTime: number,
	reloadTime: number,
	fireTime: number,
	openAt: number, -- share of the bolt cycle at which the bolt is fully back (Config/Firing.BoltCycle.back)
	reloadOpenAt: number, -- share of the reload at which the bolt is open (Config/Firing.ReloadCycle.back)
}

export type State = {
	magazine: number,
	chambered: boolean, -- a live round in the chamber
	spent: boolean, -- a fired case in the chamber
	open: boolean, -- the bolt held open on an empty rifle
	busyUntil: number,
	paused: number, -- seconds of an action left when the rifle was put away
}

function Firing.new(gun: Gun): State
	return { magazine = gun.capacity, chambered = true, spent = false, open = false, busyUntil = 0, paused = 0 }
end

local function idle(s: State, now: number, slack: number?): boolean
	return now + (slack or 0) >= s.busyUntil
end

-- What a press of the fire button does now: "Fire", "Bolt" (a case to throw out, or an empty chamber with rounds
-- left), "Open" (the bolt is held open: nothing happens), "Dry" (nothing to fire) or "Busy".
function Firing.next(s: State, now: number): string
	if not idle(s, now) then
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

-- Returns ok, the reason it can't, and what came out of the chamber when the bolt opened.
function Firing.reload(s: State, gun: Gun, now: number, slack: number?): (boolean, string?, string?)
	if not idle(s, now, slack) then
		return false, "busy", nil
	elseif not Firing.canReload(s, gun) then
		return false, if gun.clip == "Enbloc" then "not empty" else "full", nil
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
	return true, nil, out
end

-- The rifle is put away: whatever action was under way stops where it is, its time left kept.
function Firing.pause(s: State, now: number)
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
	return left
end

function Firing.rounds(s: State): number
	return s.magazine + (if s.chambered then 1 else 0)
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
