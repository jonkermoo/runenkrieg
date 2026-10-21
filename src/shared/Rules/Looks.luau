--!strict
-- A soldier's looks each life (Config/Uniforms Skins / HairColors): one entry of a pool, picked by weight, never the
-- one the soldier had last life (user 2026-10-14: the colors rotate randomly per spawn).

export type Look = { name: string, color: { number }?, weight: number }

local Looks = {}

-- The index of the pool entry for a roll `r` in [0, 1): the entries' weights laid end to end, `avoid` (last life's
-- index) left out when there is anything else.
function Looks.pick(pool: { Look }, r: number, avoid: number?): number
	if #pool <= 1 then
		return 1
	end
	local total = 0
	for i, l in pool do
		if i ~= avoid then
			total += l.weight
		end
	end
	local at = r * total
	local last = 1
	for i, l in pool do
		if i ~= avoid then
			last = i
			at -= l.weight
			if at < 0 then
				return i
			end
		end
	end
	return last
end

-- The uniform kit a soldier wears this life (src/server/Kits): `current` (the character's "Kit", rolled earlier this
-- life) when it names one of `kits`, else `override` (the player's "Kit", for testing) when it does, else the entry of
-- `pool` at the roll `r` in [0, 1), each equally likely.
function Looks.kit(current: any, override: any, pool: { string }, r: number, kits: { [string]: any }): string
	if type(current) == "string" and kits[current] then
		return current
	end
	if type(override) == "string" and kits[override] then
		return override
	end
	return pool[math.clamp(math.floor(r * #pool) + 1, 1, #pool)]
end

-- The Config/Assets hair entry a soldier wears: `style` under the helmet `shell` (nil: bareheaded); nil when bald.
function Looks.hairEntry(style: string, shell: string?): string?
	if style == "bald" then
		return nil
	end
	return "hair_" .. style .. (if shell then "_" .. shell else "")
end

-- A hit on the head (its point in the Head part's own space) lands on the helmet when it is in the top half of the
-- head's hitbox (user 2026-10-14: "it should cover the top half of your head hitbox").
function Looks.onHelmet(local_: { X: number, Y: number, Z: number }): boolean
	return local_.Y > 0
end

return Looks
