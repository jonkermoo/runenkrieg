--!strict
-- Classes and the match currency (Config/Classes; src/server/Loadouts): which class a soldier spawns as and what it
-- pays, the gear it carries per kit, what it may build, and who is credited for a death.

local Classes = {}

-- What a life as class `d` costs now: its unlock while it isn't unlocked this match (`unlocked`; the unlock pays that
-- first life), else its fee.
function Classes.price(d: any, unlocked: boolean?): number
	return if unlocked then d.fee else d.unlock
end

-- The class a soldier spawns as and what it pays: their `picked` class when it exists, isn't locked and `points` cover
-- its price (Classes.price, with `unlocked` the classes they unlocked this match); else the default (free). A `forced`
-- class (the admin panel's, src/server/DevTools) that exists wins, locked or not, and is free.
function Classes.resolve(
	picked: unknown,
	points: number,
	defs: { [string]: any },
	default: string,
	forced: unknown?,
	unlocked: { [string]: boolean }?
): (string, number)
	if type(forced) == "string" and defs[forced] then
		return forced, 0
	end
	local d = if type(picked) == "string" then defs[picked] else nil
	if d and not d.locked then
		local price = Classes.price(d, unlocked and unlocked[picked :: string])
		if price <= points then
			return picked :: string, price
		end
	end
	return default, 0
end

-- The points a heal of `hp` health pays: `per` points for every `every` health (Config/Classes.Earn.Heal, HealPer).
function Classes.healPay(hp: number, per: number, every: number): number
	return math.max(hp, 0) * per / every
end

-- Whether a drag that moved the body `moved` studs pays: far enough and not yet paid this knock-down.
function Classes.dragPays(moved: number, least: number, paid: boolean?): boolean
	return not paid and moved >= least
end

-- Whether a class can be picked at all (exists and isn't locked); paying is checked at the spawn.
function Classes.pickable(key: unknown, defs: { [string]: any }): boolean
	local d = if type(key) == "string" then defs[key] else nil
	return d ~= nil and not d.locked
end

export type Gear = { Primary: string?, Grenade: string?, Shovel: string?, headwear: string? }

-- What class `key` carries in kit `kitName`: the primary, grenades (or none), the shovel and the helmet.
function Classes.gear(
	key: string,
	kitName: string,
	defs: { [string]: any },
	kits: { [string]: any },
	gear: { [string]: { [string]: string } }
): Gear
	local d = defs[key]
	local kit = kits[kitName]
	local own = gear[kitName] or {}
	if not d or not kit then
		return {}
	end
	return {
		Primary = if d.primary == "weapon" then kit.weapon else own[d.primary],
		Grenade = if d.grenades then kit.grenade else nil,
		Shovel = kit.shovel,
		headwear = if d.helmet then own[d.helmet] or kit.headwear else kit.headwear,
	}
end

-- Whether class `key` may lay and build a piece of `kind` (Config/Build.Pieces); an unknown class builds what the
-- default does.
function Classes.mayBuild(key: unknown, kind: string, defs: { [string]: any }, default: string): boolean
	local d = (if type(key) == "string" then defs[key] else nil) or defs[default]
	return d ~= nil and table.find(d.builds, kind) ~= nil
end

-- The pieces (Config/Build.Pieces, in order) class `key` may build: the build cycle shows only these (user
-- 2026-10-27: "no need to show "engineers only" for the artillery just dont show it in the cycle at all").
function Classes.buildable<P>(key: unknown, pieces: { P }, defs: { [string]: any }, default: string): { P }
	local out = {}
	for _, p in pieces do
		if Classes.mayBuild(key, (p :: any).kind, defs, default) then
			table.insert(out, p)
		end
	end
	return out
end

export type Hit = { by: number, amount: number, at: number, zone: string? }

-- Who is credited for a death at `now` from the hits it took (`by` a player's id; the victim's own left out): the
-- latest hitter within `window` seconds gets the kill (and whether that hit was to the head), every other who took at
-- least `least` off them in that time an assist.
function Classes.credit(
	hits: { Hit },
	victim: number?,
	now: number,
	window: number,
	least: number
): (number?, boolean, { number })
	local killer, last, head = nil, -math.huge, false
	local dealt: { [number]: number } = {}
	local order: { number } = {}
	for _, h in hits do
		if h.by ~= victim and now - h.at <= window then
			if not dealt[h.by] then
				dealt[h.by] = 0
				table.insert(order, h.by)
			end
			dealt[h.by] += h.amount
			if h.at >= last then
				killer, last, head = h.by, h.at, h.zone == "Head"
			end
		end
	end
	local assists = {}
	for _, id in order do
		if id ~= killer and dealt[id] >= least then
			table.insert(assists, id)
		end
	end
	return killer, head, assists
end

-- Points after earning `amount` (never below 0).
function Classes.earn(points: number, amount: number): number
	return math.max(points + amount, 0)
end

-- `cost`: what a life as it costs now (Classes.price); `unlock` and `fee` its prices; `unlocked` this match
export type Card = {
	key: string,
	name: string,
	cost: number,
	unlock: number,
	fee: number,
	unlocked: boolean,
	locked: boolean,
	affordable: boolean,
}
export type State = { points: number, picked: string, current: string?, classes: { Card } }

-- What the loadout menu shows (Net "Loadout"): the points, the pick, the class this life and every class's card
-- (`unlocked`: the classes unlocked this match).
function Classes.state(
	points: number,
	picked: string,
	current: string?,
	list: { string },
	defs: { [string]: any },
	unlocked: { [string]: boolean }?
): State
	local cards = {}
	for _, key in list do
		local d = defs[key]
		local open = (unlocked and unlocked[key]) == true or d.unlock == 0
		local cost = Classes.price(d, open)
		table.insert(cards, {
			key = key,
			name = d.name,
			cost = cost,
			unlock = d.unlock,
			fee = d.fee,
			unlocked = open,
			locked = d.locked == true,
			affordable = d.locked ~= true and cost <= points,
		})
	end
	return { points = points, picked = picked, current = current, classes = cards }
end

return Classes
