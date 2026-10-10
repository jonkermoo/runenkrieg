--!strict
-- Client-side fracture debris for broken building sections (Net "SectionBroken"). Visual only:
-- local parts, never replicated, in the "Debris" collision group (never collides with characters),
-- removed after Config.Destruction.Debris.lifetime, capped at maxLive.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local D = require(Shared.Config.Destruction)
local Net = require(Shared.Net)

local DebrisClient = {}

local live = 0
local container: Folder

local function spawnChunk(cf: CFrame, size: Vector3, color: Color3, transparency: number, origin: Vector3)
	if live >= D.Debris.maxLive then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = transparency < 0.2
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = transparency
	p.Size = size
	p.CFrame = cf
	p.CollisionGroup = "Debris"
	p.Parent = container
	local away = cf.Position - origin
	local dist = math.max(away.Magnitude, 1)
	local push = math.clamp(40 / dist, 0.5, 1) * math.random(18, 34)
	p.AssemblyLinearVelocity = away.Unit * push + Vector3.new(0, math.random(8, 22), 0)
	p.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
	live += 1
	p.Destroying:Connect(function()
		live -= 1
	end)
	Debris:AddItem(p, D.Debris.lifetime + math.random() * 1.5)
end

-- Split a piece into up to `max` chunks along its two longest axes.
local function fracture(cf: CFrame, size: Vector3, color: Color3, t: number, origin: Vector3, max: number)
	local axes = { { "X", size.X }, { "Y", size.Y }, { "Z", size.Z } }
	table.sort(axes, function(a, b)
		return a[2] > b[2]
	end)
	local n1 = math.clamp(math.floor(axes[1][2] / 2.5), 1, max)
	local n2 = math.clamp(math.floor(axes[2][2] / 2.5), 1, math.max(1, max // n1))
	local counts = { X = 1, Y = 1, Z = 1 }
	counts[axes[1][1]] = n1
	counts[axes[2][1]] = n2
	local cs = Vector3.new(size.X / counts.X, size.Y / counts.Y, size.Z / counts.Z)
	for i = 0, counts.X - 1 do
		for j = 0, counts.Y - 1 do
			for k = 0, counts.Z - 1 do
				local off = Vector3.new(
					(i + 0.5) * cs.X - size.X / 2,
					(j + 0.5) * cs.Y - size.Y / 2,
					(k + 0.5) * cs.Z - size.Z / 2
				)
				-- slightly shrink so chunks don't start interpenetrating
				spawnChunk(cf * CFrame.new(off), cs * 0.92, color, t, origin)
			end
		end
	end
end

function DebrisClient.start()
	container = Instance.new("Folder")
	container.Name = "ClientDebris"
	container.Parent = workspace
	Net.event("SectionBroken").OnClientEvent:Connect(function(pieces: { any }, origin: Vector3)
		local per = D.Debris.chunksPerSection
		for _, piece in pieces do
			if piece.t > 0.1 then
				fracture(piece.cf, piece.size, piece.color, piece.t, origin, 9) -- glass: more, smaller shards
			else
				fracture(piece.cf, piece.size, piece.color, piece.t, origin, per)
			end
		end
	end)
end

return DebrisClient
