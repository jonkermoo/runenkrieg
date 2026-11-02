--!strict
-- Which prompts the field-note prompt draws, and how (Config/Prompts, src/client/Prompts). Pure: studs.

local Prompts = {}

export type Seen = {
	id: string,
	dist: number, -- from the player
	reach: number, -- the prompt's MaxActivationDistance
	enabled: boolean,
	blocked: string?, -- a reason key while it can't be used
	mine: boolean, -- the local player is using it
}

-- What each prompt shows: "near" (the one the key will use: `shown`, Roblox's pick), "blocked" (the nearest prompt in
-- reach that can't be used, when nothing usable is shown: the shown one too when it can't be used by this player, a
-- gun a bot of another kit mans), "far" (any other in `farReach` times its reach: only its pin, the
-- `maxPins` nearest), or nothing. A prompt off with no reason, or one the player is using, shows nothing.
function Prompts.states(seen: { Seen }, shown: string?, farReach: number, maxPins: number): { [string]: string }
	local out: { [string]: string } = {}
	local blocked: Seen? = nil
	local far: { Seen } = {}
	for _, s in seen do
		if s.mine or (not s.enabled and s.blocked == nil) then
			continue
		end
		if s.id == shown and s.blocked == nil then
			out[s.id] = "near"
		elseif s.dist <= s.reach * farReach then
			if
				s.blocked ~= nil
				and (shown == nil or shown == s.id)
				and s.dist <= s.reach
				and (blocked == nil or s.dist < blocked.dist)
			then
				if blocked then
					table.insert(far, blocked)
				end
				blocked = s
			else
				table.insert(far, s)
			end
		end
	end
	if blocked then
		out[blocked.id] = "blocked"
	end
	table.sort(far, function(a, b)
		return a.dist < b.dist
	end)
	for i = 1, math.min(#far, maxPins) do
		out[far[i].id] = "far"
	end
	return out
end

-- Why a prompt can't be used by a player of kit `myKit`: its own `reason`, else "InUse" when it is kept for another
-- `kit` (Config/Prompts.KitAttr: a gun a bot mans, taken over only by its teammates); and whether it was the kit.
function Prompts.blocked(reason: string?, kit: any, myKit: any): (string?, boolean)
	if reason == nil and kit ~= nil and myKit ~= kit then
		return "InUse", true
	end
	return reason, false
end

-- How far the hold has gone (0..1): `held` seconds of a `hold`-second prompt; a tap prompt (hold 0) never fills.
function Prompts.progress(held: number?, hold: number): number
	if held == nil or hold <= 0 then
		return 0
	end
	return math.clamp(held / hold, 0, 1)
end

-- Where the billboard sits so the pin at (`pinX`, `pinY`) of a `w` x `h` canvas is on the thing (its SizeOffset).
function Prompts.offset(pinX: number, pinY: number, w: number, h: number): (number, number)
	return 0.5 - pinX / w, pinY / h - 0.5
end

return Prompts
