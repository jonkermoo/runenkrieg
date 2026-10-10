--!strict
-- Dev-only natural building generator (templates in Config/Buildings, style in docs/ART_STYLE.md).
--   Buildings.build(name, deps) -> Model at the origin (ground = y 0, front faces -Z), unpainted roles
--   Buildings.paint(model, template, scheme, palette) -> colors every part by its "Paint" role
-- Every building: windows on every wall of every story, openable doors (ProximityPrompt; server
-- src/server/Doors), floors on every level, destructible sections (docs/DESTRUCTION.md).

local CollectionService = game:GetService("CollectionService")

local Geometry = require(script.Geometry)

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
		CFrame.new(0, (floorTop - 1 - 10) / 2, 0),
		Vector3.new(W + 0.6, floorTop - 1 + 10, Dp + 0.6),
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
		local walls = {
			{
				"front",
				CFrame.new(0, y, -Dp / 2 + T / 2),
				W,
				ends(W, W / 2),
				if story == 0 then frontDoors else nil,
				2,
			},
			{ "back", CFrame.new(0, y, Dp / 2 - T / 2) * CFrame.Angles(0, math.pi, 0), W, ends(W, W / 2), nil, 2 },
			{
				"left",
				CFrame.new(-W / 2 + T / 2, y, 0) * CFrame.Angles(0, math.pi / 2, 0),
				sideL,
				ends(sideL, Dp / 2),
				nil,
				1,
			},
			{
				"right",
				CFrame.new(W / 2 - T / 2, y, 0) * CFrame.Angles(0, -math.pi / 2, 0),
				sideL,
				ends(sideL, Dp / 2),
				nil,
				1,
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
			local hole = Geometry.stairs(model, ctx, cf, W, Dp, y - H, H, story - 1)
			for _, r in Geometry.rectMinusHole(inner, hole) do
				Geometry.slab(model, ctx, cf, r, y, "Floor", story, "Floor")
			end
		end
	end
	for story, n in wallCounts do
		model:SetAttribute("WallCount_" .. story, n)
	end
	local wallTop = floorTop + t.stories * H
	if t.quoins then
		Geometry.quoins(model, ctx, W, Dp, floorTop + 0.5, floorTop + t.stories * H)
	end
	-- ceiling: every level has a floor, including the attic floor under the roof
	Geometry.slab(model, ctx, cf, inner, wallTop, "Floor", t.stories, "Floor")
	return floorTop, wallTop
end

local function roofAndExtras(model: Model, t: any, ctx: Geometry.Ctx, wallTop: number)
	local W, Dp = t.width, t.depth
	local T = ctx.T
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

	local _, wallTop = shell(model, t, ctx, deps)
	roofAndExtras(model, t, ctx, wallTop)
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
	}
	local door = rgb(P.Doors[scheme.door])
	colors.DoorDark = Color3.new(door.R * 0.86, door.G * 0.86, door.B * 0.86)
	local jit = P.ToneJitter or 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Paint")
			local c = role and colors[role]
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
