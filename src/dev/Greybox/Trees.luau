--!strict
-- Places low-poly tree meshes from the library's TreeKit (Config/Assets.Entries.TreeKit).
-- Trunks collide; canopies block sight but not movement or bullets (CanQuery off; user 2026-10-17: "bullets through
-- leaves").

local CollectionService = game:GetService("CollectionService")

local Trees = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- One template Model per variant: pivot at the trunk base, scaled to the kind's target height.
local function buildTemplates(kit: Model, entry: any, heights: any): { [string]: { Model } }
	local out = {}
	for kind, names in entry.variants do
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
					p.CanQuery = false
				else
					p.Name = "Trunk"
				end
				p.Parent = m
			end
			local t, c = m:FindFirstChild("Trunk") :: BasePart, m:FindFirstChild("Canopy") :: BasePart
			local baseY = t.Position.Y - t.Size.Y / 2
			local topY = c.Position.Y + c.Size.Y / 2
			m.WorldPivot = CFrame.new(t.Position.X, baseY, t.Position.Z)
			m:ScaleTo(heights[kind] / (topY - baseY))
			table.insert(out[kind], m)
		end
	end
	return out
end

-- placements defaults to the map's natural trees (Rules/MapTerrain.trees).
-- kit = the TreeKit library model (src/dev/Library.ensure("TreeKit")).
function Trees.build(
	parent: Instance,
	map: any,
	MT: any,
	kit: Model,
	assets: any,
	palette: any,
	placements: { any }?
): number
	local templates = buildTemplates(kit, assets.Entries.TreeKit, assets.TreeTargetHeight)
	placements = placements or MT.trees(map)
	assert(placements, "no tree placements")
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
		tree:PivotTo(CFrame.new(t.x, MT.treeBaseY(map, t.x, t.z), t.z) * CFrame.Angles(0, math.rad(t.yaw), 0))
		local colors = palette.Trees[t.kind]
		local canopy = tree:FindFirstChild("Canopy") :: BasePart
		local trunk = tree:FindFirstChild("Trunk") :: BasePart
		canopy.Color = rgb(colors[(t.variant // 7) % #colors + 1])
		trunk.Color = rgb(if t.kind == "Birch" then palette.Trees.BirchBark else palette.Trees.Bark)
		CollectionService:AddTag(tree, "SwayTree") -- Config/TreeSway.Tag; animated by src/client/TreeSway
		tree.Parent = bucket
		if i % 200 == 0 then
			task.wait()
		end
	end
	return #placements
end

return Trees
