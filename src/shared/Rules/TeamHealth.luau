--!strict
-- Teammates' health outlines (Config/TeamHealth, Palette.UI.TeamHealth; src/client/TeamHealth draws them).

local TeamHealth = {}

export type Stop = { at: number, color: { number } }

-- The outline's colour for `health` of `max`: the stops' colours (sorted from full down) shaded between them; above
-- the first stop it's the first's, at or below the last it's the last's.
function TeamHealth.shade(health: number, max: number, stops: { Stop }): { number }
	local share = if max > 0 then math.clamp(health / max, 0, 1) else 0
	local first, last = stops[1], stops[#stops]
	if share >= first.at then
		return table.clone(first.color)
	end
	for i = 2, #stops do
		local hi, lo = stops[i - 1], stops[i]
		if share >= lo.at then
			local t = (share - lo.at) / (hi.at - lo.at)
			local out = {}
			for c = 1, 3 do
				out[c] = math.round(lo.color[c] + (hi.color[c] - lo.color[c]) * t)
			end
			return out
		end
	end
	return table.clone(last.color)
end

-- Which candidates (each `dist` studs away) get an outline: the `cap` nearest within `maxDistance`, nearest first.
function TeamHealth.pick<T>(candidates: { { key: T, dist: number } }, cap: number, maxDistance: number): { T }
	local near = {}
	for _, c in candidates do
		if c.dist <= maxDistance then
			table.insert(near, c)
		end
	end
	table.sort(near, function(a, b)
		return a.dist < b.dist
	end)
	local out = {}
	for i = 1, math.min(cap, #near) do
		out[i] = near[i].key
	end
	return out
end

return TeamHealth
