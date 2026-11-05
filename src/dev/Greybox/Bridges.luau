--!strict
-- River crossings (a map's `river.bridges`, Config/Props.Bridge): a wooden footbridge whose deck is walked over deep
-- water (Rules/MapTerrain.deckHeight, the same surface the walk grid uses), or an old stone bridge's two stumps over a
-- ford, its span fallen into the river; and a ford's path of flat rocks. Not destructible: a crossing stays a crossing.

local Bridges = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- a box centred on the line from a to b (its long axis), `w` wide and `h` tall
local function beam(
	Parts: any,
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	w: number,
	h: number,
	color: Color3
): BasePart
	local mid = (a + b) / 2
	return Parts.box(parent, name, CFrame.lookAt(mid, b), Vector3.new(w, h, (b - a).Magnitude), color)
end

local function footbridge(Parts: any, folder: Instance, map: any, MT: any, br: any, C: any, palette: any)
	local f = MT.bridgeFrame(map, br)
	local wood, dark = rgb(palette.Props.Wood), rgb(palette.Props.WoodDark)
	local side = Vector3.new(-f.uz, 0, f.ux)
	local function at(s: number, off: number, up: number): Vector3
		return Vector3.new(f.ax + f.ux * s, MT.deckHeight(map, br, f, s) + up, f.az + f.uz * s) + side * off
	end
	-- the deck, in short planked lengths following the arch
	local n = math.ceil(f.length / C.step)
	for i = 0, n - 1 do
		local s0, s1 = i * f.length / n, (i + 1) * f.length / n
		local a, b = at(s0, 0, -C.plank / 2), at(s1, 0, -C.plank / 2)
		local d = (b - a).Unit
		beam(Parts, folder, "Deck", a - d * 0.1, b + d * 0.1, br.width, C.plank, wood)
	end
	-- rails: posts along each side and a top rail between them
	local posts = math.max(1, math.floor(f.length / C.postEvery))
	for _, k in { -1, 1 } do
		local off = k * (br.width / 2 - C.post / 2)
		local prev: Vector3? = nil
		for i = 0, posts do
			local s = i * f.length / posts
			local foot = at(s, off, 0)
			Parts.box(
				folder,
				"Post",
				CFrame.new(foot + Vector3.new(0, C.railHeight / 2, 0)),
				Vector3.new(C.post, C.railHeight, C.post),
				dark
			)
			local top = foot + Vector3.new(0, C.railHeight - C.post / 2, 0)
			if prev then
				beam(Parts, folder, "Rail", prev, top, C.post, C.post, dark)
			end
			prev = top
		end
	end
	-- trestles: a pair of legs to the bed and a cross beam under the deck
	for _, t in C.legsAt do
		local s = t * f.length
		for _, k in { -1, 1 } do
			local top = at(s, k * (br.width / 2 - C.leg), -C.plank)
			local foot = Vector3.new(top.X, map.river.bedY - 1, top.Z)
			beam(Parts, folder, "Leg", foot, top, C.leg, C.leg, dark)
		end
		beam(
			Parts,
			folder,
			"Crossbeam",
			at(s, -br.width / 2 - 0.3, -C.plank - C.leg / 2),
			at(s, br.width / 2 + 0.3, -C.plank - C.leg / 2),
			C.leg,
			C.leg,
			dark
		)
	end
end

local function brokenBridge(Parts: any, folder: Instance, map: any, MT: any, br: any, C: any, palette: any)
	local f = MT.bridgeFrame(map, br)
	local stone, darkStone = rgb(palette.Props.Stone), rgb(palette.Props.StoneDark)
	local u = Vector3.new(f.ux, 0, f.uz)
	local function ground(s: number): number
		return MT.heightAt(map, f.ax + f.ux * s, f.az + f.uz * s)
	end
	for _, e in { { 0, 1 }, { f.length, -1 } } do
		local s0, dir = e[1], e[2]
		local s1 = s0 + dir * br.stump
		-- a solid stump from below its lowest ground to `stoneHeight` over its bank end
		local low = math.huge
		for k = 0, 4 do
			low = math.min(low, ground(s0 + dir * br.stump * k / 4))
		end
		local top = ground(s0) + C.stoneHeight
		local bottom = low - 2
		local mid = (s0 + s1) / 2
		local centre = Vector3.new(f.ax + f.ux * mid, (top + bottom) / 2, f.az + f.uz * mid)
		Parts.box(
			folder,
			"Stump",
			CFrame.lookAt(centre, centre + u),
			Vector3.new(br.width, top - bottom, br.stump),
			stone
		)
		-- the fallen span: a slab off the stump's inner end, sloping down into the water
		local edge = Vector3.new(f.ax + f.ux * s1, top - 0.6, f.az + f.uz * s1)
		local d = (u * dir * math.cos(math.rad(C.drop)) - Vector3.new(0, math.sin(math.rad(C.drop)), 0)).Unit
		beam(Parts, folder, "Span", edge, edge + d * C.span, br.width - 0.4, 1.2, darkStone)
	end
	-- rubble in the river between the stumps
	for i = 1, C.rubble do
		local s = f.length / 2 + (i - (C.rubble + 1) / 2) * 5
		local size = 2.5 + (i % 2) * 1.5
		local c = Vector3.new(f.ax + f.ux * s, map.river.bedY + size / 2 - 0.5, f.az + f.uz * s)
			+ Vector3.new(-f.uz, 0, f.ux) * ((i % 3) - 1) * 1.5
		Parts.box(
			folder,
			"Rubble",
			CFrame.new(c) * CFrame.Angles(0, math.rad(i * 37), math.rad(i * 11)),
			Vector3.new(size, size, size * 1.3),
			darkStone
		)
	end
end

-- a stable 0..1 from a few numbers (the same rocks every build)
local function hash(a: number, b: number, c: number): number
	local v = math.sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
	return v - math.floor(v)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- one low-poly rock: a tilted main block with two smaller blocks set into it at other angles, so it reads faceted like
-- the map's low-poly trees. `top` is its highest point, `bottom` buried in the bed.
local function rock(
	Parts: any,
	folder: Instance,
	name: string,
	at: Vector3,
	size: number,
	top: number,
	bottom: number,
	color: Color3,
	seed: number,
	C: any
)
	local h = top - bottom
	local tilt = math.rad(C.rockTilt)
	local function angles(k: number): CFrame
		return CFrame.Angles(
			(hash(seed, k, 1) - 0.5) * 2 * tilt,
			hash(seed, k, 2) * math.pi * 2,
			(hash(seed, k, 3) - 0.5) * 2 * tilt
		)
	end
	local w, d = size * lerp(0.8, 1.15, hash(seed, 0, 4)), size * lerp(0.6, 0.95, hash(seed, 0, 5))
	Parts.box(folder, name, CFrame.new(at.X, bottom + h / 2 - 0.2, at.Z) * angles(0), Vector3.new(w, h, d), color)
	for k = 1, 2 do
		local a = hash(seed, k, 6) * math.pi * 2
		local off = Vector3.new(math.cos(a), 0, math.sin(a)) * size * 0.28
		local kh = h * lerp(0.55, 0.85, hash(seed, k, 7))
		local ks = size * lerp(0.45, 0.65, hash(seed, k, 8))
		Parts.box(
			folder,
			name,
			CFrame.new(at.X + off.X, bottom + kh / 2, at.Z + off.Z) * angles(k),
			Vector3.new(ks, kh, ks * lerp(0.7, 1, hash(seed, k, 9))),
			color:Lerp(Color3.new(0, 0, 0), 0.06 * k)
		)
	end
end

-- a ford's rocks (a ford with `rocks`): flat-topped stepping stones winding across the water square to the river, at
-- uneven steps and sizes, a few half-sunk pebbles strewn round them and boulders at the water's edge on each bank
local function rockPath(Parts: any, folder: Instance, map: any, MT: any, ford: any, C: any, palette: any)
	local r = map.river
	local f = MT.bridgeFrame(map, { x = ford.x, z = ford.z, length = r.width + 2 * r.bankWidth })
	local shades = { rgb(palette.Props.Stone), rgb(palette.Props.StoneDark), rgb(palette.Terrain.Rock) }
	local function shade(seed: number): Color3
		local a = shades[1 + math.floor(hash(seed, 9, 1) * #shades)]
		return a:Lerp(shades[1], hash(seed, 9, 2) * 0.4)
	end
	local side = Vector3.new(-f.uz, 0, f.ux)
	local seed0 = ford.z * 0.37
	-- the ground as built (the terrain's voxels, not heightAt: they sit a little over it on the banks)
	local only = RaycastParams.new()
	only.FilterType = Enum.RaycastFilterType.Include
	only.FilterDescendantsInstances = { workspace.Terrain }
	only.IgnoreWater = true
	local function groundAt(x: number, z: number): number
		local hit = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), only)
		return if hit then hit.Position.Y else MT.heightAt(map, x, z)
	end
	local phase = hash(seed0, 1, 1) * math.pi * 2
	-- the stepping stones
	local s, i = 0, 0
	local wet: { number } = {}
	while s < f.length do
		s += lerp(C.rockStep[1], C.rockStep[2], hash(seed0, i, 11))
		local wob = math.sin(s / f.length * math.pi * 2 + phase) * C.rockWobble
			+ (hash(seed0, i, 12) - 0.5) * 2 * C.rockJitter
		local p = Vector3.new(f.ax + f.ux * s, 0, f.az + f.uz * s) + side * wob
		local ground = groundAt(p.X, p.Z)
		if ground < r.waterY then
			i += 1
			table.insert(wet, s)
			local seed = seed0 + i
			local top = r.waterY + lerp(C.rockTop[1], C.rockTop[2], hash(seed, 0, 13))
			rock(
				Parts,
				folder,
				"Rock",
				p,
				lerp(C.rock[1], C.rock[2], hash(seed, 0, 14)),
				top,
				ground - 0.5,
				shade(seed),
				seed,
				C
			)
		end
	end
	-- pebbles round the path, most under the water line
	if #wet > 0 then
		local s0, s1 = wet[1], wet[#wet]
		for k = 1, C.pebbles do
			local seed = seed0 + 100 + k
			local ps = lerp(s0, s1, hash(seed, 0, 15))
			local off = (hash(seed, 0, 16) - 0.5) * 2 * C.pebbleSpread
			local p = Vector3.new(f.ax + f.ux * ps, 0, f.az + f.uz * ps) + side * off
			local ground = groundAt(p.X, p.Z)
			if ground < r.waterY and math.abs(off) > 2.2 then
				local top = r.waterY + lerp(-0.3, 0.4, hash(seed, 0, 17))
				rock(
					Parts,
					folder,
					"Pebble",
					p,
					lerp(C.pebble[1], C.pebble[2], hash(seed, 0, 18)),
					top,
					ground - 0.3,
					shade(seed),
					seed,
					C
				)
			end
		end
		-- boulders at the water's edge on each bank, beside the path's ends
		for e, edge in { s0 - 1.5, s1 + 1.5 } do
			for k = 1, C.bankRocks do
				local seed = seed0 + 200 + e * 10 + k
				local off = (if k % 2 == 0 then 1 else -1) * lerp(3, 7, hash(seed, 0, 19))
				local p = Vector3.new(f.ax + f.ux * edge, 0, f.az + f.uz * edge) + side * off
				local ground = groundAt(p.X, p.Z)
				local size = lerp(C.rock[2], C.rock[2] * 1.4, hash(seed, 0, 20))
				rock(
					Parts,
					folder,
					"Boulder",
					p,
					size,
					math.max(ground, r.waterY) + size * 0.5,
					ground - 0.6,
					shade(seed),
					seed,
					C
				)
			end
		end
	end
end

-- builds every bridge of the map's river into `folder`, and the rock path of each ford with `rocks`; returns how many
-- bridges
function Bridges.build(folder: Instance, map: any, MT: any, Parts: any, C: any, palette: any): number
	for _, ford in map.river and map.river.fords or {} do
		if ford.rocks then
			local m = Instance.new("Model")
			m.Name = "RockFord"
			m.Parent = folder
			rockPath(Parts, m, map, MT, ford, C, palette)
		end
	end
	local list = map.river and map.river.bridges or {}
	for _, br in list do
		local m = Instance.new("Model")
		m.Name = br.id
		m.Parent = folder
		if br.deck then
			footbridge(Parts, m, map, MT, br, C, palette)
		else
			brokenBridge(Parts, m, map, MT, br, C, palette)
		end
	end
	return #list
end

return Bridges
