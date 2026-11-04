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

-- The replay of a long match (user 2026-11-03: "if the match summary is really long, how will we deal with that?"):
-- its last `most` captures (it always takes the same time, so more would crowd it), and which of them carry their
-- time: the latest at each point only (a point taken back and forth shows one time, not a stack).
function MatchStats.replayLog(log: { { index: number } }, most: number): ({ any }, { boolean })
	local first = math.max(1, #log - most + 1)
	local shown = {}
	for k = first, #log do
		table.insert(shown, log[k])
	end
	local timed = {}
	for k, e in shown do
		timed[k] = true
		for j = k + 1, #shown do
			if shown[j].index == e.index then
				timed[k] = false
				break
			end
		end
	end
	return shown, timed
end

-- A match clock's text: minutes and seconds ("14:32").
function MatchStats.clock(seconds: number): string
	local s = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", s // 60, s % 60)
end

return MatchStats
