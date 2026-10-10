--!strict
-- Pure destruction rules (docs/DESTRUCTION.md): blast falloff, structural collapse, color schemes.

local Destruction = {}

-- Damage at distance d from a blast of `damage` with `radius`: full at the center, 0 at the edge.
function Destruction.blastDamage(d: number, radius: number, damage: number): number
	if d >= radius then
		return 0
	end
	return damage * (1 - d / radius) ^ 1.5
end

-- counts[story] = { initial = n, standing = m } for WALL sections. Returns the lowest story whose
-- standing walls fell below `fraction` of the original (it and everything above collapse), or nil.
function Destruction.collapseFrom(
	counts: { [number]: { initial: number, standing: number } },
	fraction: number
): number?
	local lowest: number? = nil
	for story, c in counts do
		if c.initial > 0 and c.standing / c.initial < fraction then
			if lowest == nil or story < lowest then
				lowest = story
			end
		end
	end
	return lowest
end

export type Scheme = { wall: string, roof: string, trim: number, door: number }

-- Deterministic color scheme for one copy of a template: wall + roof keys from the template's allowed
-- lists, trim/door indices into the palette lists.
function Destruction.scheme(template: any, palette: any, seed: number): Scheme
	-- independent digits of the seed per role, so wall/roof/door choices don't move together
	seed = math.abs(math.floor(seed))
	return {
		wall = template.walls[seed % #template.walls + 1],
		roof = template.roofs[(seed // 5) % #template.roofs + 1],
		trim = (seed // 23) % #palette.Buildings.Trim + 1,
		door = (seed // 3) % #palette.Buildings.Doors + 1,
	}
end

return Destruction
