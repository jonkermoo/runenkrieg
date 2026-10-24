--!strict
-- Craters fill back in over time (Config/Damage.Blast.Crater.Refill; user 2026-10-23: "during long battles i dont want
-- the map to disappear because of craters"). Each voxel a blast changed keeps what it was before; after `delay` s it
-- eases back to that in `steps` even steps over `time` s, then stays mud `mud` s more before its own material returns.
-- Dug ground (trenches, gun pits) never refills: the server leaves those voxels out. Pure: numbers only; materials are
-- opaque values, `air` is the empty one.

local Refill = {}

export type Cfg = {
	delay: number,
	time: number,
	mud: number,
	steps: number,
	maxCraters: number,
	rimFill: number,
}

-- how far a crater `age` s old has filled back (0..1), in whole steps
function Refill.share(age: number, r: Cfg): number
	if r.time <= 0 then
		return if age >= r.delay then 1 else 0
	end
	local s = math.clamp((age - r.delay) / r.time, 0, 1)
	return math.floor(s * r.steps + 1e-9) / r.steps
end

-- whether a crater `age` s old is done: filled and its mud gone
function Refill.done(age: number, r: Cfg): boolean
	return age >= r.delay + r.time + r.mud
end

-- a voxel's occupancy at `share`: from `from` (just after the blast) back to `before`
function Refill.occupancy(from: number, before: number, share: number): number
	return from + (before - from) * math.clamp(share, 0, 1)
end

-- A voxel's material at occupancy `occ`: empty is `air`; once `done`, what it was before (or, where it was empty before
-- and still holds earth, what the blast made it); until then what the blast made it, and earth put back is `mud`.
function Refill.material<M>(occ: number, before: M, from: M, done: boolean, air: M, mud: M): M
	if occ <= 0 then
		return air
	end
	if done and before ~= air then
		return before
	end
	if from ~= air then
		return from
	end
	return mud
end

-- How many of the oldest craters start filling now (their wait cut short) when `count` craters are still waiting and at
-- most `cap` may wait (0: no cap).
function Refill.overCap(count: number, cap: number): number
	if cap <= 0 then
		return 0
	end
	return math.max(count - cap, 0)
end

-- the age a crater that must start filling now is given (its wait over, nothing filled yet)
function Refill.startNow(age: number, r: Cfg): number
	return math.max(age, r.delay)
end

-- whether a point `rho` studs from a new blast lies under the earth it throws: past its bowl's `mouth`, out to `outer`
function Refill.underRim(rho: number, mouth: number, outer: number): boolean
	return rho > mouth and rho <= outer
end

-- An older crater's voxel at occupancy `occ` under a new blast's thrown earth: `rimFill` of what it still lacks of
-- `before` is put back now (nothing taken away).
function Refill.rimFilled(occ: number, before: number, rimFill: number): number
	if before <= occ then
		return occ
	end
	return occ + (before - occ) * math.clamp(rimFill, 0, 1)
end

return Refill
