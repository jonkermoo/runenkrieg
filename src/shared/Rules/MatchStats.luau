--!strict
-- A match's results (src/server/MatchStats, src/client/Results; user 2026-10-31, the results screen R3 / F1): the
-- honours (most kills, most HP healed, most HP built), the FFA standings and when the map replay draws each capture.
-- Pure: numbers and tables only.

local MatchStats = {}

export type Row = { id: number, name: string, kit: string?, [string]: any }
export type Honour = { name: string, kit: string?, value: number }

-- The best row by `key` (more first, a tie to the name first in the alphabet); nil when nobody has any.
function MatchStats.best(rows: { Row }, key: string): Honour?
	local top: Row? = nil
	for _, r in rows do
		local v = r[key] or 0
		if v > 0 then
			local t = top
			if not t or v > (t[key] or 0) or (v == (t[key] or 0) and r.name < t.name) then
				top = r
			end
		end
	end
	if not top then
		return nil
	end
	return { name = top.name, kit = top.kit, value = math.floor(top[key] + 0.5) }
end

-- Every row's place by `key` (more first, a tie to the name first in the alphabet).
function MatchStats.ranked(rows: { Row }, key: string): { Row }
	local out = table.clone(rows)
	table.sort(out, function(a, b)
		local x, y = a[key] or 0, b[key] or 0
		if x ~= y then
			return x > y
		end
		return a.name < b.name
	end)
	return out
end

-- The standings shown (F1): the first `top` by `key`, and `me` (by id) after them with its place when it's lower.
-- Each entry: { place, name, value, me }.
function MatchStats.standings(rows: { Row }, key: string, top: number, me: number?): { { [string]: any } }
	local ranked = MatchStats.ranked(rows, key)
	local out = {}
	for i, r in ranked do
		if i <= top or r.id == me then
			table.insert(out, { place = i, name = r.name, value = r[key] or 0, me = r.id == me })
		end
	end
	return out
end

-- When the replay draws capture `k` of `n` (seconds from its start): `lead` in, the last done `tail` before `total`,
-- the rest evenly between.
function MatchStats.replayAt(k: number, n: number, total: number, lead: number, tail: number): number
	if n <= 1 then
		return lead
	end
	return lead + (k - 1) * (total - lead - tail) / (n - 1)
end

-- A match clock's text: minutes and seconds ("14:32").
function MatchStats.clock(seconds: number): string
	local s = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", s // 60, s % 60)
end

return MatchStats
