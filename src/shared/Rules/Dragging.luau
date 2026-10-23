--!strict
-- Dragging rules (Config/Dragging): who may drag whom, and when a drag lets go. Plain values, so Lune tests run them.

local Dragging = {}

-- What the server sees of a dragger and a body at one moment.
export type State = {
	same: boolean, -- the same soldier
	team: boolean, -- teammates (Rules/Teams.same)
	draggerHealth: number,
	draggerDown: boolean, -- knocked down (ragdolled)
	draggerBusy: boolean, -- healing, casting, or something in the hands
	bodyHealth: number,
	bodyDown: boolean, -- knocked down (ragdolled)
	distance: number, -- studs between the two roots
}

export type Cfg = { Range: number, Break: number, StartSlack: number }

local function ok(s: State, limit: number): boolean
	return not s.same
		and s.team
		and s.draggerHealth > 0
		and not s.draggerDown
		and not s.draggerBusy
		and s.bodyHealth > 0
		and s.bodyDown
		and s.distance == s.distance
		and s.distance <= limit
end

-- Whether a drag may start: a living, knocked-down teammate in Range (plus the server's lag slack when `slack`), the
-- dragger on their feet with empty hands. (One dragger per body: the caller checks.)
function Dragging.canStart(s: State, cfg: Cfg, slack: boolean?): boolean
	return ok(s, cfg.Range + (if slack then cfg.StartSlack else 0))
end

-- Whether a drag goes on: as for the start, with the body allowed up to Break studs behind.
function Dragging.keep(s: State, cfg: Cfg): boolean
	return ok(s, cfg.Break)
end

return Dragging
