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
--   determined by hp"): Build swings add HP (Trenches.work, from src/server/Build). Its pieces (Config/Assets
--   trench_pieces v12: chunky earth slabs with plank steps; the earth heaped behind them is the terrain's bank) show its stage
--   (Rules.trenchStage): while it is dug, none (its markers stay and the terrain is cut a little deeper each swing);
--   dug full, a wall each side and a floor rolled from its seed (Rules.trenchPieces), a wall across a dead end, none
--   where another trench tees in; damaged, destruction stages (boards working loose, then slabs and boards down, earth
--   and boards slumped on the floor) while the terrain fills back in over them.
-- - Destroy swings (any team's trench), blasts and bullets (Trenches.blast / Trenches.shot, from src/server/Build, by
--   Config/Build.Structures) take HP off: it is buried (filled in with mud, no clods thrown); at 0 it is a scar, a
--   lumpy dip of churned earth that stays.
-- - Each square lies tilted with the ground across it (Rules.crossTilt; user 2026-11-02: "make the terrain match the
--   angle of the slope, not make it flat"): its hole, walls and pieces turned whole by the slope from one wall top to
--   the other (Rules.tiltedCut), refused over Trench.maxCross.
-- - Dugouts (src/server/Build, Config/Build.Dugout) are cut into a square's wall (Trenches.pocket) in the same
--   reshape: their tunnel under the wall from the doorway down to the room, and the room, hollowed out under the ground
--   (the earth they have filled with left in); the walls of every square give way over the doorway, their banks run
--   on over it.
-- The terrain is reshaped from the ground as it was before any trench touched it (kept per voxel), so digging,
-- joining, falling in and scars are all the one union of every square's profile over that ground.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local C = require(Shared.Config.Build)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Build)
local Survey = require(Shared.BuildSurvey)
local DevWorld = require(script.Parent.DevWorld)
local Net = require(Shared.Net)
local Hitches = require(Shared.Hitches)

local Trenches = {}

local T = C.Trench
local D = C.Dugout
local VOXEL = 4
local TOP = Rules.trenchTop(T)
local RUN = TOP - T.floor -- how far a wall leans back from its foot to its top edge
-- the terrain is cut a little deeper and wider than the pieces lie (Config/Build.Trench.carve), so its 4-stud voxels
-- stay behind the boards and under the floor instead of poking through them
local CARVE = table.clone(T)
CARVE.floor = T.floor + T.carve.wider
CARVE.depth = T.depth + T.carve.deeper
local RIM = math.max(T.bank.width, T.grassClear) -- how far past its wall tops a square changes the ground
local KIND = "TrenchBlock"
-- the meshes of a wall (its smooth slab, its earth slabs, plank steps in two tones) and of a floor (its slab, its slabs);
-- all but the planks collide (user 2026-11-02: "some units are able to go inside it to hide")
local WALL_PARTS = { "", "Chunks", "Planks", "PlanksDark" }
local FLOOR_PARTS = { "", "Chunks" }

type Link = { kind: string, other: Block, which: string? } -- "end" (with `which` end of `other`) or "tee"

export type Block = {
	id: number,
	team: string,
	a: Vector3, -- end A on the ground (its height is the ground line's there)
	b: Vector3,
	dir: Vector3, -- flat unit, A to B
	across: Vector3, -- flat unit, to the block's right
	length: number,
	-- the ground's rise per stud across it, to `across` (Rules.crossTilt): its hole, walls and pieces turned with it
	tilt: number,
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
	soil: Enum.Material?, -- the terrain it is dug into (soilOf)
}

local blocks: { [number]: Block } = {}
-- dugouts' pockets (Trenches.pocket), by their dugout's model: its frame (on the trench floor at the foot of the wall,
-- level, looking out into the trench: +Z back into the wall), its square, its room's size (width, height, depth) and
-- how high it has filled with earth over its room's floor
type Pocket = { frame: CFrame, blk: Block, room: Vector3, fill: number }
local pockets: { [Instance]: Pocket } = {}
local byModel: { [Model]: Block } = {}
local nextId = 0
-- the ground before any trench: per voxel (voxelKey), { occupancy, material }
local original: { [number]: { o: number, m: Enum.Material } } = {}
-- a voxel's key in `original` from its place in voxel units (a number: a string each voxel cost a reshape about a ms)
local function voxelKey(x: number, y: number, z: number): number
	return ((x + 32768) * 65536 + y + 32768) * 65536 + z + 32768
end

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

-- the footprint of every piece laid (its Frame and Size: src/server/Build), a bridge's too unless `noBridges`
local function footprints(noBridges: boolean?): { Rules.Footprint }
	local out: { Rules.Footprint } = {}
	for _, m in folder():GetChildren() do
		local frame, size = m:GetAttribute("Frame"), m:GetAttribute("Size")
		local piece = Rules.piece(m:GetAttribute("Piece"), C.Pieces)
		if
			typeof(frame) == "CFrame"
			and typeof(size) == "Vector3"
			and not (noBridges and piece and piece.kind == "Bridge")
		then
			table.insert(out, {
				x = frame.Position.X,
				z = frame.Position.Z,
				rx = frame.RightVector.X,
				rz = frame.RightVector.Z,
				width = size.X,
				depth = size.Z,
			})
		end
	end
	return out
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

-- a block's point `u` along, `v` across, on its ground (flat parts from end A; its line tilted across by its tilt)
local function at(blk: Block, u: number, v: number): Vector3
	local y = blk.a.Y + (blk.b.Y - blk.a.Y) * math.clamp(u / blk.length, 0, 1) + v * blk.tilt
	return Vector3.new(blk.a.X, y, blk.a.Z) + blk.dir * u + blk.across * v
end

-- a block's way out to `across` and its up, both turned by its tilt (its cross-section's own frame)
local function tilted(blk: Block): (Vector3, Vector3)
	local c = 1 / math.sqrt(1 + blk.tilt * blk.tilt)
	local s = blk.tilt * c
	return blk.across * c + Vector3.yAxis * s, Vector3.yAxis * c - blk.across * s
end

local function live(blk: Block?): boolean
	return blk ~= nil and blocks[blk.id] == blk and not blk.scar
end

-- how deep a square is cut now: its HP's share of the full depth
local function shareOf(blk: Block): number
	return if blk.scar then 0 else Rules.trenchDepth(blk.hp, blk.built, T.hp)
end

-- the soil a square is dug into: the terrain's material a few voxels down from the middle of its ground line, as it
-- was before any trench, the grass skipped (Rules.trenchSoil)
local function soilOf(blk: Block): Enum.Material
	if blk.soil then
		return blk.soil
	end
	local mid = (blk.a + blk.b) / 2
	local ix, iz = math.floor(mid.X / VOXEL), math.floor(mid.Z / VOXEL)
	local names = {}
	for k = 1, 3 do
		local iy = math.floor(mid.Y / VOXEL) - k
		local o = original[voxelKey(ix, iy, iz)]
		local m = o and o.m
		if not m then
			local corner = Vector3.new(ix, iy, iz) * VOXEL
			local ok, mats = pcall(
				workspace.Terrain.ReadVoxels,
				workspace.Terrain,
				Region3.new(corner, corner + Vector3.one * VOXEL),
				VOXEL
			)
			m = if ok then mats[1][1][1] else nil
		end
		if m then
			table.insert(names, m.Name)
		end
	end
	local soil = (Enum.Material :: any)[Rules.trenchSoil(names, T.soil)] :: Enum.Material
	blk.soil = soil
	return soil
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
	m:SetAttribute("HP", Rules.trenchShownHP(blk.hp, T.hp.max))
	m:SetAttribute("MaxHP", T.hp.max)
	m:SetAttribute("Falling", blk.falling)
	local function linkName(l: Link?): string
		return if l and live(l.other) then l.kind else ""
	end
	m:SetAttribute("LinkA", linkName(blk.linkA))
	m:SetAttribute("LinkB", linkName(blk.linkB))
end

-- a reshape still to do (Trenches.start does a few columns a step: Trench.reshape): the region round `centre`
-- (within `reach`, flat), how many voxel columns across it and how many are done
type Reshape = { centre: Vector3, reach: number, region: Region3, columns: number, done: number }
local reshapes: { Reshape } = {}
-- the squares whose pieces are due again, once the reshapes are done (they stand on the ground: sitsOnGround)
local due: { Block } = {}

-- Reshapes the terrain of `job` from its voxel column `i0` to `i1` across: back to the ground before any trench where
-- one touched it, then cut by every square there (the deepest cut wins), banks thrown up where nothing cuts, scars as
-- shallow dips.
local function reshapeColumns(job: Reshape, i0: number, i1: number)
	local terrain = workspace.Terrain
	local centre, reach = job.centre, job.reach
	local whole = job.region.CFrame.Position - job.region.Size / 2
	local from = whole + Vector3.new((i0 - 1) * VOXEL, 0, 0)
	local region = Region3.new(from, whole + Vector3.new(i1 * VOXEL, job.region.Size.Y, job.region.Size.Z))
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
		if flat <= reach + blk.length / 2 + TOP + RIM then
			table.insert(near, { blk = blk, shape = shapeOf(blk), share = shareOf(blk) })
		end
	end
	for ix = 1, size.X do
		for iz = 1, size.Z do
			local x, z = corner.X + (ix - 0.5) * VOXEL, corner.Z + (iz - 0.5) * VOXEL
			local column = table.create(size.Y, 0)
			for iy = 1, size.Y do
				local o = original[voxelKey(gx + ix - 1, gy + iy - 1, gz + iz - 1)]
				if o then
					occs[ix][iy][iz] = o.o
					mats[ix][iy][iz] = o.m
				end
				column[iy] = occs[ix][iy][iz]
			end
			local top = Rules.columnTop(column, corner.Y, VOXEL)
			local cut: number? = nil
			local bank: number? = nil
			local soil: Enum.Material? = nil -- (the cut's, else the bank's or the bare rim's)
			for _, n in near do
				local blk: Block = n.blk
				local rel = Vector3.new(x - blk.a.X, 0, z - blk.a.Z)
				local u, v = rel:Dot(blk.dir), rel:Dot(blk.across)
				-- (a tilted square's profile is turned whole: its reach across in its own frame and the cut there, over
				-- the line's ground at the centre)
				local w, lift = v, 0
				if blk.tilt ~= 0 and not blk.scar then
					w, lift = Rules.tiltedCut(v, blk.tilt, function(off: number): number
						local rx = Rules.trenchReach(u, off, n.shape, T.floor)
						return if rx then Rules.trenchProfile(rx, n.share, CARVE) or 0 else 0
					end)
				end
				local r = Rules.trenchReach(u, w, n.shape, T.floor)
				if r then
					local line = blk.a.Y + (blk.b.Y - blk.a.Y) * math.clamp(u / blk.length, 0, 1)
					if blk.scar then
						if r <= TOP then
							local want = line + v * blk.tilt - T.scar.depth * (1 - r / TOP)
							if not cut or want < cut then
								cut, soil = want, soilOf(blk)
							end
						end
					else
						local h = Rules.trenchProfile(r, n.share, CARVE)
						if h and h < 0 then
							local want = line + (if blk.tilt ~= 0 then lift else h)
							if not cut or want < cut then
								cut, soil = want, soilOf(blk) -- (filled in with its soil, the colour of its pieces)
							end
						elseif h and h > 0 and top then
							bank = math.max(bank or -math.huge, top + h)
						end
						if not cut and n.share > 0 and r <= TOP + RIM then
							soil = soil or soilOf(blk)
						end
					end
				end
			end
			-- a dugout: its tunnel (under its steps, up to its roof: Rules.dugoutRoof) and its room hollowed out under
			-- the ground, the earth it has filled with left in (the voxels whose middles lie in `hollow`;
			-- Config/Build.Dugout cut, cutTop, slotCut)
			-- (`hollow`: the band's bottom, its top, the earth it has filled with up to (a voxel across that line part
			-- full, so the earth rises smoothly), and that earth's soil)
			local hollow: { any }? = nil
			local function open(lo: number, hi: number, earth: number, pk: Pocket)
				if hollow then
					hollow[1], hollow[2] = math.min(hollow[1], lo), math.max(hollow[2], hi)
					if earth > hollow[3] then
						hollow[3], hollow[4] = earth, soilOf(pk.blk)
					end
				else
					hollow = { lo, hi, earth, soilOf(pk.blk) }
				end
			end
			for _, pk in pockets do
				local l = pk.frame:PointToObjectSpace(Vector3.new(x, pk.frame.Position.Y, z))
				local y0 = pk.frame.Position.Y
				local floor = y0 - D.drop
				local earth = if pk.fill > 0 then floor + pk.fill else -math.huge
				if math.abs(l.X) <= D.slot / 2 + D.slotCut and l.Z >= -D.slotCut and l.Z <= D.stair then
					local under = y0 - D.drop * math.clamp((l.Z + VOXEL / 2) / D.stair, 0, 1) - D.cut
					local roof = y0 + Rules.dugoutRoof(l.Z, D, pk.room.Y, RUN, T.depth) + D.cutTop
					open(under, roof, earth, pk)
				end
				local back = D.stair + pk.room.Z + D.cut
				if math.abs(l.X) <= pk.room.X / 2 + D.cut and l.Z >= D.stair - D.cut and l.Z <= back then
					open(floor - D.cut, floor + pk.room.Y + D.cutTop, earth, pk)
				end
			end
			if cut or bank or soil or hollow then
				for iy = 1, size.Y do
					local key = voxelKey(gx + ix - 1, gy + iy - 1, gz + iz - 1)
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
						mats[ix][iy][iz] = soil :: Enum.Material
					end
				end
			elseif soil then
				-- the bank thrown up and the bare rim round it: soil, no grass
				local out = if bank then Rules.shapeColumn(column, corner.Y, VOXEL, bank, false) else column
				for iy = 1, size.Y do
					if out[iy] > occs[ix][iy][iz] then
						occs[ix][iy][iz] = out[iy]
					end
					if occs[ix][iy][iz] > 0 then
						local m = mats[ix][iy][iz]
						if out[iy] > column[iy] or m == Enum.Material.Grass or m == Enum.Material.LeafyGrass then
							mats[ix][iy][iz] = soil
						end
					end
				end
			end
			if hollow then
				for iy = 1, size.Y do
					local y = corner.Y + (iy - 0.5) * VOXEL
					if y >= hollow[1] and y <= hollow[2] then
						-- (smooth terrain draws a part-full voxel's surface about half a voxel higher than its share)
						local o = math.clamp((hollow[3] - y) / VOXEL, 0, 1)
						occs[ix][iy][iz] = o
						mats[ix][iy][iz] = if o > 0 then hollow[4] else Enum.Material.Air
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, VOXEL, mats, occs)
end

-- the terrain round `centre` (within `reach`, flat) to be reshaped (one already waiting there starts again)
local function reshape(centre: Vector3, reach: number)
	for _, job in reshapes do
		if job.centre == centre and job.reach == reach then
			job.done = 0
			return
		end
	end
	local half = Vector3.new(reach, T.depth + T.bank.height + VOXEL * 4, reach)
	local region = Region3.new(centre - half, centre + half):ExpandToGrid(VOXEL)
	local columns = math.round(region.Size.X / VOXEL)
	table.insert(reshapes, { centre = centre, reach = reach, region = region, columns = columns, done = 0 })
end

-- the next few columns of the oldest reshape; false when there is none
local function reshapeStep(): boolean
	local job = reshapes[1]
	if not job then
		return false
	end
	local t0 = os.clock()
	local i1 = math.min(job.done + T.reshape.columns, job.columns)
	reshapeColumns(job, job.done + 1, i1)
	job.done = i1
	if i1 >= job.columns then
		table.remove(reshapes, 1)
		DevWorld.touchRegion(job.region) -- (put back at the next match: src/server/DevWorld)
		Net.event("GroundDug"):FireAllClients(job.centre, job.reach, true) -- (the grass follows the ground)
	end
	Hitches.since("Trench reshape", t0)
	return true
end

local function reshapeBlock(blk: Block)
	local mid = (blk.a + blk.b) / 2
	reshape(mid, blk.length / 2 + TOP + RIM + VOXEL)
end

-- a square still to be dug (user 2026-10-24: "make the entire planning thing better and more stylish"): a stake at
-- each corner of its outline (its top edges), its top
-- painted, with cord round it sagging a little between the stake tops (Beams). No flags (user 2026-10-24: "i dont
-- think we need a flag. lets just do the stakes"). A stake a piece stands over is left out, and its cords with it
-- (user 2026-11-02: "remove the stakes on the points if things get built over or under it").
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
	local stakes: { [number]: BasePart } = {}
	local under = footprints()
	for i, c in { { 0, -TOP }, { blk.length, -TOP }, { blk.length, TOP }, { 0, TOP } } do
		local g = at(blk, c[1], c[2])
		local covered = false
		for _, fp in under do
			if Rules.onFootprintAt(g.X, g.Z, fp, M.peg[1] / 2) then
				covered = true
				break
			end
		end
		if covered then
			continue
		end
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
		stakes[i] = stake
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
		if not s0 or not s1 then
			continue
		end
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

-- every square still pegged out near `blk` (its own too) staked again on the ground as the reshape left it: the bank
-- thrown up as a square is dug buried its stakes, the cut left them hanging (user 2026-11-03: "keep the planning
-- strings around unbuilt trenches there until its built so people know where trenches are being built")
local function restakeNear(blk: Block)
	local mid = (blk.a + blk.b) / 2
	for _, o in blocks do
		local m = o.model
		if live(o) and m and m:FindFirstChild("Markers") then
			local omid = (o.a + o.b) / 2
			local reach = (blk.length + o.length) / 2 + 2 * (TOP + RIM + VOXEL)
			if Vector3.new(mid.X - omid.X, 0, mid.Z - omid.Z).Magnitude <= reach then
				markers(o)
			end
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

-- the dirt in its soil's colour (Mud for a gun pit), each piece shaded off it (user 2026-10-24: "make the trench match
-- the color of the mud"; 2026-11-01: "match the color of the terrain underneath (not the grass)"); planks their own wood
local function pieceColor(name: string, soil: Enum.Material?): Color3
	local B = Palette.Build
	if string.find(name, "PlanksDark") then
		return rgb(B.PlankDark)
	elseif string.find(name, "Planks") then
		return rgb(B.Plank)
	end
	local i = tonumber(string.match(name, "^Wall(%d+)"))
	local tone = ((i or 1) - 1) % #B.TrenchWall + 1
	local shade
	if string.find(name, "Parapet") or string.find(name, "Apron") or string.find(name, "Fall") then
		shade = B.TrenchParapet[tone]
	elseif string.find(name, "^Floor") then
		shade = if string.find(name, "Chunks") then B.TrenchFloorChunks else B.TrenchFloor
	else
		shade = if string.find(name, "Chunks") then B.TrenchWallChunks[tone] else B.TrenchWall[tone]
	end
	local base = workspace.Terrain:GetMaterialColor(soil or Enum.Material.Mud)
	return Color3.new(math.min(base.R * shade, 1), math.min(base.G * shade, 1), math.min(base.B * shade, 1))
end

-- The dirt pieces' library model and each mesh's place from its Origin (piece space: x along, y up, z out of the hole),
-- and a piece's colour, for other dug holes (src/server/Artillery's gun pits)
function Trenches.pieceKit(): (Model?, { [string]: CFrame })
	return pieceKit(), offsets
end
function Trenches.pieceColor(name: string): Color3
	return pieceColor(name)
end

-- Where a side wall of `blk` can stand (`sign` 1 toward its `across`, -1 away): each stretch along it (u0,
-- u1: studs from end A, running on up to `ext` { A, B } past each end) where none of its `probes` is in another dug
-- trench; a probe { off, keep } is the point `off` out from the centre line, kept further than `keep` from the other's
-- line. A wall keeps its foot out of the other's floor and its top edge out of the other's hole, so where trenches join
-- it stops at the other trench's wall line and stands in neither the opening nor the other trench (user 2026-10-24:
-- "make sure that the joints connect by the walls"); `gap0`, `gap1`: how much further its foot could have run on there
-- (a corner piece fills it). Only stretches on the square itself count.
local SPAN_STEP = 0.5
local HEAP_BACK = TOP + T.joins.heapReach -- how far out the back of a dirt heap reaches
local WALL_PROBES = { { T.floor + 0.5, T.floor + 0.25 }, { TOP - 0.3, TOP - 0.5 } }
type Span = { u0: number, u1: number, gap0: number, gap1: number }
local function sideSpans(blk: Block, sign: number, probes: { { number } }, ext: { number }, wall: boolean): { Span }
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
			-- a dugout's doorway: no wall over it (its own pieces are the wall's face there; the bank runs on over it)
			for _, pk in pockets do
				local l = pk.frame:PointToObjectSpace(p)
				if
					wall
					and math.abs(l.X) <= D.slot / 2 + D.openFront
					and l.Z >= -D.openFront
					and l.Z <= D.stair + D.openFront
				then
					inside = true
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
local function piecesNow(blk: Block)
	local m = blk.model :: Model
	local k = pieceKit()
	if not k then
		return
	end
	local shape = shapeOf(blk)
	-- how far the side pieces run on past an end: round the outside of a bend to meet the next square's (on the inside
	-- the other's hole cuts them back), round a dead end to meet the wall across it
	local function runOn(link: Link?, dead: boolean, leave: Vector3): number
		if dead then
			return RUN
		elseif not link or link.kind ~= "end" then
			return 0
		end
		local o = link.other
		local out = if link.which == "A" then -o.dir else o.dir
		local t = math.tan(math.rad(Rules.bend(out.X, out.Z, leave.X, leave.Z)) / 2)
		return TOP * math.min(t, 1.5)
	end
	-- an end toward a square still to be dug (dug out of order) stays open: no wall across, nothing run on into it; the
	-- walls join when that square is dug (user 2026-10-24: "whenever i build not in order, it forms walls")
	local function pending(link: Link?): boolean
		return link ~= nil and live(link.other) and link.other.hp <= 0
	end
	local closeA = shape.deadA and not pending(blk.linkA)
	local closeB = shape.deadB and not pending(blk.linkB)
	local wallExt = {
		if shape.deadA and not closeA then 0 else runOn(blk.linkA, closeA, blk.dir),
		if shape.deadB and not closeB then 0 else runOn(blk.linkB, closeB, -blk.dir),
	}
	-- each side's walls, along the stretches clear of other trenches; the dirt heaped behind them is the terrain's own
	-- bank (Rules.trenchProfile, Config/Build.Trench.bank: user 2026-11-03, "make the trench pile blended into the
	-- terrain so it doesnt look like bricks still"), sinking with the fill
	local walls = {}
	-- buried by what it lost: the pieces stay where they were laid and the terrain fills back in over them (user
	-- 2026-11-02: "i also liked the old design where trenches slowly filled with terrain"; a floor riding up on the fill
	-- lay over it as loose slabs)
	local stage, stageN = Rules.trenchStage(blk.hp, blk.built, T.hp, T.stages)
	local soil = soilOf(blk)
	local sig = `{stage}{stageN}{closeA}{closeB}`
	for side, sign in { 1, -1 } do
		walls[side] = sideSpans(blk, sign, WALL_PROBES, wallExt, true)
		for _, s in walls[side] do
			sig ..= `|{s.u0},{s.u1},{s.gap0},{s.gap1}`
		end
		sig ..= ";"
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
	-- (all in the square's cross-section turned by its tilt: `v` across and the depth down in that frame)
	local outT, upT = tilted(blk)
	local function floorAt(u: number, v: number): Vector3
		return at(blk, u, 0) + outT * v - upT * T.depth
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
			local side = x:Dot(blk.across)
			origin = floorAt(if out:Dot(flat) < 0 then 0 else blk.length, -side * (u0 or T.floor))
			x = outT * side -- (across the end, tilted with the square)
		else
			local fromStart = x:Dot(flat) > 0
			x = if fromStart then along else -along
			local u = if fromStart then u0 or 0 else u1 or blk.length
			origin = floorAt(u, if onLine then 0 else out:Dot(blk.across) * T.floor)
			out = outT * out:Dot(blk.across) -- (out of a side, tilted with the square)
		end
		local y = out:Cross(x).Unit
		return CFrame.fromMatrix(origin, x, y, x:Cross(y).Unit)
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
		p.Color = pieceColor(tone or name, soil)
		local base = not string.find(name, "Planks")
		p.Anchored = true
		p.CanCollide = base
		p.CanQuery = base
		p.CanTouch = false
		p.Parent = holder
	end
	-- the stage's pieces (Config/Assets trench_pieces v12, tools/blender/trench/trench_wood.py): finished, wall
	-- variant `n`'s; damaged, destruction stage Hit<k>'s
	local wallName = function(n: number): string
		return if stage == "Hit" then `Hit{stageN}Wall` else `Wall{n}`
	end
	local function wall(n: number, cf: CFrame, stretch: number)
		for _, suffix in WALL_PARTS do
			place(`{wallName(n)}{suffix}`, cf, stretch, `Wall{n}{suffix}`)
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
	-- the floor on the centre line turned either way
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
	end
	local floorCf = frame(if roll.flip then blk.across else -blk.across, false, true)
	for _, suffix in FLOOR_PARTS do
		place(`Floor{roll.floor}{suffix}`, floorCf, stretch)
	end
	-- the earth and boards fallen off a damaged square's wall onto its floor, against one side (by its seed)
	local side = if roll.flip then 1 else -1
	local sideCf = frame(blk.across * side, false, false, 0, blk.length)
	if stage == "Hit" then
		for _, suffix in { "", "Planks", "PlanksDark" } do
			place(`Hit{stageN}Fall{suffix}`, sideCf, stretch, `Fall{suffix}`)
		end
	end
	-- dead ends: a plain wall across, as wide as the trench at the top (its foot runs on behind the side walls)
	for e, dead in { closeA, closeB } do
		if dead then
			local out = if e == 1 then -flat else flat
			wall(roll.ends[e], frame(out, true, false, TOP), 2 * TOP / P.segment)
		end
	end
end
local function pieces(blk: Block)
	local t0 = os.clock()
	piecesNow(blk)
	Hitches.since("Trench pieces", t0)
end

-- a square's pieces as it stands: once dug full (none while it is dug: its markers and the cut alone), buried by the
-- fill and worn through the destruction stages as it loses HP, to the end (0 HP fills it in: finish)
local function fit(blk: Block)
	local m = blk.model
	if not m then
		return
	end
	if blk.built then
		pieces(blk)
	else
		local old = m:FindFirstChild("Pieces")
		if old then
			old:Destroy()
		end
	end
end

-- a square's pieces due again (Trenches.start: after the reshapes waiting)
local function refit(blk: Block)
	if not table.find(due, blk) then
		table.insert(due, blk)
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
local function applyNow(blk: Block, reshapeIt: boolean)
	if reshapeIt then
		reshapeBlock(blk)
		restakeNear(blk)
	end
	local m = blk.model
	if not m then
		return
	end
	-- (staked out until it is first dug full, through any hit it takes while it is dug: a shot used to pull them up)
	local markersOn = not blk.built
	local pegs = m:FindFirstChild("Markers")
	if markersOn and not pegs then
		markers(blk)
	elseif not markersOn and pegs then
		pegs:Destroy()
	end
	-- its pieces (due once the ground is reshaped: Trenches.start)
	refit(blk)
	-- the built squares round it: their dead-end walls go once it is dug into, their side walls step back from its hole
	-- (user 2026-10-24: "when you build the next segment it doesnt take down the original wall")
	local mid = (blk.a + blk.b) / 2
	for _, o in blocks do
		if o ~= blk and o.model and o.model:FindFirstChild("Pieces") then
			local reach = (blk.length + o.length) / 2 + 2 * TOP
			if Vector3.new(mid.X - (o.a.X + o.b.X) / 2, 0, mid.Z - (o.a.Z + o.b.Z) / 2).Magnitude <= reach then
				refit(o)
			end
		end
	end
	publish(blk)
end
local function apply(blk: Block, reshapeIt: boolean)
	local t0 = os.clock()
	applyNow(blk, reshapeIt)
	Hitches.since("Trench square", t0)
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
	restakeNear(blk)
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
			return at(blk, u, v).Y, false
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

-- Lays a plan (Net "Build" "Plan", or a bot's Build.planAs): its start and end (ground points), `owner` the UserId or
-- BotId that laid it. Returns the reason when refused.
function Trenches.plan(owner: number, team: string, root: BasePart, a0: Vector3, b0: Vector3): string?
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
	if Rules.tooClose(a.X, a.Z, b.X, b.Z, linkA ~= nil, linkB ~= nil, segs, T.spacing, TOP) then
		return "Too close to another trench: extend it instead"
	end
	-- the ground along it: no water, not too steep along, nothing standing in the way
	local samples = math.max(math.ceil(length / 3), 1)
	local heights, line = {}, {}
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
		line[i + 1] = h
	end
	if Rules.runSlope(line, length / samples, T.slopeSpan) > T.maxSlope then
		return "Too steep"
	end
	-- each square's tilt across, from the ground at its wall tops either side (Rules.crossTilt)
	local across = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X)
	local tilts = {}
	local lows, highs = {}, {} -- (each square's lowest and highest ground: its line and wall tops)
	for i, span in spans do
		local left, right = {}, {}
		for _, f in { 0.2, 0.5, 0.8 } do
			local p = a + flat.Unit * (span.from + (span.to - span.from) * f)
			for _, side in { -1, 1 } do
				local q = p + across * side * TOP
				local h, wet = groundAt(q.X, q.Z, a.Y)
				if not h or wet then
					return if wet then "Not in water" else "Needs open ground"
				end
				table.insert(if side < 0 then left else right, h)
			end
		end
		local tilt = Rules.crossTilt(left, right, TOP, T.maxCross)
		if not tilt then
			return "Too steep"
		end
		tilts[i] = tilt
		local lo, hi = math.huge, -math.huge
		for _, h in left do
			lo, hi = math.min(lo, h), math.max(hi, h)
		end
		for _, h in right do
			lo, hi = math.min(lo, h), math.max(hi, h)
		end
		for j = math.floor(span.from / length * samples), math.ceil(span.to / length * samples) do
			local h = heights[math.clamp(j, 0, samples)]
			lo, hi = math.min(lo, h), math.max(hi, h)
		end
		lows[i], highs[i] = lo, hi
	end
	-- nor by a tree: none whose trunk would stand in its cut, on its walls or on its heaps (Trench.treeClear)
	if Survey.treeNear(a, b) then
		return "A tree is in the way"
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace.Terrain, folder() }
	-- nothing solid over any square's whole width out to its heaps' edge, from its lowest ground to Trench.wayHeight
	-- over its highest, the end squares on past their dead ends by the end heap (Trench.wayHeight)
	local half = TOP + T.joins.heapReach
	local past = TOP + T.joins.deadEndHeap
	for i, span in spans do
		local from = span.from - (if i == 1 then past else 0)
		local to = span.to + (if i == #spans then past else 0)
		local c = a + dir * ((from + to) / 2)
		local y = (lows[i] + highs[i] + T.wayHeight) / 2
		local box = CFrame.lookAt(Vector3.new(c.X, y, c.Z), Vector3.new(c.X + dir.X, y, c.Z + dir.Z))
		local size = Vector3.new(2 * half, highs[i] - lows[i] + T.wayHeight, to - from)
		for _, p in workspace:GetPartBoundsInBox(box, size, params) do
			local model = p:FindFirstAncestorWhichIsA("Model")
			if p.CanCollide and not (model and model:FindFirstChildOfClass("Humanoid")) then
				return "In the way"
			end
		end
	end
	-- nor near a foxhole, wire or gun: as far off as they keep from a trench (Rules.trenchKeep)
	local near = Survey.nearPieces(a, b, folder())
	if near then
		return `Too close to the {string.lower(near)}`
	end
	-- nor under a piece: no structure's footprint over its open cut (Config/Build.Trench.overhang; the same rule as a
	-- piece over a trench, Survey.overTrench), except a bridge, which lies across the trench it joins
	local cut = Rules.trenchCut(a.X, a.Z, b.X, b.Z, TOP - T.overhang)
	for _, theirs in footprints(true) do
		if Rules.footprintsOverlap(cut, theirs) then
			return "A structure is in the way"
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
			tilt = tilts[i],
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
		m:SetAttribute("Tilt", blk.tilt)
		m:SetAttribute("Owner", owner)
		blk.model = m
		byModel[m] = blk
		m.Parent = f
		apply(blk, false)
	end
	return nil
end

-- A piece was laid (src/server/Build, its Frame and Size set): the stakes of every square still pegged out near it are
-- set again, without those it stands over
function Trenches.restake(piece: Model)
	local frame, size = piece:GetAttribute("Frame"), piece:GetAttribute("Size")
	if typeof(frame) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return
	end
	for _, blk in blocks do
		local m = blk.model
		if live(blk) and m and m:FindFirstChild("Markers") then
			local mid = (blk.a + blk.b) / 2
			local flat = Vector3.new(mid.X - frame.Position.X, 0, mid.Z - frame.Position.Z)
			if flat.Magnitude <= blk.length / 2 + TOP + (size.X + size.Z) / 2 then
				markers(blk)
			end
		end
	end
end

-- the block a structure model is (src/server/Build routes swings here), or nil
function Trenches.blockOf(model: Instance): Block?
	return if model:IsA("Model") then byModel[model] else nil
end

-- every live square of `team` (nil: every team's): its model, team, middle, HP and whether it was dug full once
-- (src/server/Build.worksOf)
function Trenches.squares(team: string?): { { model: Model, team: string, at: Vector3, hp: number, built: boolean } }
	local out = {}
	for _, blk in blocks do
		if live(blk) and blk.model and (team == nil or blk.team == team) then
			table.insert(
				out,
				{ model = blk.model, team = blk.team, at = (blk.a + blk.b) / 2, hp = blk.hp, built = blk.built }
			)
		end
	end
	return out
end

-- how far `p` is from a block's line (flat)
function Trenches.distance(blk: Block, p: Vector3): number
	return Survey.toSegment(p, blk.a, blk.b)
end

-- One swing at a square (src/server/Build checked the soldier, the shovel, the reach and the rate): Build adds HP to any
-- square, Destroy takes it off (an undug plan's square is pulled up). (Any trench: a soldier's kit is rolled each life,
-- so after a respawn your own trench was another kit's; user 2026-10-25: "you should be able to fix/edit any trench")
-- `power`: what share of Trench.hp.swing or hp.destroy this soldier's swing does (Rules/Build.swingPower). True when
-- this swing dug the square to full for the first time (src/server/Loadouts pays the digger).
function Trenches.work(blk: Block, _team: string, mode: string, power: number, share: number?): (boolean, number)
	if not live(blk) then
		return false, 0
	end
	local H = T.hp
	if mode == "Build" then
		if blk.hp >= H.max then
			return false, 0
		end
		local first = not blk.built
		local before = blk.hp
		blk.hp = Rules.trenchSwing(blk.hp, H.max, Rules.digAmount(H.swing * power, H.max, share), true)
		blk.worked = os.clock()
		for _, o in blk.run do
			o.worked = blk.worked -- (the plan stays while it's being dug)
		end
		local done = false
		if blk.hp >= H.max then
			blk.falling = false
			done = first
			blk.built = true
		end
		apply(blk, true)
		return done, blk.hp - before
	end
	if blk.hp <= 0 then
		finish(blk, false) -- a plan pulled up
		return false, 0
	end
	local left, gone = Rules.trenchSwing(blk.hp, H.max, Rules.digAmount(H.destroy * power, H.max, share), false)
	blk.hp = left
	blk.worked = os.clock()
	blk.falling = true
	if gone then
		finish(blk, true)
		return false, 0
	end
	apply(blk, true) -- (it falls in a little every swing)
	return false, 0
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
				local v = (point - o.a):Dot(o.across)
				if d < best and Rules.inTrenchGround(d, point.Y - at(o, u, v).Y, T, T.shotSlack) then
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

-- A dugout (src/server/Build): `key` its model, cut into `square`'s wall at `frame` (on the trench floor at the foot of
-- the wall, looking out into the trench), its room `room` (width, height, depth) past its steps, filled with earth
-- `fill` studs over its room's floor (Rules.dugoutFillHeight); nil `frame` fills it back. Reshapes the ground there and
-- the walls of the squares round it.
function Trenches.pocket(key: Instance, square: Model?, frame: CFrame?, room: Vector3?, fill: number?)
	local old = pockets[key]
	local blk = square and byModel[square]
	if frame and room and blk then
		pockets[key] = { frame = frame, blk = blk, room = room, fill = fill or 0 }
	else
		pockets[key] = nil
	end
	local spot = if frame then frame.Position elseif old then old.frame.Position else nil
	if not spot or (not frame and not old) then
		return
	end
	local reach = D.stair + (if room then room.Z elseif old then old.room.Z else 0) + D.cut + VOXEL
	reshape(spot, reach)
	for _, o in blocks do
		local mid = (o.a + o.b) / 2
		if live(o) and o.model and o.model:FindFirstChild("Pieces") then
			if Vector3.new(mid.X - spot.X, 0, mid.Z - spot.Z).Magnitude <= reach + o.length / 2 then
				refit(o)
			end
		end
	end
end

-- a square's dirt colour for `name` (a trench piece's name: its shade) in the soil it is dug into, for the earth of
-- a dugout in it (src/server/Build)
function Trenches.soilColor(square: Model, name: string): Color3
	local blk = byModel[square]
	return pieceColor(name, if blk then soilOf(blk) else nil)
end

-- whether a trench ever touched voxel `key` ("x,y,z" in voxel units)
function Trenches.dug(key: string): boolean
	local x, y, z = string.match(key, "^(-?%d+),(-?%d+),(-?%d+)$")
	return x ~= nil and original[voxelKey(tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number)] ~= nil
end

-- Removes every trench and scar, the ground put back (dev: the admin panel's undo)
function Trenches.clear()
	local list = {}
	for _, blk in blocks do
		table.insert(list, blk)
	end
	table.clear(pockets)
	for _, blk in list do
		if blk.model then
			byModel[blk.model] = nil
			blk.model:Destroy()
		end
		blocks[blk.id] = nil
	end
	table.clear(due)
	for _, blk in list do
		reshapeBlock(blk)
	end
	local more = true
	while more do -- (all at once)
		more = reshapeStep()
	end
end

function Trenches.start()
	-- the reshapes waiting, for at most Trench.reshape.budget ms a frame; then the squares' pieces due, one a frame (a
	-- square's pieces made afresh are about a ms)
	RunService.Heartbeat:Connect(function()
		if not reshapes[1] and not due[1] then
			return
		end
		local t0 = os.clock()
		local stop = t0 + T.reshape.budget / 1000
		local worked = false
		while os.clock() < stop and reshapeStep() do
			worked = true
		end
		if not worked and due[1] then
			local blk = table.remove(due, 1) :: Block
			if live(blk) then
				fit(blk)
			end
		end
		Hitches.since("Trench frame", t0)
	end)
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
