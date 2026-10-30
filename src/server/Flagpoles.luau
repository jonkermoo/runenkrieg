--!strict
-- The capture-point flagpoles (Config/Flagpole, Rules/Flagpole; FLAGPOLE.md, user 2026-10-27): while the frontline
-- match runs (Workspace's Frontline folder, src/server/Frontline) a pole stands on each of Map 1's sector points,
-- the HQs' bigger with a knee-high ring of sandbags, and the zone's edge is marked by a ring of stakes. The pole blocks
-- bullets like a post; the stakes and bags don't collide. The flag, halyard, rags and sounds are each client's
-- (src/client/Flagpoles). Taken away when the match stops. Pieces from the asset library (Config/Assets flagpole,
-- sandbag_pile).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Flagpole)
local HudCfg = require(Shared.Config.ModeHud)
local Assets = require(Shared.Config.Assets)
local Palette = require(Shared.Config.Palette)
local Build = Palette.Build :: any
local Map = require(Shared.Config.Maps.Map1)
local Rules = require(Shared.Rules.Flagpole)

local Flagpoles = {}

local COLORS = Palette.Flagpole :: any

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

local function ground(x: number, z: number): number
	local hit =
		workspace:Raycast(Vector3.new(x, Cfg.GroundRay.top, z), Vector3.new(0, -Cfg.GroundRay.depth, 0), terrainOnly)
	return if hit then hit.Position.Y else 0
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- an asset's pieces from the library: each MeshPart by name with its CFrame from the asset's Origin
local kits: { [string]: { [string]: { part: BasePart, offset: CFrame } } } = {}
local function library(key: string): { [string]: { part: BasePart, offset: CFrame } }?
	if kits[key] then
		return kits[key]
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
		warn(`[Flagpoles] {key} is not in the asset library: run the Library sync in the dev place`)
		return nil
	end
	local pieces = {}
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d ~= origin then
			pieces[d.Name] = { part = d, offset = origin.CFrame:ToObjectSpace(d.CFrame) }
		end
	end
	kits[key] = pieces
	return pieces
end

local function still(p: BasePart, solid: boolean)
	p.Anchored = true
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
end

-- a library piece at `at` (where the asset's Origin goes), scaled by k
local function piece(pieces: any, name: string, at: CFrame, k: number, parent: Instance): BasePart?
	local src = pieces[name]
	if not src then
		return nil
	end
	local p = src.part:Clone()
	p.Size *= k
	local o = src.offset
	p.CFrame = at * CFrame.new(o.Position * k) * o.Rotation
	p.Parent = parent
	return p
end

local folder: Folder? = nil

-- One sector's pole, stakes and (at an HQ) sandbags.
local function stand(s: any, i: number, parent: Instance)
	local pieces = library(Cfg.Asset)
	if not pieces then
		return
	end
	local k = if s.isHQ then Cfg.HQScale else 1
	local model = Instance.new("Model")
	model.Name = s.id
	model:SetAttribute("Sector", s.id)
	model:SetAttribute("HQ", s.isHQ == true)
	model:SetAttribute("Scale", k)
	-- (each pole turned its own way, so the cleats don't all face one side)
	local foot = CFrame.new(s.x, ground(s.x, s.z) - Cfg.Sink, s.z) * CFrame.Angles(0, i * 2.4, 0)
	for _, name in { "Pole", "Knob", "Cleat" } do
		local p = piece(pieces, name, foot, k, model)
		if p then
			still(p, name == "Pole")
			p.Color = rgb(COLORS[name])
			if name == "Pole" then
				model.PrimaryPart = p
			end
		end
	end
	local stakes = Instance.new("Folder")
	stakes.Name = "Stakes"
	stakes.Parent = model
	local rng = Random.new(i)
	for n, a in Rules.ring(s.radius, Cfg.Stakes.spacing) do
		local x, z = s.x + math.cos(a) * s.radius, s.z + math.sin(a) * s.radius
		local lean = math.rad(rng:NextNumber(-Cfg.Stakes.lean, Cfg.Stakes.lean))
		local at = CFrame.new(x, ground(x, z) - Cfg.Sink, z)
			* CFrame.Angles(0, -a, 0)
			* CFrame.Angles(lean, rng:NextNumber(0, 2 * math.pi), 0)
		local p = piece(pieces, "Stake", at, 1, stakes)
		if p then
			still(p, false)
			p.CastShadow = false
			p.Name = `Stake{n}`
			p.Color = rgb(COLORS.Stake)
		end
	end
	if s.isHQ then
		local SB = Cfg.Sandbags
		local bags = library("sandbag_pile")
		local bag = bags and bags[SB.bag]
		local cord = bags and bags[SB.cord]
		if bag then
			for n, a in Rules.ring(SB.radius, SB.length) do
				local x, z = s.x + math.cos(a) * SB.radius, s.z + math.sin(a) * SB.radius
				-- (the bag's length along the ring: the pile's x is along it; centred on its spot, its height kept)
				local at = CFrame.new(x, ground(x, z) - SB.sink, z) * CFrame.Angles(0, -a - math.pi / 2, 0)
				local bagAt = at * CFrame.new(0, bag.offset.Y, 0) * bag.offset.Rotation
				local p = bag.part:Clone()
				p.CFrame = bagAt
				still(p, false)
				p.Name = `Sandbag{n}`
				local jitter = 1 + ((n * 37) % 7 / 6 - 0.5) * 2 * SB.shade
				local c = Build.Sandbag
				p.Color = Color3.fromRGB(
					math.clamp(c[1] * jitter, 0, 255),
					math.clamp(c[2] * jitter, 0, 255),
					math.clamp(c[3] * jitter, 0, 255)
				)
				p.Parent = model
				if cord then
					local t = cord.part:Clone()
					t.CFrame = bagAt * bag.offset:ToObjectSpace(cord.offset)
					still(t, false)
					t.Name = `Sandbag{n}Cord`
					t.Color = rgb(Build.SandbagCord)
					t.Parent = model
				end
			end
		end
	end
	model.Parent = parent
end

local function clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

local function standAll(front: Instance)
	clear()
	local f = Instance.new("Folder")
	f.Name = Cfg.FolderName
	for i, s in Map.sectors do
		if front:FindFirstChild(s.id) then
			stand(s, i, f)
		end
	end
	f.Parent = workspace
	folder = f
end

function Flagpoles.start()
	local function added(child: Instance)
		if child.Name == HudCfg.FrontlineFolder and child:IsA("Folder") then
			-- (its sector folders are parented before it, by src/server/Frontline.start)
			standAll(child)
		end
	end
	workspace.ChildAdded:Connect(added)
	workspace.ChildRemoved:Connect(function(child)
		if child.Name == HudCfg.FrontlineFolder and not workspace:FindFirstChild(HudCfg.FrontlineFolder) then
			clear()
		end
	end)
	local existing = workspace:FindFirstChild(HudCfg.FrontlineFolder)
	if existing then
		added(existing)
	end
end

return Flagpoles
