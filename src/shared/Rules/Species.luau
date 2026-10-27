--!strict
-- Species rules (Config/Species): which species a soldier is, what colour each piece of its ears and tail takes, and
-- the procedural motion's angles. Pure: the server (src/server/Species) and client (src/client/SpeciesMotion) feed
-- it the numbers.

local Species = {}

-- The species for a uniform `kit`, or nil (a plain human). `override` (a player's "Species" attribute: a Kinds name
-- or "human") wins when it names something real. A bald soldier (`hairStyle`, the "HairStyle" attribute) is never a
-- species, so no ears, no tail and the plain helmet (user 2026-10-23: "bald people can't be a species"). `rolled`
-- (the "SpeciesRoll" attribute, Species.roll) false: a plain human this life; nil (never rolled): the kit's species.
function Species.of(kit: string, override: any, cfg: any, hairStyle: any, rolled: any): string?
	if override == "human" or hairStyle == "bald" then
		return nil
	end
	if type(override) == "string" and cfg.Kinds[override] then
		return override
	end
	if rolled == false then
		return nil
	end
	return cfg.Kits[kit]
end

-- Whether a soldier is their nation's species this life, for a roll `r` in [0, 1) and `chance` (Config/Species.Chance).
function Species.roll(r: number, chance: number): boolean
	return r < chance
end

-- A part's name without a ".001"-style suffix (an exporter's duplicate-name mark).
function Species.base(name: string): string
	return (string.gsub(name, "%.%d+$", ""))
end

-- A piece's name `<Piece>_<role>` split into the piece and its role ("EarRTufts_Fluff" -> "EarRTufts", "Fluff").
function Species.split(name: string): (string, string?)
	local piece, role = string.match(name, "^(.-)_(%a+)$")
	if not piece then
		return name, nil
	end
	return piece, role
end

-- Which ear ("EarL" / "EarR") a piece belongs to, or nil; `shell` when it is the ear itself (the part that swings),
-- `ruff` when it is the fur round the root (stays on the head, hidden under a helmet).
function Species.ear(piece: string): (string?, boolean, boolean)
	local tag, rest = string.match(piece, "^(Ear[LR])(.*)$")
	if not tag then
		return nil, false, false
	end
	return tag, rest == "", rest == "Ruff"
end

-- The tail segment number of a piece ("Tail3" -> 3), or nil.
function Species.segment(piece: string): number?
	local n = string.match(piece, "^Tail(%d+)$")
	return n and tonumber(n)
end

-- The colour (0-255 RGB) of a piece with `role`: Fur the hair colour, Fluff the hair colour part way to cream, Skin
-- the skin tone, Inner / Tip the palette's.
function Species.color(role: string?, hair: { number }, skin: { number }, palette: any): { number }
	if role == "Skin" then
		return skin
	elseif role == "Fluff" then
		local k = palette.FluffShare
		local out = {}
		for i = 1, 3 do
			out[i] = math.floor(hair[i] + (palette.Cream[i] - hair[i]) * k + 0.5)
		end
		return out
	elseif role == "Inner" or role == "Tip" then
		return palette[role]
	end
	return hair
end

-- One ear's wanted angles (degrees about the head's X and Y at its pivot) at time `t`: only an idle sway (user
-- 2026-10-25: twitching, lying back and flattening poked the ears out through the helmet holes).
--   side = 1 right / -1 left, seed = its own rhythm, motion = the species' share (Kind.earMotion).
--   X tilts the ear back, Y swivels it.
function Species.earAngles(t: number, side: number, seed: number, motion: number, cfg: any): (number, number)
	local sway = math.sin((t * cfg.swayHz + seed) * 2 * math.pi) * cfg.swayDeg
	return sway * cfg.swayTilt * motion, side * sway * cfg.swaySwivel * motion
end

-- Tail segment `i` of `n`: its wanted angles (degrees about the Torso's X and Y at its joint) at time `t`, moving
-- `forward` and `sideways` studs/s in the Torso's frame; `dead` 0..1. X < 0 lifts the tail, Y swings it (+ = to the
-- right of a tail pointing back).
function Species.tailAngles(
	i: number,
	n: number,
	t: number,
	forward: number,
	sideways: number,
	dead: number,
	cfg: any
): (number, number)
	local live = 1 - dead
	local sway = math.sin(t * cfg.swayHz * 2 * math.pi - (i - 1) * cfg.phasePerSegment) * cfg.swayDeg
	local lift = math.clamp(forward * cfg.liftPerSpeed, 0, cfg.liftMax) / n
	local lag = math.clamp(-sideways * cfg.lagPerSpeed, -cfg.lagMax, cfg.lagMax) / n
	local x = -lift * live + dead * cfg.deadDroopDeg
	local y = (sway + lag) * live
	return x, y
end

-- Eases `from` toward `to` at `rate` per second over `dt` (frame-rate independent).
function Species.ease(from: number, to: number, rate: number, dt: number): number
	return to + (from - to) * math.exp(-rate * dt)
end

return Species
