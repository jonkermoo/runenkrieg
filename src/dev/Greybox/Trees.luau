--!strict
-- Places low-poly tree meshes from the uploaded tree kit (Config/Assets.TreeKit).
-- Trunks collide; canopies block shots/sight (CanQuery) but not movement.

local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local Trees = {}

local PALETTE = {
	Pine = { Color3.fromRGB(44, 88, 52), Color3.fromRGB(52, 98, 58), Color3.fromRGB(38, 80, 48) },
	Broadleaf = { Color3.fromRGB(78, 140, 56), Color3.fromRGB(92, 150, 60), Color3.fromRGB(70, 126, 52) },
	Birch = { Color3.fromRGB(130, 165, 70), Color3.fromRGB(118, 156, 62) },
}
local BARK = {
	Pine = Color3.fromRGB(96, 70, 50),
	Broadleaf = Color3.fromRGB(104, 78, 56),
	Birch = Color3.fromRGB(222, 220, 210),
}

-- The kit model, loading it into ServerStorage.Assets if this place does not have it yet.
local function getKit(kitCfg: any): Model
	local folder = ServerStorage:FindFirstChild("Assets")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Assets"
		folder.Parent = ServerStorage
	end
	local kit = (folder :: Instance):FindFirstChild("TreeKit")
	if kit and kit:GetAttribute("AssetId") == kitCfg.id then
		return kit :: Model
	end
	if kit then
		kit:Destroy()
	end
	local loaded = InsertService:LoadAsset(kitCfg.id)
	local model = (loaded:FindFirstChildWhichIsA("Model") or loaded) :: Model
	model.Name = "TreeKit"
	model:SetAttribute("AssetId", kitCfg.id)
	model.Parent = folder
	if model ~= loaded then
		loaded:Destroy()
	end
	return model
end

-- One template Model per variant: pivot at the trunk base, scaled to the kind's target height.
local function buildTemplates(kitCfg: any): { [string]: { Model } }
	local kit = getKit(kitCfg)
	local out = {}
	for kind, names in kitCfg.variants do
		out[kind] = {}
		for _, name in names do
			local trunk = kit:FindFirstChild(name .. "_Trunk") :: MeshPart
			local canopy = kit:FindFirstChild(name .. "_Canopy") :: MeshPart
			assert(trunk and canopy, "tree kit missing " .. name)
			local m = Instance.new("Model")
			m.Name = kind
			for _, src in { trunk, canopy } do
				local p = src:Clone()
				p.Anchored = true
				p.Material = Enum.Material.SmoothPlastic
				p.CastShadow = true
				p.CollisionFidelity = Enum.CollisionFidelity.Box
				if src == canopy then
					p.Name = "Canopy"
					p.CanCollide = false
					p.CanTouch = false
				else
					p.Name = "Trunk"
				end
				p.Parent = m
			end
			local t, c = m:FindFirstChild("Trunk") :: BasePart, m:FindFirstChild("Canopy") :: BasePart
			local baseY = t.Position.Y - t.Size.Y / 2
			local topY = c.Position.Y + c.Size.Y / 2
			m.WorldPivot = CFrame.new(t.Position.X, baseY, t.Position.Z)
			m:ScaleTo(kitCfg.targetHeight[kind] / (topY - baseY))
			table.insert(out[kind], m)
		end
	end
	return out
end

function Trees.build(parent: Instance, map: any, MT: any, assets: any): number
	local kitCfg = assets.TreeKit
	local templates = buildTemplates(kitCfg)
	local placements = MT.trees(map)
	local bucket: Instance = parent
	for i, t in placements do
		if (i - 1) % 400 == 0 then
			local f = Instance.new("Folder")
			f.Name = "Trees_" .. math.floor(i / 400)
			f.Parent = parent
			bucket = f
		end
		local variants = templates[t.kind]
		local tree = variants[t.variant % #variants + 1]:Clone()
		tree:ScaleTo(tree:GetScale() * t.scale)
		local gy = MT.heightAt(map, t.x, t.z)
		tree:PivotTo(CFrame.new(t.x, gy - 0.8, t.z) * CFrame.Angles(0, math.rad(t.yaw), 0))
		local palette = PALETTE[t.kind]
		local canopy = tree:FindFirstChild("Canopy") :: BasePart
		local trunk = tree:FindFirstChild("Trunk") :: BasePart
		canopy.Color = palette[(t.variant // 7) % #palette + 1]
		trunk.Color = BARK[t.kind]
		tree.Parent = bucket
		if i % 200 == 0 then
			task.wait()
		end
	end
	return #placements
end

return Trees
