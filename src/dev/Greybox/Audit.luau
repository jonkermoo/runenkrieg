--!strict
-- Checks a built map against the map rules (docs/maps/MAP_RULES.md), on the real terrain and parts:
--   require(game.ServerStorage.Dev.Greybox:Clone()).audit("Map1")
-- - floors: no ground over any building's ground floor (or 1.5 studs round it)
-- - walls: no ground more than a floor's height over a building's base within `wallReach` of its walls
-- - doors: walking out from every doorstep, no drop over a step (Config/Buildings.Steps.rise + slack)
-- - rails: no ground over the railway
-- - spawns: no sight line from the enemy's point or front row to a wave line's heads (terrain and parts)
-- Returns a report string; each line that starts with FAIL names a thing to fix.

local Audit = {}

local function terrainOnly(): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = { workspace.Terrain }
	p.IgnoreWater = true
	return p
end

function Audit.run(mapName: string, deps: any): string
	local B, Front, M, R, Map = deps.B, deps.Front, deps.M, deps.FrontRules, deps.map
	local A = B.Audit
	local root = workspace:FindFirstChild(mapName)
	assert(root, `{mapName} isn't built`)
	local params = terrainOnly()
	local function ground(x: number, z: number, above: number): number?
		local hit = workspace:Raycast(Vector3.new(x, above + 100, z), Vector3.new(0, -300, 0), params)
		return hit and hit.Position.Y
	end
	local lines = {}
	local function report(ok: boolean, what: string)
		table.insert(lines, (if ok then "ok   " else "FAIL ") .. what)
	end

	local village = root:FindFirstChild("Village")
	local buildings = village and village:FindFirstChild("Buildings")
	if buildings then
		local floorsBad, wallsBad, doorsBad, doors = {}, {}, {}, 0
		for _, b in buildings:GetChildren() do
			local t = B.Templates[b:GetAttribute("Template")]
			-- floors
			for _, sec in b:GetDescendants() do
				if sec:IsA("Model") and sec:GetAttribute("Kind") == "Floor" and sec:GetAttribute("Story") == -1 then
					for _, p in sec:GetChildren() do
						if p:IsA("BasePart") then
							local top = p.Position.Y + p.Size.Y / 2
							for u = -p.Size.X / 2 - 1.5, p.Size.X / 2 + 1.5, A.step do
								for v = -p.Size.Z / 2 - 1.5, p.Size.Z / 2 + 1.5, A.step do
									local q = p.CFrame * CFrame.new(u, 0, v)
									local g = ground(q.X, q.Z, top)
									if g and g > top + 0.05 and not table.find(floorsBad, b.Name) then
										table.insert(floorsBad, b.Name)
									end
								end
							end
						end
					end
				end
			end
			-- walls
			if t then
				local at = b:GetPivot()
				local hw, hd = t.width / 2 + A.wallReach, t.depth / 2 + A.wallReach
				for u = -hw, hw, A.step do
					for v = -hd, hd, A.step do
						local q = at * CFrame.new(u, 0, v)
						local g = ground(q.X, q.Z, at.Y)
						if g and g - at.Y > B.Foundation + A.slack and not table.find(wallsBad, b.Name) then
							table.insert(wallsBad, b.Name)
						end
					end
				end
			end
			-- doors: walk out, the floor under foot the higher of a step and the ground
			local steps = {}
			for _, s in b:GetChildren() do
				if s.Name == "Steps" then
					for _, p in s:GetChildren() do
						table.insert(steps, p)
					end
				end
			end
			for _, d in b:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Doorstep" then
					doors += 1
					local look = d.CFrame.LookVector
					local y = d.Position.Y + d.Size.Y / 2
					for k = 1, math.ceil(A.walkOut / 0.7) do
						local p = d.Position + look * (d.Size.Z / 2 + k * 0.7)
						local h = ground(p.X, p.Z, y) or -math.huge
						for _, s in steps do
							local lp = s.CFrame:PointToObjectSpace(Vector3.new(p.X, s.Position.Y, p.Z))
							if math.abs(lp.X) <= s.Size.X / 2 and math.abs(lp.Z) <= s.Size.Z / 2 + 0.05 then
								h = math.max(h, s.Position.Y + s.Size.Y / 2)
							end
						end
						if y - h > B.Steps.rise + A.slack and not table.find(doorsBad, b.Name) then
							table.insert(doorsBad, b.Name)
						end
						y = h
					end
				end
			end
		end
		local n = #buildings:GetChildren()
		report(#floorsBad == 0, `floors above the ground: {n} buildings {table.concat(floorsBad, ", ")}`)
		report(#wallsBad == 0, `no ground against the walls: {table.concat(wallsBad, ", ")}`)
		report(#doorsBad == 0, `{doors} doors walkable: {table.concat(doorsBad, ", ")}`)
		local rail = village:FindFirstChild("Railway")
		if rail then
			local bad, sleepers = 0, 0
			for _, s in rail:GetDescendants() do
				if s.Name == "Sleeper" and s:IsA("BasePart") then
					sleepers += 1
					local g = ground(s.Position.X, s.Position.Z, s.Position.Y)
					if g and g > s.Position.Y + 0.2 then
						bad += 1
					end
				end
			end
			report(bad == 0, `rails on the ground: {bad} of {sleepers} sleepers under it`)
		end
	end

	-- spawn cover: each side's line at a sector seen from the next sector's point and the enemy's front row there
	local S = Map.sectors
	if #S >= 3 and Map.spawnZones then
		local every = RaycastParams.new()
		every.FilterType = Enum.RaycastFilterType.Exclude
		every.FilterDescendantsInstances = { workspace:FindFirstChild("SpawnMarkers") :: Instance }
		every.IgnoreWater = true
		local function unit(x: number, z: number): (number, number)
			local l = math.sqrt(x * x + z * z)
			return x / l, z / l
		end
		local function line(side: string, i: number, rows: number): { Vector3 }
			local s = S[i]
			local cx, cz
			if i == (if side == "West" then 1 else #S) then
				local r = Map.spawnZones[side]
				cx, cz = (r.minX + r.maxX) / 2, (r.minZ + r.maxZ) / 2
			else
				local b = S[if side == "West" then i - 1 else i + 1]
				local dx, dz = unit(b.x - s.x, b.z - s.z)
				cx, cz = s.x + dx * (s.radius + Front.Line.edge), s.z + dz * (s.radius + Front.Line.edge)
			end
			local aim = S[if side == "West" then i + 1 else i - 1]
			local fx, fz = unit(aim.x - cx, aim.z - cz)
			local out = {}
			for k = 1, rows * Front.Line.perRow do
				local r, bk = R.slot(k, Front.Line)
				local x, z = cx - fz * r - fx * bk, cz + fx * r - fz * bk
				table.insert(out, Vector3.new(x, ground(x, z, 200) or 0, z))
			end
			return out
		end
		local seen, total = 0, 0
		for i = 1, #S - 1 do
			for _, p in { { "West", i, "East", i + 1 }, { "East", i + 1, "West", i } } do
				local viewers = line(p[3], p[4], 1)
				local pt = S[p[4]]
				table.insert(viewers, Vector3.new(pt.x, ground(pt.x, pt.z, 200) or 0, pt.z))
				for _, slot in line(p[1], p[2], 2) do
					for _, v in viewers do
						total += 1
						local from = v + Vector3.new(0, M.Character.EyeHeight, 0)
						local to = slot + Vector3.new(0, M.Character.Height, 0)
						if not workspace:Raycast(from, to - from, every) then
							seen += 1
						end
					end
				end
			end
		end
		report(seen == 0, `spawn cover: {seen} of {total} sight lines reach a wave line's heads`)
	end
	return table.concat(lines, "\n")
end

return Audit
