--!strict
-- Normal bots sapping forward (Config/Bots.Sap; user 2026-11-02: "currently AI dont build trenches to push forward.
-- they should do it if they are obviously unable to advance under fire and need trenches"; "30 s stuck, half dig"): an
-- attacking squad that can't get forward under fire digs a zig-zag trench (a sap) toward its objective, run by run, half
-- of it digging while the rest give covering fire, and moves up each run once it is dug. Pure: the server
-- (src/server/Bots) plans and digs the runs through src/server/Build's planAs / workAs.

local BotSap = {}

-- Whether a squad is stuck: `since` seconds from its mark (the last time it gained `cfg.progress` studs toward its
-- objective) with less than that gained (`gained`), and either shot at (`underFire`) or `lost` members down since the
-- mark (at least `cfg.losses`).
function BotSap.stalled(
	since: number,
	gained: number,
	underFire: boolean,
	lost: number,
	cfg: { stall: number, progress: number, losses: number }
): boolean
	return since >= cfg.stall and gained < cfg.progress and (underFire or lost >= cfg.losses)
end

-- Run `k` (1, 2, ...) of a sap from (hx, hz) toward the objective (ox, oz): `cfg.run` studs long (no further than the
-- objective), turned `cfg.angle` degrees off the straight line, to one side then the other (a zig-zag: no straight
-- line of fire down it). Returns its far end.
function BotSap.run(
	hx: number,
	hz: number,
	ox: number,
	oz: number,
	k: number,
	cfg: { run: number, angle: number }
): (number, number)
	local dx, dz = ox - hx, oz - hz
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 1e-6 then
		return hx, hz
	end
	local a = math.rad(cfg.angle) * (if k % 2 == 1 then 1 else -1)
	local ux, uz = dx / dist, dz / dist
	local rx, rz = ux * math.cos(a) - uz * math.sin(a), ux * math.sin(a) + uz * math.cos(a)
	local len = math.min(cfg.run, dist)
	return hx + rx * len, hz + rz * len
end

-- Whether a sap is over: its head within `edge` studs of the objective, or `quiet` seconds with nobody shooting at the
-- squad (it can get forward in the open again).
function BotSap.over(headToObjective: number, edge: number, sinceFire: number, quiet: number): boolean
	return headToObjective <= edge or sinceFire >= quiet
end

return BotSap
