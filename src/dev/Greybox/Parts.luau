--!strict
-- Part helpers for generated map geometry. Every part is anchored smooth plastic.

local Parts = {}

local created = 0

-- Yield every so often so Studio stays responsive and the MCP connection does not drop.
local function tick()
	created += 1
	if created % 250 == 0 then
		task.wait()
	end
end

function Parts.count(): number
	return created
end

function Parts.reset()
	created = 0
end

function Parts.box(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	className: string?
): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Name = name
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	tick()
	return p
end

function Parts.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

return Parts
