--!strict
-- Mage bots (Config/Bots.Staff; user 2026-11-02): which staff stage a bot casts, and whether a teammate is in the way
-- of a beam or near its blast. Pure: the server (src/server/Bots) casts through src/server/StaffCast's openAs / aimAs /
-- castAs, with the players' mana, cooldowns and holds.

local BotStaff = {}

-- What a bot knows at the moment it would cast (`visible` false: at where its squad last knew an enemy, behind cover)
export type Shot = {
	distance: number,
	visible: boolean,
	affordable: number, -- the highest stage its mana pays for (0: none)
	group: number, -- enemies within the cluster of the target (the target too)
	strong: boolean, -- the target is in a building, an MG nest or at a gun
	mateOnLine: boolean, -- a teammate near the beam's line
	mateNearBlast: boolean, -- a teammate near where a mega shot lands
}

-- The stage to cast (0: none), the strongest the shot calls for and the mana pays for, each within its range
-- (`ranges`: Config/Damage.Staff.Range):
-- - Full (3): at a group of `cfg.megaGroup` or a strongpoint, no teammate near the blast (user: "Groups and
--   strongpoints");
-- - Medium (2): past the quick shot's range, at cover (not visible), a group of 2 or more, or a strongpoint;
-- - Quick (1): a seen target within its range.
-- Never with a teammate near the beam's line.
function BotStaff.stage(s: Shot, ranges: { number }, cfg: { megaGroup: number }): number
	if s.mateOnLine or s.affordable < 1 then
		return 0
	end
	if
		s.affordable >= 3
		and s.distance <= ranges[3]
		and (s.group >= cfg.megaGroup or s.strong)
		and not s.mateNearBlast
	then
		return 3
	end
	if
		s.affordable >= 2
		and s.distance <= ranges[2]
		and (s.distance > ranges[1] or not s.visible or s.group >= 2 or s.strong)
	then
		return 2
	end
	if s.visible and s.distance <= ranges[1] then
		return 1
	end
	return 0
end

-- How far point (px, pz) lies from the flat segment (ax, az)-(bx, bz).
function BotStaff.toSegment(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) else 0
	local cx, cz = ax + dx * t, az + dz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

-- Whether any of `mates` (not the caster) stands within `line` studs of the beam from (ax, az) to (bx, bz), and
-- whether any stands within `blast` of (bx, bz).
function BotStaff.mates(
	mates: { { x: number, z: number } },
	ax: number,
	az: number,
	bx: number,
	bz: number,
	line: number,
	blast: number
): (boolean, boolean)
	local onLine, nearBlast = false, false
	for _, m in mates do
		if BotStaff.toSegment(m.x, m.z, ax, az, bx, bz) <= line then
			onLine = true
		end
		if math.sqrt((m.x - bx) ^ 2 + (m.z - bz) ^ 2) <= blast then
			nearBlast = true
		end
	end
	return onLine, nearBlast
end

-- Whether an open circle is released now: held its stage's `hold` and the cooldown over (`readyIn` 0).
function BotStaff.release(held: number, hold: number, readyIn: number): boolean
	return held >= hold and readyIn <= 0
end

return BotStaff
