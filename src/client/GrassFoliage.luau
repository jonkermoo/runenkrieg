--!strict
-- Client grass: low-poly tufts on Grass/LeafyGrass terrain around the camera, density and draw
-- distance from the GrassQuality setting (Config/Foliage.Levels). Candidates come from Rules/Grass
-- (deterministic per cell); each is raycast onto the terrain for exact height and material.
-- Nearby tufts sway in workspace.GlobalWind. Purely visual: no collision, no queries, no shadows.
-- Two layers, each with its own models, cells, levels and sway: the thick tufts (Config/Foliage, Assets GrassKit) and
-- the thin, flowy blade patches (Config/Foliage.Blades, Assets GrassBlades; in place of Roblox's terrain grass).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Foliage = require(Shared.Config.Foliage)
local Palette = require(Shared.Config.Palette)
local Assets = require(Shared.Config.Assets)
local Grass = require(Shared.Rules.Grass)
local Blast = require(Shared.Rules.Blast)
local DamageCfg = require(Shared.Config.Damage)
local Net = require(Shared.Net)
local TreeCfg = require(Shared.Config.TreeSway)
local Settings = require(script.Parent.Settings)

local GrassFoliage = {}

type Tuft = { part: BasePart, base: CFrame, x: number, z: number }
type Chunk = { tufts: { Tuft } }

local CHUNKS_PER_TICK = 6 -- spreads loading over frames when the camera jumps

-- One layer: `entryName`'s `variant` meshes, placed by `Cfg` (Config/Foliage or one of its layers), shaded from
-- `palette`, in workspace.<folderName>.
local function layer(entryName: string, variant: string, Cfg: any, palette: { { number } }, folderName: string)
	local entry = Assets.Entries[entryName]
	local kit = ReplicatedStorage:WaitForChild("Assets")
		:WaitForChild(entry.category)
		:WaitForChild(entry.folder)
		:WaitForChild(entryName)
	local templates: { BasePart } = {}
	for _, name in (entry.variants :: any)[variant] do
		local t = kit:WaitForChild(name) :: BasePart
		local c = t:Clone()
		c.Anchored = true
		c.CanCollide = false
		c.CanQuery = false
		c.CanTouch = false
		c.CastShadow = false
		c.Material = Enum.Material.SmoothPlastic
		table.insert(templates, c)
	end
	local shades = {}
	for _, s in palette do
		table.insert(shades, Color3.fromRGB(s[1], s[2], s[3]))
	end
	local grows: { [Enum.Material]: boolean } = {}
	for _, m in Cfg.Materials do
		grows[(Enum.Material :: any)[m]] = true
	end

	local container = Instance.new("Folder")
	container.Name = folderName
	container.Parent = workspace

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = true

	local loaded: { [string]: Chunk } = {}
	-- the ground under fallen trunks: { ax, az, bx, bz } lines, no grass within UnderTrunk.radius (user 2026-10-17)
	local trunks: { [Model]: { number } } = {}
	local function underTrunk(x: number, z: number): boolean
		for _, s in trunks do
			if Grass.nearSegment(x, z, s[1], s[2], s[3], s[4], Foliage.UnderTrunk.radius) then
				return true
			end
		end
		return false
	end
	local level = Cfg.Levels[Settings.get("GrassQuality")]
	container:SetAttribute("Quality", Settings.get("GrassQuality")) -- debug/test visibility

	local function unload(key: string)
		local c = loaded[key]
		if c then
			for _, t in c.tufts do
				t.part:Destroy()
			end
			loaded[key] = nil
		end
	end

	local function load(cx: number, cz: number)
		local chunk: Chunk = { tufts = {} }
		for _, c in Grass.chunk(cx, cz, level.density, Cfg) do
			local hit = workspace:Raycast(Vector3.new(c.x, 150, c.z), Vector3.new(0, -400, 0), params)
			if hit and grows[hit.Material] and not underTrunk(c.x, c.z) then
				local p = templates[c.variant % #templates + 1]:Clone()
				p.Size *= c.scale
				p.Color = shades[c.shade % #shades + 1]
				local base = CFrame.new(hit.Position.X, hit.Position.Y + p.Size.Y / 2 - Cfg.Sink, hit.Position.Z)
					* CFrame.Angles(0, math.rad(c.yaw), 0)
				p.CFrame = base
				p.Parent = container
				table.insert(chunk.tufts, { part = p, base = base, x = c.x, z = c.z })
			end
		end
		loaded[cx .. ":" .. cz] = chunk
	end

	local function clear()
		for key in loaded do
			unload(key)
		end
	end

	-- a blast churns the ground round it (src/server/Damage): the grass standing there goes at once (user 2026-10-17:
	-- "grass should be instantly gone after an explosion"). Checked again once the voxels have arrived.
	-- `depth`: tufts within `r` across and this far up or down from the blast go whatever the ground says (the server
	-- churns exactly that: src/server/Damage); the rest go if their ground no longer grows grass
	local function scrub(position: Vector3, r: number, depth: number)
		local size = Cfg.ChunkSize
		for cx = math.floor((position.X - r) / size), math.floor((position.X + r) / size) do
			for cz = math.floor((position.Z - r) / size), math.floor((position.Z + r) / size) do
				local c = loaded[cx .. ":" .. cz]
				if c then
					for i = #c.tufts, 1, -1 do
						local t = c.tufts[i]
						if (t.x - position.X) ^ 2 + (t.z - position.Z) ^ 2 <= r * r then
							local y = t.base.Position.Y
							local churned = math.abs(y - position.Y) <= depth
							local hit = not churned
								and workspace:Raycast(Vector3.new(t.x, y + 12, t.z), Vector3.new(0, -40, 0), params)
							if churned or not hit or not grows[hit.Material] then
								t.part:Destroy()
								table.remove(c.tufts, i)
							end
						end
					end
				end
			end
		end
	end
	-- (Destruction.explode sends a plain radius, not a reach: harmless, scrub only takes tufts off ground that changed)
	Net.event("Explosion").OnClientEvent:Connect(function(position: Vector3, reach: number)
		local C = DamageCfg.Blast.Crater
		local churn = Blast.churnFromReach(reach, DamageCfg.Blast)
		scrub(position, churn, churn / C.churn * C.churnDepth + Foliage.Scrub.margin) -- at once
		for _, after in Foliage.Scrub.after do
			task.delay(after, scrub, position, churn + Foliage.Scrub.margin, -1)
		end
	end)

	local function clearUnder(s: { number })
		local r = Foliage.UnderTrunk.radius
		local size = Cfg.ChunkSize
		for cx = math.floor((math.min(s[1], s[3]) - r) / size), math.floor((math.max(s[1], s[3]) + r) / size) do
			for cz = math.floor((math.min(s[2], s[4]) - r) / size), math.floor((math.max(s[2], s[4]) + r) / size) do
				local c = loaded[cx .. ":" .. cz]
				if c then
					for i = #c.tufts, 1, -1 do
						local t = c.tufts[i]
						if Grass.nearSegment(t.x, t.z, s[1], s[2], s[3], s[4], r) then
							t.part:Destroy()
							table.remove(c.tufts, i)
						end
					end
				end
			end
		end
	end
	local function fallen(inst: Instance)
		local to, length = inst:GetAttribute("FallTo"), inst:GetAttribute("FallLength")
		if not inst:IsA("Model") or typeof(to) ~= "CFrame" or type(length) ~= "number" then
			return
		end
		local tree = inst
		local a = to.Position
		local b = a + to.UpVector * length
		local s = { a.X, a.Z, b.X, b.Z }
		trunks[tree] = s
		clearUnder(s)
		tree.Destroying:Connect(function()
			trunks[tree] = nil
		end)
	end
	CollectionService:GetInstanceAddedSignal(TreeCfg.FallingTag):Connect(function(inst)
		task.delay(DamageCfg.Trees.Fall.time, fallen, inst) -- once it is down
	end)
	for _, inst in CollectionService:GetTagged(TreeCfg.FallingTag) do
		fallen(inst)
	end

	Settings.changed("GrassQuality", function(value)
		level = Cfg.Levels[value]
		container:SetAttribute("Quality", value)
		clear()
	end)

	-- chunk streaming around the camera
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / Cfg.UpdateHz then
			return
		end
		acc = 0
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local p = cam.CFrame.Position
		local wanted = {}
		local budget = CHUNKS_PER_TICK
		for _, c in Grass.chunksAround(p.X, p.Z, level.radius, Cfg.ChunkSize) do
			local key = c[1] .. ":" .. c[2]
			wanted[key] = true
			if not loaded[key] and budget > 0 then
				load(c[1], c[2])
				budget -= 1
			end
		end
		-- unload with a little hysteresis so chunks at the edge don't flicker
		local keep = {}
		for _, c in Grass.chunksAround(p.X, p.Z, level.radius + Cfg.ChunkSize, Cfg.ChunkSize) do
			keep[c[1] .. ":" .. c[2]] = true
		end
		local n = 0
		for key in loaded do
			if not keep[key] then
				unload(key)
			else
				n += 1
			end
		end
		container:SetAttribute("Chunks", n)
	end)

	-- sway for nearby tufts
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local swayed: { Tuft } = {}
	RunService.RenderStepped:Connect(function()
		table.clear(parts)
		table.clear(cframes)
		local cam = workspace.CurrentCamera
		local r = level.swayRadius
		-- restore tufts that swayed last frame but are now out of range (or sway is off)
		for _, t in swayed do
			table.insert(parts, t.part)
			table.insert(cframes, t.base)
		end
		table.clear(swayed)
		if cam and r > 0 then
			local p = cam.CFrame.Position
			local wind = workspace.GlobalWind
			local speed = math.max(wind.Magnitude, 1e-3)
			local wx, wz = wind.X / speed, wind.Z / speed
			local strength = math.clamp(speed / 12, 0.2, 1.5)
			local amp = math.rad(Cfg.Sway.amp) * strength
			local now = os.clock()
			local ccx, ccz = math.floor(p.X / Cfg.ChunkSize), math.floor(p.Z / Cfg.ChunkSize)
			local cr = math.ceil(r / Cfg.ChunkSize)
			for i = ccx - cr, ccx + cr do
				for j = ccz - cr, ccz + cr do
					local c = loaded[i .. ":" .. j]
					if c then
						for _, t in c.tufts do
							if (t.x - p.X) ^ 2 + (t.z - p.Z) ^ 2 < r * r then
								local a = amp
									* (
										0.5
										+ 0.5
											* math.sin(2 * math.pi * Cfg.Sway.freq * now - (t.x * wx + t.z * wz) * 0.08)
									)
								local axis = Vector3.new(wz, 0, -wx)
								local pivot = t.base * CFrame.new(0, -t.part.Size.Y / 2, 0)
								local rot = CFrame.new(pivot.Position)
									* CFrame.fromAxisAngle(axis, a)
									* CFrame.new(-pivot.Position)
								table.insert(parts, t.part)
								table.insert(cframes, rot * t.base)
								table.insert(swayed, t)
							end
						end
					end
				end
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

function GrassFoliage.start()
	task.spawn(layer, "GrassKit", "Tuft", Foliage, Palette.GrassTufts, "ClientGrass")
	task.spawn(layer, "GrassBlades", "Blade", Foliage.Blades, Palette.GrassBlades, "ClientGrassBlades")
end

return GrassFoliage
