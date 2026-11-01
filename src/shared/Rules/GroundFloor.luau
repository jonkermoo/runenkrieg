--!strict
-- How deep blasts may cut the ground (Config/Damage.Blast.Crater.Floor; user 2026-10-31: "it should be based off
-- thickness not location, so entire hills cant be destroyed and low ground cant have a hole torn through the map").
-- Each column keeps a floor set by its ground as it first was (its surface and the base under it), never by how it is
-- now, so blast after blast can't work down past it. Pure: numbers only.

local GroundFloor = {}

export type Cfg = {
	minKeep: number,
	coreShare: number,
}

-- A column's ground (`occs` bottom to top, `y0` the bottom voxel's base, `res` the voxel size; empty and water voxels
-- 0): the top of its highest solid voxel and the base of its lowest, or nil when it has none.
function GroundFloor.span(occs: { number }, y0: number, res: number): (number?, number?)
	local surface, base = nil, nil
	for i, o in occs do
		if o > 0 then
			base = base or y0 + (i - 1) * res
			surface = y0 + (i - 1) * res + o * res
		end
	end
	return surface, base
end

-- The lowest the ground may be cut to in a column whose ground first stood from `base` up to `surface`: at least
-- `minKeep` studs over its base (thin low ground keeps a bottom) and `coreShare` of its thickness (a hill keeps its
-- core), never over its surface.
function GroundFloor.floor(surface: number, base: number, c: Cfg): number
	local thick = surface - base
	return base + math.min(thick, math.max(c.minKeep, thick * c.coreShare))
end

-- A column cut from `before` to `after` (occupancies bottom to top, `y0`, `res` as GroundFloor.span) held at `floor`:
-- each voxel keeps what it had under the floor. Nothing is added that `before` didn't have.
function GroundFloor.hold(before: { number }, after: { number }, y0: number, res: number, floor: number): { number }
	local out = table.create(#after, 0)
	for i, o in after do
		local keep = math.clamp((floor - (y0 + (i - 1) * res)) / res, 0, 1)
		out[i] = math.max(o, math.min(before[i], keep))
	end
	return out
end

return GroundFloor
