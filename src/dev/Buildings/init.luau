--!strict
-- Dev-only natural building generator (templates in Config/Buildings, style in docs/ART_STYLE.md).
--   Buildings.build(name, deps) -> Model at the origin (ground = y 0, front faces -Z), unpainted roles
--   Buildings.paint(model, template, scheme, palette) -> colors every part by its "Paint" role
-- Every building: windows on every wall of every story, openable doors (ProximityPrompt; server
-- src/server/Doors), floors on every level, destructible sections (docs/DESTRUCTION.md).

local CollectionService = game:GetService("CollectionService")

local Geometry = require(script.Geometry)

local Buildings = {}

type Deps = { B: any, D: any, M: any }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Window/door plan for one wall of one story. sections = widths; doorIndex = the center section.
local function plan(
	t: any,
	M: any,
	side: string,
	story: number,
	n: number,
	doorIndex: number?
): { [number]: Geometry.Opening? }
	local Bm = M.Building
	local tw = t.window or { w = 3, bottom = Bm.WindowSill, top = Bm.WindowTop }
	local win: Geometry.Opening = { kind = "window", w = tw.w, bottom = tw.bottom, top = tw.top }
	local out: { [number]: Geometry.Opening? } = {}
	if side == "front" then
		for i = 1, n do
			if story == 0 and i == doorIndex then
				out[i] = { kind = "door", w = Bm.DoorWidth, bottom = 0, top = Bm.DoorHeight }
			elseif story > 0 then
				if n <= 2 or (i > 1 and i < n) then
					out[i] = win
				end
			elseif (i - (doorIndex or 0)) % 2 == 1 then
				out[i] = win
			end
		end
	elseif side == "back" then
		for i = 1, n do
			if story == 0 and t.backDoor and i == 1 then
				-- section 1 of the back wall is the building's +X end (the back frame is rotated 180),
				-- past the end of the stair flight, which starts at -X
				out[i] = { kind = "door", w = Bm.DoorWidth, bottom = 0, top = Bm.DoorHeight }
			elseif i % 2 == 0 or n <= 2 then
				out[i] = win
			end
		end
	else
		for i = 1, n do
			if n <= 2 or i == math.floor(n / 2) + 1 then
				out[i] = win
			end
		end
	end
	return out
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
		CFrame.new(0, (floorTop - 1 - 4) / 2, 0),
		Vector3.new(W + 0.6, floorTop - 1 + 4, Dp + 0.6),
		"Foundation"
	)
	Geometry.slab(model, ctx, cf, { -W / 2, W / 2, -Dp / 2, Dp / 2 }, floorTop, "Floor", -1, "Floor")
	Geometry.plinth(model, ctx, W, Dp, floorTop + 0.5)

	local wallCounts = {}
	local inner = { -W / 2 + T, W / 2 - T, -Dp / 2 + T, Dp / 2 - T }
	for story = 0, t.stories - 1 do
		local y = floorTop + story * H
		local frontW = M.Building.DoorWidth + 1
		local frontSections, doorIndex = Geometry.layout(W, D.SectionWidth, if story == 0 then frontW else nil)
		local backSections = Geometry.layout(W, D.SectionWidth)
		local sideSections = Geometry.layout(Dp - 2 * T, D.SectionWidth)
		local walls = {
			{ "front", CFrame.new(0, y, -Dp / 2 + T / 2), frontSections },
			{ "back", CFrame.new(0, y, Dp / 2 - T / 2) * CFrame.Angles(0, math.pi, 0), backSections },
			{ "left", CFrame.new(-W / 2 + T / 2, y, 0) * CFrame.Angles(0, math.pi / 2, 0), sideSections },
			{ "right", CFrame.new(W / 2 - T / 2, y, 0) * CFrame.Angles(0, -math.pi / 2, 0), sideSections },
		}
		local count = 0
		for _, w in walls do
			local secs = w[3]
			Geometry.wall(
				model,
				ctx,
				cf * w[2],
				H,
				story,
				secs,
				plan(t, M, w[1], story, #secs, if w[1] == "front" then doorIndex else nil)
			)
			count += #secs
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
