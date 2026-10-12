--!strict
-- Dev only (dev place): helmets shown on hair, in both head states (docs/HATS.md "Two head states"): helmet ON =
-- the helmet over its shell's shaved hair, helmet OFF (shot off) = the original hair, untouched. Used by the
-- gallery (src/dev/Library) and the DevHelmets dummies:
--   require(game.ServerStorage.Dev.HairPreview:Clone()).dummies()
--
-- The hair is the measuring baseline (references/hairs/baseline: ripped Roblox hair, never uploaded), so it lives
-- only as data in workspace.DevHairRef and is built here as EditableMesh MeshParts (rebuilt on demand, not saved):
--   AyanoData           the original: "vertices|triangles", vertices in tenths of its own units, Roblox axes;
--                       head-local studs = v * SCALE + OFFSET (its fit on the R6 head)
--   HairUnder_<shell>   tools/blender/gear/hair_under.py's changes for one helmet shell: "the original triangles
--                       shaved off|the new cut triangles (9 head-local studs each)"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local HairPreview = {}

local SCALE = 0.0072
local OFFSET = Vector3.new(0, -0.02, 0.02) -- raised 0.08 (user 2026-10-12: the head poked through the crown)
local HAIR_COLOR = Color3.fromRGB(104, 70, 46) -- the preview's hair (in game: the soldier's hair color)
local HEAD_TO_STAND = 2.5 -- a dummy's head center above its stand's center
local PAIR_GAP = 2.7 -- the shot-off head beside the helmet-on head

local function fresh(module: Instance): any
	return require(module:Clone() :: ModuleScript)
end

local function numbers(s: string): { number }
	local out = {}
	for n in string.gmatch(s, "[^,]+") do
		table.insert(out, tonumber(n) :: number)
	end
	return out
end

-- The data, or nil when this place has none (then callers show helmets bare).
local function data(): (Instance?, { number }?, { number }?)
	local ref = workspace:FindFirstChild("DevHairRef")
	local src = ref and ref:FindFirstChild("AyanoData") :: StringValue?
	if not src then
		return nil, nil, nil
	end
	local v, t = string.match(src.Value, "^([^|]*)|(.*)$")
	return ref, numbers(v :: string), numbers(t :: string)
end

function HairPreview.available(): boolean
	return (data()) ~= nil
end

-- The hair as a MeshPart in head-local studs (place it at the head's CFrame): the original (shell = nil) or the
-- one shaved for a helmet shell.
function HairPreview.hair(shell: string?): MeshPart?
	local ref, V, T = data()
	if not ref or not V or not T then
		return nil
	end
	local drop, extra = {}, {}
	if shell then
		local d = ref:FindFirstChild("HairUnder_" .. shell) :: StringValue?
		if not d then
			return nil
		end
		local dropS, newS = string.match(d.Value, "^([^|]*)|(.*)$")
		for _, k in numbers(dropS :: string) do
			drop[k] = true
		end
		extra = numbers(newS :: string)
	end
	local function P(i: number): Vector3
		return Vector3.new(V[i * 3 + 1], V[i * 3 + 2], V[i * 3 + 3]) * SCALE + OFFSET
	end
	local em = AssetService:CreateEditableMesh()
	for k = 1, #T, 3 do
		if not drop[(k - 1) / 3] then -- every triangle its own vertices: flat-shaded facets
			em:AddTriangle(em:AddVertex(P(T[k])), em:AddVertex(P(T[k + 1])), em:AddVertex(P(T[k + 2])))
		end
	end
	for k = 1, #extra, 9 do
		em:AddTriangle(
			em:AddVertex(Vector3.new(extra[k], extra[k + 1], extra[k + 2])),
			em:AddVertex(Vector3.new(extra[k + 3], extra[k + 4], extra[k + 5])),
			em:AddVertex(Vector3.new(extra[k + 6], extra[k + 7], extra[k + 8]))
		)
	end
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(em))
	part.Name = "Hair"
	part.Color = HAIR_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored, part.CanCollide = true, false
	return part
end

-- A bare R6 head (the classic head mesh) at `cf`, in the default uniform's skin.
function HairPreview.head(cf: CFrame): Part
	local U = fresh(ReplicatedStorage.Shared.Config.Uniforms)
	local h = Instance.new("Part")
	h.Name = "Head"
	h.Size = Vector3.new(2, 1, 1)
	h.Color = Color3.fromRGB(table.unpack(U.Kits[U.Default].skin))
	h.Material = Enum.Material.SmoothPlastic
	h.Anchored = true
	h.CFrame = cf
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Head
	m.Scale = Vector3.new(1.25, 1.25, 1.25)
	m.Parent = h
	return h
end

-- A copy of a helmet's library model in its team colors, worn on `head` at its Config/Assets fit (brim height,
-- shell center).
function HairPreview.helmet(entryName: string, library: Model, head: BasePart): Model
	local A = fresh(ReplicatedStorage.Shared.Config.Assets)
	local fit = A.Entries[entryName].fit
	local helmet = library:Clone()
	helmet.Name = "Helmet"
	local shell: BasePart? = nil
	for _, p in helmet:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored, p.CanCollide = true, false
			p.Material = Enum.Material.SmoothPlastic
			if string.find(string.lower(p.Name), "^helmet") then
				shell = p
				p.Color = Color3.fromRGB(table.unpack(fit.color))
			elseif fit.parts and fit.parts[p.Name] then
				p.Color = Color3.fromRGB(table.unpack(fit.parts[p.Name]))
			end
		end
	end
	assert(shell, `{entryName}: no helmet shell part`)
	local c = fit.center or { 0, 0, 0 }
	local want = head.CFrame * CFrame.new(c[1], fit.brim + c[2], c[3]) * shell.CFrame.Rotation
	helmet:PivotTo(want * shell.CFrame:Inverse() * helmet:GetPivot())
	return helmet
end

-- One helmet in both head states, side by side, as a Model: HelmetOn (head, helmet, its shaved hair) and HelmetOff
-- (head, the original hair). `at` = the helmet-on head's CFrame. Without hair data: the helmet on a bare head only.
function HairPreview.pair(entryName: string, library: Model, at: CFrame): Model
	local A = fresh(ReplicatedStorage.Shared.Config.Assets)
	local fit = A.Entries[entryName].fit
	local model = Instance.new("Model")
	model.Name = entryName
	local on = Instance.new("Model")
	on.Name = "HelmetOn"
	local head = HairPreview.head(at)
	head.Parent = on
	HairPreview.helmet(entryName, library, head).Parent = on
	local hair = HairPreview.hair(fit.shell)
	if hair then
		hair.CFrame = head.CFrame
		hair.Parent = on
	end
	on.Parent = model
	if hair then
		local off = Instance.new("Model")
		off.Name = "HelmetOff"
		local head2 = HairPreview.head(at * CFrame.new(PAIR_GAP, 0, 0))
		head2.Parent = off
		local hair2 = HairPreview.hair(nil) :: MeshPart
		hair2.CFrame = head2.CFrame
		hair2.Parent = off
		off.Parent = model
	end
	return model
end

local function label(parent: Instance, text: string, y: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 34)
	gui.StudsOffset = Vector3.new(0, y, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
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

-- Rebuild workspace.DevHelmets: per team (Olive, Grey, White) every helmet as a pair on stands, labeled.
function HairPreview.dummies(): string
	local A = fresh(ReplicatedStorage.Shared.Config.Assets)
	local old = workspace:FindFirstChild("DevHelmets")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "DevHelmets"
	root:SetAttribute("DevOnly", true)
	local ORIGIN = Vector3.new(240, 20.68, -2450) -- the stands' centre line, by the other dev dummies
	local x, count = 0, 0
	for _, team in { "Olive", "Grey", "White" } do
		local tf = Instance.new("Folder")
		tf.Name = team
		tf.Parent = root
		local names = {}
		for name, e in A.Entries do
			if e.category == "Teams" and e.folder == team .. "/Helmets" then
				table.insert(names, name)
			end
		end
		table.sort(names)
		local teamStart = x
		for _, name in names do
			local library = ReplicatedStorage.Assets.Teams[team].Helmets[name] :: Model
			local at = CFrame.new(ORIGIN + Vector3.new(x, HEAD_TO_STAND, 0))
			local pair = HairPreview.pair(name, library, at)
			for _, state in pair:GetChildren() do
				local head = state:FindFirstChild("Head") :: BasePart
				local stand = Instance.new("Part")
				stand.Name = "Stand"
				stand.Size = Vector3.new(0.8, 4, 0.8)
				stand.Color = Color3.fromRGB(120, 116, 110)
				stand.Material = Enum.Material.SmoothPlastic
				stand.Anchored = true
				stand.Position = head.Position - Vector3.new(0, HEAD_TO_STAND, 0)
				stand.Parent = state
				label(head, if state.Name == "HelmetOn" then name else "shot off", 2.4)
			end
			pair.Parent = tf
			x += 7
			count += 1
		end
		local sign = Instance.new("Part")
		sign.Name = "Label"
		sign.Anchored, sign.CanCollide, sign.Transparency = true, false, 1
		sign.Size = Vector3.new(1, 1, 1)
		sign.Position = ORIGIN + Vector3.new((teamStart + x - 7) / 2 + PAIR_GAP / 2, 6.5, 0)
		label(sign, team .. " team", 0)
		sign.Parent = tf
		x += 3
	end
	root.Parent = workspace
	return string.format(
		"DevHelmets: %d helmets, each on hair and shot off (hair data: %s)",
		count,
		if HairPreview.available() then "yes" else "missing, helmets shown bare"
	)
end

return HairPreview
