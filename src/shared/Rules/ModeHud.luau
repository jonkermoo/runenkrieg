--!strict
-- The game modes' top bar (src/client/ModeHud, Config/ModeHud; user 2026-10-29, option B of the mode HUD drafts: "front
-- bar ... just make the diamond on the top show the progress"). Pure: numbers and strings only.
-- Territory Push (src/server/Frontline): a sector's control runs from 1 (West holds it) to -1 (East holds it); the bar
-- shows the viewer's side on the left, so East players see the chain reversed.

local ModeHud = {}

-- Where the front stands along the bar, 0..1 from the West end: the share of the chain West holds, each sector counting
-- (control + 1) / 2 (a neutral one half), so the front slides with the fought-over sector's control.
function ModeHud.front(controls: { number }): number
	local n = #controls
	if n == 0 then
		return 0.5
	end
	local sum = 0
	for _, c in controls do
		sum += (math.clamp(c, -1, 1) + 1) / 2
	end
	return sum / n
end

-- Which sector (west-to-east index) sits at bar slot `slot` for a viewer on `side`, and the front as that viewer sees it
-- (the viewer's own side always on the left).
function ModeHud.slot(slot: number, n: number, side: string?): number
	return if side == "East" then n + 1 - slot else slot
end
function ModeHud.seenFront(front: number, side: string?): number
	return if side == "East" then 1 - front else front
end

export type Pin = {
	fillSide: string?, -- whose colour fills the diamond (nil: empty)
	fill: number, -- 0..1, the diamond filled from its bottom tip (the flag's height on the pole)
	state: string, -- "Held" | "Neutral" | "Contested" | "Attacked" (the holder's lead lost in its zone)
}

-- A sector's diamond: filled from the bottom in the colour of the side its control leans to, as far as the control
-- goes (the flag's height). Contested: soldiers of both sides in the zone, even numbers. Attacked: its holder is outnumbered
-- in its zone (control is running away from them).
function ModeHud.pin(owner: string?, control: number, west: number, east: number): Pin
	local fill = math.clamp(math.abs(control), 0, 1)
	local fillSide = if control > 0 then "West" elseif control < 0 then "East" else nil
	local state = "Held"
	if west > 0 and west == east then
		state = "Contested"
	elseif (owner == "West" and east > west) or (owner == "East" and west > east) then
		state = "Attacked"
	elseif owner ~= "West" and owner ~= "East" then
		state = "Neutral"
	end
	return { fillSide = if fill > 0 then fillSide else nil, fill = fill, state = state }
end

-- Point Capture (FFA, src/server/ZoneMatch): the line under the bar for the live zone's state, as the viewer sees it.
function ModeHud.zoneLine(state: string?, holderIsMe: boolean, holderName: string?): string
	if state == "Held" then
		return if holderIsMe then "HELD BY YOU" else `HELD BY {string.upper(holderName or "?")}`
	elseif state == "Contested" then
		return "CONTESTED"
	end
	return "ZONE FREE"
end

-- Point Capture: the line under the clock naming the point leader (nil: nobody has a point yet) and their score; in the
-- results, the winner.
function ModeHud.leaderLine(name: string?, isMe: boolean, score: number, results: boolean): string
	if results then
		if isMe then
			return "YOU WIN"
		end
		return if name then `{string.upper(name)} WINS` else "NO WINNER"
	end
	if not name then
		return "NO LEADER YET"
	end
	return `LEADER: {if isMe then "YOU" else string.upper(name)} ({score})`
end

return ModeHud
