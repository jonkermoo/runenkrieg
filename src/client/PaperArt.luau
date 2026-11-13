--!strict
-- A drawn piece from the paper sheet (Config/PaperArt) as an ImageLabel: PaperArt.new(name, sliceScale?) -> the sprite,
-- clear behind, filling its parent from its middle (a nine-slice one sliced, its border `sliceScale` of its drawn size).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Art = require(ReplicatedStorage:WaitForChild("Shared").Config.PaperArt)

local PaperArt = {}

function PaperArt.new(name: string, sliceScale: number?): ImageLabel
	local sp = Art.sprites[name]
	local r = sp.rect
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = `rbxassetid://{Art.image}`
	img.ImageRectOffset = Vector2.new(r[1], r[2])
	img.ImageRectSize = Vector2.new(r[3], r[4])
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(1, 1)
	local c = sp.slice
	if c then
		img.ScaleType = Enum.ScaleType.Slice
		img.SliceCenter = Rect.new(c[1], c[2], c[3], c[4])
		img.SliceScale = sliceScale or 1
	end
	return img
end

return PaperArt
