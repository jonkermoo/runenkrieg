--!strict
-- Which soldier face shows (docs/CHARACTERS.md Faces; Config/Uniforms.Faces): one face per health third, each with a
-- closed version (blinks, death).
-- VERY IMPORTANT (user 2026-10-11): a killed character shows the CLOSED face of the tier it was in LAST, so
-- healthy -> 0 in one hit shows the healthy closed face. The death face is never picked from health 0.

export type Face = { name: string, above: number, open: number, closed: number }

local Faces = {}

-- The tier (index into `faces`, top first) for a living character's health share: the first whose `above` the share
-- is over. The last tier has above = 0, so any living share lands somewhere.
function Faces.tier(share: number, faces: { Face }): number
	for i, f in faces do
		if share > f.above then
			return i
		end
	end
	return #faces
end

-- After a health change: the tier to show and whether the eyes are closed. Dead (health <= 0) keeps the last tier and
-- closes its eyes; alive picks the tier from health.
function Faces.after(lastTier: number, health: number, maxHealth: number, faces: { Face }): (number, boolean)
	if health <= 0 then
		return lastTier, true
	end
	return Faces.tier(health / math.max(maxHealth, 1e-6), faces), false
end

-- A seconds-long gap before the next blink, from a 0..1 random number.
function Faces.blinkGap(r: number, minGap: number, maxGap: number): number
	return minGap + (maxGap - minGap) * math.clamp(r, 0, 1)
end

return Faces
