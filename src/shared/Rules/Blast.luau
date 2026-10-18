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

export type SectionHit = {
	fail: number, -- its class's fail pressure (kPa)
	maxHP: number,
	hp: number, -- what it has left
	weaken: number,
	wear: number?, -- at most this share of maxHP per blast (Config/Damage.Staff.Blasts `wear`), nil: no cap
	wearFull: number?, -- ...in full within this many studs of the blast
	wearReach: number?, -- ...fading to 0 at this many
	distance: number?, -- the section's distance from the blast (studs), for `wearReach`
	keep: boolean?, -- never broken, only worn (Config/Damage.Blast.WearOnly): it keeps at least 1 HP
	brittle: boolean?, -- breaks at `fail` or takes nothing (Config/Damage.Blast.Brittle)
}

-- what a map section loses to a blast at `kpa`: Blast.sectionDamage (all or nothing when brittle), capped by a light
-- blast's `wear` (in full to `wearFull`, fading out to `wearReach`), and short of breaking it when it must be kept
function Blast.sectionHit(kpa: number, s: SectionHit): number
	local amount = Blast.sectionDamage(kpa, s.fail, s.maxHP, s.weaken)
	if s.brittle and amount < s.maxHP then
		amount = 0
	end
	if s.wear then
		local share = s.wear
		if s.wearReach then
			local full = math.min(s.wearFull or 0, s.wearReach)
			local d = s.distance or 0
			if d >= s.wearReach then
				share = 0
			elseif d > full then
				share *= 1 - (d - full) / (s.wearReach - full)
			end
		end
		amount = math.min(amount, share * s.maxHP)
	end
	if s.keep then
		amount = math.min(amount, math.max(s.hp - 1, 0))
	end
	return amount
end

-- how far from a `kg` charge the overpressure falls to `kpa` (studs; 0 if it never reaches that)
function Blast.reachOf(kpa: number, kg: number, cfg: { MetresPerStud: number, AmbientKPa: number }): number
	if kg <= 0 or Blast.kpa(0, kg, cfg) < kpa then
		return 0
	end
	local lo, hi = 0, 1
	while Blast.kpa(hi, kg, cfg) >= kpa do
		hi *= 2
	end
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		if Blast.kpa(mid, kg, cfg) >= kpa then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

-- How much of a blast reaches a soldier behind cover (user 2026-10-18): the share of their body parts with a clear
-- line from the blast (`clear` of `total`); below `minShare`, none. The knock needs at least `knockShare`.
function Blast.exposure(clear: number, total: number, minShare: number): number
	if total <= 0 then
		return 1
	end
	local share = math.clamp(clear / total, 0, 1)
	return if share < minShare then 0 else share
end

-- the crater's radius (studs) for a `kg` charge
function Blast.crater(kg: number, perCubeRoot: number): number
	return if kg > 0 then perCubeRoot * kg ^ (1 / 3) else 0
end

-- How far a blast reaching `reach` studs (Damage.blast's search, Config/Damage.Blast.Reach) churns the ground: the same
-- for every charge, since both grow by its cube root. Clients get only the reach (Net "Explosion").
function Blast.churnFromReach(reach: number, b: any): number
	return reach * b.Crater.churn * b.Crater.perCubeRoot * b.MetresPerStud / b.Reach
end

export type CraterPlan = {
	radius: number, -- the hole's ball
	sink: number, -- how far under the blast point the hole's centre is
	rim: { { dx: number, dz: number, radius: number, sink: number } }, -- balls of earth round it, under the ground
	churn: number, -- the ground out to here turns to blasted earth
}

-- The crater a `kg` charge leaves (Config/Damage.Blast.Crater): the hole, its low rim of earth and how far the ground
-- around is churned. Nothing for no charge.
function Blast.craterPlan(kg: number, c: any): CraterPlan?
	return Blast.craterPlanFor(Blast.crater(kg, c.perCubeRoot), c)
end

-- the same for a hole of radius `r`
function Blast.craterPlanFor(r: number, c: any): CraterPlan?
	if r <= 0 then
		return nil
	end
	local rim = {}
	for i = 1, c.rim.count do
		local a = (i - 1) / c.rim.count * 2 * math.pi
		table.insert(rim, {
			dx = math.cos(a) * c.rim.at * r,
			dz = math.sin(a) * c.rim.at * r,
			radius = c.rim.size * r,
			sink = c.rim.sink * r,
		})
	end
	return { radius = r, sink = c.sink * r, rim = rim, churn = c.churn * r }
end

return Blast
