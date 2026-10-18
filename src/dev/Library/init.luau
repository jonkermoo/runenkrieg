--!strict
-- Dev-only asset library tools (dev place only). From the Studio command bar / MCP:
--   require(game.ServerStorage.Dev.Library:Clone()).sync()
-- 1. Mirrors Config/Assets.Entries into ReplicatedStorage.Assets.<Category>.<Folder>.<EntryName>
--    (loads new or changed ids via InsertService; unchanged entries are kept).
-- 2. Rebuilds Workspace.DevGallery: every library asset on a labeled pad, far outside the map (helmets worn on the
--    preview hair, helmet on + shot off: src/dev/HairPreview).
-- Saved with the place; Rojo does not manage ReplicatedStorage.Assets or the gallery.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Library = {}

local DEV_PLACE_ID = 103459731368962
local GALLERY_ORIGIN = Vector3.new(0, 0, -2600) -- beyond the map skirt and the fog
local PAD_GAP = 12

local function fresh(module: Instance): any
	return require(module:Clone() :: ModuleScript)
end

local function shared(): Instance
	return ReplicatedStorage:WaitForChild("Shared")
end

local function folder(parent: Instance, name: string): Instance
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Instance
end

-- A folder path inside `parent`: "Gear/Olive/Helmets" nests (Config/Assets `folder`), made as needed.
local function path(parent: Instance, p: string): Instance
	local f = parent
	for _, name in string.split(p, "/") do
		f = folder(f, name)
	end
	return f
end

-- The same path if it exists, else nil.
local function find(parent: Instance?, p: string): Instance?
	local f = parent
	for _, name in string.split(p, "/") do
		f = f and f:FindFirstChild(name)
	end
	return f
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Art rule: every library mesh is anchored SmoothPlastic (colors are applied where it's used).
local function normalize(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Material = Enum.Material.SmoothPlastic
		end
	end
end

-- The library model for one registry entry, loading it if missing or out of date.
function Library.ensure(entryName: string): Model
	assert(game.PlaceId == DEV_PLACE_ID, "Library tools only run in the DEV place")
	local A = fresh(shared().Config.Assets)
	local e = A.Entries[entryName]
	assert(e, "unknown asset entry " .. entryName)
	local root = folder(ReplicatedStorage, "Assets")
	local target = path(folder(root, e.category), e.folder)
	local existing = target:FindFirstChild(entryName)
	if e.uniform then
		-- a uniform: the team's Shirt + Pants (Config/Uniforms image ids), rebuilt from config every sync
		if existing then
			existing:Destroy()
		end
		local kit = fresh(shared().Config.Uniforms).Kits[e.uniform]
		local model = Instance.new("Model")
		model.Name = entryName
		local shirt = Instance.new("Shirt")
		shirt.ShirtTemplate = "rbxassetid://" .. tostring(kit.shirt)
		shirt.Parent = model
		local pants = Instance.new("Pants")
		pants.PantsTemplate = "rbxassetid://" .. tostring(kit.pants)
		pants.Parent = model
		model:SetAttribute("Procedural", true)
		model:SetAttribute("Source", e.source)
		model:SetAttribute("Description", e.description)
		model.Parent = target
		return model
	end
	if e.prop then
		if existing then
			existing:Destroy()
		end
		local Props = fresh(ServerStorage:WaitForChild("Dev"):WaitForChild("Props"))
		local model = Props.build(e.prop, { P = fresh(shared().Config.Props), D = fresh(shared().Config.Destruction) })
		Props.paint(model, fresh(shared().Config.Palette))
		model.Name = entryName
		model:SetAttribute("Procedural", true)
		model:SetAttribute("Description", e.description)
		model.Parent = target
		return model
	end
	if e.template then
		-- procedural: always rebuilt from code + config so the library matches the repo
		if existing then
			existing:Destroy()
		end
		local Buildings = fresh(ServerStorage:WaitForChild("Dev"):WaitForChild("Buildings"))
		local deps = {
			B = fresh(shared().Config.Buildings),
			D = fresh(shared().Config.Destruction),
			M = fresh(shared().Config.Metrics),
			O = fresh(shared().Rules.Openings),
		}
		local model = Buildings.build(e.template, deps)
		model.Name = entryName
		model:SetAttribute("Procedural", true)
		model:SetAttribute("Description", e.description)
		model.Parent = target
		return model
	end
	if existing and existing:GetAttribute("AssetId") == e.id then
		return existing :: Model
	end
	if existing then
		existing:Destroy()
	end
	local loaded = InsertService:LoadAsset(e.id :: number)
	local model = (loaded:FindFirstChildWhichIsA("Model") or loaded) :: Model
	model.Name = entryName
	model:SetAttribute("AssetId", e.id)
	model:SetAttribute("Source", e.source)
	model:SetAttribute("Description", e.description)
	normalize(model)
	model.Parent = target
	if model ~= loaded then
		loaded:Destroy()
	end
	return model
end

local function label(parent: BasePart, text: string, offsetY: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 46)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 400
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.TextScaled = true
	t.Font = Enum.Font.GothamMedium
	t.Text = text
	t.Parent = gui
	gui.Parent = parent
end

-- Preview colors for the gallery only (real colors are applied by the systems that place assets).
local function previewColor(d: BasePart, palette: any)
	local n = d.Name
	if string.find(n, "Canopy") then
		d.Color = rgb(if string.find(n, "Pine") then palette.Trees.Pine[1] else palette.Trees.Broadleaf[1])
	elseif string.find(n, "Trunk") then
		d.Color = rgb(if string.find(n, "Birch") then palette.Trees.BirchBark else palette.Trees.Bark)
	elseif string.find(n, "Grass") then
		d.Color = rgb(palette.GrassTufts[1])
	end
end

-- The library model for an entry, built only if it isn't in the library yet (use for placement).
function Library.get(entryName: string): Model
	local A = fresh(shared().Config.Assets)
	local e = A.Entries[entryName]
	assert(e, "unknown asset entry " .. entryName)
	local root = ReplicatedStorage:FindFirstChild("Assets")
	local f = find(root and root:FindFirstChild(e.category), e.folder)
	local m = f and f:FindFirstChild(entryName)
	if m then
		return m :: Model
	end
	return Library.ensure(entryName)
end

function Library.gallery(): string
	local A = fresh(shared().Config.Assets)
	local palette = fresh(shared().Config.Palette)
	local old = workspace:FindFirstChild("DevGallery")
	if old then
		old:Destroy()
	end
	local g = Instance.new("Model")
	g.Name = "DevGallery"
	g:SetAttribute("DevOnly", true)

	-- deterministic order: by category, then entry name
	local names = {}
	for name in A.Entries do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		local ea, eb = A.Entries[a], A.Entries[b]
		local ia, ib = table.find(A.Categories, ea.category) or 99, table.find(A.Categories, eb.category) or 99
		if ia ~= ib then
			return ia < ib
		end
		return a < b
	end)

	local Bcfg = fresh(shared().Config.Buildings)
	local RulesD = fresh(shared().Rules.Destruction)
	local Buildings = fresh(ServerStorage:WaitForChild("Dev"):WaitForChild("Buildings"))
	local z = 0
	local width = 0
	local propNames = {}
	for _, name in names do
		local e = A.Entries[name]
		if e.prop then
			table.insert(propNames, name)
			continue
		end
		if e.uniform then
			continue -- clothing only, no shape to show (worn on the DevUniforms dummies)
		end
		local src = (find(ReplicatedStorage.Assets[e.category], e.folder) :: Instance)[name] :: Model
		local copy: Model
		if e.template then
			-- buildings: the same template in several color schemes, side by side
			local t = Bcfg.Templates[e.template]
			copy = Instance.new("Model")
			copy.Name = name
			-- pick seeds whose schemes show different wall AND roof colors
			local schemes = {}
			local usedWall, usedRoof = {}, {}
			for seed = 0, 500 do
				local sc = RulesD.scheme(t, palette, seed)
				if not usedWall[sc.wall] and (not usedRoof[sc.roof] or #t.roofs < 3) then
					usedWall[sc.wall], usedRoof[sc.roof] = true, true
					table.insert(schemes, sc)
				end
				if #schemes == 3 then
					break
				end
			end
			local x = 0
			for i, sc in schemes do
				local v = src:Clone()
				Buildings.paint(v, sc, palette)
				v:PivotTo(CFrame.new(x, 0, 0))
				v.Name = name .. "_" .. i
				v.Parent = copy
				x += t.width + 16
			end
			-- a new Model's pivot defaults to its bounding-box center; keep ground level (y 0) as the pivot
			copy.WorldPivot = CFrame.identity
		elseif e.fit and e.fit.shell then
			-- helmets: worn on a head over the preview hair, beside the same hair shot off (src/dev/HairPreview)
			local HairPreview = fresh(ServerStorage:WaitForChild("Dev"):WaitForChild("HairPreview"))
			copy = HairPreview.pair(name, src, CFrame.identity)
		else
			copy = src:Clone()
			for _, d in copy:GetDescendants() do
				if d:IsA("BasePart") then
					previewColor(d, palette)
					if e.folder == "Shared/Bandages" and palette.Medical[d.Name] then
						d.Color = rgb(palette.Medical[d.Name])
					end
				end
			end
		end
		local cf, size = copy:GetBoundingBox()
		-- small assets (grass, bandages) are shown 4x so they are readable; the label says so
		local zoom = if (e.category == "Foliage" or e.folder == "Shared/Bandages") and size.Magnitude < 20 then 4 else 1
		if zoom ~= 1 then
			copy:ScaleTo(copy:GetScale() * zoom)
			cf, size = copy:GetBoundingBox()
		end
		local padSize = Vector3.new(size.X + 8, 1, size.Z + 8)
		local padPos = GALLERY_ORIGIN + Vector3.new(padSize.X / 2, -0.5, z + padSize.Z / 2)
		local pad = Instance.new("Part")
		pad.Name = "Pad_" .. name
		pad.Anchored = true
		pad.Material = Enum.Material.SmoothPlastic
		pad.Color = Color3.fromRGB(70, 72, 68)
		pad.Size = padSize
		pad.Position = padPos
		pad.Parent = g
		if e.template then
			-- buildings sit with ground level (y 0) on the pad top
			local minX = cf.Position.X - size.X / 2
			copy:PivotTo(CFrame.new(GALLERY_ORIGIN.X + 4 - minX, 0, padPos.Z))
		else
			copy:PivotTo(copy:GetPivot() + (padPos + Vector3.new(0, 0.5 + size.Y / 2, 0) - cf.Position))
		end
		copy.Parent = g
		local idText = if e.id then "id " .. tostring(e.id) else "procedural, 3 color schemes"
		label(
			pad,
			string.format(
				"%s  [%s/%s]  %s%s",
				name,
				e.category,
				e.folder,
				idText,
				if zoom ~= 1 then "  (shown 4x)" else ""
			),
			size.Y + 4
		)
		z += padSize.Z + PAD_GAP
		width = math.max(width, padSize.X)
	end
	-- props: one row, side by side, true scale
	if #propNames > 0 then
		local x = 4
		local rowDepth = 0
		for _, name in propNames do
			local e = A.Entries[name]
			local copy = ((find(ReplicatedStorage.Assets[e.category], e.folder) :: Instance)[name] :: Model):Clone()
			local cf, size = copy:GetBoundingBox()
			local cx = GALLERY_ORIGIN.X + x + size.X / 2
			local cz = GALLERY_ORIGIN.Z + z + 6
			copy:PivotTo(CFrame.new(cx - (cf.Position.X - copy:GetPivot().Position.X), 0, cz))
			copy.Parent = g
			local pad = Instance.new("Part")
			pad.Name = "Pad_" .. name
			pad.Anchored = true
			pad.Material = Enum.Material.SmoothPlastic
			pad.Color = Color3.fromRGB(70, 72, 68)
			pad.Size = Vector3.new(size.X + 3, 1, size.Z + 3)
			pad.Position = Vector3.new(cx, -0.5, cz)
			pad.Parent = g
			label(pad, name, size.Y + 3)
			x += size.X + 6
			rowDepth = math.max(rowDepth, size.Z + 3)
			width = math.max(width, x)
		end
		z += rowDepth + 12
	end
	-- neutral floor under everything
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.fromRGB(104, 128, 76)
	floor.Size = Vector3.new(width + 80, 2, z + 80)
	floor.Position = GALLERY_ORIGIN + Vector3.new(width / 2, -1.2, z / 2 - 20)
	floor.Parent = g
	g.Parent = workspace
	return string.format(
		"Gallery: %d assets at %s (select Workspace.DevGallery, press F)",
		#names,
		tostring(GALLERY_ORIGIN)
	)
end

function Library.sync(): string
	assert(game.PlaceId == DEV_PLACE_ID, "Library tools only run in the DEV place")
	local A = fresh(shared().Config.Assets)
	local root = folder(ReplicatedStorage, "Assets")
	for _, c in A.Categories do
		folder(root, c)
	end
	local count = 0
	for name in A.Entries do
		Library.ensure(name)
		count += 1
	end
	-- prune library models no longer in the registry or no longer in their entry's folder (a reorganize), then
	-- every emptied subfolder, deepest first (category folders stay)
	for _, model in root:GetDescendants() do
		if model:IsA("Model") and (model:GetAttribute("AssetId") or model:GetAttribute("Procedural")) then
			local e = A.Entries[model.Name]
			if not e or model.Parent ~= find(root:FindFirstChild(e.category), e.folder) then
				model:Destroy()
			end
		end
	end
	local all = root:GetDescendants()
	for i = #all, 1, -1 do
		local f = all[i]
		if f:IsA("Folder") and f.Parent ~= root and #f:GetChildren() == 0 then
			f:Destroy()
		end
	end
	-- legacy location from before the library existed
	local legacy = ServerStorage:FindFirstChild("Assets")
	if legacy then
		legacy:Destroy()
	end
	return string.format("Library: %d entries in ReplicatedStorage.Assets. %s", count, Library.gallery())
end

return Library
