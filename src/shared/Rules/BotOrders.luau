--!strict
-- A side's bot orders in Normal as plain numbers (Config/Bots.Normal; src/server/Bots gives them). Each side's commander
-- looks at the sectors (who holds each, its control, the soldiers in each zone) and sends its bots to two places at
-- most: the sector the side attacks (Rules/Frontline.target) and, while one of its own sectors is being taken, that
-- sector to defend. A bot keeps its order while the share allows, so orders don't flicker between ticks.

local BotOrders = {}

export type Order = "Attack" | "Defend"
export type Plan = { attack: number?, defend: number?, share: number }

local function enemy(side: string): string
	return if side == "West" then "East" else "West"
end

-- Whether the enemy is taking `side`'s sector `i`: enemies in its zone, and either more of them than defenders or its
-- control off `side`'s end (control runs from 1, West's, to -1, East's).
local function underAttack(side: string, control: number, counts: { West: number, East: number }): boolean
	local foes = (counts :: any)[enemy(side)]
	local own = (counts :: any)[side]
	if foes <= 0 then
		return false
	end
	local rest = if side == "West" then 1 else -1
	return foes > own or math.abs(control - rest) > 1e-3
end

-- Where `side`'s bots go: `target` (the sector it attacks, nil when none) and, while an own sector is under attack,
-- that one with `share` (Config/Bots.Normal.defendShare) of the bots: the one with most enemies in it, the frontmost
-- on a tie (nearest the enemy's end). With none under attack and a `front` (the side's sector nearest the enemy),
-- `hold` of the bots hold it (and dig in there: Rules/BotTrenches; user 2026-11-02: "dig in at once").
function BotOrders.plan(
	side: string,
	owner: { string },
	control: { number },
	counts: { { West: number, East: number } },
	target: number?,
	share: number,
	front: number?,
	hold: number?
): Plan
	local defend: number? = nil
	local most = 0
	local n = #owner
	for k = 1, n do
		-- from the side's front backwards: the frontmost wins a tie
		local i = if side == "West" then n + 1 - k else k
		if owner[i] == side and counts[i] and underAttack(side, control[i], counts[i]) then
			local foes = (counts[i] :: any)[enemy(side)]
			if foes > most then
				most = foes
				defend = i
			end
		end
	end
	if not target and defend then
		return { attack = nil, defend = defend, share = 1 }
	end
	if not defend and target and front and hold and hold > 0 then
		return { attack = target, defend = front, share = hold }
	end
	return { attack = target, defend = defend, share = if defend then share else 0 }
end

-- How many of `bots` defend at `share`: rounded, at least one when there is a share and two bots or more, never all
-- while there is a sector to attack.
function BotOrders.defenders(bots: number, share: number, attacking: boolean): number
	if share <= 0 or bots <= 0 then
		return 0
	end
	if not attacking then
		return bots
	end
	local d = math.floor(bots * share + 0.5)
	if bots >= 2 then
		d = math.clamp(d, 1, bots - 1)
	else
		d = 0
	end
	return d
end

-- The orders for `ids` (in a steady order) given each one's `current` order: `defenders` of them Defend, the rest
-- Attack, moving as few as it can (the defenders kept first, then the next in line).
function BotOrders.assign(ids: { any }, current: { [any]: Order }, defenders: number): { [any]: Order }
	local out: { [any]: Order } = {}
	local left = defenders
	for _, id in ids do
		if current[id] == "Defend" and left > 0 then
			out[id] = "Defend"
			left -= 1
		end
	end
	for _, id in ids do
		if out[id] == nil then
			if left > 0 then
				out[id] = "Defend"
				left -= 1
			else
				out[id] = "Attack"
			end
		end
	end
	return out
end

return BotOrders
