--!strict
-- Healing rules (H1; Config/Healing): which item a patient needs, how long a heal takes, slow recovery, the next wrap.
-- Plain numbers, so Lune tests run them.

local Healing = {}

export type Cfg = {
	MedPackFrom: number,
	SecondsPerHp: number,
	MaxSeconds: number,
	Recovery: { cap: number, delay: number, rate: number },
	Wraps: { { entry: string, part: string } },
	Grab: { time: number, take: number },
	Open: { time: number },
}

-- The item a patient at `health` of `max` gets: the med pack from MedPackFrom up, the bandage below; nil when there is
-- nothing to heal (full, or dead).
function Healing.kind(health: number, max: number, cfg: Cfg): ("MedPack" | "Bandage")?
	if health <= 0 or health >= max then
		return nil
	end
	return if health >= cfg.MedPackFrom then "MedPack" else "Bandage"
end

-- Seconds from the start of a heal until the patient's health starts to rise: the grab from the pack, and for the med
-- pack its opening too.
function Healing.prep(kind: string, cfg: Cfg): number
	return cfg.Grab.time + (if kind == "MedPack" then cfg.Open.time else 0)
end

-- Health healed per second (to full: SecondsPerHp a point, so a whole bar takes at most MaxSeconds).
function Healing.rate(max: number, cfg: Cfg): number
	return 1 / math.min(cfg.SecondsPerHp, cfg.MaxSeconds / math.max(max, 1))
end

-- Seconds a heal from `health` to `max` takes.
function Healing.duration(health: number, max: number, cfg: Cfg): number
	return math.max(max - health, 0) / Healing.rate(max, cfg)
end

-- One heal step: the health after `dt` seconds of healing (never past max).
function Healing.step(health: number, max: number, dt: number, cfg: Cfg): number
	return math.min(max, health + Healing.rate(max, cfg) * dt)
end

-- Slow recovery: the health after `dt` seconds, `since` seconds after the last hit; never above the cap, never lowers.
function Healing.recover(health: number, since: number, dt: number, cfg: Cfg): number
	local r = cfg.Recovery
	if health <= 0 or health >= r.cap or since < r.delay then
		return health
	end
	return math.min(r.cap, health + r.rate * dt)
end

-- The wrap a finished bandage heal adds when the patient already has `count`, or nil (all on).
function Healing.nextWrap(count: number, cfg: Cfg): { entry: string, part: string }?
	return cfg.Wraps[count + 1]
end

-- Whether two soldiers `distance` studs apart are close enough: to start (Range plus `slack`) or to go on (Break).
function Healing.inReach(distance: number, limit: number, slack: number?): boolean
	return distance == distance and distance <= limit + (slack or 0)
end

return Healing
