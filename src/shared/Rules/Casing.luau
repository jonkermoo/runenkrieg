--!strict
-- A spent case landing (Config/Firing.Cases): which surface it hit, and how its clink is played there. Pure.

local Casing = {}

export type Surface = { volume: number, eq: { number } }
export type Case = { pitch: number, volume: number, eq: { number } }
export type Cases = {
	surfaces: { [string]: Surface },
	materials: { [string]: string },
	default: string,
	still: number,
}

-- The surface a material (its Enum.Material name) counts as.
function Casing.surface(material: string, c: Cases): string
	return c.materials[material] or c.default
end

-- Whether a touch at `speed` studs/s is a landing (else the case is rolling or lying still).
function Casing.lands(speed: number, c: Cases): boolean
	return speed >= c.still
end

-- How a gun's `case` sounds on `surface`: a share of the sound's volume, its pitch, its eq (dB, low / mid / high).
function Casing.sound(case: Case, surface: string, c: Cases): (number, number, { number })
	local s = c.surfaces[surface] or c.surfaces[c.default]
	return case.volume * s.volume, case.pitch, { case.eq[1] + s.eq[1], case.eq[2] + s.eq[2], case.eq[3] + s.eq[3] }
end

return Casing
