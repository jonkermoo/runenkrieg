--!strict
-- What a Normal bot does besides fighting (Config/Bots.Actions; user 2026-11-01: grenades, healing, dragging): pure
-- picks on the facts src/server/Bots gathers each planner tick. Dragging a downed teammate beats healing, healing beats
-- a grenade, and each only while its conditions hold.

local BotActions = {}

export type Mate = {
	distance: number, -- studs from the bot
	health: number, -- 0..1
	down: boolean, -- knocked down (ragdolled) and alive
	busy: boolean, -- being healed or dragged already
	exposed: boolean, -- in sight of an enemy spot the bot knows
}

export type Enemy = {
	x: number,
	z: number,
	distance: number, -- studs from the bot
	visible: boolean, -- the bot sees it now
	hiddenFor: number, -- seconds it has been known but out of sight (0 while visible)
}

-- Whether the bot may stop fighting for a heal or a drag: nobody has shot at it or hit it for `calm` seconds.
function BotActions.calm(sinceThreat: number, sinceHurt: number, calm: number): boolean
	return sinceThreat >= calm and sinceHurt >= calm
end

-- Whether a bot may drag or heal a teammate now (user 2026-11-03: "when in a fight bots should only grab you if in
-- cover. else, they protect you and grab/heal you once it is safe"): when it is safe (Rules/BotBuild.safeToWork), or in
-- a fight with the bot itself hidden from the threat where it stands (`selfHidden`) or the teammate out of the enemy's
-- sight (`exposed` false).
function BotActions.mayTend(safe: boolean, selfHidden: boolean, exposed: boolean): boolean
	return safe or selfHidden or not exposed
end

-- Who rescues a casualty (user 2026-11-03 play test: "a downed soldier currently causes AI to scramble around the
-- downed soldier to heal them, breaking all push and formation ... only have 1 soldier save them"): among the free
-- bots of its side within `range` studs (each its distance and whether it is in the casualty's squad), one of its own
-- squad first, then the nearest. The index, or nil.
function BotActions.rescuer(cands: { { distance: number, sameSquad: boolean } }, range: number): number?
	local best: number? = nil
	for i, c in cands do
		if c.distance <= range then
			local o = best and cands[best]
			if
				not o
				or (c.sameSquad and not o.sameSquad)
				or (c.sameSquad == o.sameSquad and c.distance < o.distance)
			then
				best = i
			end
		end
	end
	return best
end

-- The nearest hurt teammate to heal (under `below` health, within `within` studs, alive, not being healed), or nil.
function BotActions.healPick(mates: { Mate }, cfg: { below: number, within: number }): number?
	local best, bestD = nil, math.huge
	for i, m in mates do
		if m.health > 0 and m.health < cfg.below and not m.busy and m.distance <= cfg.within and m.distance < bestD then
			best, bestD = i, m.distance
		end
	end
	return best
end

-- The nearest downed teammate in the open to drag to cover (within `within` studs, nobody dragging them), or nil.
function BotActions.dragPick(mates: { Mate }, cfg: { within: number }): number?
	local best, bestD = nil, math.huge
	for i, m in mates do
		if m.down and m.exposed and m.health > 0 and not m.busy and m.distance <= cfg.within and m.distance < bestD then
			best, bestD = i, m.distance
		end
	end
	return best
end

-- Where a grenade would do the most: the enemy with `group` or more enemies (itself counted) within `cluster` studs,
-- or one known but out of sight (in cover) for `hidden` seconds; between `min` and `max` studs off and with no
-- teammate within `safe` studs of it. The index of the enemy to throw at and how many it would catch, or nil.
function BotActions.grenadeAt(
	enemies: { Enemy },
	mates: { { x: number, z: number } },
	cfg: {
		min: number,
		max: number,
		cluster: number,
		group: number,
		hidden: number,
		safe: number,
	}
): (number?, number)
	local best, bestCount = nil, 0
	for i, e in enemies do
		if e.distance < cfg.min or e.distance > cfg.max then
			continue
		end
		local count = 0
		for _, o in enemies do
			local dx, dz = o.x - e.x, o.z - e.z
			if dx * dx + dz * dz <= cfg.cluster * cfg.cluster then
				count += 1
			end
		end
		local hiding = not e.visible and e.hiddenFor >= cfg.hidden
		if count < cfg.group and not hiding then
			continue
		end
		local clear = true
		for _, m in mates do
			local dx, dz = m.x - e.x, m.z - e.z
			if dx * dx + dz * dz < cfg.safe * cfg.safe then
				clear = false
				break
			end
		end
		if clear and count > bestCount then
			best, bestCount = i, count
		end
	end
	return best, bestCount
end

-- The throw's pitch (radians above level) that lands `d` studs off and `h` studs higher at `speed` with `gravity`:
-- the low arc; nil when it can't reach.
function BotActions.lobPitch(d: number, h: number, speed: number, gravity: number): number?
	local v2 = speed * speed
	local disc = v2 * v2 - gravity * (gravity * d * d + 2 * h * v2)
	if disc < 0 or d <= 0 then
		return nil
	end
	return math.atan((v2 - math.sqrt(disc)) / (gravity * d))
end

return BotActions
