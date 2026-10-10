--!strict
-- Dev-only asset library tools (dev place only). From the Studio command bar / MCP:
--   require(game.ServerStorage.Dev.Library:Clone()).sync()
-- 1. Mirrors Config/Assets.Entries into ReplicatedStorage.Assets.<Category>.<Folder>.<EntryName>
--    (loads new or changed ids via InsertService; unchanged entries are kept).
-- 2. Rebuilds Workspace.DevGallery: every library asset on a labeled pad, far outside the map.
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
	local target = folder(folder(root, e.category), e.folder)
	local existing = target:FindFirstChild(entryName)
	if existing and existing:GetAttribute("AssetId") == e.id then
		return existing :: Model
	end
	if existing then
		existing:Destroy()
	end
	local loaded = InsertService:LoadAsset(e.id)
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

	local z = 0
	local width = 0
	for _, name in names do
		local e = A.Entries[name]
		local src = ReplicatedStorage.Assets[e.category][e.folder][name] :: Model
		local copy = src:Clone()
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				previewColor(d, palette)
			end
		end
		local cf, size = copy:GetBoundingBox()
		-- small assets (grass) are shown 4x so they are readable; the label says so
		local zoom = if size.Magnitude < 20 then 4 else 1
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
		copy:PivotTo(copy:GetPivot() + (padPos + Vector3.new(0, 0.5 + size.Y / 2, 0) - cf.Position))
		copy.Parent = g
		label(
			pad,
			string.format(
				"%s  [%s/%s]  id %d%s",
				name,
				e.category,
				e.folder,
				e.id,
				if zoom ~= 1 then "  (shown 4x)" else ""
			),
			size.Y + 4
		)
		z += padSize.Z + PAD_GAP
		width = math.max(width, padSize.X)
	end
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
	-- legacy location from before the library existed
	local legacy = ServerStorage:FindFirstChild("Assets")
	if legacy then
		legacy:Destroy()
	end
	return string.format("Library: %d entries in ReplicatedStorage.Assets. %s", count, Library.gallery())
end

return Library
