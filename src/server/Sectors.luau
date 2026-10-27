--!strict
-- The sector dividers and point markers (Config/Sectors, built by src/dev/Greybox) are seen while editing only: in play
-- every part tagged with their tags turns invisible and its labels go, except in the DEV place with
-- Config/Sectors.ShowInDevPlay on.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Sectors)

local Sectors = {}

local function hide(inst: Instance)
	if inst:IsA("BasePart") then
		inst.Transparency = 1
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
end

function Sectors.start()
	if Cfg.ShowInDevPlay and game.PlaceId == Cfg.DevPlaceId then
		return
	end
	for _, tag in { Cfg.Divider.Tag, Cfg.Marker.Tag } do
		for _, inst in CollectionService:GetTagged(tag) do
			hide(inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(hide)
	end
end

return Sectors
