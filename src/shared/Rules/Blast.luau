--!strict
-- A blast that behaves like a real one (Config/Damage.Blast; user 2026-10-17). Hopkinson-Cranz scaled distance
-- Z = R / W^(1/3) (R metres from the charge, W kg of TNT) and the Kinney-Graham peak overpressure; from that, a
-- soldier's damage and knock, a map section's damage, whether a tree snaps, and the crater. Pure: numbers only.

local Blast = {}

-- the scaled distance (m / kg^(1/3)) at `studs` from a `kg` charge
function Blast.scaled(studs: number, kg: number, metresPerStud: number): number
	if kg <= 0 then
		return math.huge
	end
	return math.max(studs, 0) * metresPerStud / kg ^ (1 / 3)
end

-- the studs at which a `kg` charge reaches scaled distance `z`
function Blast.studsAt(z: number, kg: number, metresPerStud: number): number
	return z * kg ^ (1 / 3) / metresPerStud
end

-- Kinney-Graham peak side-on overpressure (kPa) at scaled distance `z` (m / kg^(1/3))
function Blast.overpressure(z: number, ambient: number): number
	if z == math.huge then
		return 0
	end
	z = math.max(z, 0.05) -- (inside the charge itself)
	local top = 808 * (1 + (z / 4.5) ^ 2)
	local bottom = math.sqrt((1 + (z / 0.048) ^ 2) * (1 + (z / 0.32) ^ 2) * (1 + (z / 1.35) ^ 2))
	return ambient * top / bottom
end

-- overpressure (kPa) at `studs` from a `kg` charge
function Blast.kpa(studs: number, kg: number, cfg: { MetresPerStud: number, AmbientKPa: number }): number
	return Blast.overpressure(Blast.scaled(studs, kg, cfg.MetresPerStud), cfg.AmbientKPa)
end

-- a soldier's damage at `kpa`: 0 up to `from`, rising in a straight line to `max` at `kill`
function Blast.soldierDamage(kpa: number, s: { from: number, kill: number, max: number }): number
	if kpa <= s.from then
		return 0
	end
	return s.max * math.min((kpa - s.from) / (s.kill - s.from), 1)
end

-- the knock at `kpa` (the first entry it is above), or nil
function Blast.knock(kpa: number, knocks: { { above: number, knock: string } }): string?
	for _, k in knocks do
		if kpa > k.above then
			return k.knock
		end
	end
	return nil
end

-- a map section's damage at `kpa`: all of it (`maxHP`) at its class's `fail`, MaxHP x (kpa / fail)^weaken below
function Blast.sectionDamage(kpa: number, fail: number, maxHP: number, weaken: number): number
	if kpa <= 0 then
		return 0
	end
	if kpa >= fail then
		return maxHP
	end
	return maxHP * (kpa / fail) ^ weaken
end

-- the crater's radius (studs) for a `kg` charge
function Blast.crater(kg: number, perCubeRoot: number): number
	return if kg > 0 then perCubeRoot * kg ^ (1 / 3) else 0
end

return Blast
