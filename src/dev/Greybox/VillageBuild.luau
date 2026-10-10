--!strict
-- Assembles the village on the map from Rules/Village's layout: library building templates (each copy
-- in its own color scheme, standing on the highest ground under its footprint, bare-earth yard),
-- plot boundaries, telegraph poles + sagging wires, signposts, parked cars, yard clutter, features.

local VillageBuild = {}

-- deps: { MT, B, P, D, palette, RulesD, Props, Buildings, Library }
function VillageBuild.build(root: Instance, map: any, layout: any, deps: any): { [string]: number }
	local MT, B, palette = deps.MT, deps.B, deps.palette
	local propDeps = { P = deps.P, D = deps.D }
	local function ground(x: number, z: number): number
		return MT.heightAt(map, x, z)
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
		-- stand on the highest ground under the footprint; the deep foundation fills down the slope
		local rx, rz = -lot.fz, lot.fx
		local hi = -math.huge
		for _, s in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 }, { 0, 0 }, { 0, -1 }, { 0, 1 } } do
			local x = lot.x + rx * lot.width / 2 * s[1] + lot.fx * lot.depth / 2 * s[2]
			local z = lot.z + rz * lot.width / 2 * s[1] + lot.fz * lot.depth / 2 * s[2]
			hi = math.max(hi, ground(x, z))
		end
		local pos = Vector3.new(lot.x, hi, lot.z)
		copy:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(lot.fx, 0, lot.fz)))
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
		local pos = Vector3.new(p.x, ground(p.x, p.z), p.z)
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

	-- point props: signposts, cars, yard clutter, features
	local props = folder(root, "Props")
	local function place(kind: string, x: number, z: number, yaw: number, carIndex: number?)
		local m = deps.Library.get(kind):Clone()
		if carIndex then
			deps.Props.paint(m, palette, carIndex)
		end
		m:PivotTo(CFrame.new(x, ground(x, z), z) * CFrame.Angles(0, math.rad(yaw), 0))
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
