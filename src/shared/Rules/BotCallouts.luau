--!strict
-- When a bot calls out, and what it says (Config/Bots.Callouts; src/server/Bots sends it, src/client/BotSay shows it
-- as a bubble over its head, never in the chat log). User 2026-11-01: "they would say im hit or let me heal you ... dont
-- let them spam it too much to flood other players, only when necessary ... you can make them not say anything unless a
-- player is near them". Pure: numbers and tables only.

local BotCallouts = {}

export type State = {
	bots: { [any]: { at: number, events: { [string]: number } } },
	sides: { [string]: number },
}

function BotCallouts.new(): State
	return { bots = {}, sides = {} }
end

-- Whether bot `id` on `side` may call out `event` now: a player within `cfg.near` studs (`nearest`), its own wait since
-- its last callout (`botEvery`) and since this event (`sameEvery`), its side's (`sideEvery`), and the event's chance
-- (`roll` 0..1 against `cfg.chance[event]`; an event with no chance is never said).
function BotCallouts.can(
	s: State,
	id: any,
	side: string,
	event: string,
	now: number,
	nearest: number,
	roll: number,
	cfg: any
): boolean
	if nearest > cfg.near then
		return false
	end
	local chance = cfg.chance[event]
	if not chance or roll >= chance then
		return false
	end
	local b = s.bots[id]
	if b then
		if now - b.at < cfg.botEvery then
			return false
		end
		local last = b.events[event]
		if last and now - last < cfg.sameEvery then
			return false
		end
	end
	local sideAt = s.sides[side]
	if sideAt and now - sideAt < cfg.sideEvery then
		return false
	end
	return true
end

-- Notes that bot `id` on `side` called out `event` at `now`.
function BotCallouts.said(s: State, id: any, side: string, event: string, now: number)
	local b = s.bots[id]
	if not b then
		b = { at = now, events = {} }
		s.bots[id] = b
	end
	b.at = now
	b.events[event] = now
	s.sides[side] = now
end

-- Forgets bot `id` (it left).
function BotCallouts.forget(s: State, id: any)
	s.bots[id] = nil
end

-- One of `lines` (`roll` 0..1), its "{name}" filled with `name` (a line needing a name is skipped without one); nil
-- when there is none to say.
function BotCallouts.line(lines: { string }?, roll: number, name: string?): string?
	if not lines then
		return nil
	end
	local can = {}
	for _, l in lines do
		if name or not string.find(l, "{name}", 1, true) then
			table.insert(can, l)
		end
	end
	if #can == 0 then
		return nil
	end
	local pick = can[math.clamp(math.floor(roll * #can) + 1, 1, #can)]
	return (string.gsub(pick, "{name}", name or ""))
end

return BotCallouts
