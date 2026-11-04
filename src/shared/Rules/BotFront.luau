--!strict
-- How a side fights its way forward in Normal (Config/Bots.Front; user 2026-11-03: "once points are starting be
-- captured and fights start (pretty early), bots should prioritize trenching lines (use real strategies) to push,
-- rather than the open field"; "bots are too focused on pushing down the center"). Pure.
-- - The side's plan: "open" (walking where it's safe) until contact (the first capture, or the first shots at one of
--   its squads), then "trench": its attacking squads sap toward the objective once near it, dig a parallel across
--   when close, and go over the top together from it (Rules/BotTrenches.jumpOff, overTop).
-- - Flanks: a share of its attacking squads takes a lane off to one side; a share of its MG nests and gun spots too
--   (Rules/BotBuild.plan, gunSpots).

local BotFront = {}

BotFront.Plans = table.freeze({ "open", "trench", "assault", "flank" })

-- The side's plan: `forced` (the admin panel) first, else "assault" while its offensive has gone (`going`:
-- Rules/BotOrders.going; Config/Bots.Offensive), else "trench" once it has had contact (`contactAt`), else "open".
function BotFront.plan(contactAt: number?, forced: string?, going: boolean?): string
	if forced then
		return forced
	end
	if going then
		return "assault"
	end
	return if contactAt then "trench" else "open"
end

-- Whether any sector changed hands between two looks at the owners (`was` nil: the first look, no).
function BotFront.captured(was: { string }?, now: { string }): boolean
	if not was then
		return false
	end
	for i, o in now do
		if was[i] ~= o then
			return true
		end
	end
	return false
end

-- Whether an attacking squad saps now: stuck under fire (`stalled`: Rules/BotSap.stalled) in any plan; in "trench"
-- (and "flank") also once within `cfg.sapFrom` studs of its objective's zone edge (`toEdge`); never while assaulting,
-- nor when `allowed` is false (its side holds the initiative and isn't gathering: Config/Bots.Sap).
function BotFront.sapNow(
	plan: string,
	stalled: boolean,
	toEdge: number,
	cfg: { sapFrom: number },
	allowed: boolean?
): boolean
	if plan == "assault" or allowed == false then
		return false
	end
	if plan == "open" then
		return stalled
	end
	return stalled or toEdge <= cfg.sapFrom
end

-- Whether a sap's head (`toEdge` studs from the objective's zone edge) is close enough for the parallel
-- (`cfg.parallel.at`).
function BotFront.parallelNow(toEdge: number, cfg: { parallel: { at: number } }): boolean
	return toEdge <= cfg.parallel.at
end

-- The parallel: a trench run `width` studs long across the way from the sap's head (hx, hz) to the objective (ox, oz),
-- centred on the head. Its two ends.
function BotFront.parallel(
	hx: number,
	hz: number,
	ox: number,
	oz: number,
	width: number
): (number, number, number, number)
	local dx, dz = ox - hx, oz - hz
	local d = math.sqrt(dx * dx + dz * dz)
	local ux, uz = if d > 1e-6 then dx / d else 1, if d > 1e-6 then dz / d else 0
	local ax, az = -uz, ux -- (across)
	local h = width / 2
	return hx - ax * h, hz - az * h, hx + ax * h, hz + az * h
end

-- The lane a new attacking squad takes (user: "1 squad in 3"): a flank (-1 or 1, the side with fewer of the side's
-- flankers, `left` and `right`) while fewer than `share` of its `total` attacking squads (the new one counted, rounded
-- down) are on one; else nil (the quietest lane, as before).
function BotFront.flank(total: number, left: number, right: number, share: number): number?
	if left + right >= math.floor(total * share + 1e-9) then
		return nil
	end
	return if left <= right then -1 else 1
end

return BotFront
