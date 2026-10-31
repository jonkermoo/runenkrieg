--!strict
-- Dev cinematic settings for filming (the admin panel's "Cinematic" rows, Config/DevTools.Admin.Cinematic), this player
-- only. Each item is hidden while the Player has its "DevCinematic<id>" attribute:
-- - Hud: the game's HUD guis (HudGuis) kept off; whatever their owner sets meanwhile comes back when shown again.
-- - RobloxUi: every Roblox core gui (chat, player list, backpack...) and the top bar; each comes back as it was. The
--   hotbar's number keys (HotbarKeys) still equip / unequip the tools meanwhile, in the order they arrived as the
--   hotbar orders them.
-- - DevUi: the dev pins and the settings gear; the other dev panels close. The admin panel stays where F2 puts it
--   (Settings Key_AdminPanel), and src/client/DevAdminMenu hides the dev labels too.
-- - NameTags: the names and health bars over every humanoid's head.
-- The "Game" switch (the Player's GameAttribute) on top: what any other player sees. The dev pins (all but the settings
-- gear) and the dev panels but the admin panel go, src/client/DevAdminMenu hides the dev labels and src/client/
-- SettingsMenu its dev-only rows; the hit readout (GameGuis) is kept off as Hud keeps its guis; the sector dividers and markers shown in dev play (Config/Sectors) go as in the live
-- game. F2 still opens the admin panel, whose Game row turns it off again.
-- DevCinematic.start(player), DevCinematic.hidden(player, id), DevCinematic.set(player, id, on),
-- DevCinematic.gameView(player), DevCinematic.setGameView(player, on), DevCinematic.clear(player).

local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local SectorCfg = require(Shared.Config.Sectors)
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

function DevCinematic.gameView(player: Player): boolean
	return player:GetAttribute(C.GameAttribute) == true
end

function DevCinematic.setGameView(player: Player, on: boolean)
	player:SetAttribute(C.GameAttribute, if on then true else nil)
end

function DevCinematic.clear(player: Player)
	for _, item in C.Items do
		DevCinematic.set(player, item.id, false)
	end
	DevCinematic.setGameView(player, false)
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

local function isGameGui(child: Instance): boolean
	return child:IsA("LayerCollector") and table.find(C.GameGuis, child.Name) ~= nil
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

-- the hidden hotbar's keys: the tools in the order they first came to this player (weak keys)
local arrived: { [Tool]: number } = setmetatable({}, { __mode = "k" }) :: any
local arrivals = 0

local function stamp(d: Instance)
	if d:IsA("Tool") and not arrived[d] then
		arrivals += 1
		arrived[d] = arrivals
	end
end

local function hotbarKey(player: Player, input: InputObject)
	local slot = table.find(C.HotbarKeys, input.KeyCode.Name)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not slot or not character or not humanoid or not backpack then
		return
	end
	local tools: { Tool } = {}
	for _, holder in { backpack, character } do
		for _, t in holder:GetChildren() do
			if t:IsA("Tool") then
				stamp(t)
				table.insert(tools, t)
			end
		end
	end
	table.sort(tools, function(a, b)
		return arrived[a] < arrived[b]
	end)
	local tool = tools[slot]
	if not tool then
		return
	elseif tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
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

-- Game: the sector dividers and markers (and their labels) hidden here as the live server hides them (src/server/
-- Sectors); each label's state before hiding (weak keys)
local SECTOR_TAGS = { SectorCfg.Divider.Tag, SectorCfg.Marker.Tag }
local sectorLabels: { [BillboardGui]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local sectorConns: { RBXScriptConnection } = {}

local function hideSector(inst: Instance)
	if inst:IsA("BasePart") then
		inst.LocalTransparencyModifier = 1
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BillboardGui") and sectorLabels[d] == nil then
			sectorLabels[d] = d.Enabled
			d.Enabled = false
		end
	end
end

local function hideSectors(on: boolean)
	if on and #sectorConns == 0 then
		for _, tag in SECTOR_TAGS do
			for _, inst in CollectionService:GetTagged(tag) do
				hideSector(inst)
			end
			table.insert(sectorConns, CollectionService:GetInstanceAddedSignal(tag):Connect(hideSector))
		end
	elseif not on and #sectorConns > 0 then
		for _, c in sectorConns do
			c:Disconnect()
		end
		table.clear(sectorConns)
		for _, tag in SECTOR_TAGS do
			for _, inst in CollectionService:GetTagged(tag) do
				if inst:IsA("BasePart") then
					inst.LocalTransparencyModifier = 0
				end
			end
		end
		for label, was in sectorLabels do
			label.Enabled = was
		end
		table.clear(sectorLabels)
	end
end

function DevCinematic.start(player: Player)
	local playerGui = player:WaitForChild("PlayerGui")

	-- a gui kept off by the cinematic Hud or by the Game switch
	local function keptOff(child: Instance): boolean
		return isHud(child) and DevCinematic.hidden(player, "Hud") or isGameGui(child) and DevCinematic.gameView(player)
	end

	local function applyHud()
		for _, child in playerGui:GetChildren() do
			if isHud(child) or isGameGui(child) then
				if keptOff(child) then
					holdOff(child :: LayerCollector)
				else
					release(child :: LayerCollector)
				end
			end
		end
	end

	-- DevUi: the dev pins and the settings gear; Game: the dev pins only (dev guis are built after this starts, so
	-- re-applied on each new gui)
	local function applyDev()
		local on = DevCinematic.hidden(player, "DevUi")
		local playerView = DevCinematic.gameView(player)
		for _, name in DevPanel.Panels do
			local g = playerGui:FindFirstChild(name)
			local gear = name == "SettingsMenu"
			local button = g and g:FindFirstChild(if gear then "Gear" else "Pin") :: GuiObject?
			if button then
				button.Visible = not on and not (playerView and not gear)
			end
			local panel = (on or playerView) and name ~= "DevAdminMenu" and not gear and g and g:FindFirstChild("Panel")
			if panel then
				(panel :: GuiObject).Visible = false
			end
		end
	end

	playerGui.ChildAdded:Connect(function(child)
		if keptOff(child) then
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

	-- every tool's arrival (in the backpack or straight into the hands), for the hidden hotbar's order
	player.DescendantAdded:Connect(stamp)
	for _, d in player:GetDescendants() do
		stamp(d)
	end
	local function watchCharacter(character: Model)
		character.ChildAdded:Connect(stamp)
	end
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and coreBefore and coreBefore[Enum.CoreGuiType.Backpack] then
			hotbarKey(player, input)
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
	local function applyGame()
		applyDev()
		applyHud()
		hideSectors(DevCinematic.gameView(player))
	end
	player:GetAttributeChangedSignal(C.GameAttribute):Connect(applyGame)
	applyGame()
end

return DevCinematic
