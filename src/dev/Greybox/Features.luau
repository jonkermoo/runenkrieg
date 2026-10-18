--!strict
-- Out-of-bounds panels, test spawn, atmosphere.

local CollectionService = game:GetService("CollectionService")

local Parts = require(script.Parent.Parts)

local Features = {}

-- Red force-field panels along every edge of the playable bounds. The client fades each panel
-- in as the player approaches (src/client/BoundaryFade), one wall per side (in pieces of at most MaxPieceLength). Panels are solid walls for now;
-- soft bounds (warning + countdown) can replace collision later.
function Features.bounds(parent: Instance, map: any, cfg: any): number
	Features.boundaryGroup(cfg)
	local folder = Parts.folder(parent, "Bounds")
	local b = map.bounds
	local color = Color3.fromRGB(cfg.ColorRGB[1], cfg.ColorRGB[2], cfg.ColorRGB[3])
	local height = cfg.TopY - cfg.BottomY
	local edges = {
		{ Vector3.new(b.minX, 0, b.minZ), Vector3.new(b.maxX, 0, b.minZ) },
		{ Vector3.new(b.maxX, 0, b.minZ), Vector3.new(b.maxX, 0, b.maxZ) },
		{ Vector3.new(b.maxX, 0, b.maxZ), Vector3.new(b.minX, 0, b.maxZ) },
		{ Vector3.new(b.minX, 0, b.maxZ), Vector3.new(b.minX, 0, b.minZ) },
	}
	local count = 0
	for _, e in edges do
		local a, c = e[1], e[2]
		local L = (c - a).Magnitude
		local dir = (c - a).Unit
		local n = math.ceil(L / cfg.MaxPieceLength)
		local w = L / n
		for i = 0, n - 1 do
			local mid = a + dir * ((i + 0.5) * w)
			local cf = CFrame.fromMatrix(Vector3.new(mid.X, cfg.BottomY + height / 2, mid.Z), dir, Vector3.yAxis)
			local p = Parts.box(folder, "BoundaryPanel", cf, Vector3.new(w, height, 1), color)
			p.Material = (Enum.Material :: any)[cfg.Material]
			p.CollisionGroup = cfg.CollisionGroup
			local mesh = Instance.new("BlockMesh")
			mesh.Scale = Vector3.new(1, 1, cfg.DrawnThickness)
			mesh.Parent = p
			p.Transparency = 1 - cfg.MaxOpacity
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			-- the whole side, so every piece of it fades alike (src/client/BoundaryFade)
			p:SetAttribute("SideFrom", a)
			p:SetAttribute("SideTo", c)
			CollectionService:AddTag(p, cfg.Tag)
			count += 1
		end
	end
	return count
end

-- The walls' collision group: it blocks only Config/Boundary.Blocks (characters), so raycasts and everything else pass.
-- Also set up by the server at start (src/server/init), since a place may come without it.
function Features.boundaryGroup(cfg: any)
	local PhysicsService = game:GetService("PhysicsService")
	for _, g in { cfg.CollisionGroup, table.unpack(cfg.Blocks) } do
		if not PhysicsService:IsCollisionGroupRegistered(g) then
			PhysicsService:RegisterCollisionGroup(g)
		end
	end
	for _, g in PhysicsService:GetRegisteredCollisionGroups() do
		PhysicsService:CollisionGroupSetCollidable(cfg.CollisionGroup, g.name, table.find(cfg.Blocks, g.name) ~= nil)
	end
end

-- Neutral spawn for walking the map before teams exist.
function Features.testSpawn(parent: Instance, map: any, MT: any)
	local z = map.spawnZones.West
	local x, zc = (z.minX + z.maxX) / 2, (z.minZ + z.maxZ) / 2
	local sp = Instance.new("SpawnLocation")
	sp.Name = "TestSpawn"
	sp.Anchored = true
	sp.Neutral = true
	sp.Transparency = 1
	sp.CanCollide = false
	sp.Size = Vector3.new(6, 1, 6)
	sp.CFrame = CFrame.new(x, MT.heightAt(map, x, zc) + 0.5, zc)
	sp.Duration = 0
	sp.Parent = parent
end

-- Shared wind for grass, particles and tree sway (Config/TreeSway.DefaultWind).
function Features.wind(cfg: any)
	workspace.GlobalWind = Vector3.new(cfg.DefaultWind.x, 0, cfg.DefaultWind.z)
end

function Features.atmosphere(palette: any)
	local lighting = game:GetService("Lighting")
	local atm = lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atm.Density = 0.38
	atm.Offset = 0.15
	atm.Haze = 0.8
	atm.Glare = 0
	local a = palette.Atmosphere
	atm.Color = Color3.fromRGB(a.color[1], a.color[2], a.color[3])
	atm.Decay = Color3.fromRGB(a.decay[1], a.decay[2], a.decay[3])
	atm.Parent = lighting
end

return Features
