--!strict
-- Assembles the village on the map from Rules/Village's layout: library building templates (each copy
-- in its own color scheme, standing on the highest ground under its footprint, bare-earth yard),
-- plot boundaries, telegraph poles + sagging wires, signposts, parked cars, yard clutter, features.

local VillageBuild = {}

-- deps: { MT, B, P, D, palette, RulesD, Props, Buildings, Library, VillageRules }
function VillageBuild.build(root: Instance, map: any, layout: any, deps: any): { [string]: number }
	local MT, B, palette = deps.MT, deps.B, deps.palette
	-- the props' meshes (Config/Assets.Entries.PropKit); every point prop's library model rebuilt from them first,
	-- so a place whose library still holds older (box) props builds the current ones
	local propDeps = { P = deps.P, D = deps.D, Kit = deps.Library.ensure("PropKit") }
	for _, kind in deps.P.Kinds do
		if not deps.Props.isLinear(kind) then
			deps.Library.ensure(kind)
		end
	end
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

	-- How far an arcade's paving (src/dev/Buildings Geometry: a portico's, a loggia's) runs out from a doorstep at its
	-- level (nil: none there). A ground-floor door's steps start where its portico ends, not under the paving; an upper
	-- door onto a loggia needs none (it is reached from inside). By the paving's own box: the copy isn't in the world
	-- yet, so a ray can't find it.
	local function pavingRun(copy: Instance, d: BasePart): number?
		local paving = {}
		for _, p in copy:GetDescendants() do
			if p:IsA("BasePart") and p.Name == "Paving" then
				table.insert(paving, p)
			end
		end
		local top = d.Position.Y + d.Size.Y / 2
		local edge = d.Position + d.CFrame.LookVector * (d.Size.Z / 2)
		local function on(dist: number): boolean
			local at = edge + d.CFrame.LookVector * dist
			for _, p in paving do
				local lp = p.CFrame:PointToObjectSpace(at)
				local surface = p.Position.Y + p.Size.Y / 2
				if
					math.abs(lp.X) <= p.Size.X / 2
					and math.abs(lp.Z) <= p.Size.Z / 2
					and math.abs(top - surface) <= B.Steps.rise
				then
					return true
				end
			end
			return false
		end
		if not on(0.5) then
			return nil
		end
		local run = 0.5
		while run < 40 and on(run + 0.5) do
			run += 0.5
		end
		return run
	end

	-- A flooded clay pit (src/dev/Buildings Geometry.clayPit, Config/Buildings.ClayPit): its marker's oval dug into the
	-- terrain as a bowl `Pit` deep at the middle, its banks mud, the water `drop` under the lowest ground round its rim
	local function digPit(m: Model)
		local K = B.ClayPit
		local marker = m:FindFirstChild("Pit") :: BasePart
		local at = marker.CFrame
		local a, b = marker.Size.X / 2, marker.Size.Z / 2
		local depth = m:GetAttribute("Pit") :: number
		local rim = math.huge
		for k = 0, 23 do
			local t = k * math.pi / 12
			local q = at * CFrame.new(math.cos(t) * (a + 2), 0, math.sin(t) * (b + 2))
			rim = math.min(rim, ground(q.X, q.Z))
		end
		local water = rim - K.drop
		local cell = 2
		-- (the ground read before any of it is dug: a dug column lowers its neighbours' voxels)
		local cells = {}
		for u = -a, a, cell do
			for v = -b, b, cell do
				local e = (u / a) ^ 2 + (v / b) ^ 2
				if e <= 1 then
					local q = at * CFrame.new(u, 0, v)
					table.insert(cells, { x = q.X, z = q.Z, e = e, g = ground(q.X, q.Z) })
				end
			end
		end
		local T = workspace.Terrain
		for _, c in cells do
			-- (a flat bottom over the middle, the banks in its outer `shelf` share: terrain voxels are 4 studs, a
			-- shallow bowl's water too thin to show)
			local k = math.clamp((1 - c.e) / K.shelf, 0, 1)
			local bed = water + K.bank - (depth + K.bank) * k
			local top = math.max(c.g, water) + 4
			T:FillBlock(
				CFrame.new(c.x, (bed + top) / 2, c.z),
				Vector3.new(cell + 0.4, top - bed, cell + 0.4),
				Enum.Material.Air
			)
			T:FillBlock(CFrame.new(c.x, bed - 1, c.z), Vector3.new(cell + 0.4, 2, cell + 0.4), Enum.Material.Mud)
			if bed < water then
				T:FillBlock(
					CFrame.new(c.x, (bed + water) / 2, c.z),
					Vector3.new(cell + 0.4, water - bed, cell + 0.4),
					Enum.Material.Water
				)
			end
		end
	end

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
				-- on the highest ground under it (its box's corners and middle), so no end of a tent sinks into a slope
				local box, size = d:GetBoundingBox()
				local top = -math.huge
				for _, o in { { 0, 0 }, { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
					local q = box * CFrame.new(o[1] * size.X / 2, 0, o[2] * size.Z / 2)
					top = math.max(top, ground(q.X, q.Z))
				end
				d:PivotTo(d:GetPivot() + Vector3.new(0, top - hi, 0))
			elseif d:IsA("Model") and d:GetAttribute("OnWater") and map.river then
				-- (a ferry's boat floats on the river)
				d:PivotTo(d:GetPivot() + Vector3.new(0, map.river.waterY - hi, 0))
			elseif d:IsA("Model") and d:GetAttribute("Pit") then
				-- (a flooded clay pit: dug into the ground)
				digPit(d)
			end
		end
		-- stone steps down from any door left up a bank (Rules/Village.steps), each step solid down into the ground
		for _, d in copy:GetDescendants() do
			local run = d:IsA("BasePart") and d.Name == "Doorstep" and pavingRun(copy, d) or nil
			local upper = ((d.Parent and d.Parent:GetAttribute("Story")) or 0) >= 1
			if d:IsA("BasePart") and d.Name == "Doorstep" and not (run and upper) then
				local S = B.Steps
				local look = d.CFrame.LookVector -- (a wall frame's -Z is its outside)
				-- (from the portico's front edge when the door opens onto one)
				local edge = d.Position + look * (d.Size.Z / 2 + (run or 0))
				local side = d.CFrame.RightVector
				local w = d.Size.X
				local function lowest(dist: number): number
					local p = edge + look * dist
					local y = math.huge
					for _, k in { -0.5, 0, 0.5 } do
						local q = p + side * (w * k)
						y = math.min(y, ground(q.X, q.Z))
					end
					return y
				end
				local steps = deps.VillageRules.steps(d.Position.Y + d.Size.Y / 2, lowest, S.rise, S.run, S.max)
				if #steps > 0 then
					local m = Instance.new("Model")
					m.Name = "Steps"
					local stone = Color3.fromRGB(table.unpack(palette.Buildings.Foundation))
					for _, s in steps do
						local g = math.min(lowest(s.out - S.run / 2), lowest(s.out + S.run / 2)) - 1
						local p = Instance.new("Part")
						p.Name = "Step"
						p.Anchored = true
						p.Material = Enum.Material.SmoothPlastic
						p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
						p.Color = stone
						p.Size = Vector3.new(w, s.top - g, S.run + 0.05)
						local mid = edge + look * s.out
						p.CFrame = CFrame.lookAt(
							Vector3.new(mid.X, (s.top + g) / 2, mid.Z),
							Vector3.new(mid.X, (s.top + g) / 2, mid.Z) + look
						)
						p.Parent = m
					end
					m.Parent = copy
				end
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
	local x0 = deps.VillageRules.railX(map)
	if x0 then
		local R = deps.P.Railway
		local rf = folder(root, "Railway")
		local metal = Color3.fromRGB(table.unpack(palette.Buildings.Metal))
		local wood = Color3.fromRGB(table.unpack(palette.Props.WoodDark))
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
