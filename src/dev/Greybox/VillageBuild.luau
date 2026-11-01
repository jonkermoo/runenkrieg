--!strict
-- Assembles the village on the map from Rules/Village's layout: library building templates (each copy
-- in its own color scheme, standing on the highest ground under its footprint, bare-earth yard),
-- plot boundaries, telegraph poles + sagging wires, signposts, parked cars, yard clutter, features.

local VillageBuild = {}

-- deps: { MT, B, P, D, palette, RulesD, Props, Buildings, Library, VillageRules }
function VillageBuild.build(root: Instance, map: any, layout: any, deps: any): { [string]: number }
	local MT, B, palette = deps.MT, deps.B, deps.palette
	local propDeps = { P = deps.P, D = deps.D }
	-- The rendered smooth-terrain surface can sit ~1 stud off the analytic heightAt, so place everything on
	-- the real surface (raycast against terrain only); fall back to heightAt if the ray misses.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = true
	local function ground(x: number, z: number): number
		local hit = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params)
		return if hit then hit.Position.Y else MT.heightAt(map, x, z)
	end
	-- highest real ground under a small footprint (so nothing sinks on a slope)
	local function groundUnder(x: number, z: number, r: number): number
		local y = ground(x, z)
		for _, o in { { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } } do
			y = math.max(y, ground(x + o[1], z + o[2]))
		end
		return y
	end
	local function folder(parent: Instance, name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
		return f
	end
	local stats = { buildings = 0, boundaries = 0, poles = 0, props = 0 }

	-- buildings
	local bf = folder(root, "Buildings")
	for _, lot in layout.lots do
		local template = deps.Library.get(lot.style)
		local copy = template:Clone()
		copy.Name = lot.id
		deps.Buildings.paint(copy, deps.RulesD.scheme(B.Templates[lot.style], palette, lot.colorSeed), palette)
		-- stand on the highest ground under the footprint and just round its walls, sampled all over it (never sunk
		-- into a rise between samples); the deep foundation fills down the slope, with a footing under it where the
		-- ground falls further than it reaches
		local rx, rz = -lot.fz, lot.fx
		local hi, lo = -math.huge, math.huge
		for _, p in deps.VillageRules.footprintPoints(lot, B.GroundSample.pad, B.GroundSample.step) do
			local y = ground(p[1], p[2])
			hi, lo = math.max(hi, y), math.min(lo, y)
		end
		local pos = Vector3.new(lot.x, hi, lot.z)
		local at = CFrame.lookAt(pos, pos + Vector3.new(lot.fx, 0, lot.fz))
		copy:PivotTo(at)
		local extra = deps.VillageRules.footing(hi, lo, B.FoundationDepth)
		if extra > 0 then
			local footing = Instance.new("Part")
			footing.Name = "Footing"
			footing.Anchored = true
			footing.Material = Enum.Material.SmoothPlastic
			footing.Color = Color3.fromRGB(table.unpack(palette.Buildings.Foundation))
			footing.Size = Vector3.new(lot.width + 0.6, extra + 1, lot.depth + 0.6)
			footing.CFrame = at * CFrame.new(0, -B.FoundationDepth - extra / 2 + 0.5, 0)
			footing.Parent = copy
		end
		-- cut the hillside back round it (Rules/Village.cutHeight): a dug terrace, never ground climbing its walls
		local cut = B.GroundCut
		local hw, hd = lot.width / 2, lot.depth / 2
		for u = -hw - cut.reach, hw + cut.reach, cut.cell do
			for v = -hd - cut.reach, hd + cut.reach, cut.cell do
				local du, dv = math.max(0, math.abs(u) - hw), math.max(0, math.abs(v) - hd)
				local allowed = deps.VillageRules.cutHeight(hi, math.sqrt(du * du + dv * dv), cut)
				if allowed then
					local x, z = lot.x + rx * u + lot.fx * v, lot.z + rz * u + lot.fz * v
					local g = ground(x, z)
					if g > allowed + 0.2 then
						workspace.Terrain:FillBlock(
							CFrame.new(x, (allowed + g) / 2 + 2, z),
							Vector3.new(cut.cell + 0.4, g - allowed + 4, cut.cell + 0.4),
							Enum.Material.Air
						)
					end
				end
			end
		end
		-- a landmark's headstones and gateway stand on the real ground where they are, not the building's level
		for _, d in copy:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("OnGround") then
				local p = d:GetPivot().Position
				d:PivotTo(d:GetPivot() + Vector3.new(0, ground(p.X, p.Z) - hi, 0))
			end
		end
		copy.Parent = bf
		-- bare-earth yard: no grass tufts (or terrain decoration) poking through the floor
		local pad = 1.5 -- just around the walls; wider yards blend into the dirt roads
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, s in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
			local x = lot.x + rx * (lot.width / 2 + pad) * s[1] + lot.fx * (lot.depth / 2 + pad) * s[2]
			local z = lot.z + rz * (lot.width / 2 + pad) * s[1] + lot.fz * (lot.depth / 2 + pad) * s[2]
			minX, maxX, minZ, maxZ = math.min(minX, x), math.max(maxX, x), math.min(minZ, z), math.max(maxZ, z)
		end
		local region = Region3.new(Vector3.new(minX, hi - 20, minZ), Vector3.new(maxX, hi + 30, maxZ)):ExpandToGrid(4)
		for _, m in { Enum.Material.Grass, Enum.Material.LeafyGrass } do
			workspace.Terrain:ReplaceMaterial(region, 4, m, Enum.Material.Ground)
		end
		stats.buildings += 1
		task.wait()
	end

	-- plot boundaries
	local fences = folder(root, "Boundaries")
	for _, f in layout.fences do
		deps.Props.linear(
			f.kind,
			fences,
			Vector3.new(f.a[1], 0, f.a[2]),
			Vector3.new(f.b[1], 0, f.b[2]),
			ground,
			propDeps
		)
		stats.boundaries += 1
	end
	deps.Props.paint(fences, palette)
	task.wait()

	-- telegraph poles along the main road, wired pole to pole
	local pf = folder(root, "Poles")
	local poleTemplate = deps.Library.get("Pole")
	local tops = {}
	for i, p in layout.poles do
		local pole = poleTemplate:Clone()
		local pos = Vector3.new(p.x, groundUnder(p.x, p.z, 0.5), p.z)
		-- crossarm across the road so the wires run along it
		pole:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(p.dx, 0, p.dz)) * CFrame.Angles(0, math.pi / 2, 0))
		pole.Parent = pf
		local pts = {}
		for _, a in pole:GetDescendants() do
			if a:IsA("Attachment") then
				table.insert(pts, a.WorldPosition)
			end
		end
		tops[i] = pts
		stats.poles += 1
	end
	local wires = folder(pf, "Wires")
	for i = 1, #layout.poles - 1 do
		local a, b = tops[i], tops[i + 1]
		if #a == 2 and #b == 2 and (a[1] - b[1]).Magnitude < 80 then
			-- connect the nearer pairs so wires don't cross
			local straight = (a[1] - b[1]).Magnitude + (a[2] - b[2]).Magnitude
			local crossed = (a[1] - b[2]).Magnitude + (a[2] - b[1]).Magnitude
			if crossed < straight then
				b = { b[2], b[1] }
			end
			deps.Props.wire(wires, a[1], b[1], propDeps)
			deps.Props.wire(wires, a[2], b[2], propDeps)
		end
	end
	deps.Props.paint(wires, palette)

	-- the railway: two rails on sleepers along x = railX through the map and past it, each segment following the ground
	if map.village.railX then
		local R = deps.P.Railway
		local rf = folder(root, "Railway")
		local metal = Color3.fromRGB(table.unpack(palette.Buildings.Metal))
		local wood = Color3.fromRGB(table.unpack(palette.Props.WoodDark))
		local x0 = map.village.railX
		local z0, z1 = map.bounds.minZ - R.beyond, map.bounds.maxZ + R.beyond
		local n = math.ceil((z1 - z0) / R.segment)
		-- each joint's bed: the highest ground round it, across the sleepers and halfway to the joints either side
		local bed = {}
		for i = 0, n do
			local z = z0 + i * (z1 - z0) / n
			local samples = {}
			for k = -R.samples, R.samples do
				local zk = z + k / R.samples * R.segment / 2
				for _, dx in { -(R.gauge / 2 + 1), 0, R.gauge / 2 + 1 } do
					table.insert(samples, ground(x0 + dx, zk))
				end
			end
			bed[i] = deps.VillageRules.railBed(samples)
		end
		for i = 0, n - 1 do
			local seg = Instance.new("Model")
			seg.Name = "Track"
			local za, zb = z0 + i * (z1 - z0) / n, z0 + (i + 1) * (z1 - z0) / n
			local ya, yb = bed[i], bed[i + 1]
			local function part(name: string, cf: CFrame, size: Vector3, color: Color3)
				local p = Instance.new("Part")
				p.Name = name
				p.Anchored = true
				p.Material = Enum.Material.SmoothPlastic
				p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				p.CFrame, p.Size, p.Color = cf, size, color
				p.Parent = seg
			end
			for _, side in { -1, 1 } do
				local x = x0 + side * R.gauge / 2
				local a, b = Vector3.new(x, ya + R.height, za), Vector3.new(x, yb + R.height, zb)
				part("Rail", CFrame.lookAt((a + b) / 2, b), Vector3.new(0.3, 0.35, (b - a).Magnitude + 0.05), metal)
			end
			for k = 0, R.sleepers - 1 do
				local t = (k + 0.5) / R.sleepers
				part(
					"Sleeper",
					CFrame.new(x0, ya + (yb - ya) * t + 0.12, za + (zb - za) * t),
					Vector3.new(R.gauge + 2, 0.3, 0.9),
					wood
				)
			end
			seg.Parent = rf
		end
		task.wait()
	end

	-- point props: signposts, cars, yard clutter, features
	local props = folder(root, "Props")
	local function place(kind: string, x: number, z: number, yaw: number, carIndex: number?)
		local m = deps.Library.get(kind):Clone()
		if carIndex then
			deps.Props.paint(m, palette, carIndex)
		end
		local _, size = m:GetBoundingBox()
		local r = math.max(size.X, size.Z) / 2
		m:PivotTo(CFrame.new(x, groundUnder(x, z, r), z) * CFrame.Angles(0, math.rad(yaw), 0))
		m.Parent = props
		stats.props += 1
	end
	for _, s in layout.signs do
		place("Signpost", s.x, s.z, math.deg(math.atan2(-s.dx, -s.dz)))
	end
	for _, c in layout.cars do
		place("Car", c.x, c.z, math.deg(math.atan2(-c.dx, -c.dz)), c.variant)
	end
	for _, y in layout.yard do
		place(y.kind, y.x, y.z, y.yaw)
	end
	return stats
end

return VillageBuild
