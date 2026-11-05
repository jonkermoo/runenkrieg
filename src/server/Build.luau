--!strict
-- Player building on the server (phase 4.4; Config/Build, Rules/Build, shared/BuildSurvey). The client lays a
-- blueprint (Net "Build" "Place": the piece and where); the server surveys the ground, checks the rules and the caps,
-- and lays it in Workspace[Config/Build.Folder]. Trenches are planned and dug in src/server/Trenches (Net "Build"
-- "Plan": start and end).
-- Every structure is on HP 0..100 (user 2026-10-27: "all structures follow an HP strucutre, not how many digs"), its
-- "Work" attribute (and "HP" / "MaxHP" for the shovel's panel); laid at 0 with its first stage down at once, gone with
-- nothing left once a Destroy swing or a hit takes it to 0 (user: "remove the crumble. 0 hp should just disappear").
-- Every shovel swing (Net "Build" "Work", the target and the shovel's mode, user 2026-10-23):
-- - Build at your team's piece adds its swing's HP (Rules.hpSwing); it rises in stages and stands at full HP;
-- - Destroy at any piece, any team's, takes HP off; at 0 it is gone; at a tree it chops it (src/server/Trees).
-- - Sandbag piles: Config/Assets sandbag_pile's bags in one "Sandbag" section, on HP (Config/Build.Sandbags.hp): laid
--   at stage 1 (scraped ground, empty sacks), Build swings add HP, Destroy swings and weapons take it, its bags
--   standing by HP.
-- - Barbed wire: Config/Assets barbed_wire's meshes in two looks by HP (Rules.wireLook: on the ground, standing),
--   nothing queries them (bullets pass); src/server/Wire slows soldiers in it and hurts the enemy. On HP (Wire.hp).
-- - Hesco barriers (kind "Hesco"; Config/Build.Hesco): on HP (its work is its HP), laid with the empty perimeter
--   standing; the model's pieces for the stage its HP stands at (Rules.builtStage: the perimeter, then the dirt rising,
--   slumping as it wears), cloned from the asset library; only the dirt collides and stops bullets; gone at 0.
-- - Guns (Config/Build.Pieces kind "Gun"; Config/Build.Guns): a holder model in the folder (what swings go to) with the
--   gun's parts in it (src/server/Artillery.parts), laid out on the ground and fitted a quarter of its HP at a time
--   (Artillery.assemble, Config/Artillery.Assembly), a building site round them (Rules/Scaffold); a howitzer's pit
--   (Ground.pit from the ground as it was) deepens with each stage, the parts down on its floor. At full HP the real gun
--   stands (src/server/Artillery.place, in the team's paint) and its HP is the gun's own, mirrored on the holder; weapons
--   leave it a wreck at 0, a shovel's Destroy swing at 0 takes it away, its pit filled back.
-- - MG nests (kind "Nest"; Config/Build.Nest): the pile's bags on a ring (Rules.nestRing) and a round mount bag in one
--   "Sandbag" section, on HP in 4 stages like a Hesco barrier's: laid flat (empty sacks, the M2 in pieces on the
--   ground), the bags filled and the gun set up on the mount bag stage by stage (Artillery.parts / assemble,
--   Rules.nestShown); once it has stood its HP is its gun's, worn and fixed as a built field gun's.
-- - Foxholes (Config/Build.Foxhole): laid as a marked spot (a scraped patch, an unseen disc the shovel's light shows);
--   one Build swing carves the pit and its lip into the terrain in dark dirt (Ground.plot / shapeColumns,
--   Rules.foxholeHeight) and the piece is gone: from then on it is only ground, no HP, worn by nothing but what wears
--   the terrain. A Destroy swing at the spot takes the spot away.
-- - Bridges (Config/Build.Bridge): laid on a trench square (Survey.bridgeSpot), its planks the Config/Assets
--   bridge_pieces layout its seed rolls, stretched to the square's length; on HP (Bridge.hp): laid at stage 1, Build
--   swings add HP, Destroy swings and weapons take it, its boards standing by HP (Rules.bridgeStage). At 0, or once its
--   square is buried under Bridge.fall% (or gone), it is simply gone: no debris.
-- - Dugouts (kind "Dugout"; Config/Build.Dugout): steps cut down through a trench square's wall into a room under the
--   ground (Survey.dugoutSpot, Trenches.pocket), Config/Assets dugout_pieces' meshes shown by HP (Rules.dugoutShown:
--   built in 4 stages, then filling with earth from its room's floor up to its doorframe as it wears, anyone it reaches
--   lifted onto it), unseen plates to walk and bump on. Soldiers in the room of one that has stood are safe from blasts
--   outside it (Build.sheltered, src/server/Damage.blast). At 0, or when its trench square goes, it is gone, the wall
--   and ground as they were, anyone inside put out over the trench (or the ground, the trench gone).
-- Build.blast (from src/server/Damage.blast) and Build.shot (src/server/Firing): weapons wear down trenches, sandbags,
-- wire, bridges and dugouts by Config/Build.Structures.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local D = require(Shared.Config.Destruction)
local Palette = require(Shared.Config.Palette)
local Assets = require(Shared.Config.Assets)
local ShovelCfg = require(Shared.Config.Shovel)
local ArtilleryCfg = require(Shared.Config.Artillery)
local ArtilleryRules = require(Shared.Rules.Artillery)
local W = require(Shared.Config.Weapons)
local DevCfg = require(Shared.Config.DevTools)
local BotsCfg = require(Shared.Config.Bots)
local Rules = require(Shared.Rules.Build)
local FrontCfg = require(Shared.Config.Frontline)
local FrontRules = require(Shared.Rules.Frontline)
local Scaffold = require(Shared.Rules.Scaffold)
local Survey = require(Shared.BuildSurvey)
local SectorCfg = require(Shared.Config.Sectors)
local Map1 = require(Shared.LiveMap).map -- (the match's map)
local MapTerrain = require(Shared.Rules.MapTerrain)
local SectorRules = require(Shared.Rules.Sectors)
local Net = require(Shared.Net)
local Hitches = require(Shared.Hitches)
local Ground = require(script.Parent.Ground)
local Trees = require(script.Parent.Trees)
local Trenches = require(script.Parent.Trenches)
local Loadouts = require(script.Parent.Loadouts)

local Build = {}

-- the shortest time between two shovel strikes (a swing comes too soon under SwingSlack of it)
local GAP = Rules.strikeGap({ ShovelCfg.Dig, ShovelCfg.Chip })

-- an MG nest's (or a gun ring's) bag full and lying as its empty sack (Config/Build.Nest / GunRing `flat`)
type Sack = { full: CFrame, size: Vector3, color: Color3, flat: CFrame, flatSize: Vector3, cord: boolean, top: boolean }

type Rec = {
	model: Model,
	piece: Rules.Piece,
	team: string,
	owner: number,
	work: number,
	need: number,
	built: boolean, -- has stood once
	paid: boolean?, -- its builder has had the points for it (once per piece)
	born: number,
	worked: number,
	frame: CFrame,
	grassed: boolean?, -- barbed wire: the grass under it cleared
	base: CFrame?, -- a Hesco barrier: its footprint's centre on the lowest ground under it
	shown: number?, -- a Hesco barrier: the stage its pieces show
	stageParts: { [number]: { BasePart } }?, -- a Hesco barrier: every stage's pieces, laid out once
	-- a gun piece: where the gun stands (on the ground before its pit), its blueprint or the gun standing (once it has
	-- stood, `built`), its pit's ground as it was (Ground.pitBase) and the share of it dug now; an MG nest: its gun's
	-- place and parts
	at: CFrame?,
	parts: Model?,
	site: Model?, -- its scaffold and tools while it is built (Config/Build.Scaffold)
	gun: Model?,
	pitBase: Ground.PitBase?,
	dug: number?,
	laid: { number }?, -- a sandbag pile, wire or Hesco barrier: its ground's heights when laid (Build.blast's support)
	ground: CFrame?, -- an MG nest: the ground at the ring's middle (its building site stands on it)
	-- an MG nest: its ground as it was laid (put back once it is fixed whole) and the top of it in each column (a blast's
	-- earth heaps no higher than Config/Build.Nest.heap over it)
	nestBase: Ground.PitBase?,
	nestTops: { [string]: number }?,
	sacks: { [BasePart]: Sack }?, -- an MG nest (or a gun's sandbag ring): each bag full and as its empty sack
	square: Model?, -- a bridge: the trench square it is on (a dugout: the one it is cut into)
	pocketed: boolean?, -- a dugout: its tunnel and room cut in the ground (Trenches.pocket)
	filled: number?, -- and how high it has filled with earth over its room's floor (Rules.dugoutFillHeight)
	meshes: { [string]: BasePart }?, -- a dugout: its pieces by mesh name (Config/Assets dugout_pieces)
	plates: { BasePart }?, -- and its unseen plates (attribute "Stage")
	watch: { RBXScriptConnection }?, -- and its watch on that square
	sector: string?, -- the Map1 sector it stands in (a piece with a `sectorCap`)
	plot: Ground.Plot?, -- a foxhole's spot: the ground there as it lay
}

-- src/server/Artillery, handed in at start (it needs Damage, which needs this)
type Guns = {
	place: (string, Vector3, Vector3, { paint: string?, dug: boolean?, up: Vector3? }?) -> Model?,
	parts: (string, string?) -> Model?,
	assemble: (Model, string, CFrame, number, CFrame?) -> (),
	repair: (Model, number) -> (string?, number),
	setHp: (Model, number) -> (),
	harm: (Model, number) -> boolean,
}
local guns: Guns? = nil

local recs: { [Model]: Rec } = {}
local bridgeRoll = Random.new() -- (each bridge's board layout, Config/Build.Bridge.variants)
local showGun: (Rec) -> ()
local lastSwing: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any -- (by Builder.key)

local function rgb(c: { number }, jitter: number?): Color3
	local k = 1 + (jitter or 0)
	return Color3.fromRGB(math.clamp(c[1] * k, 0, 255), math.clamp(c[2] * k, 0, 255), math.clamp(c[3] * k, 0, 255))
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

local function teamOf(character: Model): string?
	local kit = character:GetAttribute("Kit")
	return if type(kit) == "string" then kit else nil
end

local function holdsShovel(character: Model): boolean
	local tool = character:FindFirstChildOfClass("Tool")
	local name = tool and tool:GetAttribute("Weapon")
	return type(name) == "string" and W[name] ~= nil and W[name].class == "Shovel"
end

-- a dev player's admin dig step (Config/DevTools.Admin.Dig, set by src/server/DevTools), nil for everyone else
local function digShare(player: Player): number?
	local share = player:GetAttribute(DevCfg.Admin.Dig.attribute)
	return if player:GetAttribute(DevCfg.Attribute) == true and type(share) == "number" then share else nil
end

-- a dev player with the admin panel's build anything on (Config/DevTools.Admin.BuildAllAttribute): any class builds
-- every piece
local function buildsAll(player: Player): boolean
	return player:GetAttribute(DevCfg.Attribute) == true and player:GetAttribute(DevCfg.Admin.BuildAllAttribute) == true
end

local function refuse(player: Player, reason: string)
	Net.event("Build"):FireClient(player, "Refused", reason)
end

local function newPart(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.CastShadow = true
	p.Parent = model
	return p
end

local function section(parent: Instance, name: string, kind: string, class: string, hp: number): Model
	local s = Instance.new("Model")
	s.Name = name
	s:SetAttribute("Kind", kind)
	s:SetAttribute("Class", class)
	s:SetAttribute("Story", 0)
	s:SetAttribute("MaxHP", hp)
	s:SetAttribute("HP", hp)
	s.Parent = parent
	CollectionService:AddTag(s, D.SectionTag)
	return s
end

-- the bags of a sandbag pile: the first `stage` stand, the rest unseen (no see-through finished pile over it, user round
-- 7: "remove ... the transparent overlay of what the final strucutre looks like"); stage 1's scraped ground always
-- shows, its empty sacks only while no bag stands
local function showSandbags(r: Rec, stage: number)
	for _, s in r.model:GetChildren() do
		for _, p in s:GetChildren() do
			if p:IsA("BasePart") then
				local look = p:GetAttribute("Look")
				if look == "Sacks" then
					p.Transparency = if stage == 0 then 0 else 1
				elseif look ~= "Ground" then
					local row = p:GetAttribute("Row") :: number
					local up = row <= stage
					p.Transparency = if up then 0 else 1
					p.CastShadow = up
					p.CanCollide = up
					p.CanQuery = up
				end
			end
		end
	end
end

-- A piece's library model (Config/Assets `key`, in ReplicatedStorage.Assets, kept by the Library sync: the barbed wire,
-- the sandbag pile, the bridge planks) and each mesh's place from its Origin (piece space: x along, y up from the ground, z across), found
-- once
local kits: { [string]: { model: Model, offsets: { [string]: CFrame } } } = {}
local function libraryKit(key: string): (Model?, { [string]: CFrame })
	local kit = kits[key]
	if kit then
		return kit.model, kit.offsets
	end
	local e = Assets.Entries[key]
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and f:FindFirstChild(e.category)
	for _, sub in string.split(e.folder, "/") do
		f = f and f:FindFirstChild(sub)
	end
	local m = f and f:FindFirstChild(key)
	local origin = m and m:FindFirstChild("Origin")
	if not (m and origin and origin:IsA("BasePart")) then
		warn("[Build] " .. key .. " is not in the asset library: run the Library sync in the dev place")
		return nil, {}
	end
	local offsets = {}
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d ~= origin then
			offsets[d.Name] = origin.CFrame:ToObjectSpace(d.CFrame)
		end
	end
	kits[key] = { model = m :: Model, offsets = offsets }
	return m :: Model, offsets
end

-- a sandbag pile (Config/Build.Pieces `bags`): its meshes from the library in one section, each bag's with the "Row" of
-- its bag (Rules.pileBag) so it stands by stage (showSandbags), stage 1's (`stage1`) with its "Look"; all of it laid on
-- `on`, the ground under it as it lies (Survey.onGround); false when the library has no pile
local function layoutPile(r: Rec, on: CFrame): boolean
	local p = r.piece
	local kit, offsets = libraryKit(p.asset)
	if not kit then
		return false
	end
	local base = on * CFrame.new(0, -C.Sandbags.sink, 0)
	local s = section(r.model, "Pile", "Sandbags", "Sandbag", C.Sandbags.hp.max)
	s:SetAttribute("HP", r.work)
	for _, d in kit:GetChildren() do
		local bag = Rules.pileBag(d.Name, p.bags)
		local offset = offsets[d.Name]
		if bag and offset and d:IsA("BasePart") then
			local part = d:Clone()
			part.Anchored = true
			part.Material = Enum.Material.SmoothPlastic
			local jitter = ((bag * 37) % 7 / 6 - 0.5) * 2 * C.Sandbags.shade
			part.Color = if Rules.isPileCord(d.Name)
				then rgb(Palette.Build.SandbagCord)
				else rgb(Palette.Build.Sandbag, jitter)
			part.CFrame = base * offset
			part:SetAttribute("Row", bag)
			part.Parent = s
		elseif offset and d:IsA("BasePart") and (d.Name == p.stage1.ground or d.Name == p.stage1.sacks) then
			-- stage 1: on the ground, blocking nothing (soldiers walk and bullets pass over it)
			local part = d:Clone()
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Material = Enum.Material.SmoothPlastic
			local isGround = d.Name == p.stage1.ground
			part.Color = rgb(if isGround then Palette.Build.SandbagPatch else Palette.Build.SandbagSacks)
			part.CFrame = on * offset -- (on the ground, not sunk with the bags)
			part:SetAttribute("Look", if isGround then "Ground" else "Sacks")
			part.Parent = s
		end
	end
	return true
end

-- a nest's (or a gun ring's) bag (or its cord) `d` laid at `cf` in `holder`, its `row` on the ring, and its empty sack
-- in `sacks`: flattened by `flat` along whichever of its axes stands up, on the ground `base` under it (a top bag's over
-- the sacks below)
local function layBag(
	holder: Instance,
	base: CFrame,
	flat: number,
	sacks: { [BasePart]: Sack },
	d: BasePart,
	cf: CFrame,
	row: number,
	top: boolean
)
	local part = d:Clone()
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	local jitter = ((row * 37) % 7 / 6 - 0.5) * 2 * C.Sandbags.shade
	local cord = Rules.isPileCord(d.Name)
	part.Color = if cord then rgb(Palette.Build.SandbagCord) else rgb(Palette.Build.Sandbag, jitter)
	part.CFrame = cf
	part:SetAttribute("Row", row)
	part.Parent = holder
	local up = base.UpVector
	local size = part.Size
	local ups = {
		math.abs(cf.RightVector:Dot(up)),
		math.abs(cf.UpVector:Dot(up)),
		math.abs(cf.LookVector:Dot(up)),
	}
	local axis = if ups[1] >= ups[2] and ups[1] >= ups[3] then 1 elseif ups[2] >= ups[3] then 2 else 3
	local height = if axis == 1 then size.X elseif axis == 2 then size.Y else size.Z
	local flatH, y = Rules.nestSack(height, flat, top)
	local flatSize = Vector3.new(
		if axis == 1 then flatH else size.X,
		if axis == 2 then flatH else size.Y,
		if axis == 3 then flatH else size.Z
	)
	local at = base:PointToObjectSpace(cf.Position)
	sacks[part] = {
		full = cf,
		size = size,
		color = part.Color,
		flat = CFrame.new(base:PointToWorldSpace(Vector3.new(at.X, y, at.Z))) * cf.Rotation,
		flatSize = flatSize,
		cord = cord,
		top = top,
	}
end

-- the ring's bags (Rules.nestRing on `n.ring`) from the pile `kit` (its parts' `offsets`, its `bags` by slot) laid by
-- `lay` round `base` (plan space: the ring's middle, x right, z back), each on its row (from `firstRow`)
local function layRing(
	n: any,
	bags: { string },
	kit: Instance,
	offsets: { [string]: CFrame },
	base: CFrame,
	firstRow: number,
	lay: (BasePart, CFrame, number, boolean) -> ()
)
	local ring = Rules.nestRing(n.ring)
	for i, b in ring do
		local o = offsets[bags[b.slot]]
		if o then
			local along = CFrame.fromMatrix(Vector3.new(b.x, 0, b.z), Vector3.new(b.dx, 0, b.dz), Vector3.yAxis)
			local bagCf = base * along * CFrame.new(0, o.Y, o.Z) * o.Rotation
			for _, d in kit:GetChildren() do
				local mo = offsets[d.Name]
				if mo and d:IsA("BasePart") and Rules.pileBag(d.Name, bags) == b.slot then
					lay(d, bagCf * o:Inverse() * mo, i + firstRow - 1, b.slot == 3)
				end
			end
		end
	end
end

-- a nest's (or a gun ring's) bags as `bags` says (Rules.nestShown): "none" all lying as their empty sacks, "bottom"
-- the bottom ones filled, "all", or worn: that share of the ring's bags still standing, the top bags gone first
-- (Rules.nestWearOrder; row 1, an MG nest's mount bags, always stands)
local function showBags(r: Rec, bags: string | number)
	local standing: { [number]: boolean }? = nil
	if type(bags) == "number" then
		local rows, tops = {}, {}
		for part, sack in r.sacks or {} do
			local row = part:GetAttribute("Row") :: number?
			if row and row > 1 and tops[row] == nil then
				tops[row] = sack.top
				table.insert(rows, row)
			end
		end
		table.sort(rows, function(a, b)
			return Rules.nestWearOrder(a, tops[a]) < Rules.nestWearOrder(b, tops[b])
		end)
		local set = {}
		local gone = #rows - Rules.nestStanding(#rows, bags)
		for i = gone + 1, #rows do
			set[rows[i]] = true
		end
		standing = set
	end
	for part, sack in r.sacks or {} do
		local row = part:GetAttribute("Row") :: number?
		local up = bags == "all"
			or (bags == "bottom" and not sack.top)
			or (standing ~= nil and (row == 1 or (row ~= nil and standing[row] == true)))
		part.CanCollide = up
		part.CanQuery = up
		part.Transparency = if sack.cord and not up then 1 else 0
		part.CFrame = if up then sack.full else sack.flat
		part.Size = if up then sack.size else sack.flatSize
		part.Color = if up or sack.cord then sack.color else rgb(Palette.Build.SandbagSacks)
	end
end

-- an MG nest (Config/Build.Nest): one "Sandbag" section of every bag, each with the "Row" it is laid in (the mount bag
-- first, then the ring's bags in Rules.nestRing's order), and the gun's parts (Artillery.parts) on the mount bag, set
-- up by quarters (showNest). The piece's frame is the ring's middle, its look the way the gun points; the bags lie on
-- `on`, the ground under it as it lies (Survey.onGround), the gun stands level. Stage 1, from when it is laid: the
-- pile's scraped ground under each pile and its empty sacks in the middle (`stage1`, "Look" like a pile's). False when
-- the library lacks the pile or the mount bag.
local function layoutNest(r: Rec, on: CFrame): boolean
	local p, n = r.piece, C.Nest
	local kit, offsets = libraryKit(p.asset)
	local bagKit, bagOffsets = libraryKit(p.mountBag)
	if not kit or not bagKit then
		return false
	end
	local base = on * CFrame.new(0, -C.Sandbags.sink, 0)
	local s = section(r.model, "Nest", "Nest", "Sandbag", n.hp.max)
	s:SetAttribute("HP", r.work)
	local function stage1(d: BasePart, cf: CFrame, look: string)
		local part = d:Clone()
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = rgb(if look == "Ground" then Palette.Build.SandbagPatch else Palette.Build.SandbagSacks)
		part.CFrame = cf
		part:SetAttribute("Look", look)
		part.Parent = s
	end
	local sacks: { [BasePart]: Sack } = {}
	r.sacks = sacks
	local function lay(d: BasePart, cf: CFrame, row: number, top: boolean)
		layBag(s, base, n.flat, sacks, d, cf, row, top)
	end
	local ring, radius = Rules.nestRing(n.ring)
	-- the mount bag (gun space: x right, y up, z back), in the point of the V
	local mount = base * CFrame.new(0, 0, -radius + n.mountBack)
	for _, d in bagKit:GetChildren() do
		local o = bagOffsets[d.Name]
		if o and d:IsA("BasePart") then
			lay(d, mount * o, 1, false)
		end
	end
	-- the ring's bags: the pile's bag of that slot (piece space: x along it), turned to lie along the ring
	layRing(n, p.bags, kit, offsets, base, 2, lay)
	-- stage 1: the scraped ground under each pile (along the line from its first bag to its second); the empty sacks
	-- are the bags themselves, flat (showNest)
	local ground = kit:FindFirstChild(p.stage1.ground)
	for i = 1, #ring - 1 do
		local a, b = ring[i], ring[i + 1]
		if ground and ground:IsA("BasePart") and a.slot == 1 and b.slot == 2 and a.pile == b.pile then
			local dx, dz = b.x - a.x, b.z - a.z
			local l = math.sqrt(dx * dx + dz * dz)
			local mid = Vector3.new((a.x + b.x) / 2, 0, (a.z + b.z) / 2)
			local cf = on * CFrame.fromMatrix(mid, Vector3.new(dx / l, 0, dz / l), Vector3.yAxis)
			stage1(ground, cf * offsets[ground.Name], "Ground")
		end
	end
	-- its ground as it is laid, once (user 2026-10-29: "once its fixed its cleared"; Build.nestCeiling)
	if not r.nestBase then
		local across = math.sqrt(p.width ^ 2 + p.depth ^ 2) / 2 + n.ground
		r.nestBase = Ground.snapshot(on.Position, across, n.snapshot[1], n.snapshot[2])
		r.nestTops = if r.nestBase then Ground.surface(r.nestBase) else nil
	end
	-- the gun, in parts, on the mount bag's top under its pivot, tilted with the nest (level unless it was laid on a
	-- slope, Config/Build.Slope), each set up in its quarter
	r.ground = on
	r.at = base * CFrame.new(0, n.bagTop, -radius + n.gunBack)
	if guns then
		r.parts = guns.parts(p.gun, C.Guns.paint[r.team])
		if r.parts then
			r.parts.Parent = r.model
		end
	end
	return true
end

-- a gun's building site (Config/Build.Scaffold, Rules/Scaffold) at gun space's origin; Build pivots it onto the floor
local function buildSite(spec: { [string]: any }): Model
	local model = Instance.new("Model")
	model.Name = "Site"
	local colors = Palette.Build.Scaffold :: { [string]: { number } }
	for _, piece in Scaffold.pieces(spec, C.Scaffold.Sizes) do
		local a = Vector3.new(piece.a[1], piece.a[2], piece.a[3])
		local b = Vector3.new(piece.b[1], piece.b[2], piece.b[3])
		local up = Vector3.new(piece.up[1], piece.up[2], piece.up[3])
		local mid = (a + b) / 2
		local p = newPart(
			model,
			piece.color,
			Vector3.new(piece.w, piece.h, (b - a).Magnitude),
			CFrame.lookAt(mid, b, up),
			rgb(colors[piece.color])
		)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
	model.WorldPivot = CFrame.new()
	return model
end

-- an MG nest as it stands (Rules.nestShown): being built, by its HP; once it has stood, by its gun's HP (Config/
-- Artillery.Wreck). Its filled bags up, the rest lying as their empty sacks (nothing blocks or is hit); its gun's parts
-- set up by quarters (Artillery.assemble), or the real gun standing; till then a building site in the ring (Config/
-- Build.Scaffold mg08, as the guns'; user 2026-10-28: "just have some signs of "construction" see the field cannon and
-- mortar stages"). Each change is the next stage at once (user 2026-10-28: "no animation").
local apply: (Rec) -> ()

local function showNest(r: Rec)
	local p = r.piece
	local wreck: number? = nil
	if r.built then
		local g = ArtilleryCfg.Guns[p.gun or ""]
		local hp = r.gun and r.gun:GetAttribute("HP")
		wreck = if g and type(hp) == "number" then ArtilleryRules.wreckStage(hp, g.hp, ArtilleryCfg.Wreck.at) else 0
	end
	local bags, quarters = Rules.nestShown(r.work, C.Nest, wreck)
	showBags(r, bags)
	if not guns or not r.at then
		return
	end
	local spec = C.Scaffold[p.gun or ""]
	local building = not r.built and quarters < C.Nest.quarters
	if building and spec and not r.site and r.ground then
		r.site = buildSite(spec)
		r.site:PivotTo(r.ground)
		r.site.Parent = r.model
	elseif not building and r.site then
		r.site:Destroy()
		r.site = nil
	end
	-- set up whole: the real gun stands there (src/server/Artillery: manned, laid and fired; its own HP, the nest's
	-- once it has stood); below that, in parts
	if quarters >= C.Nest.quarters then
		if r.gun then
			return
		end
		if r.parts then
			r.parts:Destroy()
			r.parts = nil
		end
		local gun =
			guns.place(p.gun, r.at.Position, r.at.LookVector, { paint = C.Guns.paint[r.team], up = r.at.UpVector })
		r.gun = gun
		if gun then
			gun:SetAttribute("Piece", p.key)
			-- its HP is the nest's: the shovel's panel and the bags show it
			gun:GetAttributeChangedSignal("HP"):Connect(function()
				if r.gun == gun then
					apply(r)
				end
			end)
			-- gone some other way (the dev tools' clear): stood again
			gun.Destroying:Connect(function()
				if r.gun == gun then
					r.gun = nil
				end
			end)
		end
		return
	end
	if r.gun then
		local gun = r.gun
		r.gun = nil
		gun:Destroy()
	end
	if not r.parts then
		r.parts = guns.parts(p.gun, C.Guns.paint[r.team])
		if r.parts then
			r.parts.Parent = r.model
		end
	end
	if r.parts then
		guns.assemble(r.parts, p.gun, r.at, quarters)
	end
end

-- which look (Rules.wireLook) a barbed_wire mesh belongs to: Bundle* on the ground, the rest standing; nil for the
-- Wreck* meshes, which no look uses since it is on HP alone
local function wireLookOf(name: string): string?
	return if string.sub(name, 1, 6) == "Bundle"
		then "Bundle"
		elseif string.sub(name, 1, 5) == "Wreck" then nil
		else "Standing"
end

-- (laid on `on`, the ground under it as it lies: Survey.onGround)
local function layoutWire(r: Rec, on: CFrame)
	local base = on
	local holder = Instance.new("Folder")
	holder.Name = "Wire"
	holder.Parent = r.model
	local kit, offsets = libraryKit("barbed_wire")
	if not kit then
		return
	end
	for _, d in kit:GetChildren() do
		local offset = offsets[d.Name]
		local look = wireLookOf(d.Name)
		if offset and look and d:IsA("BasePart") then
			local part = d:Clone()
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Material = Enum.Material.SmoothPlastic
			part.Color = rgb(if string.find(d.Name, "Pickets") then Palette.Build.Picket else Palette.Build.Wire)
			part.CFrame = base * offset
			part:SetAttribute("Look", look)
			part.Parent = holder
		end
	end
end

-- the wire's look by its HP (Rules.wireLook): bundled on the ground from the moment it is laid and while low, standing
-- from Wire.stand of its HP; it slows and hurts only standing ("Armed"). The grass goes from under it as it is laid.
local function showWire(r: Rec)
	local holder = r.model:FindFirstChild("Wire")
	if not holder then
		return
	end
	local look = Rules.wireLook(r.work, r.need, C.Wire, r.built)
	for _, p in holder:GetChildren() do
		if p:IsA("BasePart") then
			p.Transparency = if p:GetAttribute("Look") == look then 0 else 1
			p.CastShadow = p.Transparency == 0
		end
	end
	r.model:SetAttribute("Look", look)
	r.model:SetAttribute("Armed", look == "Standing")
	if not r.grassed then
		r.grassed = true
		Net.event("GroundDug"):FireAllClients(r.frame.Position, C.Wire.grass)
	end
end

-- a wire shakes and rattles (src/client/WireShake) from `at`: when it takes damage (Destroy swings, blasts; user
-- 2026-10-27: "both", as well as each tick it hurts someone, src/server/Wire)
local function shakeWire(r: Rec, at: Vector3)
	r.model:SetAttribute("RattleFrom", at)
	r.model:SetAttribute("ShakeAt", workspace:GetServerTimeNow())
end

-- The Hesco barrier's library model (ReplicatedStorage.Assets, kept by the Library sync) and where each mesh sits from
-- its Origin (piece space), found once
local hescoKit: Model? = nil
local hescoAt: { [string]: CFrame } = {}
local hescoWarned = false
local function hescoPieces(asset: string): Model?
	if hescoKit then
		return hescoKit
	end
	local e = Assets.Entries[asset]
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and e and f:FindFirstChild(e.category)
	for _, sub in string.split(if e then e.folder else "", "/") do
		f = f and f:FindFirstChild(sub)
	end
	local m = f and f:FindFirstChild(asset)
	local origin = m and m:FindFirstChild("Origin")
	if not (m and origin and origin:IsA("BasePart")) then
		if not hescoWarned then
			hescoWarned = true
			warn(`[Build] {asset} is not in the asset library: run the Library sync in the dev place`)
		end
		return nil
	end
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") then
			hescoAt[d.Name] = origin.CFrame:ToObjectSpace(d.CFrame)
		end
	end
	hescoKit = m :: Model
	return hescoKit
end

-- a Hesco barrier's pieces, every stage's laid out once (cloned from the asset library) in a holder per stage
-- ("Stage<s>"), all hidden: a change of stage only shows one and hides another (cloning a stage's meshes at each change
-- was slow to show, user round 5)
local function layHesco(r: Rec): boolean
	if r.stageParts then
		return true
	end
	local kit = hescoPieces(r.piece.asset)
	if not kit then
		return false
	end
	local base = r.base :: CFrame
	local out: { [number]: { BasePart } } = {}
	for s = 0, r.piece.stages do
		local holder = Instance.new("Model")
		holder.Name = "Stage" .. s
		out[s] = {}
		for name, off in hescoAt do
			local kind, n = string.match(name, "^(%a+)(%d)$")
			local src = kit:FindFirstChild(name)
			if kind and tonumber(n) == s and src and src:IsA("BasePart") then
				local part = src:Clone()
				part.Anchored = true
				part.Material = Enum.Material.SmoothPlastic
				part.Color = rgb(Palette.Build.Hesco[kind])
				part.CFrame = base * off
				part.CanTouch = false
				part:SetAttribute("Blocks", table.find(C.Hesco.blocks, kind) ~= nil)
				part.Transparency = 1
				part.CanCollide = false
				part.CanQuery = false
				part.CastShadow = false
				part.Parent = holder
				table.insert(out[s], part)
			end
		end
		holder.Parent = r.model
	end
	r.stageParts = out
	return true
end

-- shows or hides stage `s`'s pieces; only Config/Build.Hesco.blocks (the dirt) collide or are hit
local function showStage(r: Rec, s: number, on: boolean)
	for _, part in (r.stageParts :: any)[s] or {} do
		local blocks = on and part:GetAttribute("Blocks") == true
		part.Transparency = if on then 0 else 1
		part.CastShadow = on
		part.CanCollide = blocks
		part.CanQuery = blocks -- (bullets pass the mesh and liner)
	end
end

-- a Hesco barrier as its HP stands (its work: Config/Build.Hesco.hp): the stage it stands at shown, its HP on the
-- model for the shovel's panel, like a gun's
local function showHesco(r: Rec)
	r.model:SetAttribute("HP", math.ceil(r.work))
	r.model:SetAttribute("MaxHP", r.need)
	local stage = Rules.builtStage(r.work, r.need, r.piece.stages, r.built)
	if r.shown == stage or not layHesco(r) then
		return
	end
	if r.shown then
		showStage(r, r.shown, false)
	end
	showStage(r, stage, true)
	r.shown = stage
end

-- A bridge's planks (Config/Assets bridge_pieces): the layout its seed rolls (Rules.bridgeVariant), maybe turned round,
-- stretched along the trench to its square's `length`, and the unseen plate along the deck that you walk on
local function layoutBridge(r: Rec, length: number, seed: number)
	local kit, offsets = libraryKit("bridge_pieces")
	local p = r.piece
	local v, turned = Rules.bridgeVariant(seed, C.Bridge.variants)
	local cf = r.frame * (if turned then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
	local stretch = length / p.width
	for _, set in { "Frame", "Boards", "More" } do
		for _, tone in { "", "Dark" } do
			local name = `Bridge{v}{set}{tone}`
			local src = kit and kit:FindFirstChild(name)
			local off = offsets[name]
			if src and src:IsA("BasePart") and off then
				local part = src:Clone()
				part.Size = Vector3.new(src.Size.X * stretch, src.Size.Y, src.Size.Z)
				part.CFrame = cf * CFrame.new(off.Position.X * stretch, off.Position.Y, off.Position.Z) * off.Rotation
				part.Color = rgb(if tone == "Dark" then Palette.Build.BridgeDark else Palette.Build.Bridge)
				part.Anchored = true
				part.Material = Enum.Material.SmoothPlastic
				part.CanCollide = false
				part.CanQuery = false -- (bullets pass the planks)
				part.CanTouch = false
				part:SetAttribute("Set", set)
				part.Parent = r.model
			end
		end
	end
	local plate = newPart(
		r.model,
		"Walk",
		Vector3.new(length, C.Bridge.plate, p.depth),
		r.frame * CFrame.new(0, p.height - C.Bridge.plate / 2, 0),
		rgb(Palette.Build.Bridge)
	)
	plate.Transparency = 1
	plate.CastShadow = false
	plate.CanTouch = false
end

-- a bridge as its HP stands (its work; Rules.bridgeStage): the frame and stage 1's boards, then all of them; walkable
-- while it stands. Its HP on the model for the shovel's panel.
local function showBridge(r: Rec)
	r.model:SetAttribute("HP", math.ceil(r.work))
	r.model:SetAttribute("MaxHP", r.need)
	local stage = Rules.bridgeStage(r.work, r.need, r.paid == true)
	for _, part in r.model:GetChildren() do
		if part:IsA("BasePart") then
			if part.Name == "Walk" then
				part.CanCollide = stage >= 1
				part.CanQuery = stage >= 1
			else
				part.Transparency = if stage >= 2 or part:GetAttribute("Set") ~= "More" then 0 else 1
			end
		end
	end
end

-- A dugout's pieces (Config/Build.Dugout, Config/Assets dugout_pieces) laid in its frame (on the trench floor at the
-- foot of the wall, +Z back into it), all unseen until shown (showDugout); the meshes stop nothing, so unseen plates do:
-- the ramp down its steps and the tunnel's sides (stage 1 on), the room's floor, walls and ceiling (2 on); the earth
-- it fills with is the ground itself. False when the asset library lacks the pieces.
local function layoutDugout(r: Rec): boolean
	local G, p = C.Dugout, r.piece
	local kit, offsets = libraryKit(G.asset)
	if not kit then
		return false
	end
	local soil = if r.square then Trenches.soilColor(r.square, "Wall1") else rgb(Palette.Build.SandbagPatch)
	local timber, plank = rgb(Palette.Build.Dugout), rgb(Palette.Build.DugoutPlank)
	local meshes = {}
	for _, src in kit:GetChildren() do
		local off = offsets[src.Name]
		if src:IsA("BasePart") and src.Name ~= "Origin" and off then
			local part = src:Clone()
			part.CFrame = r.frame * off
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			part.Color = if table.find(G.soil, src.Name)
				then soil
				elseif table.find(G.dark, src.Name) then timber
				else plank
			part.Parent = r.model
			meshes[src.Name] = part
		end
	end
	local plates = {}
	local function plate(name: string, size: Vector3, cf: CFrame, stage: number)
		local part = newPart(r.model, name, size, r.frame * cf, plank)
		part.Transparency = 1
		part.CastShadow = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part:SetAttribute("Stage", stage)
		table.insert(plates, part)
	end
	local w, h, d = p.width, p.height, p.depth
	local floor, top, t = -G.drop, C.Trench.depth, G.walk
	local back = G.stair + d
	-- 1: the ramp down the steps (from the wall's foot to the room's floor), the slot's sides and its end over the room
	local slope = math.atan2(G.drop, G.stair)
	local run = math.sqrt(G.drop * G.drop + G.stair * G.stair)
	plate(
		"Ramp",
		Vector3.new(G.slot, t, run),
		CFrame.new(0, floor / 2, G.stair / 2) * CFrame.Angles(slope, 0, 0) * CFrame.new(0, -t / 2, 0),
		1
	)
	for _, sx in { -1, 1 } do
		local side = Vector3.new(t, top - floor, G.stair)
		plate("Side", side, CFrame.new(sx * (G.slot + t) / 2, (top + floor) / 2, G.stair / 2), 1)
	end
	local over = top - (floor + h)
	plate("End", Vector3.new(G.slot, over, t), CFrame.new(0, floor + h + over / 2, G.stair - t / 2), 1)
	-- 2: the room's floor (on its duckboards), ceiling, sides, back, and its front either side of the slot
	plate("Floor", Vector3.new(w, t, d), CFrame.new(0, floor + G.walk - t / 2, G.stair + d / 2), 2)
	plate("Ceiling", Vector3.new(w, t, d), CFrame.new(0, floor + h + t / 2, G.stair + d / 2), 2)
	for _, sx in { -1, 1 } do
		plate("Wall", Vector3.new(t, h, d), CFrame.new(sx * (w + t) / 2, floor + h / 2, G.stair + d / 2), 2)
		local front = (w - G.slot) / 2
		plate(
			"Wall",
			Vector3.new(front, h, t),
			CFrame.new(sx * (G.slot / 2 + front / 2), floor + h / 2, G.stair - t / 2),
			2
		)
	end
	plate("Wall", Vector3.new(w, h, t), CFrame.new(0, floor + h / 2, back + t / 2), 2)
	-- 1 (the ground is cut from then on): the cut round them filled, past their plates (Rules.dugoutSeals); a bullet
	-- meeting one is shot into the ground (Build.shot: colliding, a part is queried whatever its CanQuery)
	local face = Rules.trenchTop(C.Trench) - C.Trench.floor
	for _, s in Rules.dugoutSeals(p, G, face, top) do
		local size = Vector3.new(s.x1 - s.x0, s.y1 - s.y0, s.z1 - s.z0)
		plate(s.name, size, CFrame.new((s.x0 + s.x1) / 2, (s.y0 + s.y1) / 2, (s.z0 + s.z1) / 2), 1)
		plates[#plates]:SetAttribute("Seal", true)
	end
	r.meshes, r.plates = meshes, plates
	return true
end

-- everyone in a dugout's room or on its steps (players, bots and test dummies) and their roots
local function inDugout(r: Rec): { { model: Model, root: BasePart } }
	local G, p = C.Dugout, r.piece
	local seen: { [Model]: boolean } = {}
	local people: { Model } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(people, player.Character)
		end
	end
	for _, tag in { BotsCfg.Tag, DevCfg.Dummies.Tag } do
		for _, m in CollectionService:GetTagged(tag) do
			if m:IsA("Model") then
				table.insert(people, m)
			end
		end
	end
	local out = {}
	for _, m in people do
		local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and not seen[m] then
			seen[m] = true
			local l = r.frame:PointToObjectSpace(root.Position)
			local inRoom = Rules.inDugout(l.X, l.Y, l.Z, p, G)
			local onSteps = math.abs(l.X) <= G.slot / 2 and l.Z >= 0 and l.Z <= G.stair and l.Y < C.Trench.depth
			if inRoom or onSteps then
				table.insert(out, { model = m, root = root })
			end
		end
	end
	return out
end

-- where a dugout puts people out: `Dugout.eject` over the trench floor in front of its doorway, or over the ground
-- above its room once its trench is gone
local function ejectSpot(r: Rec): Vector3
	local G = C.Dugout
	if r.square and r.square.Parent then
		return (r.frame * CFrame.new(0, G.eject, -G.slot / 2)).Position
	end
	local over = (r.frame * CFrame.new(0, G.ejectRay[1], G.stair + r.piece.depth / 2)).Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(over, Vector3.new(0, -G.ejectRay[2], 0), params)
	return (if hit then hit.Position else over) + Vector3.new(0, G.eject, 0)
end

-- a dugout as its HP stands (Rules.dugoutShown): its meshes for its build stage, the plates that go with them; the
-- ground cut from stage 1 on and filled back with earth as it wears (a whole Dugout.fillStep at a time), anyone the
-- earth reaches lifted onto it (put out once it leaves no standing room)
local function showDugout(r: Rec)
	if not r.meshes and not layoutDugout(r) then
		return
	end
	local G = C.Dugout
	local stage, fill = Rules.dugoutShown(r.work, r.need, r.built, G)
	local height = Rules.dugoutFillHeight(math.floor(fill / G.fillStep + 1e-6) * G.fillStep, G)
	if stage >= 1 and r.filled ~= height then
		r.pocketed = true
		r.filled = height
		Trenches.pocket(r.model, r.square, r.frame, Survey.footprint(r.piece), height)
		-- anyone it reaches stands on it, or is put out once there is no standing room left under the roof
		local feet = height - G.drop
		local run = Rules.trenchTop(C.Trench) - C.Trench.floor
		for _, o in inDugout(r) do
			local l = r.frame:PointToObjectSpace(o.root.Position)
			local roof = if l.Z >= G.stair
				then r.piece.height - G.drop
				else Rules.dugoutRoof(l.Z, G, r.piece.height, run, C.Trench.depth)
			if roof - feet < G.headroom then
				o.model:PivotTo(CFrame.new(ejectSpot(r)) * o.root.CFrame.Rotation)
			elseif l.Y < feet + G.lift then
				o.model:PivotTo(o.root.CFrame + r.frame.UpVector * (feet + G.lift - l.Y))
			end
		end
	end
	if r.shown == stage then
		return
	end
	r.shown = stage
	local on = {}
	for _, name in if stage == 0 then G.laid else {} do
		on[name] = true
	end
	for s = 1, stage do
		for _, name in G.build[s] do
			on[name] = true
		end
	end
	for name, part in r.meshes or {} do
		part.Transparency = if on[name] then 0 else 1
	end
	for _, part in r.plates or {} do
		local solid = stage >= (part:GetAttribute("Stage") :: number)
		part.CanCollide = solid
		part.CanQuery = solid
	end
end

-- a dugout gone: everyone in its tunnel or room put out `Dugout.eject` over the trench floor in front of its doorway,
-- or over the ground above the room once its trench is gone
local function ejectDugout(r: Rec)
	local spot = ejectSpot(r)
	for _, o in inDugout(r) do
		o.model:PivotTo(CFrame.new(spot) * o.root.CFrame.Rotation)
	end
end

-- a piece goes: simply gone, nothing left (user 2026-10-27: "remove the crumble. 0 hp should just disappear")
local function remove(r: Rec)
	if not recs[r.model] then
		return
	end
	recs[r.model] = nil
	for _, c in r.watch or {} do
		c:Disconnect()
	end
	-- a dugout: anyone inside put out, the ground filled back
	if r.pocketed then
		r.pocketed = false
		ejectDugout(r)
		Trenches.pocket(r.model, nil, nil, nil)
	end
	-- a gun piece: the gun goes, its pit filled back in
	local gun = r.gun
	r.gun = nil
	if gun then
		gun:Destroy()
	end
	if r.pitBase and (r.dug or 0) > 0 then
		Ground.restore(r.pitBase)
		Net.event("GroundDug"):FireAllClients(r.frame.Position, r.piece.depth)
	end
	r.model:Destroy()
end

-- a gun's sandbag ring (Config/Build.GunRing, its piece's `ring`): the MG nest's bags round its pivot on the ground
-- (`r.at`, before its pit), each with its empty sack, in a Model "Ring" (not a structure: it is the gun's). False when
-- the library lacks the pile.
local function layoutRing(r: Rec, n: any): boolean
	local kit, offsets = libraryKit(n.asset)
	local at = r.at
	if not kit or not at then
		return false
	end
	local holder = Instance.new("Model")
	holder.Name = "Ring"
	holder.Parent = r.model
	local base = at * CFrame.new(0, -C.Sandbags.sink, 0)
	local sacks: { [BasePart]: Sack } = {}
	r.sacks = sacks
	layRing(n, n.bags, kit, offsets, base, 2, function(d: BasePart, cf: CFrame, row: number, top: boolean)
		layBag(holder, base, n.flat, sacks, d, cf, row, top)
	end)
	return true
end

-- a gun's sandbag ring as the gun stands (Rules.ringShown): being built, by its HP; once it has stood, by its gun's
-- Wreck stage (Config/Artillery.Wreck), its bags going with the gun's stages as an MG nest's
local function showRing(r: Rec)
	local n = r.piece.ring and C.GunRing[r.piece.ring]
	if not n then
		return
	end
	if not r.sacks and not layoutRing(r, n) then
		return
	end
	local wreck: number? = nil
	if r.built then
		local g = ArtilleryCfg.Guns[r.piece.gun or ""]
		local hp = r.gun and r.gun:GetAttribute("HP")
		wreck = if g and type(hp) == "number" then ArtilleryRules.wreckStage(hp, g.hp, ArtilleryCfg.Wreck.at) else 0
	end
	showBags(r, Rules.ringShown(r.work, r.need, n, wreck))
end

-- a gun piece as its HP stands: its pit dug to its stage, then its parts on the pit's floor, fitted to the quarter of
-- its HP, or the gun standing there once it has stood (Rules.pitShare)
showGun = function(r: Rec)
	local p = r.piece
	local gunCfg = ArtilleryCfg.Guns[p.gun]
	local at = r.at :: CFrame
	if not guns or not gunCfg then
		return
	end
	local share = Rules.pitShare(r.built, r.work, r.need, p.stages)
	local d = gunCfg.dig
	if d and share ~= r.dug then
		local back = -at.LookVector
		local ramp = d.ramp and { dir = back, width = d.ramp.width, length = d.ramp.length }
		r.pitBase = r.pitBase or Ground.pitBase(at.Position, d.radius, d.depth, d.rim, d.rimHeight, ramp, d.wall)
		local base = r.pitBase
		if base then
			if share > 0 then
				local out =
					Ground.pit(at.Position, d.radius, d.depth * share, d.rim, d.rimHeight * share, ramp, d.wall, base)
				Net.event("GroundDug"):FireAllClients(at.Position, out)
			else
				Ground.restore(base)
				Net.event("GroundDug"):FireAllClients(at.Position, p.depth)
			end
		end
		r.dug = share
	end
	local paint = C.Guns.paint[r.team]
	showRing(r)
	if r.built then
		if not r.gun then
			if r.parts then
				r.parts:Destroy()
			end
			if r.site then
				r.site:Destroy()
			end
			r.parts, r.site = nil, nil
			local gun =
				guns.place(p.gun, at.Position, at.LookVector, { paint = paint, dug = d ~= nil, up = at.UpVector })
			r.gun = gun
			if gun then
				gun:SetAttribute("Piece", p.key)
				-- the holder's link to it: the shovel's light goes round the gun itself (src/client/Build)
				local link = r.model:FindFirstChild("Gun") :: ObjectValue? or Instance.new("ObjectValue")
				link.Name = "Gun"
				link.Value = gun
				link.Parent = r.model
				-- its HP is the gun's own now (Config/Artillery.Guns `hp`: 100), mirrored on the holder for the shovel's
				-- panel (src/client/Build)
				local function hp()
					local v = gun:GetAttribute("HP")
					if type(v) == "number" and recs[r.model] then
						r.work = v
						r.model:SetAttribute("Work", v)
						r.model:SetAttribute("HP", v)
						showRing(r) -- (its sandbags wear with it)
					end
				end
				hp()
				gun:GetAttributeChangedSignal("HP"):Connect(hp)
				-- gone some other way (the dev tools' clear): the piece goes too
				gun.Destroying:Connect(function()
					if r.gun == gun then
						r.gun = nil
						remove(r)
					end
				end)
			end
		end
		return
	end
	if not r.parts then
		r.parts = guns.parts(p.gun, paint)
		if r.parts then
			r.parts.Parent = r.model
		end
	end
	local floor = at.Position - Vector3.new(0, if d then d.depth * share else 0, 0)
	local on = at.Rotation + floor -- (tilted as it was laid on a slope: Config/Build.Slope)
	if r.parts then
		local quarters = Rules.stageOf(r.work, r.need, ArtilleryCfg.Assembly.quarters)
		guns.assemble(r.parts, p.gun, on, quarters)
	end
	local spec = C.Scaffold[p.gun]
	if not r.site and spec then
		r.site = buildSite(spec)
		r.site.Parent = r.model
	end
	if r.site then
		r.site:PivotTo(on)
	end
end

-- the dark dirt a foxhole is dug in and what of the ground under it turns to it (Config/Build.Foxhole.soil, bare)
local foxholeSoil = (Enum.Material :: any)[C.Foxhole.soil] :: Enum.Material
local foxholeBare: { Enum.Material } = {}
for _, name in C.Foxhole.bare do
	table.insert(foxholeBare, (Enum.Material :: any)[name])
end

-- a foxhole's spot dug (its one Build swing): the pit and its lip carved into the ground there, in dark dirt, and the
-- piece gone (it is only ground now)
local function showFoxhole(r: Rec)
	if r.work < r.need or not r.plot then
		return
	end
	local F = C.Foxhole
	local centre, look = r.frame.Position, r.frame.LookVector
	Ground.shapeColumns(r.plot, function(at: Vector3): number?
		return Rules.foxholeHeight(at.X - centre.X, at.Z - centre.Z, look.X, look.Z, F)
	end, foxholeSoil, foxholeSoil, foxholeBare)
	Net.event("GroundDug"):FireAllClients(centre, Rules.foxholeReach(F))
	r.plot = nil
	task.defer(remove, r)
end

-- shows a piece as its HP stands now
function apply(r: Rec)
	r.model:SetAttribute("Work", r.work)
	r.model:SetAttribute("Built", r.built)
	-- (every structure's HP out of its max, for the shovel's panel, src/client/Build)
	r.model:SetAttribute("HP", r.work)
	r.model:SetAttribute("MaxHP", r.need)
	local kind = r.piece.kind
	if kind == "Sandbags" then
		-- (its work is its HP: shown on the shovel's panel like a gun's)
		r.model:SetAttribute("HP", r.work)
		r.model:SetAttribute("MaxHP", r.need)
		showSandbags(r, Rules.pileShown(r.work, r.need, C.Sandbags.hp.swing, #r.piece.bags, r.built))
	elseif kind == "Nest" then
		showNest(r)
		-- (stood once: its gun's HP)
		local g = ArtilleryCfg.Guns[r.piece.gun or ""]
		if r.built and r.gun and g then
			local hp = r.gun:GetAttribute("HP")
			r.model:SetAttribute("HP", hp)
			r.model:SetAttribute("MaxHP", g.hp)
			local s = r.model:FindFirstChild("Nest")
			if s then
				s:SetAttribute("HP", hp)
				s:SetAttribute("MaxHP", g.hp)
			end
		end
	elseif kind == "Wire" then
		showWire(r)
	elseif kind == "Gun" then
		showGun(r)
	elseif kind == "Hesco" then
		showHesco(r)
	elseif kind == "Bridge" then
		showBridge(r)
	elseif kind == "Foxhole" then
		showFoxhole(r)
	elseif kind == "Dugout" then
		showDugout(r)
	end
end

-- a Hesco barrier, a sandbag pile or an MG nest worn by `amount` of its HP by a weapon: it shows what it has left; at 0 it is gone,
-- no rubble (user 2026-10-27: "remove the crumble. 0 hp should just disappear")
local function wear(r: Rec, amount: number)
	-- an MG nest that has stood: its gun takes it (as a share of its HP); hit at 0 it is gone
	local g = ArtilleryCfg.Guns[r.piece.gun or ""]
	if r.piece.kind == "Nest" and r.built and r.gun and g and guns then
		local hp = r.gun:GetAttribute("HP")
		if type(hp) == "number" and hp <= 0 then
			remove(r)
		else
			guns.harm(r.gun, amount / r.need * g.hp)
		end
		return
	end
	r.work = math.max(r.work - amount, 0)
	if r.work <= 0 then
		remove(r)
		return
	end
	local pile = r.model:FindFirstChild("Pile") or r.model:FindFirstChild("Nest")
	if pile then
		pile:SetAttribute("HP", r.work)
	end
	apply(r)
end

-- `team`'s live pieces: `owner`'s only (nil: anyone's), of `key` only (nil: any; "shared": those without a
-- `playerCap` of their own, Config/Build.PerPlayer), in `sector` only (nil: anywhere)
local function count(team: string, owner: number?, key: string?, sector: string?): number
	local n = 0
	for _, r in recs do
		local p = r.piece
		local keyed = key == nil or (if key == "shared" then p.playerCap == nil else p.key == key)
		if
			r.team == team
			and (owner == nil or r.owner == owner)
			and keyed
			and (sector == nil or r.sector == sector)
		then
			n += 1
		end
	end
	return n
end

-- the Map1 sector `p` lies in (Rules/Sectors.sectorAt)
local function sectorOf(p: Vector3): string
	return SectorRules.sectorAt(Map1, MapTerrain, p.X, p.Z, SectorCfg.Divider.RiverSegments)
end

-- why `team` can't build a gun yet in a Normal match (its side's sectors held, src/server/Frontline); nil outside one
local function gunLocked(key: string, team: string?): string?
	local front = workspace:FindFirstChild(FrontCfg.FolderName)
	if not front or not team then
		return nil
	end
	local side = if front:GetAttribute("West") == team
		then "West"
		elseif front:GetAttribute("East") == team then "East"
		else nil
	local held = side and front:GetAttribute(side .. FrontCfg.HeldAttribute)
	if type(held) ~= "number" then
		return nil
	end
	return FrontRules.gunLocked(FrontCfg.Artillery, key, held)
end

-- who builds: a player's character or a bot soldier (Config/Bots.Tag), its id (a UserId or a bot's negative
-- Config/Bots.IdAttribute: whose pieces are whose, the caps, the points) and what its swings are timed by
type Builder = {
	character: Model,
	root: BasePart,
	team: string?,
	id: number,
	player: Player?,
	key: Instance,
	said: string?, -- the last reason told (Build.workAs)
}

-- the player's builder (`shovel`: only while they hold the shovel)
local function soldier(player: Player, shovel: boolean): Builder?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root or (shovel and not holdsShovel(character)) then
		return nil
	end
	return {
		character = character,
		root = root,
		team = teamOf(character),
		id = player.UserId,
		player = player,
		key = player,
	}
end

-- a live bot soldier's builder (it builds without a shovel in its hands: the bot side shows what it does)
local function bot(model: Model): Builder?
	local id = model:GetAttribute(BotsCfg.IdAttribute)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if
		not CollectionService:HasTag(model, BotsCfg.Tag)
		or type(id) ~= "number"
		or not root
		or not humanoid
		or humanoid.Health <= 0
	then
		return nil
	end
	return { character = model, root = root, team = teamOf(model), id = id, key = model }
end

-- tells a player why (Net "Build" "Refused"); a bot gets the reason returned instead
local function tell(b: Builder, reason: string)
	b.said = reason
	if b.player then
		refuse(b.player, reason)
	end
end

local function shareOf(b: Builder): number?
	return if b.player then digShare(b.player) else nil
end

-- how much of a piece's own swing amount this builder's swing of `mode` does (Config/Build.Power); a bot's times the
-- admin panel's bot dig speed (Config/DevTools.Admin.BotDig, on Workspace while not 1)
local function powerOf(b: Builder, mode: string): number
	local k = Rules.swingPower(mode, Loadouts.classOf(b.character), C.Power)
	local fast = if b.player then nil else workspace:GetAttribute(DevCfg.Admin.BotDig.attribute)
	return if type(fast) == "number" and fast > 0 then k * fast else k
end

local function allBuild(b: Builder): boolean
	return b.player ~= nil and buildsAll(b.player)
end

local function award(b: Builder, reason: string)
	if b.player then
		Loadouts.award(b.player, reason)
	else
		Loadouts.awardBot(b.id, reason)
	end
end

-- a foxhole spot's parts: the scraped patch on the ground and an unseen disc over where its pit will be (what the
-- shovel's light shows); neither blocks, is hit or touched
local function layoutFoxhole(r: Rec)
	local F = C.Foxhole
	local function flat(name: string, size: Vector3, cf: CFrame, color: Color3): Part
		local p = newPart(r.model, name, size, cf, color)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		return p
	end
	flat(
		"Patch",
		Vector3.new(F.patch.size, F.patch.thick, F.patch.size),
		r.frame * CFrame.new(0, F.patch.thick / 2, 0),
		rgb(Palette.Build.SandbagPatch)
	)
	local mark = flat(
		"Mark",
		Vector3.new(0.05, F.radius * 2, F.radius * 2),
		r.frame * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		rgb(Palette.Build.Focus)
	)
	mark.Shape = Enum.PartType.Cylinder
	mark.Transparency = 0.98
end

-- Lays a blueprint (Net "Build" "Place"). `dev`: the admin panel's spawn list (Build.devPlace): no shovel, reach or
-- limits, and a sandbag pile or MG nest stands finished at once. Returns why it was refused, nil when laid.
local function place(b: Builder, key: any, at: any, dev: boolean?): string?
	local character, root, team = b.character, b.root, b.team
	local piece = Rules.piece(key, C.Pieces)
	if not piece or typeof(at) ~= "CFrame" or piece.kind == "Trench" then
		return "No such piece"
	end
	if not team then
		return "No team (the character has no Kit)"
	end
	local foxhole = piece.kind == "Foxhole"
	local F = C.Foxhole
	-- (a foxhole: round its grid corner, Rules.foxholeSnap)
	local spot0 = if foxhole
		then Vector3.new(
			Rules.foxholeSnap(at.Position.X, F.voxel),
			at.Position.Y,
			Rules.foxholeSnap(at.Position.Z, F.voxel)
		)
		else at.Position
	local frame = Survey.frame(spot0, at.LookVector)
	-- (a gun: `frame` the gun, `box` the ground it needs; any other piece: the same)
	local gunAt: CFrame? = nil
	if piece.kind == "Gun" then
		local y = Survey.groundAt(frame.Position.X, frame.Position.Z, frame.Position.Y) or frame.Position.Y
		gunAt = CFrame.new(frame.Position.X, y, frame.Position.Z) * frame.Rotation
		frame = Survey.box(piece, gunAt :: CFrame)
	end
	local f = folder()
	-- (a bridge: its trench square decides where it goes, not the ground)
	local bridge = piece.kind == "Bridge"
	local spot, square, length = nil, nil, nil
	if bridge then
		local s, sf, len, m = Survey.bridgeSpot(f, frame.Position)
		spot = Rules.bridgeSpot(s, C.Bridge)
		if sf and len then
			frame, length, square = sf, len, m
		end
	end
	-- (a dugout: the trench square wall `at` is by decides where it goes, Survey.dugoutSpot)
	local dugout = piece.kind == "Dugout"
	if dugout then
		local s, df, m = Survey.dugoutSpot(f, frame.Position)
		spot = Rules.dugoutSpot(s, C.Dugout)
		if df and m then
			frame, square = df, m
		end
	end
	local inTrench = bridge or dugout -- (no ground survey: its square decides)
	-- (a dugout's footprint, its steps and room back from the wall's foot: Survey.dugoutBox)
	local dugBox, dugSize = Survey.dugoutBox(piece, frame)
	local report = Survey.ground(piece, frame)
	if not inTrench then
		frame = CFrame.new(frame.Position.X, report.centre, frame.Position.Z) * frame.Rotation
	end
	local gunPiece = gunAt ~= nil
	local sector = if piece.sectorCap then sectorOf(frame.Position) else nil
	local ok, reason = Rules.canPlace({
		piece = piece,
		distance = if dev then 0 else (root.Position - (if gunAt then gunAt.Position else frame.Position)).Magnitude,
		reach = C.Reach + 2, -- (the client's ghost checks C.Reach; slack for movement since)
		spot = spot,
		slope = if inTrench then 0 else report.slope,
		maxSlope = piece.maxSlope or C.Trench.maxSlope,
		ground = inTrench or report.ground,
		water = not inTrench and report.water,
		overlap = if dugout
			then Survey.onPiece({ width = dugSize.X, depth = dugSize.Z, height = dugSize.Y }, dugBox, f)
			elseif inTrench then Survey.onPiece(piece, frame, f)
			else Survey.blocked(piece, frame, report.low, { character }) or Survey.onPiece(piece, frame, f),
		-- (none over a trench's open cut, dug or planned: the bots' pieces too, Build.placeAs)
		overTrench = not inTrench and Survey.overTrench(piece, frame, f),
		gunGap = gunPiece and Survey.gunGap(piece, (gunAt :: CFrame).Position, f),
		-- (a foxhole, wire or gun keeps off trenches: their hole, walls and bank; Rules.trenchKeep)
		nearTrench = Survey.nearTrench(piece, frame, f),
		mine = if dev then 0 else count(team, b.id, "shared"),
		team = if dev then 0 else count(team, nil),
		kind = if dev then 0 else count(team, nil, piece.key),
		mineKind = if dev then 0 else count(team, b.id, piece.key),
		sector = if dev or not sector then 0 else count(team, nil, piece.key, sector),
		locked = if dev then nil else gunLocked(piece.key, team),
		perPlayer = C.PerPlayer,
		perTeam = C.PerTeam,
		-- (only engineers build guns: Config/Classes; the admin panel's build anything: everyone)
		allowed = dev or Loadouts.mayBuild(character, piece.kind) or allBuild(b),
	})
	if not ok then
		tell(b, reason or "Can't build here")
		return reason or "Can't build here"
	end
	-- a gun or an MG nest (Config/Build.Slope, Rules.slopeLay): the earth under it cut and filled to the plane it lies
	-- on as it is laid, level or tilted, and everything of it laid on that plane, so nothing floats or sinks at any
	-- stage (laid on the plane, not the ground read again: a terrain raycast in the same frame as the write still finds
	-- the ground as it was, Studio 2026-11-03)
	local laidOn: CFrame? = nil
	if piece.lay and not inTrench then
		local plane = Survey.lay(piece, frame, report)
		if not plane then
			tell(b, "Too steep")
			return "Too steep"
		end
		local S = C.Slope
		local w, d = piece.width / 2 + S.pad, piece.depth / 2 + S.pad
		local reach = Ground.level(plane, { -w, -d }, { w, d }, S.blend, (Enum.Material :: any)[S.material])
		Net.event("GroundDug"):FireAllClients(plane.Position, reach)
		frame = CFrame.new(frame.Position.X, plane.Position.Y, frame.Position.Z) * frame.Rotation
		laidOn = plane
		if gunAt then
			gunAt = plane * CFrame.new(0, 0, -(piece.back or 0))
		end
	end
	local model = Instance.new("Model")
	model.Name = piece.key
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local now = os.clock()
	-- (a sandbag pile's work is its HP: laid at stage 1, Config/Build.Sandbags.hp)
	local bags = piece.kind == "Sandbags"
	local nest = piece.kind == "Nest"
	local r: Rec = {
		model = model,
		piece = piece,
		team = team,
		owner = b.id,
		-- (its work is its HP: laid at its `place`, Rules.hpOf)
		work = (Rules.hpOf(piece, C) or { place = 0 }).place,
		need = (Rules.hpOf(piece, C) or { max = piece.work }).max,
		built = bridge, -- (a bridge stands, crossable, from the moment it is laid)
		born = now,
		worked = now,
		frame = frame,
		sector = sector,
		at = gunAt,
		laid = if bags or piece.kind == "Wire" or piece.kind == "Hesco" then report.heights else nil,
	}
	if bags then
		if not layoutPile(r, Survey.onGround(piece, frame, report)) then
			model:Destroy()
			tell(b, "Can't build here") -- (the dev place's asset library lacks the pile: layoutPile warns)
			return "The asset library lacks the sandbag pile"
		end
	elseif nest then
		if not layoutNest(r, laidOn or Survey.onGround(piece, frame, report)) then
			model:Destroy()
			tell(b, "Can't build here") -- (the dev place's asset library lacks the pile or the mount bag)
			return "The asset library lacks the pile or the mount bag"
		end
	elseif piece.kind == "Wire" then
		layoutWire(r, Survey.onGround(piece, frame, report))
	elseif piece.kind == "Hesco" then
		r.base = CFrame.new(frame.Position.X, report.low, frame.Position.Z) * frame.Rotation
	elseif bridge and square and length then
		r.square = square
		layoutBridge(r, length, bridgeRoll:NextInteger(0, 2 ^ 20))
	elseif foxhole then
		r.plot = Ground.plot(frame.Position, Rules.foxholeReach(F), F.depth + F.voxel * 2, F.heap.height + F.voxel * 2)
		if not r.plot then
			model:Destroy()
			tell(b, "Can't build here")
			return "The ground can't be read"
		end
		layoutFoxhole(r)
	elseif dugout then
		r.square = square
		-- (Build.worksOf's `at`: the middle of its room's floor)
		r.at = frame * CFrame.new(0, C.Dugout.walk - C.Dugout.drop, C.Dugout.stair + piece.depth / 2)
		if not layoutDugout(r) then
			model:Destroy()
			tell(b, "Can't build here") -- (the dev place's asset library lacks the pieces: libraryKit warns)
			return "The asset library lacks the dugout's pieces"
		end
	end
	model:SetAttribute("Piece", piece.key)
	model:SetAttribute("Team", team)
	model:SetAttribute("Need", r.need)
	model:SetAttribute("Frame", if dugout then dugBox else frame)
	model:SetAttribute(
		"Size",
		if length
			then Vector3.new(length, piece.height, piece.depth)
			elseif dugout then dugSize
			else Survey.footprint(piece)
	)
	if gunAt then
		model:SetAttribute("At", gunAt)
	end
	recs[model] = r
	model.Parent = f
	Trenches.restake(model) -- (no stake through it)
	if dev and (bags or nest or foxhole or dugout) then
		-- (finished, as if dug to the end; no match points for it)
		r.work = r.need
		r.built, r.paid = true, true
		local s = model:FindFirstChild(if nest then "Nest" else "Pile")
		if s then
			s:SetAttribute("HP", r.work)
		end
	end
	apply(r)
	-- a dugout goes with its square (user 2026-11-02: "if the trench gets destroyed, the dugout should automatically be
	-- destroyed too, putting all players above ground"): filled back, anyone inside put on the ground over it
	if dugout then
		local cutInto = square
		square = nil
		if cutInto then
			r.watch = {
				cutInto.AncestryChanged:Connect(function()
					if recs[model] and not cutInto.Parent then
						remove(r)
					end
				end),
			}
		end
	end
	-- a bridge falls in with its square: buried past where its dirt pieces go, or gone
	if square then
		local function check()
			local hp, max = square:GetAttribute("HP"), square:GetAttribute("MaxHP")
			local buried = type(hp) == "number" and type(max) == "number" and Rules.bridgeFalls(hp, max, C.Bridge.fall)
			if recs[model] and (buried or not square.Parent) then
				remove(r)
			end
		end
		r.watch = { square:GetAttributeChangedSignal("HP"):Connect(check), square.AncestryChanged:Connect(check) }
	end
	if bags or nest then
		-- weapons wear it (Build.blast / Build.shot, wear) and its section's HP follows; anything else that changes that
		-- HP is followed back, its bags by its HP
		local s = model:FindFirstChild(if nest then "Nest" else "Pile")
		if s then
			s:GetAttributeChangedSignal("HP"):Connect(function()
				local hp = s:GetAttribute("HP")
				if recs[model] and type(hp) == "number" and hp ~= r.work then
					r.work = math.max(hp, 0)
					apply(r)
				end
			end)
		end
		model.ChildRemoved:Connect(function()
			for _, c in model:GetChildren() do
				if CollectionService:HasTag(c, D.SectionTag) then
					return
				end
			end
			remove(r)
		end)
	end
	return nil
end

-- Plans a trench (Net "Build" "Plan": its start and end on the ground)
-- Returns why it was refused, nil when laid.
local function plan(b: Builder, from: any, to: any): string?
	if not b.team or typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return "No team or no such plan"
	end
	local reason = Trenches.plan(b.id, b.team, b.root, from, to)
	if reason then
		tell(b, reason)
	end
	return reason
end

-- HP a player's Build swings added (a match's "most HP built": src/server/MatchStats), to each watcher (a bot's
-- count for nothing there)
local builtWatchers: { (Player, number) -> () } = {}
function Build.onBuilt(fn: (Player, number) -> ())
	table.insert(builtWatchers, fn)
end
local function credit(b: Builder, hp: number)
	local player = b.player
	if hp > 0 and player then
		for _, fn in builtWatchers do
			task.spawn(fn, player, hp)
		end
	end
end

-- A shovel swing (Net "Build" "Work"): at a piece, a trench block or a tree, in the shovel's mode. Every swing that
-- lands sets lastSwing[b.key] to now (Build.workAs tells a bot's from it).
local function work(b: Builder, target: any, mode: any)
	local character, root, team = b.character, b.root, b.team
	if not team or typeof(target) ~= "Instance" then
		return
	end
	if mode ~= "Build" and mode ~= "Destroy" then
		return
	end
	local now = os.clock()
	if Rules.tooSoon(now, lastSwing[b.key], GAP, C.SwingSlack) then
		return
	end
	local k = powerOf(b, mode)
	-- a trench block
	local blk = Trenches.blockOf(target)
	if blk then
		if Trenches.distance(blk, root.Position) <= C.Trench.swingReach then
			lastSwing[b.key] = now
			local done, added = Trenches.work(blk, team, mode, k, shareOf(b))
			credit(b, added)
			if done then
				award(b, "Trench")
			end
		end
		return
	end
	-- a tree (Destroy only)
	if
		mode == "Destroy"
		and target:IsA("BasePart")
		and (target.Position - root.Position).Magnitude <= C.SwingReach + 4
	then
		if Trees.chop(target, root.Position) then
			lastSwing[b.key] = now
		end
		return
	end
	-- a piece
	local r = if target:IsA("Model") then recs[target] else nil
	if not r or Survey.distanceTo(target, root.Position) > C.SwingReach then
		return
	end
	local own = team == r.team
	-- a Hesco barrier: swings work its HP (Config/Build.Hesco.hp); its team's Build swings repair it too
	if r.piece.kind == "Hesco" then
		local build = mode == "Build"
		if build and (not own or r.work >= r.need) then
			return
		end
		lastSwing[b.key] = now
		local h = C.Hesco.hp
		local step = Rules.digAmount((if build then h.swing else h.destroy) * k, h.max, shareOf(b))
		local left, gone = Rules.hpSwing(r.work, build, h, step)
		if gone then
			remove(r)
			return
		end
		credit(b, left - r.work)
		r.work = left
		r.worked = now
		if r.work >= r.need and not r.built then
			award(b, "Piece")
			r.built = true
		end
		apply(r)
		return
	end
	local standing = (r.piece.kind == "Gun" or r.piece.kind == "Nest") and r.gun and r.built
	if mode == "Build" and standing then
		-- fixing a standing gun, any team's (Config/Artillery.Repair; user 2026-10-27: "make it so you can fix a
		-- artillery by digging too ... its fine if the cannon looks buried, as long as it gets flattenned out again once
		-- its fixed", "enemie teams should be able to repair and fix enemie trenches and artillery")
		local gun = r.gun
		local g = ArtilleryCfg.Guns[(r.piece :: any).gun or ""]
		local hp = gun:GetAttribute("HP")
		if not guns or not g or type(hp) ~= "number" or hp >= g.hp then
			return
		end
		lastSwing[b.key] = now
		local what, after = guns.repair(gun, Rules.digAmount(g.hp / g.repair * k, g.hp, shareOf(b)))
		if what then
			-- back in service or whole: a fresh gun in its place, the howitzer's pit dug out again from the ground as
			-- it was (the field gun levels its own ground as it stands), damaged to what it has
			r.gun = nil
			gun:Destroy()
			local d = g.dig
			local at = r.at
			if d and r.pitBase and at then
				local ramp = d.ramp and { dir = -at.LookVector, width = d.ramp.width, length = d.ramp.length }
				local out = Ground.pit(at.Position, d.radius, d.depth, d.rim, d.rimHeight, ramp, d.wall, r.pitBase)
				Net.event("GroundDug"):FireAllClients(at.Position, out)
			end
			local nest = r.piece.kind == "Nest"
			-- fixed whole, an MG nest's ground is cleared back to how it lay (user 2026-10-29: "once its fixed its
			-- cleared"), only on its own footprint
			local base = r.nestBase
			if nest and what == "whole" and base then
				Ground.restoreWithin(base, function(column: Vector3): boolean
					local l = r.frame:PointToObjectSpace(column)
					return Rules.onFootprint(l.X, l.Z, r.piece.width, r.piece.depth, C.Nest.ground)
				end)
				Net.event("GroundDug"):FireAllClients(r.frame.Position, math.max(r.piece.width, r.piece.depth))
			end
			if nest then
				showNest(r)
			else
				showGun(r)
			end
			if r.gun and what == "usable" then
				guns.setHp(r.gun, after)
			end
			if nest then
				apply(r) -- (its bags and panel by the fresh gun's HP)
			end
		end
		return
	end
	if mode == "Destroy" and standing and r.gun and guns then
		-- a standing gun loses HP to the shovel as to any damage (Artillery.harm), as many swings as fix it; a swing that
		-- takes it to 0, or at a wreck weapons left at 0, and it is gone (Config/Build.Guns)
		local g = ArtilleryCfg.Guns[(r.piece :: any).gun or ""]
		local hp = r.gun:GetAttribute("HP")
		if not g or type(hp) ~= "number" then
			return
		end
		lastSwing[b.key] = now
		local step = Rules.digAmount(g.hp / g.repair * k, g.hp, shareOf(b))
		local _, gone = Rules.hpSwing(hp, false, { max = g.hp }, step)
		if gone then
			remove(r)
		else
			guns.harm(r.gun, step)
		end
		return
	end
	if mode == "Build" and (not own or r.work >= r.need) then
		return
	end
	if mode == "Build" and not Loadouts.mayBuild(character, r.piece.kind) and not allBuild(b) then
		tell(b, "Engineers only") -- (anyone may take one apart)
		return
	end
	lastSwing[b.key] = now
	-- a sandbag pile or an MG nest: swings work its HP (Config/Build.Sandbags.hp / Nest.hp); its team's Build swings
	-- repair it too
	local nest = r.piece.kind == "Nest"
	if r.piece.kind == "Sandbags" or nest then
		local h = if nest then C.Nest.hp else C.Sandbags.hp
		local build = mode == "Build"
		local step = Rules.digAmount((if build then h.swing else h.destroy) * k, h.max, shareOf(b))
		local left, gone = Rules.hpSwing(r.work, build, h, step)
		if gone then
			remove(r)
			return
		end
		credit(b, left - r.work)
		r.work = left
		r.worked = now
		if r.work >= r.need then
			if not r.paid then
				award(b, "Piece") -- (once per piece)
			end
			r.built, r.paid = true, true
		end
		local s = r.model:FindFirstChild(if nest then "Nest" else "Pile")
		if s then
			s:SetAttribute("HP", r.work)
		end
		apply(r)
		return
	end
	-- a bridge: swings work its HP (Config/Build.Bridge.hp); its team's Build swings repair it too; at 0 it is gone
	if r.piece.kind == "Bridge" then
		local h = C.Bridge.hp
		local build = mode == "Build"
		local step = Rules.digAmount((if build then h.swing else h.destroy) * k, h.max, shareOf(b))
		local left, gone = Rules.trenchSwing(r.work, h.max, step, build)
		if gone then
			remove(r)
			return
		end
		credit(b, left - r.work)
		r.work = left
		r.worked = now
		if r.work >= r.need and not r.paid then
			award(b, "Piece") -- (once per piece)
			r.paid = true
		end
		apply(r)
		return
	end
	-- barbed wire, a gun being built: swings work its HP (Rules.hpOf); its team's Build swings repair a wire too
	local h = Rules.hpOf(r.piece, C)
	if h then
		local build = mode == "Build"
		local step = Rules.digAmount((if build then h.swing else h.destroy) * k, h.max, shareOf(b))
		local left, gone = Rules.hpSwing(r.work, build, h, step)
		if gone then
			remove(r)
			return
		end
		credit(b, left - r.work)
		r.work = left
		r.worked = now
		if r.work >= r.need then
			if not r.paid then
				award(b, "Piece") -- (once per piece)
			end
			r.built, r.paid = true, true
		end
		apply(r)
		if r.piece.kind == "Wire" and not build then
			shakeWire(r, root.Position)
		end
		return
	end
	local was = r.work
	local amount = Rules.digAmount(Rules.swingWork(r.piece, k), r.need, shareOf(b))
	local left, gone = Rules.swing(r.work, r.need, mode == "Build", amount)
	if gone then
		remove(r) -- (at 0 it is simply gone)
		return
	end
	credit(b, left - r.work)
	r.work = left
	r.worked = now
	if r.work >= r.need then
		if not r.paid then
			award(b, "Piece") -- (once per piece: built again after Destroy swings pays nothing)
		end
		r.built, r.paid = true, true
	end
	local stages = r.piece.stages or 1
	if Rules.stageOf(was, r.need, stages) ~= Rules.stageOf(r.work, r.need, stages) or r.work >= r.need then
		apply(r)
	else
		r.model:SetAttribute("Work", r.work)
	end
end

-- A blast at `position` (src/server/Damage.blast, after the crater) of `kg`, `key` what it is to built things (a
-- Config/Build.Structures key; nil: by its charge): trenches are buried (src/server/Trenches), sandbag piles and wire
-- worn down, each by how far it is from the blast.
-- The admin panel's spawn list (src/server/DevTools "PlacePiece"): a Config/Build piece laid finished at `at`
-- (facing its LookVector) for `player`'s team; still refused on ground it can't stand on. Returns why it was refused,
-- nil when laid.
function Build.devPlace(player: Player, key: string, at: CFrame): string?
	local b = soldier(player, false)
	return if b then place(b, key, at, true) else "No character"
end

-- Bot soldiers build as players do (the same checks: the class's builds list, the team, reach, caps, the artillery
-- level, the ground survey; its pieces are its BotId's, its points Loadouts.awardBot's). `model`: a live bot
-- (Config/Bots.Tag, BotId and Kit attributes). Each returns why it was refused, nil when done.

-- Lays piece `key` (a Config/Build.Pieces key, not "Trench") at `at`, facing `look` (flat; nil: as `at` faces); the
-- bot within Config/Build.Reach of it.
function Build.placeAs(model: Model, key: string, at: Vector3 | CFrame, look: Vector3?): string?
	local b = bot(model)
	if not b then
		return "Not a live bot"
	end
	local cf = if typeof(at) == "CFrame" then at else CFrame.new(at)
	local flat = if look then Vector3.new(look.X, 0, look.Z) else Vector3.zero
	if flat.Magnitude > 1e-3 then
		cf = CFrame.lookAt(cf.Position, cf.Position + flat)
	end
	return place(b, key, cf)
end

-- Why a dugout can't go in the trench square wall by `at` (Survey.dugoutSpot, Rules.dugoutSpot: a dug square, room for
-- it, no other dugout near, ground over and round its room), none of the caps or reach; nil when it can (the bots'
-- dugout spots, src/server/Bots/Commander)
function Build.dugoutFor(at: Vector3): string?
	local s = Survey.dugoutSpot(folder(), at)
	return Rules.dugoutSpot(s, C.Dugout)
end

-- Why gun `key` (a Config/Build.Pieces key of kind "Gun") can't stand at `at` (its spot, facing its way): the ground
-- checks a bot's Build.placeAs makes there (open, dry and gentle ground, nothing in the way, off trenches and other
-- guns, a plane to lay it on), none of the caps or reach; nil when it can (the bots' gun spots, src/server/Bots/Commander;
-- user 2026-11-03: the bots built no howitzers: the 28-stud pit's scored spots were all "In the way")
function Build.siteFor(key: string, at: CFrame): string?
	local piece = Rules.piece(key, C.Pieces)
	if not piece or piece.kind ~= "Gun" then
		return "No such gun"
	end
	local frame = Survey.frame(at.Position, at.LookVector)
	local y = Survey.groundAt(frame.Position.X, frame.Position.Z, frame.Position.Y) or frame.Position.Y
	local gunAt = CFrame.new(frame.Position.X, y, frame.Position.Z) * frame.Rotation
	frame = Survey.box(piece, gunAt)
	local f = folder()
	local report = Survey.ground(piece, frame)
	frame = CFrame.new(frame.Position.X, report.centre, frame.Position.Z) * frame.Rotation
	local ok, reason = Rules.canPlace({
		piece = piece,
		distance = 0,
		reach = math.huge,
		slope = report.slope,
		maxSlope = piece.maxSlope or C.Trench.maxSlope,
		ground = report.ground,
		water = report.water,
		overlap = Survey.blocked(piece, frame, report.low) or Survey.onPiece(piece, frame, f),
		overTrench = Survey.overTrench(piece, frame, f),
		gunGap = Survey.gunGap(piece, gunAt.Position, f),
		nearTrench = Survey.nearTrench(piece, frame, f),
		mine = 0,
		team = 0,
		kind = 0,
		mineKind = 0,
		sector = 0,
		perPlayer = math.huge,
		perTeam = math.huge,
		allowed = true,
	})
	if not ok then
		return reason or "Can't build here"
	end
	if piece.lay and not Survey.lay(piece, frame, report) then
		return "Too steep"
	end
	return nil
end

-- Plans a trench from `from` to `to` (ground points); the bot within Config/Build.Trench.firstReach of either end.
function Build.planAs(model: Model, from: Vector3, to: Vector3): string?
	local b = bot(model)
	if not b then
		return "Not a live bot"
	end
	return plan(b, from, to)
end

-- a shovel swing's sound (Net "Dug") from `character` to every player but `except` (the swinger, who plays its own),
-- one swinger's (`key`: a Player or a bot's model) no closer together than Config/Shovel.SoundGap
local lastSound: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local function sendDug(key: Instance, character: Model, kind: string, except: Player?)
	local now = os.clock()
	if lastSound[key] and now - lastSound[key] < ShovelCfg.SoundGap then
		return
	end
	lastSound[key] = now
	for _, p in Players:GetPlayers() do
		if p ~= except then
			Net.event("Dug"):FireClient(p, character, kind)
		end
	end
end

-- a bot's swing of `mode` that landed, heard by every player as a player's: its swing's marker sounds
-- (Config/Shovel.Marks), the strike's now (the hit lands on it) and the rest's that much later
local function botDug(b: Builder, mode: string)
	local name = C.Swings[mode]
	local swing, marks = (ShovelCfg :: any)[name], ShovelCfg.Marks[name]
	sendDug(b.key, b.character, marks.Strike)
	if marks.Rest then
		local humanoid = b.character:FindFirstChildOfClass("Humanoid")
		task.delay(swing.rest - swing.strike, function()
			if b.character.Parent and humanoid and humanoid.Health > 0 then
				sendDug(b.key, b.character, marks.Rest)
			end
		end)
	end
end

-- One shovel swing at `target` (a piece's model, a trench square's model or a tree's part) in `mode` ("Build" or
-- "Destroy"), no sooner than Config/Build.SwingSlack of the shortest strike gap after its last (it swings on
-- Build.nextSwing); within Config/Build.SwingReach of a piece
-- (Trench.swingReach of a square). Nil when the swing landed.
function Build.workAs(model: Model, target: Instance, mode: string): string?
	local b = bot(model)
	if not b then
		return "Not a live bot"
	end
	local before = lastSwing[model]
	if Rules.tooSoon(os.clock(), before, GAP, C.SwingSlack) then
		return "Too soon"
	end
	work(b, target, mode)
	if lastSwing[model] ~= before then
		botDug(b, mode)
		return nil
	end
	return b.said or "Nothing to work there"
end

-- when a bot's next swing of `mode` ("Build" or "Destroy") is due: a player's cadence holding the key, the first
-- (`due` nil) at the swing's strike, then one each loop (Config/Build.Swings, Rules.nextSwing)
function Build.nextSwing(mode: string, due: number?, now: number): number
	return Rules.nextSwing(ShovelCfg[C.Swings[mode]], due, now)
end

-- A built thing and the work it wants (Build.worksOf)
export type Work = {
	model: Model, -- what Build.workAs swings at
	key: string, -- its Config/Build.Pieces key ("Trench" for a trench square)
	kind: string,
	team: string,
	owner: number?, -- who laid it (a UserId or a BotId); nil for a trench square
	at: Vector3, -- where to stand near (a gun's own spot; a square's middle)
	hp: number, -- its HP now (a standing gun's: the gun's)
	max: number,
	swing: number, -- HP one Build swing of the class asked for adds (none: a soldier's of no listed class; Config/Build.Power)
	left: number, -- Build swings to full (Rules.workLeft); 0 when whole
	built: boolean, -- has stood once (a standing gun is repaired, not built)
}

-- Every piece and trench square of `team` (nil: every team's) and the work each wants of a builder of `class` (nil: a
-- soldier of no listed class)
function Build.worksOf(team: string?, class: string?): { Work }
	local out: { Work } = {}
	local power = Rules.swingPower("Build", class, C.Power)
	for _, r in recs do
		if team == nil or r.team == team then
			local hp, max = r.work, r.need
			local h = Rules.hpRules(r.piece.kind, C, r.piece)
			local swing = if h and h.swing then h.swing else 1
			local g = ArtilleryCfg.Guns[(r.piece :: any).gun or ""]
			local gunHp = r.gun and r.gun:GetAttribute("HP")
			if r.built and g and type(gunHp) == "number" then
				hp, max, swing = gunHp, g.hp, g.hp / g.repair
			end
			swing = Rules.swingWork(r.piece, swing * power)
			table.insert(out, {
				model = r.model,
				key = r.piece.key,
				kind = r.piece.kind,
				team = r.team,
				owner = r.owner,
				at = if r.at then r.at.Position else r.frame.Position,
				hp = hp,
				max = max,
				swing = swing,
				left = Rules.workLeft(hp, max, swing),
				built = r.built,
			})
		end
	end
	local T = C.Trench.hp
	for _, s in Trenches.squares(team) do
		table.insert(out, {
			model = s.model,
			key = "Trench",
			kind = "Trench",
			team = s.team,
			at = s.at,
			hp = s.hp,
			max = T.max,
			swing = T.swing * power,
			left = Rules.workLeft(s.hp, T.max, T.swing * power),
			built = s.built,
		})
	end
	return out
end

function Build.blast(position: Vector3, kg: number, key: string?)
	local S = C.Structures
	local src = Rules.structureSource(key, kg, S)
	local t0 = os.clock()
	Trenches.blast(position, src)
	Hitches.since("Blast trenches", t0)
	local cut = {}
	local worn: { { r: Rec, amount: number } } = {} -- (Hesco barriers: worn after the loop, which bursting changes)
	for _, r in recs do
		local frame = r.model:GetAttribute("Frame") :: CFrame
		if r.piece.kind == "Bridge" and r.built then
			-- by how far the blast is from its box: the deck from heap to heap, down to the trench's floor under it
			local size = r.model:GetAttribute("Size") :: Vector3
			local l = frame:PointToObjectSpace(position)
			local dx = math.max(math.abs(l.X) - size.X / 2, 0)
			local dz = math.max(math.abs(l.Z) - size.Z / 2, 0)
			local dy = math.max(l.Y - size.Y, -C.Trench.depth - l.Y, 0)
			local share = Rules.structureHit(math.sqrt(dx * dx + dy * dy + dz * dz), src, S.edge, src.bridge or 0)
			if share > 0 then
				local left, gone = Rules.bridgeHit(r.work, r.need, share)
				r.work = left
				if gone then
					table.insert(cut, r)
				else
					apply(r)
				end
			end
		elseif r.piece.kind == "Wire" then
			local l = frame:PointToObjectSpace(position)
			local dx = math.max(math.abs(l.X) - r.piece.width / 2, 0)
			local dz = math.max(math.abs(l.Z) - r.piece.depth / 2, 0)
			local d = math.sqrt(dx * dx + dz * dz + math.max(l.Y - r.piece.height, 0) ^ 2)
			local hit = r.need * Rules.structureHit(d, src, S.edge, src.wire) / 100
			if hit > 0 then
				r.work -= hit
				if r.work <= 0 then
					table.insert(cut, r)
				else
					apply(r) -- (worn low, it lies bundled on the ground)
					shakeWire(r, position)
				end
			end
		elseif
			r.piece.kind == "Sandbags"
			-- (stood: the blast hits its gun, Artillery)
			or (r.piece.kind == "Nest" and not (r.built and r.gun))
			-- (a field gun or howitzer being built, as an MG nest being built: its parts and pit go back a stage as its
			-- HP falls, at 0 it is gone; bullets don't wear it, Build.shot)
			or (r.piece.kind == "Gun" and not r.built)
		then
			-- the pile (or MG nest, or gun) by how far the blast is from its box (Destruction leaves class Sandbag to this)
			local p = r.piece
			local l = frame:PointToObjectSpace(position)
			local d = Vector3.new(
				math.max(math.abs(l.X) - p.width / 2, 0),
				math.max(l.Y - p.height, -l.Y, 0),
				math.max(math.abs(l.Z) - p.depth / 2, 0)
			).Magnitude
			local share = Rules.structureHit(d, src, S.edge)
			if share > 0 then
				table.insert(worn, { r = r, amount = r.need * share / 100 })
			end
		elseif r.piece.kind == "Dugout" then
			-- by how far the blast is from its slot or room (Rules.dugoutDistance); Dugout.soak of a sandbag pile's share
			local l = r.frame:PointToObjectSpace(position)
			local d = Rules.dugoutDistance(l.X, l.Y, l.Z, r.piece, C.Dugout, C.Trench.depth)
			local share = Rules.structureHit(d, src, S.edge) * C.Dugout.soak
			if share > 0 then
				table.insert(worn, { r = r, amount = r.need * share / 100 })
			end
		elseif r.piece.kind == "Hesco" then
			-- the whole basket by how far the blast is from its box, Hesco.soak of a sandbag column's share
			local p = r.piece
			local l = frame:PointToObjectSpace(position)
			local d = Vector3.new(
				math.max(math.abs(l.X) - p.width / 2, 0),
				math.max(l.Y - p.height, -l.Y, 0),
				math.max(math.abs(l.Z) - p.depth / 2, 0)
			).Magnitude
			local share = Rules.structureHit(d, src, S.edge) * C.Hesco.soak
			if share > 0 then
				table.insert(worn, { r = r, amount = r.need * share / 100 })
			end
		end
	end
	for _, r in cut do
		remove(r) -- (at 0 it is simply gone)
	end
	for _, w in worn do
		wear(w.r, w.amount)
	end
	-- and a piece whose ground the crater took from under it is gone, never left hanging (Config/Build.Support)
	local t1 = os.clock()
	local SUP = C.Support
	for _, r in recs do
		local laid = r.laid
		if laid and recs[r.model] and (r.frame.Position - position).Magnitude < SUP.reach then
			if not Rules.supported(laid, Survey.ground(r.piece, r.frame).heights, SUP.gap, SUP.share) then
				remove(r)
			end
		end
	end
	Hitches.since("Blast support", t1)
end

-- A bullet meeting `part` at `point` (src/server/Firing): a trench square (a piece, or the ground in it) or a sandbag
-- pile loses Structures.bullet
function Build.shot(part: Instance, point: Vector3)
	-- (a dugout's seal is the ground it fills: shot as the ground; a colliding part is always met, CanQuery or not)
	if part:GetAttribute("Seal") then
		Trenches.shot(workspace.Terrain, point)
		return
	end
	if Trenches.shot(part, point) then
		return
	end
	local s = part.Parent
	-- a dugout's plates (they lie in its model; its meshes stop nothing)
	local dug = if s and s:IsA("Model") then recs[s] else nil
	if dug and dug.piece.kind == "Dugout" then
		wear(dug, dug.need * C.Structures.bullet.hit * C.Dugout.soak / 100)
		return
	end
	local pile = if s and s:IsA("Model") and s:GetAttribute("Class") == "Sandbag" then recs[s.Parent :: Model] else nil
	if pile then
		wear(pile, pile.need * C.Structures.bullet.hit / 100)
		return
	end
	-- a Hesco barrier's dirt (the only piece of it a bullet meets): `s` its stage's holder ("Stage<s>"), in the
	-- piece's model
	local model = s and s.Parent
	local r = if model and model:IsA("Model") then recs[model] else nil
	if r and r.piece.kind == "Hesco" then
		wear(r, r.need * C.Structures.bullet.hit * C.Hesco.soak / 100)
	end
end

-- Whether a soldier with their torso at `at` is sheltered from a blast at `blast` (src/server/Damage.blast): in the room
-- of a dugout that has stood (Rules.dugoutShelters) and the blast outside it (user 2026-11-02: "anything above them
-- should not hurt them"). A blast in the room (a grenade down the steps) hurts as any other.
function Build.sheltered(at: Vector3, blast: Vector3): boolean
	for _, r in recs do
		local p = r.piece
		if p.kind == "Dugout" and Rules.dugoutShelters(r.work, r.built) then
			local a, b = r.frame:PointToObjectSpace(at), r.frame:PointToObjectSpace(blast)
			if Rules.inDugout(a.X, a.Y, a.Z, p, C.Dugout) and not Rules.inDugout(b.X, b.Y, b.Z, p, C.Dugout) then
				return true
			end
		end
	end
	return false
end

-- whether `p` is on a dugout's ground (its steps and room and Config/Build.Dugout.ground round them): craters never
-- carve it (src/server/Ground.guard)
function Build.onDugout(p: Vector3): boolean
	for _, r in recs do
		if r.piece.kind == "Dugout" then
			local l = r.frame:PointToObjectSpace(p)
			local g = C.Dugout.ground
			local run = C.Dugout.stair + r.piece.depth
			if math.abs(l.X) <= r.piece.width / 2 + g and l.Z >= -g and l.Z <= run + g then
				return true
			end
		end
	end
	return false
end

-- the barbed wire that stands: its box (centre frame and size), its team and model, for src/server/Wire
export type WireBox = { frame: CFrame, size: Vector3, team: string, model: Model }
-- whether `p` is on an MG nest's ground (its footprint round the ring's middle and Config/Build.Nest.ground round it,
-- from the moment it is laid): craters never carve it (src/server/Ground.guard; user 2026-10-29: "similarily to the
-- artilierries, give the turret some ground. the ground beneath it shouldnt be be to be destroyed")
function Build.onNest(p: Vector3): boolean
	for _, r in recs do
		if r.piece.kind == "Nest" then
			local l = r.frame:PointToObjectSpace(p)
			if Rules.onFootprint(l.X, l.Z, r.piece.width, r.piece.depth, C.Nest.ground) then
				return true
			end
		end
		-- a gun's sandbag ring (Config/Build.GunRing `ground`): the band its bags stand on, not the pit inside it
		local n = r.piece.ring and C.GunRing[r.piece.ring]
		if n and r.at and Rules.onRing(r.at:PointToObjectSpace(p), n) then
			return true
		end
	end
	return false
end

-- how high the ground may stand at `p` on an MG nest's ground: a little (Config/Build.Nest.heap) over how it lay when
-- the nest was laid (user 2026-10-29: "dont allow the turret to be fully submerged in terrain. only a little for
-- visual"); nil off its ground
function Build.nestCeiling(p: Vector3): number?
	for _, r in recs do
		local tops = r.nestTops
		if r.piece.kind == "Nest" and tops then
			local l = r.frame:PointToObjectSpace(p)
			local top = tops[Ground.column(p)]
			if top and Rules.onFootprint(l.X, l.Z, r.piece.width, r.piece.depth, C.Nest.ground) then
				return top + C.Nest.heap
			end
		end
	end
	return nil
end

-- whether `p` is on a Hesco barrier's ground (its footprint and Config/Build.Hesco.ground round it): craters never carve
-- it (src/server/Ground.guard); the barrier takes the blast (Build.blast)
function Build.onHesco(p: Vector3): boolean
	for _, r in recs do
		if r.piece.kind == "Hesco" then
			local l = r.frame:PointToObjectSpace(p)
			if Rules.onFootprint(l.X, l.Z, r.piece.width, r.piece.depth, C.Hesco.ground) then
				return true
			end
		end
	end
	return false
end

function Build.wires(): { WireBox }
	local out = {}
	for _, r in recs do
		if r.piece.kind == "Wire" and r.model:GetAttribute("Armed") == true then
			local p = r.piece
			local frame = r.model:GetAttribute("Frame") :: CFrame
			table.insert(out, {
				frame = frame * CFrame.new(0, p.height / 2, 0),
				size = Vector3.new(p.width, p.height + 3, p.depth),
				team = r.team,
				model = r.model,
			})
		end
	end
	return out
end

-- whether a trench ever touched voxel `key` ("x,y,z" in voxel units): src/server/Ground never refills it
function Build.dug(key: string): boolean
	return Trenches.dug(key)
end

-- whether `p` is within `extra` of a trench's ground (src/server/Ground keeps craters off it)
function Build.nearTrench(p: Vector3, extra: number): boolean
	return Trenches.near(p, extra)
end

-- Removes every piece and trench (dev: the admin panel's undo)
function Build.clear()
	local list = {}
	for _, r in recs do
		table.insert(list, r)
	end
	for _, r in list do
		remove(r)
	end
	Trenches.clear()
end

-- a player's shovel swing's sound (Net "Dug"), passed on to everyone else
local function dug(player: Player, kind: any)
	if kind ~= "Dig" and kind ~= "Toss" and kind ~= "Chip" then
		return
	end
	local b = soldier(player, true)
	if b then
		sendDug(player, b.character, kind, player)
	end
end

function Build.start(artillery: Guns)
	guns = artillery
	folder()
	Trenches.start()
	Ground.guard(Build.onHesco)
	Ground.guard(Build.onNest)
	Ground.guard(Build.onDugout)
	Ground.ceiling(Build.nestCeiling)
	Net.event("Dug").OnServerEvent:Connect(dug)
	Net.event("Build").OnServerEvent:Connect(function(player: Player, kind: any, a: any, b: any)
		local builder = soldier(player, true)
		if not builder then
			return
		end
		if kind == "Place" then
			place(builder, a, b)
		elseif kind == "Plan" then
			plan(builder, a, b)
		elseif kind == "Work" then
			work(builder, a, b)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		lastSound[player] = nil
	end)
	-- blueprints nobody worked on
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			local stale = {}
			for _, r in recs do
				-- (a bridge is laid at stage 1: untouched while it has no more HP than that and was never whole)
				local fresh = if r.piece.kind == "Bridge"
					then r.work <= C.Bridge.hp.place and not r.paid
					else r.work <= 0 and not r.built
				if fresh and now - r.worked > C.BlueprintLife then
					table.insert(stale, r)
				end
			end
			for _, r in stale do
				remove(r)
			end
		end
	end)
end

return Build
