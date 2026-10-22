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
-- Where a ray first meets a worn helmet's shape: the ellipsoid filling its box (user 2026-10-22: a shot at a helmet's
-- crown missed, because the top of every helmet stands above the Head's hitbox). `o` and `d` are the ray's start and
-- unit direction in the box's own space, `half` the box's half size; returns the distance along the ray, or nil (a
-- miss, or the start already inside).
function Looks.crownAt(
	o: { X: number, Y: number, Z: number },
	d: { X: number, Y: number, Z: number },
	half: { X: number, Y: number, Z: number }
): number?
	if half.X <= 0 or half.Y <= 0 or half.Z <= 0 then
		return nil
	end
	-- scaled to a unit sphere: |o' + t d'|^2 = 1
	local ox, oy, oz = o.X / half.X, o.Y / half.Y, o.Z / half.Z
	local dx, dy, dz = d.X / half.X, d.Y / half.Y, d.Z / half.Z
	local a = dx * dx + dy * dy + dz * dz
	local b = 2 * (ox * dx + oy * dy + oz * dz)
	local c = ox * ox + oy * oy + oz * oz - 1
	if a <= 0 or c <= 0 then
		return nil
	end
	local disc = b * b - 4 * a * c
	if disc < 0 then
		return nil
	end
	local t = (-b - math.sqrt(disc)) / (2 * a)
	return if t >= 0 then t else nil
end

function Looks.hairEntry(style: string, shell: string?): string?
	if style == "bald" then
		return nil
	end
	return "hair_" .. style .. (if shell then "_" .. shell else "")
end

-- The Config/Assets helmet a soldier of `species` wears for the kit's `headwear`: its ear-hole version
-- (`<headwear>_<species>`, tools/blender/gear/slit.py; user 2026-10-20) when there is one, else the headwear itself.
function Looks.helmetEntry(headwear: string, species: string?, entries: { [string]: any }): string
	local holed = species and headwear .. "_" .. species
	return if holed and entries[holed] then holed else headwear
end

-- A hit on the head (its point in the Head part's own space) lands on the helmet when it is in the top half of the
-- head's hitbox (user 2026-10-14: "it should cover the top half of your head hitbox").
function Looks.onHelmet(local_: { X: number, Y: number, Z: number }): boolean
	return local_.Y > 0
end

return Looks
