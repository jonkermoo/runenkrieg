--!strict
-- The trench plan's marker flag (Config/Assets marker_flag, tools/blender/trench/marker_flag.py; user 2026-10-24: "make
-- the flag for planning a better model"): stands at each end of a laid plan (src/server/Trenches) and, see-through, as
-- the planner's ghost (src/client/Build). One model for everyone, coloured by mesh name from Config/Palette.Build.Flag.
-- Its pivot is the pole's foot on the ground, the pennant flying along the pivot's +X. Until the asset library has it
-- (the Library sync in the dev place) a plain pole and pennant stand in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local Palette = require(Shared.Config.Palette)

local TrenchFlag = {}

local COLORS = Palette.Build.Flag :: { [string]: { number } }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function settle(p: BasePart, name: string)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Material = Enum.Material.SmoothPlastic
	local c = COLORS[name]
	if c then
		p.Color = rgb(c)
	end
end

-- the library's model (ReplicatedStorage.Assets), or nil before the sync
local function library(): Model?
	local e = (Assets.Entries :: any).marker_flag
	if not e then
		return nil
	end
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and f:FindFirstChild(e.category)
	for _, sub in string.split(e.folder, "/") do
		f = f and f:FindFirstChild(sub)
	end
	local m = f and f:FindFirstChild("marker_flag")
	return if m and m:IsA("Model") and m:FindFirstChild("Origin") then m else nil
end

-- a stand-in from parts, in the model's shape (pole 3.1, pennant 1.4 x 0.9 at 2.05..2.95)
local function standIn(): Model
	local m = Instance.new("Model")
	local function add(name: string, size: Vector3, at: Vector3)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(at)
		settle(p, name)
		p.Parent = m
	end
	add("Pole", Vector3.new(0.14, 3.1, 0.14), Vector3.new(0, 1.55, 0))
	add("Brass", Vector3.new(0.22, 0.22, 0.22), Vector3.new(0, 3.2, 0))
	add("Pennant", Vector3.new(1.4, 0.9, 0.04), Vector3.new(0.7, 2.5, 0))
	add("Band", Vector3.new(1.0, 0.24, 0.06), Vector3.new(0.5, 2.5, 0))
	m.WorldPivot = CFrame.new()
	return m
end

-- a new flag, unparented, its pivot at the world origin
function TrenchFlag.make(): Model
	local source = library()
	if not source then
		return standIn()
	end
	local m = source:Clone()
	local origin = m:FindFirstChild("Origin") :: BasePart
	m.WorldPivot = origin.CFrame
	origin:Destroy()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			settle(d, d.Name)
		end
	end
	m:PivotTo(CFrame.new())
	return m
end

-- every part of a flag at one transparency (the planner's ghost)
function TrenchFlag.fade(m: Model, transparency: number)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = transparency
		end
	end
end

return TrenchFlag
