--!strict
-- Trenches v2 on the server (Config/Build.Trench, Rules/Build).
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
-- - Destroy swings (any team's trench), blasts and bullets (Trenches.blast / Trenches.shot, from src/server/Build, by
--   Config/Build.Structures) take HP off: it is buried (filled in with mud, no clods thrown); at 0 it is a scar, a
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
	across: Vector3, -- flat unit, to the block's right
	length: number,
	hp: number, -- its depth: hp / Trench.hp.max of the full depth
	falling: boolean, -- lost HP since it was last full
	built: boolean, -- dug full once: from then on it is buried by the HP it loses (Rules.trenchDepth)
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
	return if blk.scar then 0 else Rules.trenchDepth(blk.hp, blk.built, T.hp)
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
								cut, churned = want, false -- (filled in as mud, the colour of its pieces)
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

-- a square still to be dug (user 2026-10-24: "make the entire planning thing better and more stylish"): a stake at
-- each corner of its outline (its top edges), its top
-- painted, with cord round it sagging a little between the stake tops (Beams). No flags (user 2026-10-24: "i dont
-- think we need a flag. lets just do the stakes")
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
	local stakes: { BasePart } = {}
	for _, c in { { 0, -TOP }, { blk.length, -TOP }, { blk.length, TOP }, { 0, TOP } } do
		local g = at(blk, c[1], c[2])
		local hit = workspace:Raycast(g + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), terrainOnly)
		local base = if hit then hit.Position else g
		local stake = part(
			holder,
			"Peg",
			Vector3.new(M.peg[1], M.peg[2], M.peg[1]),
			CFrame.new(base + Vector3.new(0, M.peg[2] / 2 - 0.15, 0)),
			rgb(Palette.Build.Picket),
			false
		)
		part(
			holder,
			"PegTop",
			Vector3.new(M.peg[1] + 0.03, M.top, M.peg[1] + 0.03),
			-- (its top a little under the stake's, so the two faces don't fight: user 2026-10-25 "make sure that the white
			-- clearly goes under or below the top of the stick")
			CFrame.new(base + Vector3.new(0, M.peg[2] - 0.15 - M.top / 2 - 0.05, 0)),
			rgb(Palette.Build.PegTop),
			false
		)
		table.insert(stakes, stake)
	end
	-- a cord's end, tied on the side of the stake it leaves from, just under the painted top (not through the stake,
	-- user 2026-10-25: "some clipping issues with the wire and stick"): its axis down, so each Beam's curve sags
	-- (CurveSize0 down from one end, CurveSize1 from the other)
	local function tie(stake: BasePart, toward: BasePart): Attachment
		local flat = Vector3.new(toward.Position.X - stake.Position.X, 0, toward.Position.Z - stake.Position.Z)
		local side = if flat.Magnitude > 1e-3 then flat.Unit * (M.peg[1] / 2 + M.string / 2) else Vector3.zero
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(side.X, M.peg[2] / 2 - M.top - 0.08, side.Z)
		a.Axis, a.SecondaryAxis = Vector3.new(0, -1, 0), Vector3.new(1, 0, 0)
		a.Parent = stake
		return a
	end
	for i = 1, 4 do
		local s0, s1 = stakes[i], stakes[i % 4 + 1]
		local a0, a1 = tie(s0, s1), tie(s1, s0)
		local sag = M.sag * (a1.WorldPosition - a0.WorldPosition).Magnitude
		local cord = Instance.new("Beam")
		cord.Name = "String"
		cord.Attachment0, cord.Attachment1 = a0, a1
		cord.Width0, cord.Width1 = M.string, M.string
		cord.CurveSize0, cord.CurveSize1 = sag, -sag
		cord.Segments = 8
		cord.FaceCamera = true
		cord.Color = ColorSequence.new(rgb(Palette.Build.String))
		cord.Transparency = NumberSequence.new(0)
		cord.LightInfluence = 1
		cord.Parent = holder
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
		warn("[Trenches] trench_pieces is not in the asset library: run the Library sync in the dev place")
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

-- the dirt in the terrain's mud colour, each piece shaded off it (user 2026-10-24: "make the trench match the color of
-- the mud"); planks their own wood
local function pieceColor(name: string): Color3
	local B = Palette.Build
	local i = tonumber(string.match(name, "^Wall(%d+)"))
	if string.find(name, "PlanksDark") then
		return rgb(B.PlankDark)
	elseif string.find(name, "Planks") then
		return rgb(B.Plank)
	end
	local shade
	if i then
		local tone = (i - 1) % #B.TrenchWall + 1
		shade = if string.find(name, "Parapet") or string.find(name, "Apron")
			then B.TrenchParapet[tone]
			elseif string.find(name, "Chunks") then B.TrenchWallChunks[tone]
			else B.TrenchWall[tone]
	else
		shade = if string.find(name, "Chunks") then B.TrenchFloorChunks else B.TrenchFloor
	end
	local mud = workspace.Terrain:GetMaterialColor(Enum.Material.Mud)
	return Color3.new(math.min(mud.R * shade, 1), math.min(mud.G * shade, 1), math.min(mud.B * shade, 1))
end

-- The dirt pieces' library model and each mesh's place from its Origin (piece space: x along, y up, z out of the hole),
-- and a piece's colour, for other dug holes (src/server/Artillery's gun pits)
function Trenches.pieceKit(): (Model?, { [string]: CFrame })
	return pieceKit(), offsets
end
function Trenches.pieceColor(name: string): Color3
	return pieceColor(name)
end

-- Where a side wall or dirt heap of `blk` can stand (`sign` 1 toward its `across`, -1 away): each stretch along it (u0,
-- u1: studs from end A, running on up to `ext` { A, B } past each end) where none of its `probes` is in another dug
-- trench; a probe { off, keep } is the point `off` out from the centre line, kept further than `keep` from the other's
-- line. A wall keeps its foot out of the other's floor and its top edge out of the other's hole, so where trenches join
-- it stops at the other trench's wall line and stands in neither the opening nor the other trench (user 2026-10-24:
-- "make sure that the joints connect by the walls"); `gap0`, `gap1`: how much further its foot could have run on there
-- (a corner piece fills it). Only stretches on the square itself count.
local SPAN_STEP = 0.5
local RUN = TOP - T.floor -- how far a wall leans back from its foot to its top edge
local HEAP_BACK = TOP + T.joins.heapReach -- how far out the back of a dirt heap reaches
local WALL_PROBES = { { T.floor + 0.5, T.floor + 0.25 }, { TOP - 0.3, TOP - 0.5 } }
local HEAP_PROBES = { { TOP + 0.4, TOP + 0.3 }, { TOP + 4.5, TOP + 0.3 }, { HEAP_BACK, TOP + 0.3 } }
type Span = { u0: number, u1: number, gap0: number, gap1: number }
local function sideSpans(blk: Block, sign: number, probes: { { number } }, ext: { number }): { Span }
	local from, to = -ext[1], blk.length + ext[2]
	local n = math.max(math.ceil((to - from) / SPAN_STEP), 1)
	local function uAt(i: number): number
		return from + (to - from) * (i - 1) / n
	end
	local blocked, footBlocked = {}, {}
	for i = 1, n + 1 do
		for k, probe in probes do
			local p = at(blk, uAt(i), sign * probe[1])
			local inside = false
			for _, o in blocks do
				if o ~= blk and live(o) and o.hp > 0 then
					local rel = Vector3.new(p.X - o.a.X, 0, p.Z - o.a.Z)
					local u, v = rel:Dot(o.dir), rel:Dot(o.across)
					if u > -0.25 and u < o.length + 0.25 and math.abs(v) < probe[2] then
						inside = true
						break
					end
				end
			end
			if inside then
				blocked[i] = true
				if k == 1 then
					footBlocked[i] = true
				end
			end
		end
		blocked[i] = blocked[i] or false
		footBlocked[i] = footBlocked[i] or false
	end
	local function gap(i: number, step: number): number
		local j = i
		while footBlocked[j + step] == false and blocked[j + step] do
			j += step
		end
		return math.abs(j - i) * (to - from) / n
	end
	local out = {}
	for _, r in Rules.freeRuns(blocked) do
		local u0, u1 = uAt(r[1]), uAt(r[2])
		if u1 - u0 >= 1.5 and u1 > 0.5 and u0 < blk.length - 0.5 then
			table.insert(out, { u0 = u0, u1 = u1, gap0 = gap(r[1], -1), gap1 = gap(r[2], 1) })
		end
	end
	return out
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
	-- how far the side pieces run on past an end: round the outside of a bend to meet the next square's (on the inside
	-- the other's hole cuts them back), round a dead end to meet the wall across it
	local function runOn(link: Link?, dead: boolean, leave: Vector3, heap: boolean): number
		if dead then
			return if heap then RUN + T.joins.deadEndHeap else RUN
		elseif not link or link.kind ~= "end" then
			return 0
		end
		local o = link.other
		local out = if link.which == "A" then -o.dir else o.dir
		local t = math.tan(math.rad(Rules.bend(out.X, out.Z, leave.X, leave.Z)) / 2)
		return if heap then HEAP_BACK * math.min(t, 1) else TOP * math.min(t, 1.5)
	end
	-- an end toward a square still to be dug (dug out of order) stays open: no wall across, nothing run on into it; the
	-- walls join when that square is dug (user 2026-10-24: "whenever i build not in order, it forms walls")
	local function pending(link: Link?): boolean
		return link ~= nil and live(link.other) and link.other.hp <= 0
	end
	local closeA = shape.deadA and not pending(blk.linkA)
	local closeB = shape.deadB and not pending(blk.linkB)
	local wallExt = {
		if shape.deadA and not closeA then 0 else runOn(blk.linkA, closeA, blk.dir, false),
		if shape.deadB and not closeB then 0 else runOn(blk.linkB, closeB, -blk.dir, false),
	}
	local heapExt = {
		if shape.deadA and not closeA then 0 else runOn(blk.linkA, closeA, blk.dir, true),
		if shape.deadB and not closeB then 0 else runOn(blk.linkB, closeB, -blk.dir, true),
	}
	-- each side's walls and dirt heaps, along the stretches clear of other trenches (the heap stands well back, so it
	-- keeps clear of their holes and walls all the way back, not just their floors)
	local walls, heaps = {}, {}
	local sig = `{closeA}{closeB}`
	for side, sign in { 1, -1 } do
		walls[side] = sideSpans(blk, sign, WALL_PROBES, wallExt)
		heaps[side] = sideSpans(blk, sign, HEAP_PROBES, heapExt)
		for _, list in { walls[side], heaps[side] } do
			for _, s in list do
				sig ..= `|{s.u0},{s.u1},{s.gap0},{s.gap1}`
			end
			sig ..= ";"
		end
	end
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
	local flat = blk.dir
	-- a frame with piece z out of the trench along `out` (flat) and x the way that keeps it right-handed with y up: a
	-- side wall or the floor runs along the square (tilted with its ground line) from whichever end that x starts at, a
	-- dead end's wall across the floor from its edge. Studio round 6: y came out upside down with x picked by hand.
	local function frame(out: Vector3, ending: boolean, onLine: boolean?, u0: number?, u1: number?): CFrame
		local x = Vector3.new(0, 1, 0):Cross(out)
		local origin
		if ending then
			origin = floorAt(if out:Dot(flat) < 0 then 0 else blk.length, 0) - x * (u0 or T.floor)
		else
			local fromStart = x:Dot(flat) > 0
			x = if fromStart then along else -along
			local u = if fromStart then u0 or 0 else u1 or blk.length
			origin = floorAt(u, if onLine then 0 else out:Dot(blk.across) * T.floor)
		end
		return CFrame.fromMatrix(origin, x, out:Cross(x).Unit, out)
	end
	local function place(name: string, cf: CFrame, stretch: number, tone: string?)
		local src = k:FindFirstChild(name)
		local off = offsets[name]
		if not (src and src:IsA("BasePart") and off) then
			return
		end
		local p = src:Clone()
		p.Size = Vector3.new(src.Size.X * stretch, src.Size.Y, src.Size.Z)
		p.CFrame = cf * CFrame.new(off.Position.X * stretch, off.Position.Y, off.Position.Z) * off.Rotation
		p.Color = pieceColor(tone or name)
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
	-- a long stretch (run on round a sharp bend) laid as several pieces about a segment long, not one stretched far
	local function pieceRuns(u0: number, u1: number): { { number } }
		local count = math.max(math.round((u1 - u0) / (P.segment * 1.25)), 1)
		local runs = {}
		for c = 0, count - 1 do
			table.insert(runs, { u0 + (u1 - u0) * c / count, u0 + (u1 - u0) * (c + 1) / count })
		end
		return runs
	end
	-- side walls (side 1 toward `across`, 2 away from it) along their clear stretches, a corner piece where one stops
	-- short of another trench (on the wall's slope, from where its top stops down to where its foot could have gone),
	-- the heaps along theirs, the floor on the centre line turned either way
	for side, sign in { 1, -1 } do
		local n = roll.walls[side]
		local out = blk.across * sign
		for _, s in walls[side] do
			for _, c in pieceRuns(s.u0, s.u1) do
				wall(n, frame(out, false, false, c[1], c[2]), (c[2] - c[1]) / P.segment)
			end
			for _, e in { { s.u0, s.gap0 }, { s.u1, s.gap1 } } do
				if e[2] > 0.3 then
					place("Corner", frame(out, false, false, e[1], e[1]), (e[2] + 0.5) / RUN, `Wall{n}`)
				end
			end
		end
		for _, s in heaps[side] do
			for _, c in pieceRuns(s.u0, s.u1) do
				local cf = frame(out, false, false, c[1], c[2])
				place(`Wall{n}Parapet`, cf, (c[2] - c[1]) / P.segment)
				place(`Wall{n}Apron`, cf, (c[2] - c[1]) / P.segment) -- (the skirt of dirt behind it)
			end
		end
	end
	local floorCf = frame(if roll.flip then blk.across else -blk.across, false, true)
	place(`Floor{roll.floor}`, floorCf, stretch)
	place(`Floor{roll.floor}Chunks`, floorCf, stretch)
	-- dead ends: a plain wall across, as wide as the trench at the top (its foot runs on behind the side walls) and its
	-- heap (a thick pile of dirt behind its top edge that collides: Config/Build.Trench) wider still, over the side
	-- heaps' ends
	for e, dead in { closeA, closeB } do
		if dead then
			local out = if e == 1 then -flat else flat
			wall(roll.ends[e], frame(out, true, false, TOP), 2 * TOP / P.segment)
			for _, start in { TOP + T.joins.deadEndHeap, 0 } do -- in two, so its slabs aren't stretched long
				local cf = frame(out, true, false, start)
				place(`Wall{roll.ends[e]}Parapet`, cf, (TOP + T.joins.deadEndHeap) / P.segment)
				place(`Wall{roll.ends[e]}Apron`, cf, (TOP + T.joins.deadEndHeap) / P.segment)
			end
		end
	end
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
	-- the dirt pieces lie in a square once it has been dug full, buried by the fill as it loses HP; well buried it is just
	-- earth, its pieces gone
	local full = blk.built and blk.hp >= T.hp.max * T.hp.bare / 100
	if full then
		pieces(blk)
	else
		local old = m:FindFirstChild("Pieces")
		if old then
			old:Destroy()
		end
	end
	-- the built squares round it: their dead-end walls go once it is dug into, their side walls step back from its hole
	-- (user 2026-10-24: "when you build the next segment it doesnt take down the original wall")
	local mid = (blk.a + blk.b) / 2
	for _, o in blocks do
		if o ~= blk and o.model and o.model:FindFirstChild("Pieces") then
			local reach = (blk.length + o.length) / 2 + 2 * TOP
			if Vector3.new(mid.X - (o.a.X + o.b.X) / 2, 0, mid.Z - (o.a.Z + o.b.Z) / 2).Magnitude <= reach then
				pieces(o)
			end
		end
	end
	publish(blk)
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
local function snap(p: Vector3, _team: string): (Vector3, Link?)
	local best: Block?, bestWhich: string?, bestD = nil, nil, T.joinReach
	for _, blk in blocks do
		if live(blk) then
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
		if live(blk) then
			local rel = Vector3.new(p.X - blk.a.X, 0, p.Z - blk.a.Z)
			local u, v = rel:Dot(blk.dir), rel:Dot(blk.across)
			if u >= 0 and u <= blk.length and math.abs(v) <= TOP then
				-- at its floor's edge on that side: a branch only opens that wall and runs out from it (user 2026-10-24:
				-- "when extending from sides, you dont add anything within the existing trench")
				return at(blk, u, if v >= 0 then T.floor else -T.floor), { kind = "tee", other = blk }
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
	local function away(p: Vector3): number
		return Vector3.new(root.Position.X - p.X, 0, root.Position.Z - p.Z).Magnitude
	end
	if math.min(away(a0), away(b0)) > T.firstReach + 4 then
		return `Too far: stand within {T.firstReach} studs of either end`
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
	-- not alongside another trench, except where it joins one
	local segs = {}
	for _, blk in blocks do
		if live(blk) then
			table.insert(segs, { blk.a.X, blk.a.Z, blk.b.X, blk.b.Z })
		end
	end
	if Rules.tooClose(a.X, a.Z, b.X, b.Z, linkA ~= nil, linkB ~= nil, segs, T.spacing) then
		return "Too close to another trench: extend it instead"
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
			built = false,
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

-- One swing at a square (src/server/Build checked the soldier, the shovel, the reach and the rate): Build adds HP to any
-- square, Destroy takes it off (an undug plan's square is pulled up). (Any trench: a soldier's kit is rolled each life,
-- so after a respawn your own trench was another kit's; user 2026-10-25: "you should be able to fix/edit any trench")
function Trenches.work(blk: Block, _team: string, mode: string)
	if not live(blk) then
		return
	end
	local H = T.hp
	if mode == "Build" then
		if blk.hp >= H.max then
			return
		end
		blk.hp = Rules.trenchSwing(blk.hp, H.max, H.swing, true)
		blk.worked = os.clock()
		for _, o in blk.run do
			o.worked = blk.worked -- (the plan stays while it's being dug)
		end
		if blk.hp >= H.max then
			blk.falling = false
			blk.built = true
		end
		apply(blk, true)
		return
	end
	if blk.hp <= 0 then
		finish(blk, false) -- a plan pulled up
		return
	end
	local left, gone = Rules.trenchSwing(blk.hp, H.max, H.destroy, false)
	blk.hp = left
	blk.worked = os.clock()
	blk.falling = true
	if gone then
		finish(blk, true)
		return
	end
	apply(blk, true) -- (it falls in a little every swing)
end

-- A square loses `amount` HP to a blast or a bullet (Config/Build.Structures): buried by that much (reshaped only when
-- its depth changes: a bullet's chip doesn't), filled in to a scar at 0
local function harm(blk: Block, amount: number)
	if amount <= 0 or not live(blk) or blk.hp <= 0 then
		return
	end
	local before = shareOf(blk)
	blk.hp = math.max(blk.hp - amount, 0)
	blk.falling = true
	if blk.hp <= 0 then
		finish(blk, true)
	else
		apply(blk, math.abs(shareOf(blk) - before) > 0.005)
	end
end

-- A blast at `position` (src/server/Build.blast) of `src` (a Config/Build.Structures entry): every dug square takes its
-- share by how far the blast is from its ground (its hole, walls and banks: 0 on or in them)
function Trenches.blast(position: Vector3, src: any)
	local S = C.Structures
	local hit = {}
	for _, blk in blocks do
		if live(blk) and blk.hp > 0 then
			local d = math.max(Survey.toSegment(position, blk.a, blk.b) - TOP - T.bank.width, 0)
			local share = Rules.structureHit(d, src, S.edge)
			if share > 0 then
				table.insert(hit, { blk = blk, amount = T.hp.max * share / 100 })
			end
		end
	end
	for _, h in hit do
		harm(h.blk, h.amount)
	end
end

-- A bullet meeting `part` at `point`: a dug square loses Structures.bullet when it is one of its pieces, or the ground
-- in its hole, walls or banks (Rules.inTrenchGround; the nearest square's: the carved terrain round a slab is what a
-- shot at a wall often meets, Studio round t1024-1602-59df); whether it was one
function Trenches.shot(struck: Instance, point: Vector3?): boolean
	local m = struck:FindFirstAncestorWhichIsA("Model")
	while m and not byModel[m] do
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	local blk = m and byModel[m]
	if not blk and struck == workspace.Terrain and point then
		local best = math.huge
		for _, o in blocks do
			if live(o) and o.hp > 0 then
				local d = Survey.toSegment(point, o.a, o.b)
				local u = math.clamp((point - o.a):Dot(o.dir), 0, o.length)
				if d < best and Rules.inTrenchGround(d, point.Y - at(o, u, 0).Y, T, T.shotSlack) then
					blk, best = o, d
				end
			end
		end
	end
	if not blk then
		return false
	end
	harm(blk, T.hp.max * C.Structures.bullet.hit / 100)
	return true
end

-- whether `p` is within `extra` of a trench's ground (its hole, walls, banks and the dirt heaped and spread past them,
-- out to its skirt; flat): blasts' craters stop short of it (src/server/Ground; user 2026-10-24: "craters stop at the
-- trench"; 2026-10-25 out to the skirt, so a crater doesn't cut under it)
function Trenches.near(p: Vector3, extra: number): boolean
	local outer = math.max(TOP + T.bank.width, HEAP_BACK)
	for _, blk in blocks do
		if live(blk) and blk.hp > 0 and Survey.toSegment(p, blk.a, blk.b) <= outer + extra then
			return true
		end
	end
	return false
end

-- whether a trench ever touched voxel `key` ("x,y,z" in voxel units)
function Trenches.dug(key: string): boolean
	return original[key] ~= nil
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
