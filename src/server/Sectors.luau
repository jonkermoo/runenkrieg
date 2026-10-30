--!strict
-- The sector dividers and point markers (Config/Sectors, built by src/dev/Greybox) are seen while editing; in play
-- every part tagged with their tags shows only while Workspace's Config/Sectors.ShowAttribute is on (the admin panel's
-- switch, src/server/DevTools). Each mode change sets it to its default (Rules/Sectors.shownByDefault: off in Normal).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Sectors)
local ModeCfg = require(Shared.Config.Modes)
local Rules = require(Shared.Rules.Sectors)

local Sectors = {}

local function shown(): boolean
	return workspace:GetAttribute(Cfg.ShowAttribute) == true
end

-- each tag's look while shown
local seen = { [Cfg.Divider.Tag] = Cfg.Divider.EditTransparency, [Cfg.Marker.Tag] = Cfg.Marker.EditTransparency }

local function apply(inst: Instance, tag: string)
	local on = shown()
	if inst:IsA("BasePart") then
		inst.Transparency = if on then seen[tag] else 1
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BillboardGui") then
			d.Enabled = on
		end
	end
end

local function applyAll()
	for tag in seen do
		for _, inst in CollectionService:GetTagged(tag) do
			apply(inst, tag)
		end
	end
end

function Sectors.start()
	for tag in seen do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			apply(inst, tag)
		end)
	end
	local function reset()
		workspace:SetAttribute(
			Cfg.ShowAttribute,
			Rules.shownByDefault(Cfg, game.PlaceId, workspace:GetAttribute(ModeCfg.Attribute))
		)
	end
	workspace:GetAttributeChangedSignal(Cfg.ShowAttribute):Connect(applyAll)
	workspace:GetAttributeChangedSignal(ModeCfg.Attribute):Connect(reset)
	reset()
	applyAll()
end

return Sectors
