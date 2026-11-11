--!strict
-- Dev-only natural building generator (templates in Config/Buildings, style in docs/ART_STYLE.md).
--   Buildings.build(name, deps) -> Model at the origin (ground = y 0, front faces -Z), unpainted roles
--   Buildings.paint(model, template, scheme, palette) -> colors every part by its "Paint" role
-- Every building: windows on every wall of every story, openable doors (ProximityPrompt; server
-- src/server/Doors), floors on every level, destructible sections (docs/DESTRUCTION.md).

local CollectionService = game:GetService("CollectionService")

local Geometry = require(script.Geometry)
local Interior = require(script.Interior)

local Buildings = {}

type Deps = { B: any, D: any, M: any, O: any } -- O = Rules/Openings

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Walls (with windows + doors), floors, stairs and ceiling.
local function shell(model: Model, t: any, ctx: Geometry.Ctx, deps: Deps): (number, number)
	local B, D, M = deps.B, deps.D, deps.M
	local W, Dp = t.width, t.depth
	local H = t.storyHeight or M.Building.StoryHeight
	local T = ctx.T
	local cf = CFrame.identity
	local floorTop = B.Foundation

	Geometry.part(
		model,
		ctx,
		"Foundation",
		-- deep foundation: placed copies sit on the highest ground under the footprint (uneven terrain)
		CFrame.new(0, (floorTop - 1 - B.FoundationDepth) / 2, 0),
		Vector3.new(W + 0.6, floorTop - 1 + B.FoundationDepth, Dp + 0.6),
		"Foundation"
	)
	Geometry.slab(model, ctx, cf, { -W / 2, W / 2, -Dp / 2, Dp / 2 }, floorTop, "Floor", -1, "Floor")
	Geometry.plinth(model, ctx, W, Dp, floorTop + 0.5)

	local wallCounts = {}
	local inner = { -W / 2 + T, W / 2 - T, -Dp / 2 + T, Dp / 2 - T }
	for story = 0, t.stories - 1 do
		local y = floorTop + story * H
		local Bm = M.Building
		local ocfg = { margin = B.OpeningMargin, post = B.FramePost, sectionWidth = D.SectionWidth }
		local heights = { door = { 0, Bm.DoorHeight }, window = { Bm.WindowSill, Bm.WindowTop } }
		-- keep-outs (wall-local u, symmetric): corner quoins, and the chimney breast on its gable
		local function ends(L: number, cornerAt: number): { { number } }
			if not t.quoins then
				return {}
			end
			local inward = cornerAt + 0.25 - B.Quoin.long -- inner edge of the quoins along this wall
			return { { -L / 2, -inward }, { inward, L / 2 } }
		end
		local sideL = Dp - 2 * T
		local frontDoors = {}
		for _, d in t.doors or { { center = 0 } } do
			table.insert(frontDoors, { center = d.center, w = d.w or Bm.DoorWidth, h = d.h or Bm.DoorHeight })
		end
		-- (a list of back doors takes the usual door size wherever it gives none, as the front and upper doors do)
		local backDoors = nil
		if type(t.backDoor) == "table" then
			backDoors = {}
			for _, d in t.backDoor do
				table.insert(backDoors, { center = d.center, w = d.w or Bm.DoorWidth, h = d.h or Bm.DoorHeight })
			end
		end
		local upperDoors = nil
		if t.upperDoors then
			upperDoors = {}
			for _, d in t.upperDoors do
				table.insert(upperDoors, { center = d.center, w = d.w or Bm.DoorWidth, h = d.h or Bm.DoorHeight })
			end
		end
		local walls = {
			{
				"front",
				CFrame.new(0, y, -Dp / 2 + T / 2),
				W,
				ends(W, W / 2),
				-- (story 1 may have doors too: out onto a loggia over a portico, the cascina's)
				if story == 0 then frontDoors elseif story == 1 then upperDoors else nil,
				t.windows or 2,
			},
			{
				"back",
				CFrame.new(0, y, Dp / 2 - T / 2) * CFrame.Angles(0, math.pi, 0),
				W,
				ends(W, W / 2),
				-- a back door (a church porch's, opening on the nave's front door behind it), or a list of them (an inn's
				-- cart arch through to the yard)
				if story == 0 and t.backDoor
					then (if backDoors then backDoors else { { center = 0, w = Bm.DoorWidth, h = Bm.DoorHeight } })
					else nil,
				t.windows or 2,
			},
			{
				"left",
				CFrame.new(-W / 2 + T / 2, y, 0) * CFrame.Angles(0, math.pi / 2, 0),
				sideL,
				ends(sideL, Dp / 2),
				if (story == 0 and t.leftDoor) or (story == 1 and t.upperDoor == "left")
					then { { center = 0, w = Bm.DoorWidth, h = Bm.DoorHeight } }
					else nil,
				t.windows or 1,
			},
			{
				"right",
				CFrame.new(W / 2 - T / 2, y, 0) * CFrame.Angles(0, -math.pi / 2, 0),
				sideL,
				ends(sideL, Dp / 2),
				-- (an upper door on a gable: VillageBuild's steps down from it make an outside stair)
				if (story == 0 and t.rightDoor) or (story == 1 and t.upperDoor == "right")
					then { { center = 0, w = Bm.DoorWidth, h = Bm.DoorHeight } }
					else nil,
				t.windows or 1,
			},
		}
		if t.gableChimney then
			local w = if t.gableChimney < 0 then walls[3] else walls[4]
			table.insert(w[4], { -2.1, 2.1 }) -- chimney breast is 4.2 wide, centered on the gable
		end
		local count = 0
		for _, w in walls do
			local sections = deps.O.layout(w[3], w[4], w[5], Bm.WindowWidth, w[6], ocfg)
			Geometry.wall(model, ctx, cf * w[2], H, story, sections, heights)
			count += #sections
		end
		wallCounts[story] = count
		if story >= 1 then
			-- (flights alternate back and front, so a tower's stack of stairs never runs into the hole above it)
			local hole = Geometry.stairs(model, ctx, cf, W, Dp, y - H, H, story - 1, (story - 1) % 2 == 1)
			for _, r in Geometry.rectMinusHole(inner, hole) do
				Geometry.slab(model, ctx, cf, r, y, "Floor", story, "Floor")
			end
		end
	end
	for story, n in wallCounts do
		model:SetAttribute("WallCount_" .. story, n)
	end
	-- the furniture (t.interior): tables and benches, beds, pillars, stalls...
	Interior.build(model, ctx, t, floorTop, H)
	local wallTop = floorTop + t.stories * H
	if t.quoins then
		Geometry.quoins(model, ctx, W, Dp, floorTop + 0.5, floorTop + t.stories * H)
	end
	-- ceiling: every level has a floor, including the attic floor under the roof; a climbable top (a tower's roof walk)
	-- gets one more flight up through it
	if t.climb then
		local top = t.stories - 1
		local hole = Geometry.stairs(model, ctx, cf, W, Dp, floorTop + top * H, H, top, top % 2 == 1)
		for _, r in Geometry.rectMinusHole(inner, hole) do
			Geometry.slab(model, ctx, cf, r, wallTop, "Floor", t.stories, "Floor")
		end
	else
		Geometry.slab(model, ctx, cf, inner, wallTop, "Floor", t.stories, "Floor")
	end
	return floorTop, wallTop
end

local function roofAndExtras(model: Model, t: any, ctx: Geometry.Ctx, wallTop: number)
	local W, Dp = t.width, t.depth
	local T = ctx.T
	if t.roofStyle == "Battlement" then
		Geometry.battlement(model, ctx, W, Dp, wallTop)
		return 0
	end
	for _, side in { -1, 1 } do
		local frame = CFrame.new(side * (W / 2 - T / 2), wallTop, 0) * CFrame.Angles(0, math.pi / 2, 0)
		Geometry.gable(model, ctx, frame, Dp, (Dp / 2) * math.tan(math.rad(t.roofPitch)), t.stories)
	end
	local ridge = Geometry.roof(model, ctx, CFrame.identity, W, Dp, wallTop, t.roofPitch, t.roofStyle)
	if t.gableChimney then
		Geometry.gableChimney(model, ctx, t.gableChimney, W, -1, wallTop, wallTop + ridge)
	end
	for _, fx in t.chimneys or {} do
		Geometry.chimney(model, ctx, CFrame.identity, fx * (W / 2 - 2), Dp / 5, wallTop - 2, wallTop + ridge + 3.5)
	end
	return ridge
end

function Buildings.build(name: string, deps: Deps): Model
	local t = deps.B.Templates[name]
	assert(t, "unknown template " .. name)
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Template", name)
	model:SetAttribute("Natural", true)
	model:SetAttribute("Repairable", deps.D.NaturalRepairable)
	CollectionService:AddTag(model, deps.D.BuildingTag)
	local ctx: Geometry.Ctx =
		{ D = deps.D, M = deps.M, B = deps.B, T = t.wallThickness or deps.B.WallThickness, class = t.class, count = 0 }

	if t.blocks then
		-- a landmark: several blocks (a church's nave, tower and porch), each built like a building of its own and
		-- moved to its place in the template's footprint, plus its features. One building for destruction: the blocks'
		-- walls are counted together per story.
		local counts = {}
		for i, b in t.blocks do
			local sub = Instance.new("Model")
			sub.Name = b.name or `Block{i}`
			ctx.T = b.wallThickness or t.wallThickness or deps.B.WallThickness
			ctx.class = b.class or t.class
			ctx.wallKey, ctx.roofKey = b.wall, b.roof
			local _, wallTop = shell(sub, b, ctx, deps)
			roofAndExtras(sub, b, ctx, wallTop)
			for key, n in sub:GetAttributes() do
				if string.match(key, "^WallCount_") then
					counts[key] = (counts[key] or 0) + n
					sub:SetAttribute(key, nil)
				end
			end
			-- (a new Model's pivot is its bounding box's centre: put it back on the block's ground first, or the block
			-- sinks by half its height)
			sub.WorldPivot = CFrame.identity
			sub:PivotTo(CFrame.new(b.x, 0, b.z) * CFrame.Angles(0, math.rad(b.yaw or 0), 0))
			sub.Parent = model
		end
		ctx.wallKey, ctx.roofKey = nil, nil
		for key, n in counts do
			model:SetAttribute(key, n)
		end
		for _, f in t.features or {} do
			local at = CFrame.new(f.x, 0, f.z) * CFrame.Angles(0, math.rad(f.yaw or 0), 0)
			if f.kind == "Graves" then
				Geometry.graves(model, ctx, at, f.count, f.gap)
			elseif f.kind == "Lychgate" then
				Geometry.lychgate(model, ctx, at, f.width)
			elseif f.kind == "Sign" then
				Geometry.sign(model, ctx, at, f.height)
			elseif f.kind == "Kiln" then
				Geometry.kiln(model, ctx, at, f.radius, f.height, f.cone)
			elseif f.kind == "HayBarn" then
				Geometry.hayBarn(model, ctx, at, f.length, f.span, f.height)
			elseif f.kind == "Wall" then
				Geometry.yardWall(model, ctx, f.a, f.b, f.height, f.thick, f.swatch)
			elseif f.kind == "Beacon" then
				Geometry.beacon(model, ctx, at)
			elseif f.kind == "BottleKiln" then
				Geometry.bottleKiln(model, ctx, at, f.radius, f.height)
			elseif f.kind == "Canopy" then
				Geometry.canopy(model, ctx, at, f.length, f.depth, f.height)
			elseif f.kind == "Platform" then
				Geometry.platform(model, ctx, at, f.length, f.depth, f.height)
			elseif f.kind == "WaterTower" then
				Geometry.waterTower(model, ctx, at, f.size, f.height)
			elseif f.kind == "Signal" then
				Geometry.signal(model, ctx, at, f.height)
			elseif f.kind == "Lattice" then
				Geometry.lattice(model, ctx, at * CFrame.new(0, f.y, 0), f.width, f.height)
			elseif f.kind == "Tent" then
				Geometry.tent(model, ctx, at, f.length, f.width, f.height, f.canvas)
			elseif f.kind == "Crates" then
				Geometry.crates(model, ctx, at, f.count)
			elseif f.kind == "Landing" then
				Geometry.landing(model, ctx, at, f.length, f.depth, f.steps)
			elseif f.kind == "Boat" then
				Geometry.boat(model, ctx, at, f.length)
			elseif f.kind == "Arcade" then
				local y = CFrame.new(0, f.y or 0, 0)
				Geometry.arcade(model, ctx, at * y, f.length, f.depth, f.height, f.bays, f.raised, f.roof)
			elseif f.kind == "Stage" then
				Geometry.stage(model, ctx, at, f.width, f.depth, f.height, f.posts)
			elseif f.kind == "Waterwheel" then
				Geometry.waterwheel(model, ctx, at * CFrame.new(0, f.y, 0), f.radius, f.width)
			elseif f.kind == "Smokestack" then
				Geometry.smokestack(model, ctx, at, f.base, f.top, f.height)
			elseif f.kind == "RingKiln" then
				Geometry.ringKiln(model, ctx, at, f.length, f.depth, f.height, f.bays)
			elseif f.kind == "DryingShed" then
				Geometry.dryingShed(model, ctx, at, f.length, f.span, f.height)
			elseif f.kind == "ClayPit" then
				Geometry.clayPit(model, ctx, at, f.length, f.width, f.depth)
			elseif f.kind == "BellTower" then
				Geometry.bellTower(model, ctx, at, f.width, f.from, f.height)
			elseif f.kind == "Facade" then
				Geometry.facade(model, ctx, at, f.width, f.height, f.pitch)
			elseif f.kind == "Fountain" then
				Geometry.fountain(model, ctx, at, f.radius)
			elseif f.kind == "GateTower" then
				Geometry.gateTower(model, ctx, at, f.width, f.depth, f.height, f.way)
			elseif f.kind == "TownWall" then
				Geometry.townWall(model, ctx, at, f.thick, f.pieces, f.tower)
			elseif f.kind == "LatticeTower" then
				Geometry.latticeTower(model, ctx, at, f.base, f.top, f.height, f.stages)
			elseif f.kind == "LanternString" then
				Geometry.lanternString(model, ctx, at, f.from, f.to, f.up)
			elseif f.kind == "Stall" then
				Geometry.stall(model, ctx, at, f.length, f.depth)
			elseif f.kind == "Carousel" then
				Geometry.carousel(model, ctx, at, f.radius)
			else
				error(`unknown landmark feature {f.kind}`)
			end
		end
	else
		local _, wallTop = shell(model, t, ctx, deps)
		roofAndExtras(model, t, ctx, wallTop)
	end
	model.WorldPivot = CFrame.identity
	model:SetAttribute("PartCount", ctx.count)
	return model
end

-- Color every part by its Paint role. scheme = Rules/Destruction.scheme(template, palette, seed).
function Buildings.paint(model: Instance, scheme: any, palette: any)
	local P = palette.Buildings
	local colors = {
		Wall = rgb(P.Walls[scheme.wall]),
		Roof = rgb(P.Roofs[scheme.roof]),
		Trim = rgb(P.Trim[scheme.trim]),
		Door = rgb(P.Doors[scheme.door]),
		Glass = rgb(P.Glass),
		Floor = rgb(P.Floor),
		Stairs = rgb(P.Stairs),
		Foundation = rgb(P.Foundation),
		Chimney = rgb(P.Chimney),
		Metal = rgb(P.Metal),
		Sign = rgb(P.Sign),
		Wood = rgb(P.Wood),
		Quoin = rgb(P.Quoin),
		Linen = rgb(P.Linen),
		Cloth = rgb(P.Cloth),
		Hay = rgb(P.Hay),
	}
	local door = rgb(P.Doors[scheme.door])
	colors.DoorDark = Color3.new(door.R * 0.86, door.G * 0.86, door.B * 0.86)
	local jit = P.ToneJitter or 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Paint")
			local c = role and colors[role]
			-- a landmark block's own colour (Geometry.part's Swatch: a stable's tarred boards beside a whitewashed inn)
			local swatch = d:GetAttribute("Swatch")
			if swatch and role == "Wall" and P.Walls[swatch] then
				c = rgb(P.Walls[swatch])
			elseif swatch and role == "Roof" and P.Roofs[swatch] then
				c = rgb(P.Roofs[swatch])
			elseif swatch and role == "Festival" and P.Festival[swatch] then
				c = rgb(P.Festival[swatch]) -- a festival stage's canvas, rune paint and lanterns
			end
			if c then
				-- hand-made look: each piece a few % lighter/darker (deterministic Tone from generation)
				local k = 1 + jit * (d:GetAttribute("Tone") or 0)
				d.Color = Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
			end
		end
	end
	model:SetAttribute("Scheme", `{scheme.wall}/{scheme.roof}/{scheme.trim}/{scheme.door}`)
end

return Buildings
