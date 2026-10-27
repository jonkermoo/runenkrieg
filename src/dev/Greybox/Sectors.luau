--!strict
-- Frontline sectors (Config/Sectors, Rules/Sectors): the invisible blocks dividing the sectors and a marker on each
-- sector's capture point. Seen while editing; the server hides them in play outside the DEV place (src/server/Sectors). They touch nothing:
-- no collision, no queries, no touches, no shadows.

local CollectionService = game:GetService("CollectionService")

local Parts = require(script.Parent.Parts)

local Sectors = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ghost(p: BasePart, transparency: number, tag: string)
	p.Transparency = transparency
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	CollectionService:AddTag(p, tag)
end

-- returns the number of divider blocks and markers
function Sectors.build(parent: Instance, map: any, MT: any, cfg: any, rules: any): (number, number)
	local folder = Parts.folder(parent, "Sectors")
	local D, Mk = cfg.Divider, cfg.Marker
	local height = D.TopY - D.BottomY
	local blocks = 0
	for _, d in map.dividers do
		local name = `Divider_{d.between[1]}_{d.between[2]}`
		for _, q in rules.pieces(rules.path(map, MT, d, D.RiverSegments), D.Thickness) do
			local dir = Vector3.new(q.dx, 0, q.dz)
			local cf = CFrame.fromMatrix(Vector3.new(q.x, D.BottomY + height / 2, q.z), dir, Vector3.yAxis)
			local p = Parts.box(folder, name, cf, Vector3.new(q.length, height, D.Thickness), rgb(D.ColorRGB))
			ghost(p, D.EditTransparency, D.Tag)
			blocks += 1
		end
	end
	for _, s in map.sectors do
		local model = Instance.new("Model")
		model.Name = `Point_{s.id}`
		model.Parent = folder
		local color = rgb(Mk.ColorRGB[s.startOwner])
		local y = MT.heightAt(map, s.x, s.z)
		-- a cylinder's axis is its X: lie it down so the disc is flat
		local disc = Parts.box(
			model,
			"Zone",
			CFrame.new(s.x, y + Mk.DiscLift, s.z) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(Mk.DiscHeight, s.radius * 2, s.radius * 2),
			color
		)
		disc.Shape = Enum.PartType.Cylinder
		ghost(disc, Mk.EditTransparency, Mk.Tag)
		local pole = Parts.box(
			model,
			"Pole",
			CFrame.new(s.x, y + Mk.PoleHeight / 2, s.z),
			Vector3.new(Mk.PoleWidth, Mk.PoleHeight, Mk.PoleWidth),
			color
		)
		ghost(pole, Mk.EditTransparency, Mk.Tag)
		model.PrimaryPart = pole
		local label = Instance.new("BillboardGui")
		label.Name = "Label"
		label.Size = UDim2.fromOffset(Mk.LabelSize[1], Mk.LabelSize[2])
		label.StudsOffsetWorldSpace = Vector3.new(0, Mk.PoleHeight / 2 + 4, 0)
		label.AlwaysOnTop = true
		label.Parent = pole
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Text = s.id
		text.TextScaled = true
		text.Font = Enum.Font.GothamBold
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0
		text.Parent = label
	end
	return blocks, #map.sectors
end

return Sectors
