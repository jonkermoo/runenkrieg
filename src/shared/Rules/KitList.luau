--!strict
-- The kit list's logic (src/client/KitList, Config/Hud.Kit): the rows' order, what a number key does, how visible the
-- list is. Pure.

local KitList = {}

-- a slot carried this life (Config/Weapons `slot`), `first` the moment it first came
export type Row = { slot: string, first: number }

-- The rows top to bottom: by their slot's place in `order` (Config/Hud.Kit.order), any other slot after them in the
-- order they first came. A new table (the same row tables); `rows` is left as it is.
function KitList.sort(rows: { Row }, order: { string }): { Row }
	local out = table.clone(rows)
	local function rank(r: Row): number
		return table.find(order, r.slot) or #order + 1
	end
	table.sort(out, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a.first < b.first
	end)
	return out
end

-- What pressing row `n`'s key does when there are `rows` rows: "draw" its item, "stow" it (it is the one in the hands),
-- or nil (no such row, or the row is `empty`: its last grenade thrown).
function KitList.press(n: number, rows: number, empty: boolean, held: boolean): string?
	if n < 1 or n > rows or empty then
		return nil
	end
	return if held then "stow" else "draw"
end

export type Show = { linger: number, fade: number }

-- How visible the list is (0 hidden .. 1 full) `since` seconds after the last change: hidden while `aiming`, full while
-- `pinned` (build mode open), else full for `cfg.linger` seconds, then fading out over `cfg.fade`.
function KitList.alpha(since: number, pinned: boolean, aiming: boolean, cfg: Show): number
	if aiming then
		return 0
	elseif pinned or since < cfg.linger then
		return 1
	elseif cfg.fade <= 0 then
		return 0
	end
	return math.clamp(1 - (since - cfg.linger) / cfg.fade, 0, 1)
end

return KitList
