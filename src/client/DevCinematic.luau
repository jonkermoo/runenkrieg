--!strict
-- Dev cinematic settings for filming (the admin panel's "Cinematic" rows, Config/DevTools.Admin.Cinematic), this player
-- only. Each item is hidden while the Player has its "DevCinematic<id>" attribute:
-- - Hud: the game's HUD guis (HudGuis) kept off; whatever their owner sets meanwhile comes back when shown again.
-- - RobloxUi: every Roblox core gui (chat, player list, backpack...) and the top bar; each comes back as it was.
-- - DevUi: the dev pins and the settings gear; the other dev panels close. The admin panel stays where F2 puts it
--   (Settings Key_AdminPanel), and src/client/DevAdminMenu hides the dev labels too.
-- - NameTags: the names and health bars over every humanoid's head.
-- DevCinematic.start(player), DevCinematic.hidden(player, id), DevCinematic.set(player, id, on),
-- DevCinematic.clear(player).

local StarterGui = game:GetService("StarterGui")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local DevPanel = require(script.Parent.DevPanel)

local DevCinematic = {}

local C = Cfg.Admin.Cinematic

local function attribute(id: string): string
	return C.AttributePrefix .. id
end

function DevCinematic.hidden(player: Player, id: string): boolean
	return player:GetAttribute(attribute(id)) == true
end

function DevCinematic.set(player: Player, id: string, on: boolean)
	player:SetAttribute(attribute(id), if on then true else nil)
end

function DevCinematic.clear(player: Player)
	for _, item in C.Items do
		DevCinematic.set(player, item.id, false)
	end
end

-- Hud: a gui kept off while hidden; `wanted` is what its owner last set, given back on show
type Held = { wanted: boolean, ours: boolean, conn: RBXScriptConnection }
local held: { [LayerCollector]: Held } = {}

local function holdOff(gui: LayerCollector)
	if held[gui] then
		return
	end
	local h: Held = { wanted = gui.Enabled, ours = gui.Enabled, conn = nil :: any }
	h.conn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			h.wanted, h.ours = true, true
			gui.Enabled = false
		elseif h.ours then
			h.ours = false -- our own switch-off
		else
			h.wanted = false
		end
	end)
	held[gui] = h
	gui.Enabled = false
end

local function release(gui: LayerCollector)
	local h = held[gui]
	if h then
		held[gui] = nil
		h.conn:Disconnect()
		if gui.Parent then
			gui.Enabled = h.wanted
		end
	end
end

local function isHud(child: Instance): boolean
	return child:IsA("LayerCollector") and table.find(C.HudGuis, child.Name) ~= nil
end

-- RobloxUi: each core gui's state before hiding
local coreBefore: { [Enum.CoreGuiType]: boolean }? = nil

local function hideCore(on: boolean)
	if on and not coreBefore then
		local before = {}
		for _, kind in Enum.CoreGuiType:GetEnumItems() do
			if kind ~= Enum.CoreGuiType.All then
				before[kind] = StarterGui:GetCoreGuiEnabled(kind)
			end
		end
		coreBefore = before
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", false) -- (errors until the core scripts register it)
	elseif not on and coreBefore then
		for kind, was in coreBefore do
			StarterGui:SetCoreGuiEnabled(kind, was)
		end
		coreBefore = nil
		pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", true)
	end
end

-- NameTags: each humanoid's display before hiding (weak keys: a removed body is forgotten)
type Tag = { distance: Enum.HumanoidDisplayDistanceType, health: Enum.HumanoidHealthDisplayType }
local tags: { [Humanoid]: Tag } = setmetatable({}, { __mode = "k" }) :: any
local tagConn: RBXScriptConnection? = nil

local function hideTag(d: Instance)
	if d:IsA("Humanoid") and not tags[d] then
		tags[d] = { distance = d.DisplayDistanceType, health = d.HealthDisplayType }
		d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
end

local function hideTags(on: boolean)
	if on and not tagConn then
		for _, d in workspace:GetDescendants() do
			hideTag(d)
		end
		tagConn = workspace.DescendantAdded:Connect(hideTag)
	elseif not on and tagConn then
		tagConn:Disconnect()
		tagConn = nil
		for humanoid, t in tags do
			humanoid.DisplayDistanceType = t.distance
			humanoid.HealthDisplayType = t.health
		end
		table.clear(tags)
	end
end

function DevCinematic.start(player: Player)
	local playerGui = player:WaitForChild("PlayerGui")

	local function applyHud()
		local on = DevCinematic.hidden(player, "Hud")
		for _, child in playerGui:GetChildren() do
			if isHud(child) then
				if on then
					holdOff(child :: LayerCollector)
				else
					release(child :: LayerCollector)
				end
			end
		end
	end

	-- DevUi: the dev pins and the settings gear (dev guis are built after this starts, so re-applied on each new gui)
	local function applyDev()
		local on = DevCinematic.hidden(player, "DevUi")
		for _, name in DevPanel.Panels do
			local g = playerGui:FindFirstChild(name)
			local button = g and g:FindFirstChild(if name == "SettingsMenu" then "Gear" else "Pin") :: GuiObject?
			if button then
				button.Visible = not on
			end
			local panel = on and name ~= "DevAdminMenu" and name ~= "SettingsMenu" and g and g:FindFirstChild("Panel")
			if panel then
				(panel :: GuiObject).Visible = false
			end
		end
	end

	playerGui.ChildAdded:Connect(function(child)
		if isHud(child) and DevCinematic.hidden(player, "Hud") then
			holdOff(child :: LayerCollector)
		elseif table.find(DevPanel.Panels, child.Name) then
			applyDev()
		end
	end)
	playerGui.ChildRemoved:Connect(function(child)
		if child:IsA("LayerCollector") and held[child] then
			release(child)
		end
	end)

	local apply = {
		Hud = applyHud,
		RobloxUi = function()
			hideCore(DevCinematic.hidden(player, "RobloxUi"))
		end,
		DevUi = applyDev,
		NameTags = function()
			hideTags(DevCinematic.hidden(player, "NameTags"))
		end,
	}
	for _, item in C.Items do
		local fn = (apply :: any)[item.id]
		player:GetAttributeChangedSignal(attribute(item.id)):Connect(fn)
		fn()
	end
end

return DevCinematic
