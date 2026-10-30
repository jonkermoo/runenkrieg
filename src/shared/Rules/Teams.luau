--!strict
-- Teams (user 2026-10-22: "make healing only team allowed"). Until real teams (M13) a soldier's team is the uniform kit
-- they wear this life: the character's "Kit" attribute (src/server/Kits; DEV and showcase dummies carry their own).
-- Shared by everything that only works between teammates (healing: src/server/Healing, src/client/Healing) or spares
-- them (no friendly fire: src/server/Damage, Config/Damage.FriendlyFire).

local Teams = {}

-- Whether two soldiers wearing kits `a` and `b` are on the same team: both known and equal. An unknown kit (not
-- rolled yet) is nobody's teammate; in a free-for-all (Config/ZoneMatch) nobody is.
function Teams.same(a: unknown, b: unknown, freeForAll: boolean?): boolean
	return not freeForAll and type(a) == "string" and a ~= "" and a == b
end

-- Whether a hit from a soldier in kit `by` spares one in kit `on` (user 2026-10-26: no friendly fire from guns, melee,
-- the staff's beam or blasts): teammates are spared unless `friendlyFire` is on. Hits on yourself are the caller's.
function Teams.spared(by: unknown, on: unknown, friendlyFire: boolean, freeForAll: boolean?): boolean
	return not friendlyFire and Teams.same(by, on, freeForAll)
end

-- Kept teams (Config/Teams; src/server/Deploy): each team's head count, from the team each player is on (`of`; a value
-- that isn't one of `teams` isn't counted).
function Teams.counts(of: { unknown }, teams: { string }): { [string]: number }
	local counts: { [string]: number } = {}
	for _, t in teams do
		counts[t] = 0
	end
	for _, t in of do
		if type(t) == "string" and counts[t] then
			counts[t] += 1
		end
	end
	return counts
end

-- How many soldiers each of `n` teams has room for on a server of `maxPlayers`.
function Teams.room(maxPlayers: number, n: number): number
	return math.ceil(maxPlayers / math.max(n, 1))
end

-- Why a soldier on team `own` can't change to `target` ("Own": already on it, "Full", "Bigger": the change would leave
-- it more than `gap` bigger than `own`, "Unknown": not a team), or nil when they can. `counts` include the soldier.
function Teams.blocked(counts: { [string]: number }, own: unknown, target: unknown, gap: number, room: number): string?
	if type(target) ~= "string" or counts[target] == nil then
		return "Unknown"
	end
	if target == own then
		return "Own"
	end
	local t = counts[target]
	if t >= room then
		return "Full"
	end
	local o = if type(own) == "string" then counts[own] else nil
	if o and t + 1 > o - 1 + gap then
		return "Bigger"
	end
	return nil
end

-- The teams in play: the two named by Normal mode's MatchTeams text ("west,east", Config/Frontline) when both are
-- among `all`, else all of them.
function Teams.playing(all: { string }, matchTeams: unknown): { string }
	if type(matchTeams) == "string" then
		local a, b = string.match(matchTeams, "^([^,]+),([^,]+)$")
		if a and b and a ~= b and table.find(all, a) and table.find(all, b) then
			return { a :: string, b :: string }
		end
	end
	return all
end

-- The team a newcomer joins: the one with the fewest soldiers, a tie broken by `r` in [0, 1).
function Teams.smallest(counts: { [string]: number }, teams: { string }, r: number): string
	local least = math.huge
	for _, t in teams do
		least = math.min(least, counts[t] or 0)
	end
	local tied: { string } = {}
	for _, t in teams do
		if (counts[t] or 0) == least then
			table.insert(tied, t)
		end
	end
	return tied[math.clamp(math.floor(r * #tied) + 1, 1, #tied)]
end

return Teams
