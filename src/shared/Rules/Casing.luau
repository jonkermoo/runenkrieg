--!strict
-- A spent case or belt link landing (Config/Cases, src/client/CaseDrop): which surface it hit, and how its clink plays
-- there. Pure.

local Casing = {}

export type Surface = { volume: number, eq: { number } }
-- a gun's cartridge case (Config/Weapons `casing`)
export type Case = { pitch: number, volume: number, eq: { number } }
export type Cases = {
	surfaces: { [string]: Surface },
	materials: { [string]: string },
	default: string,
}

-- The surface a material (its Enum.Material name) counts as.
function Casing.surface(material: string, c: Cases): string
	return c.materials[material] or c.default
end

-- How a clink plays on `surface`, for a gun's `case` (none: an MG case or link, as its kind is): a share of the
-- sound's volume, times its pitch, an eq (dB, low / mid / high) on top of the sound's own.
function Casing.sound(case: Case?, surface: string, c: Cases): (number, number, { number })
	local s = c.surfaces[surface] or c.surfaces[c.default]
	local own = case or { pitch = 1, volume = 1, eq = { 0, 0, 0 } }
	return own.volume * s.volume, own.pitch, { own.eq[1] + s.eq[1], own.eq[2] + s.eq[2], own.eq[3] + s.eq[3] }
end

-- Which lying cases go once one more lies down: the oldest past `max` (a list oldest first, `count` of them).
function Casing.excess(count: number, max: number): number
	return math.max(0, count - max)
end

return Casing
