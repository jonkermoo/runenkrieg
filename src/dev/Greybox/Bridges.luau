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

-- a path of flat rocks across a shallow ford, on the line square to the river through the ford's point; a rock only
-- where the ground is under water
local function rockPath(Parts: any, folder: Instance, map: any, MT: any, ford: any, C: any, palette: any)
	local r = map.river
	local f = MT.bridgeFrame(map, { x = ford.x, z = ford.z, length = r.width + 2 * r.bankWidth })
	local stone, darkStone = rgb(palette.Props.Stone), rgb(palette.Props.StoneDark)
	local side = Vector3.new(-f.uz, 0, f.ux)
	local i = 0
	for s = C.rockStep / 2, f.length, C.rockStep do
		local x, z = f.ax + f.ux * s, f.az + f.uz * s
		local ground = MT.heightAt(map, x, z)
		if ground < r.waterY then
			i += 1
			local h = 0.5 + 0.5 * math.sin(i * 12.9898 + ford.z * 0.37)
			local top = r.waterY + C.rockTop + (h - 0.5) * 0.3
			local c = Vector3.new(x, (top + ground - 0.5) / 2, z) + side * (h - 0.5) * 2 * C.rockJitter
			Parts.box(
				folder,
				"Rock",
				CFrame.new(c) * CFrame.Angles(0, math.rad(h * 70), 0),
				Vector3.new(C.rock * (0.85 + 0.3 * h), top - ground + 0.5, C.rock * (1.15 - 0.3 * h)),
				if i % 3 == 0 then darkStone else stone
			)
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
