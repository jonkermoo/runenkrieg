--!strict
-- Trenches v2 on the server (Config/Build.Trench, Rules/Build; design page https://claude.ai/artifact/FRZKPxjdaq3nXAzFwWwFb6).
-- Carved into the terrain like the howitzer's pit (src/server/Ground.pit; user 2026-10-23: "I really like how the
-- mortar dug out is like"): mud floor and walls, earth thrown up as a bank along both edges.
-- - A plan (Net "Build" "Plan", start, end) is one straight run, split into squares (Rules.planBlocks; user
--   2026-10-23: "you have to dig each stud", "make each square of a trench distinct"), each pegged out with its own
--   string outline everyone sees until it is dug full. Its ends join a free end of the team's trench (end to end, up
--   to Trench.maxBend) or the side of one of its squares (a T); it may not cross a trench. Undug plans go after
--   Trench.planLife.
-- - Each square has HP like any structure, and its depth is its HP (user: "they have hp. how dug in they are are
--   determined by hp"): Build swings add HP (Trenches.work, from src/server/Build); at full HP its dirt pieces go in
--   (Config/Assets trench_pieces): a wall each side and a floor rolled from its seed (Rules.trenchPieces), some walls
--   with plank steps, a wall across a dead end, none where another trench tees in.
-- - Destroy swings (any team's trench) and blasts (Trenches.blast, from src/server/Build.blast, by the overpressure
--   at the square) take HP off: it falls in (clods off the walls, shallower, churned earth); at 0 it is a scar, a
--   lumpy dip of churned earth that stays.
-- The terrain is reshaped from the ground as it was before any trench touched it (kept per voxel), so digging,
-- joining, falling in and scars are all the one union of every square's profile over that ground.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local C = require(Shared.Config.Build)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Build)
local Survey = require(Shared.BuildSurvey)
local Net = require(Shared.Net)

local Trenches = {}

local T = C.Trench
local VOXEL = 4
local TOP = Rules.trenchTop(T)
local KIND = "TrenchBlock"

type Link = { kind: string, other: Block, which: string? } -- "end" (with `which` end of `other`) or "tee"

export type Block = {
	id: number,
	team: string,
	a: Vector3, -- end A on the ground (its height is the ground line's there)
	b: Vector3,
	dir: Vector3, -- flat unit, A to B
	across: Vector3, -- flat unit, to the block's left
	length: number,
	hp: number, -- its depth: hp / Trench.hp.max of the full depth
	falling: boolean, -- lost HP since it was last full (churned earth, its pieces off)
	scar: boolean,
	linkA: Link?,
	linkB: Link?,
	run: { Block },
	model: Model?,
	worked: number,
	seed: number,
}

local blocks: { [number]: Block } = {}
local byModel: { [Model]: Block } = {}
local nextId = 0
-- the ground before any trench: per voxel ("x,y,z" in voxel units), { occupancy, material }
local original: { [string]: { o: number, m: Enum.Material } } = {}

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = false

local function rgb(c: { number }, k: number?): Color3
	local f = k or 1
	return Color3.fromRGB(math.clamp(c[1] * f, 0, 255), math.clamp(c[2] * f, 0, 255), math.clamp(c[3] * f, 0, 255))
end

local function folder(): Folder
	local f = workspace:FindFirstChild(C.Folder)
	if not f then
		f = Instance.new("Folder")
		f.Name = C.Folder
		f.Parent = workspace
	end
	return f :: Folder
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, solid: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- a block's point `u` along, `v` across, on its ground line (flat parts from end A)
local function at(blk: Block, u: number, v: number): Vector3
	local y = blk.a.Y + (blk.b.Y - blk.a.Y) * math.clamp(u / blk.length, 0, 1)
	return Vector3.new(blk.a.X, y, blk.a.Z) + blk.dir * u + blk.across * v
end

local function live(blk: Block?): boolean
	return blk ~= nil and blocks[blk.id] == blk and not blk.scar
end

-- how deep a square is cut now: its HP's share of the full depth
local function shareOf(blk: Block): number
	return if blk.scar then 0 else blk.hp / T.hp.max
end

local function shapeOf(blk: Block): Rules.BlockShape
	local function ext(link: Link?): (number, boolean)
		if not link or not live(link.other) or link.other.hp <= 0 then
			return 0, true -- a dead end: the walls close round it (also against an undug neighbour)
		end
		-- a T reaches the other trench's centre line already; straight on, the next square takes over at the joint; at
		-- a bend the hole runs on to fill the outside of the corner, where the other square is at least as deep
		if link.kind == "tee" or link.other.dir:Dot(blk.dir) > 0.995 or shareOf(link.other) < shareOf(blk) then
			return 0, false
		end
		return TOP, false
	end
	local extA, deadA = ext(blk.linkA)
	local extB, deadB = ext(blk.linkB)
	return { length = blk.length, extA = extA, extB = extB, deadA = deadA, deadB = deadB }
end

local function publish(blk: Block)
	local m = blk.model
	if not m then
		return
	end
	m:SetAttribute("HP", math.floor(blk.hp + 0.5))
	m:SetAttribute("MaxHP", T.hp.max)
	m:SetAttribute("Falling", blk.falling)
	local function linkName(l: Link?): string
		return if l and live(l.other) then l.kind else ""
	end
	m:SetAttribute("LinkA", linkName(blk.linkA))
	m:SetAttribute("LinkB", linkName(blk.linkB))
end

-- Reshapes the terrain round `centre` (within `reach`, flat): back to the ground before any trench where one touched
-- it, then cut by every square there (the deepest cut wins), banks thrown up where nothing cuts, scars as shallow dips.
local function reshape(centre: Vector3, reach: number)
	local terrain = workspace.Terrain
	local half = Vector3.new(reach, T.depth + T.bank.height + VOXEL * 4, reach)
	local region = Region3.new(centre - half, centre + half):ExpandToGrid(VOXEL)
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return
	end
	local size = mats.Size
	local corner = region.CFrame.Position - region.Size / 2
	local gx, gy, gz = math.round(corner.X / VOXEL), math.round(corner.Y / VOXEL), math.round(corner.Z / VOXEL)
	local near = {}
	for _, blk in blocks do
		local mid = (blk.a + blk.b) / 2
		local flat = Vector3.new(mid.X - centre.X, 0, mid.Z - centre.Z).Magnitude
		if flat <= reach + blk.length / 2 + TOP + T.bank.width then
			table.insert(near, { blk = blk, shape = shapeOf(blk), share = shareOf(blk) })
		end
	end
	for ix = 1, size.X do
		for iz = 1, size.Z do
			local x, z = corner.X + (ix - 0.5) * VOXEL, corner.Z + (iz - 0.5) * VOXEL
			local column = table.create(size.Y, 0)
			for iy = 1, size.Y do
				local o = original[`{gx + ix - 1},{gy + iy - 1},{gz + iz - 1}`]
				if o then
					occs[ix][iy][iz] = o.o
					mats[ix][iy][iz] = o.m
				end
				column[iy] = occs[ix][iy][iz]
			end
			local top = Rules.columnTop(column, corner.Y, VOXEL)
			local cut: number? = nil
			local churned = false
			local bank: number? = nil
			for _, n in near do
				local blk: Block = n.blk
				local rel = Vector3.new(x - blk.a.X, 0, z - blk.a.Z)
				local u, v = rel:Dot(blk.dir), rel:Dot(blk.across)
				local r = Rules.trenchReach(u, v, n.shape, T.floor)
				if r then
					local line = blk.a.Y + (blk.b.Y - blk.a.Y) * math.clamp(u / blk.length, 0, 1)
					if blk.scar then
						if r <= TOP then
							local want = line - T.scar.depth * (1 - r / TOP)
							if not cut or want < cut then
								cut, churned = want, true
							end
						end
					else
						local h = Rules.trenchProfile(r, n.share, T)
						if h and h < 0 then
							local want = line + h
							if not cut or want < cut then
								cut, churned = want, blk.falling
							end
						elseif h and h > 0 and top then
							bank = math.max(bank or -math.huge, top + h)
						end
					end
				end
			end
			if cut or bank then
				for iy = 1, size.Y do
					local key = `{gx + ix - 1},{gy + iy - 1},{gz + iz - 1}`
					if not original[key] then
						original[key] = { o = occs[ix][iy][iz], m = mats[ix][iy][iz] }
					end
				end
			end
			if cut then
				-- cut down to it; what's left of the column is mud (churned earth where it is falling in, or a scar), as the
				-- howitzer's pit
				local out = Rules.shapeColumn(column, corner.Y, VOXEL, cut, true)
				for iy = 1, size.Y do
					if out[iy] < occs[ix][iy][iz] then
						occs[ix][iy][iz] = out[iy]
					end
					if occs[ix][iy][iz] <= 0 then
						mats[ix][iy][iz] = Enum.Material.Air
					else
						mats[ix][iy][iz] = if churned then Enum.Material.Ground else Enum.Material.Mud
					end
				end
			elseif bank then
				local out = Rules.shapeColumn(column, corner.Y, VOXEL, bank, false)
				for iy = 1, size.Y do
					if out[iy] > occs[ix][iy][iz] then
						occs[ix][iy][iz] = out[iy]
						mats[ix][iy][iz] = Enum.Material.Ground
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, VOXEL, mats, occs)
	Net.event("GroundDug"):FireAllClients(centre, reach)
end

local function reshapeBlock(blk: Block)
	local mid = (blk.a + blk.b) / 2
	reshape(mid, blk.length / 2 + TOP + T.bank.width + VOXEL)
end

-- clods knocked off the walls: client debris (src/client/Debris), earth coloured
local function clods(blk: Block, n: number)
	local pieces = {}
	for _ = 1, n do
		local s = if math.random() < 0.5 then -1 else 1
		local u = math.random() * blk.length
		local h = 1 + math.random() * (T.depth - 1.5)
		local p = at(blk, u, s * (T.floor + (TOP - T.floor) * h / T.depth)) - Vector3.new(0, T.depth - h, 0)
		local size = T.clods.size[1] + math.random() * (T.clods.size[2] - T.clods.size[1])
		table.insert(pieces, {
			cf = CFrame.new(p) * CFrame.Angles(math.random() * 3, math.random() * 3, 0),
			size = Vector3.new(size, size * 0.8, size),
			color = rgb(Palette.Build.Earth, 0.85 + math.random() * 0.25),
			t = 0,
		})
	end
	Net.event("SectionBroken"):FireAllClients(pieces, at(blk, blk.length / 2, 0))
end

-- a square still to be dug: a peg at each corner of its outline (its top edges) with string round it, and a flag at
-- each end of its run
local function markers(blk: Block)
	local m = blk.model :: Model
	local old = m:FindFirstChild("Markers")
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Folder")
	holder.Name = "Markers"
	holder.Parent = m
	local M = T.markers
	local peg = rgb(Palette.Build.Picket)
	local corners = {}
	for _, c in { { 0, -TOP }, { blk.length, -TOP }, { blk.length, TOP }, { 0, TOP } } do
		local g = at(blk, c[1], c[2])
		local hit = workspace:Raycast(g + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), terrainOnly)
		local base = if hit then hit.Position else g
		part(
			holder,
			"Peg",
			Vector3.new(M.peg[1], M.peg[2], M.peg[1]),
			CFrame.new(base + Vector3.new(0, M.peg[2] / 2 - 0.15, 0)),
			peg,
			false
		)
		table.insert(corners, base + Vector3.new(0, M.peg[2] - 0.15, 0))
	end
	for i = 1, 4 do
		local p0, p1 = corners[i], corners[i % 4 + 1]
		part(
			holder,
			"String",
			Vector3.new(M.string, M.string, (p1 - p0).Magnitude),
			CFrame.lookAt((p0 + p1) / 2, p1),
			rgb(Palette.Build.String),
			false
		)
	end
	-- flags at the run's ends
	local first, last = blk.run[1], blk.run[#blk.run]
	for _, e in { { first, 0 }, { last, last.length } } do
		if e[1] == blk then
			local g = at(blk, e[2], 0)
			local hit = workspace:Raycast(g + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), terrainOnly)
			local base = if hit then hit.Position else g
			part(
				holder,
				"Pole",
				Vector3.new(0.12, M.flag, 0.12),
				CFrame.new(base + Vector3.new(0, M.flag / 2, 0)),
				peg,
				false
			)
			part(
				holder,
				"Flag",
				Vector3.new(0.05, 0.6, 0.9),
				CFrame.new(base + Vector3.new(0, M.flag - 0.35, 0)) * CFrame.new(blk.across * 0.45),
				rgb(Palette.Build.Flag),
				false
			)
		end
	end
end

-- The dirt pieces' library model (ReplicatedStorage.Assets, kept by the Library sync) and where each mesh sits from its
-- Origin (piece space), found once
local kit: Model? = nil
local offsets: { [string]: CFrame } = {}
local function pieceKit(): Model?
	if kit then
		return kit
	end
	local e = Assets.Entries.trench_pieces
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and f:FindFirstChild(e.category)
	for _, sub in string.split(e.folder, "/") do
		f = f and f:FindFirstChild(sub)
	end
	local m = f and f:FindFirstChild("trench_pieces")
	local origin = m and m:FindFirstChild("Origin")
	if not (m and origin and origin:IsA("BasePart")) then
		warn("[Trenches] trench_pieces is not in the asset library: run the Library sync (CLAUDE.md)")
		return nil
	end
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") then
			offsets[d.Name] = origin.CFrame:ToObjectSpace(d.CFrame)
		end
	end
	kit = m :: Model
	return kit
end

local function pieceColor(name: string): Color3
	local B = Palette.Build
	local i = tonumber(string.match(name, "^Wall(%d+)"))
	if string.find(name, "PlanksDark") then
		return rgb(B.PlankDark)
	elseif string.find(name, "Planks") then
		return rgb(B.Plank)
	elseif i then
		local tone = (i - 1) % #B.TrenchWall + 1
		return rgb(if string.find(name, "Chunks") then B.TrenchWallChunks[tone] else B.TrenchWall[tone])
	end
	return rgb(if string.find(name, "Chunks") then B.TrenchFloorChunks else B.TrenchFloor)
end

-- the sides of a square another trench tees into (1 its left, 2 its right): no wall there
local function teeSides(blk: Block): { boolean }
	local open = { false, false }
	for _, o in blocks do
		if o ~= blk and live(o) then
			for _, e in { { o.linkA, o.a }, { o.linkB, o.b } } do
				local l: Link? = e[1]
				if l and l.kind == "tee" and l.other == blk then
					open[if (e[2] - blk.a):Dot(blk.across) >= 0 then 1 else 2] = true
				end
			end
		end
	end
	return open
end

-- A square's dirt pieces: a wall each side and a floor (Rules.trenchPieces), a plain wall across each dead end, laid in
-- piece space (x along, y up from the floor, z out of the trench) on the square's floor, stretched along a short one.
-- Rebuilt only when its ends or tees change.
local function pieces(blk: Block)
	local m = blk.model :: Model
	local k = pieceKit()
	if not k then
		return
	end
	local shape = shapeOf(blk)
	local open = teeSides(blk)
	local sig = `{shape.deadA}{shape.deadB}{open[1]}{open[2]}`
	local old = m:FindFirstChild("Pieces")
	if old and old:GetAttribute("Sig") == sig then
		return
	end
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Folder")
	holder.Name = "Pieces"
	holder:SetAttribute("Sig", sig)
	holder.Parent = m
	local P = T.pieces
	local i = table.find(blk.run, blk)
	local prev = if i and i > 1 then blk.run[i - 1] else nil
	local roll = Rules.trenchPieces(blk.seed, prev and prev.seed, P)
	local down = Vector3.new(0, T.depth, 0)
	local function floorAt(u: number, v: number): Vector3
		return at(blk, u, v) - down
	end
	local along = (floorAt(blk.length, 0) - floorAt(0, 0)).Unit
	local right = -blk.across
	-- a frame at `origin`: piece x along `x`, z out of the trench `z` (flat), y up square to both
	local function frame(origin: Vector3, x: Vector3, z: Vector3): CFrame
		return CFrame.fromMatrix(origin, x, z:Cross(x).Unit, z)
	end
	local function place(name: string, cf: CFrame, stretch: number)
		local src = k:FindFirstChild(name)
		local off = offsets[name]
		if not (src and src:IsA("BasePart") and off) then
			return
		end
		local p = src:Clone()
		p.Size = Vector3.new(src.Size.X * stretch, src.Size.Y, src.Size.Z)
		p.CFrame = cf * CFrame.new(off.Position.X * stretch, off.Position.Y, off.Position.Z) * off.Rotation
		p.Color = pieceColor(name)
		local base = not (string.find(name, "Chunks") or string.find(name, "Planks"))
		p.Anchored = true
		p.CanCollide = base
		p.CanQuery = base
		p.CanTouch = false
		p.Parent = holder
	end
	local function wall(n: number, cf: CFrame, stretch: number)
		for _, suffix in { "", "Chunks", "Planks", "PlanksDark" } do
			place(`Wall{n}{suffix}`, cf, stretch)
		end
	end
	local stretch = blk.length / P.segment
	-- side walls: the right one runs from the start, the left one turned round from the end
	if not open[2] then
		wall(roll.walls[2], frame(floorAt(0, -T.floor), along, right), stretch)
	end
	if not open[1] then
		wall(roll.walls[1], frame(floorAt(blk.length, T.floor), -along, blk.across), stretch)
	end
	local floorCf = if roll.flip
		then frame(floorAt(blk.length, 0), -along, blk.across)
		else frame(floorAt(0, 0), along, right)
	place(`Floor{roll.floor}`, floorCf, stretch)
	place(`Floor{roll.floor}Chunks`, floorCf, stretch)
	-- dead ends: a plain wall across the floor
	local across = 2 * T.floor / P.segment
	local flat = Vector3.new(along.X, 0, along.Z).Unit
	if shape.deadA then
		wall(roll.ends[1], frame(floorAt(0, T.floor), right, -flat), across)
	end
	if shape.deadB then
		wall(roll.ends[2], frame(floorAt(blk.length, -T.floor), blk.across, flat), across)
	end
end

-- shows a square as its HP stands
local function apply(blk: Block, reshapeIt: boolean)
	if reshapeIt then
		reshapeBlock(blk)
	end
	local m = blk.model
	if not m then
		return
	end
	local markersOn = blk.hp < T.hp.max and not blk.falling
	local pegs = m:FindFirstChild("Markers")
	if markersOn and not pegs then
		markers(blk)
	elseif not markersOn and pegs then
		pegs:Destroy()
	end
	-- the dirt pieces lie in a square dug full that hasn't lost HP since
	local full = blk.hp >= T.hp.max and not blk.falling
	if full then
		pieces(blk)
	else
		local old = m:FindFirstChild("Pieces")
		if old then
			old:Destroy()
		end
	end
	publish(blk)
end

local function linked(blk: Block): { Block }
	local out = {}
	for _, l in { blk.linkA, blk.linkB } do
		if l and live(l.other) then
			table.insert(out, l.other)
		end
	end
	-- and the blocks whose ends join this one
	for _, o in blocks do
		for _, l in { o.linkA, o.linkB } do
			if l and l.other == blk and o ~= blk then
				table.insert(out, o)
			end
		end
	end
	return out
end

-- a block gone (an undug plan pulled up) or filled in to a scar: the blocks joined to it close up
local function finish(blk: Block, scar: boolean)
	local neighbours = linked(blk)
	if blk.model then
		byModel[blk.model] = nil
		blk.model:Destroy()
		blk.model = nil
	end
	if scar then
		blk.scar = true
	else
		blocks[blk.id] = nil
	end
	reshapeBlock(blk)
	for _, o in neighbours do
		if live(o) then
			apply(o, true)
		end
	end
end

-- the block whose free end `which` is nearest `p` (within Trench.joinReach), or the block whose side `p` is on
local function snap(p: Vector3, team: string): (Vector3, Link?)
	local best: Block?, bestWhich: string?, bestD = nil, nil, T.joinReach
	for _, blk in blocks do
		if live(blk) and blk.team == team then
			for _, which in { "A", "B" } do
				local link = if which == "A" then blk.linkA else blk.linkB
				local e = if which == "A" then blk.a else blk.b
				local d = Vector3.new(p.X - e.X, 0, p.Z - e.Z).Magnitude
				if (not link or not live(link.other)) and d < bestD then
					best, bestWhich, bestD = blk, which, d
				end
			end
		end
	end
	if best and bestWhich then
		local e = if bestWhich == "A" then best.a else best.b
		return e, { kind = "end", other = best, which = bestWhich }
	end
	for _, blk in blocks do
		if live(blk) and blk.team == team then
			local rel = Vector3.new(p.X - blk.a.X, 0, p.Z - blk.a.Z)
			local u, v = rel:Dot(blk.dir), rel:Dot(blk.across)
			if u >= 0 and u <= blk.length and math.abs(v) <= TOP then
				return at(blk, u, 0), { kind = "tee", other = blk }
			end
		end
	end
	return p, nil
end

-- the ground at (x, z) as it was before any trench dug there: a block's ground line where one is, else the terrain
local function groundAt(x: number, z: number, near: number): (number?, boolean)
	for _, blk in blocks do
		local rel = Vector3.new(x - blk.a.X, 0, z - blk.a.Z)
		local u, v = rel:Dot(blk.dir), rel:Dot(blk.across)
		if u >= -TOP and u <= blk.length + TOP and math.abs(v) <= TOP + T.bank.width then
			return blk.a.Y + (blk.b.Y - blk.a.Y) * math.clamp(u / blk.length, 0, 1), false
		end
	end
	local hit = workspace:Raycast(Vector3.new(x, near + 60, z), Vector3.new(0, -160, 0), terrainOnly)
	if not hit then
		return nil, false
	end
	return hit.Position.Y, hit.Material == Enum.Material.Water
end

-- the angle off straight where a run leaves a free end: `leave` points from the joint into the run
local function bendAt(link: Link, leave: Vector3): number
	local o = link.other
	local out = if link.which == "A" then -o.dir else o.dir
	return Rules.bend(out.X, out.Z, leave.X, leave.Z)
end

-- Lays a plan (Net "Build" "Plan"): its start and end (ground points). Returns the reason when refused.
function Trenches.plan(player: Player, team: string, root: BasePart, a0: Vector3, b0: Vector3): string?
	local a, linkA = snap(a0, team)
	local b, linkB = snap(b0, team)
	if linkA and linkB and linkA.other == linkB.other then
		return "That's the same trench"
	end
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = flat.Magnitude
	if length > T.maxPlan + 0.5 then
		return `Too long: at most {T.maxPlan} studs`
	end
	local spans = Rules.planBlocks(length, T.block, T.minBlock)
	if not spans then
		return "Too short"
	end
	if Vector3.new(root.Position.X - a0.X, 0, root.Position.Z - a0.Z).Magnitude > T.firstReach + 4 then
		return "Too far"
	end
	local dir = flat.Unit
	if linkA and linkA.kind == "end" and bendAt(linkA, dir) > T.maxBend then
		return "Too sharp a bend"
	end
	if linkB and linkB.kind == "end" and bendAt(linkB, -dir) > T.maxBend then
		return "Too sharp a bend"
	end
	-- it may not cross a trench: only touch the ones it joins, at its ends
	for _, blk in blocks do
		if live(blk) then
			local mid = (blk.a + blk.b) / 2
			local t0, t1 = Rules.clipRect(a.X, a.Z, b.X, b.Z, mid.X, mid.Z, blk.dir.X, blk.dir.Z, blk.length / 2, TOP)
			if t0 and t1 then
				local fromA, toB = t0 * length, (1 - t1) * length
				local joinedA = linkA and (linkA.other == blk or table.find(linked(linkA.other), blk) ~= nil)
				local joinedB = linkB and (linkB.other == blk or table.find(linked(linkB.other), blk) ~= nil)
				local okA = joinedA and fromA <= 0.01 and t1 * length <= TOP + 2
				local okB = joinedB and toB <= 0.01 and (1 - t0) * length <= TOP + 2
				if not okA and not okB then
					return "Stop at the trench, then start again from the other side"
				end
			end
		end
	end
	-- the ground along it: no water, not too steep along, nothing standing in the way
	local samples = math.max(math.ceil(length / 3), 1)
	local heights = {}
	for i = 0, samples do
		local p = a + flat * (i / samples)
		local h, wet = groundAt(p.X, p.Z, a.Y)
		if not h then
			return "Needs open ground"
		end
		if wet then
			return "Not in water"
		end
		heights[i] = h
		if i > 0 and Rules.slope(heights[i - 1], h, length / samples) > T.maxSlope then
			return "Too steep"
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace.Terrain, folder() }
	local mid = a + flat / 2
	local box = CFrame.lookAt(
		Vector3.new(mid.X, heights[math.floor(samples / 2)] + 3.5, mid.Z),
		Vector3.new(b.X, heights[math.floor(samples / 2)] + 3.5, b.Z)
	)
	for _, p in workspace:GetPartBoundsInBox(box, Vector3.new(2 * T.floor + 2, 5, math.max(length - 2, 1)), params) do
		local model = p:FindFirstAncestorWhichIsA("Model")
		if p.CanCollide and not (model and model:FindFirstChildOfClass("Humanoid")) then
			return "In the way"
		end
	end
	-- lay it: the run's blocks, linked end to end, and to the trenches it joins
	local run: { Block } = {}
	local now = os.clock()
	local f = folder()
	local function heightAt(d: number): number
		local x = d / length * samples
		local i = math.clamp(math.floor(x), 0, samples - 1)
		return heights[i] + (heights[i + 1] - heights[i]) * (x - i)
	end
	for i, span in spans do
		nextId += 1
		local pa = a + dir * span.from
		local pb = a + dir * span.to
		local blk: Block = {
			id = nextId,
			team = team,
			a = Vector3.new(pa.X, if i == 1 and linkA then a.Y else heightAt(span.from), pa.Z),
			b = Vector3.new(pb.X, if i == #spans and linkB then b.Y else heightAt(span.to), pb.Z),
			dir = dir,
			across = Vector3.new(-dir.Z, 0, dir.X),
			length = span.to - span.from,
			hp = 0,
			falling = false,
			scar = false,
			linkA = nil,
			linkB = nil,
			run = run,
			model = nil,
			worked = now,
			seed = math.random(1, 2 ^ 30),
		}
		table.insert(run, blk)
		blocks[blk.id] = blk
	end
	for i, blk in run do
		if i > 1 then
			blk.linkA = { kind = "end", other = run[i - 1], which = "B" }
			run[i - 1].linkB = { kind = "end", other = blk, which = "A" }
		end
	end
	local first, last = run[1], run[#run]
	if linkA then
		first.linkA = linkA
		if linkA.kind == "end" then
			local o = linkA.other
			local back: Link = { kind = "end", other = first, which = "A" }
			if linkA.which == "A" then
				o.linkA = back
			else
				o.linkB = back
			end
		end
	end
	if linkB then
		last.linkB = linkB
		if linkB.kind == "end" then
			local o = linkB.other
			local back: Link = { kind = "end", other = last, which = "B" }
			if linkB.which == "A" then
				o.linkA = back
			else
				o.linkB = back
			end
		end
	end
	for _, blk in run do
		local m = Instance.new("Model")
		m.Name = KIND
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		m:SetAttribute("Kind", KIND)
		m:SetAttribute("Team", team)
		m:SetAttribute("BlockA", blk.a)
		m:SetAttribute("BlockB", blk.b)
		m:SetAttribute("Owner", player.UserId)
		blk.model = m
		byModel[m] = blk
		m.Parent = f
		apply(blk, false)
	end
	return nil
end

-- the block a structure model is (src/server/Build routes swings here), or nil
function Trenches.blockOf(model: Instance): Block?
	return if model:IsA("Model") then byModel[model] else nil
end

-- how far `p` is from a block's line (flat)
function Trenches.distance(blk: Block, p: Vector3): number
	return Survey.toSegment(p, blk.a, blk.b)
end

-- One swing at a square (src/server/Build checked the soldier, the shovel, the reach and the rate): Build adds HP to your
-- team's square; Destroy takes it off any team's (an undug plan's square is pulled up).
function Trenches.work(blk: Block, team: string, mode: string)
	if not live(blk) then
		return
	end
	local H = T.hp
	if mode == "Build" then
		if team ~= blk.team or blk.hp >= H.max then
			return
		end
		blk.hp = Rules.trenchSwing(blk.hp, H.max, H.swing, true)
		blk.worked = os.clock()
		for _, o in blk.run do
			o.worked = blk.worked -- (the plan stays while it's being dug)
		end
		if blk.hp >= H.max then
			blk.falling = false
		end
		apply(blk, true)
		return
	end
	if blk.hp <= 0 then
		finish(blk, false) -- a plan pulled up
		return
	end
	local left, gone = Rules.trenchSwing(blk.hp, H.max, H.swing, false)
	blk.hp = left
	blk.worked = os.clock()
	blk.falling = true
	clods(blk, T.clods.perSwing)
	if gone then
		finish(blk, true)
		return
	end
	apply(blk, true) -- (it falls in a little every swing)
end

-- A blast at `position` (src/server/Build.blast): `kpaAt(studs)` its overpressure. Every dug square loses HP by the
-- overpressure at its line (Rules.trenchBlast): it falls in by that much.
function Trenches.blast(position: Vector3, kpaAt: (number) -> number, _reachOf: (number) -> number)
	local K, H = T.blast, T.hp
	local hit = {}
	for _, blk in blocks do
		if live(blk) and blk.hp > 0 then
			local d = Rules.trenchBlastDistance(Survey.toSegment(position, blk.a, blk.b), T)
			local loss = Rules.trenchBlast(kpaAt(d), H.max, K.from, K.full)
			if loss > 0 then
				blk.hp = math.max(blk.hp - loss, 0)
				blk.falling = true
				table.insert(hit, blk)
			end
		end
	end
	for _, blk in hit do
		clods(blk, T.clods.perSwing)
		if blk.hp <= 0 then
			finish(blk, true)
		else
			apply(blk, true)
		end
	end
end

-- Removes every trench and scar, the ground put back (dev: the admin panel's undo)
function Trenches.clear()
	local list = {}
	for _, blk in blocks do
		table.insert(list, blk)
	end
	for _, blk in list do
		if blk.model then
			byModel[blk.model] = nil
			blk.model:Destroy()
		end
		blocks[blk.id] = nil
	end
	for _, blk in list do
		reshapeBlock(blk)
	end
end

function Trenches.start()
	-- plans nobody digs go after Trench.planLife
	task.spawn(function()
		while true do
			task.wait(10)
			local now = os.clock()
			local stale = {}
			for _, blk in blocks do
				if live(blk) and blk.hp <= 0 and not blk.falling and now - blk.worked > T.planLife then
					table.insert(stale, blk)
				end
			end
			for _, blk in stale do
				if live(blk) then
					finish(blk, false)
				end
			end
		end
	end)
end

return Trenches
