--!strict
-- The kit list (user 2026-10-27: "i dont like the robblox default one", "make it a kit list but move it on the left"):
-- Roblox's default hotbar is off; in its place, bottom left, one row per item carried this life (Config/Hud.Kit,
-- Rules/KitList; layout src/shared/ui/CombatHud.json "Kit"): its number key, its name (Config/Weapons `display`) and a
-- grenade's count. The row in the hands is darker, the team's rim on its left edge (Palette.UI.Hud.Teams by the
-- character's "Kit"). Shown for Kit.linger seconds after any change (a number key, a draw or put-away, an item come or
-- gone, a count), then faded out; kept up while build mode is open (src/client/Build); hidden while aiming (the
-- character's "Aiming", src/client/Stance) and with no living soldier. Once carried, a slot keeps its row for the life:
-- the last grenade thrown (the server destroys its Tool) leaves the row greyed at x0, so the keys never move.
-- The number keys only ask (Humanoid EquipTool / UnequipTools); the draw, the put-away and the draw queued behind it
-- stay in src/client/Locomotion and src/server/Armory.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudCfg = require(Shared.Config.Hud)
local Palette = require(Shared.Config.Palette)
local Stow = require(Shared.Config.Locomotion).Stow
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.KitList)
local Build = require(script.Parent.Build)
local HudKit = require(script.Parent.HudKit)

local KitList = {}

local K = HudCfg.Kit
local C = Palette.UI.Hud :: any
local rgb = HudKit.rgb

local function color(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- a slot carried this life: the Tool filling it now (nil: gone, the last grenade thrown), its name and count
type Slot = Rules.Row & { name: string, tool: Tool?, count: number? }

-- a row on screen and its pieces
type Row = { frame: Frame, edge: Frame, key: TextLabel, name: TextLabel, count: TextLabel }

function KitList.start()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	local player = Players.LocalPlayer
	local hud = HudKit.panel("Kit", "KitList", true) -- (the HUD size setting scales it)
	local template = hud.node.KitRow :: Frame
	template.Visible = false
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, K.gap)
	layout.Parent = hud.panel

	local slots: { [string]: Slot } = {}
	local order: { Slot } = {} -- the rows top to bottom (Rules/KitList.sort)
	local rows: { Row } = {}
	local arrivals = 0
	local changedAt = -math.huge
	local pending: Tool? = nil -- pressed while the last item was still being put away
	local pendingAt = 0
	local watched: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local drawn = "" -- what the rows show now (redrawn only when it changes)

	local function changed()
		changedAt = os.clock()
	end

	local function holders(): (Model?, Backpack?)
		return player.Character, player:FindFirstChildOfClass("Backpack")
	end

	-- the rows on screen: one per slot, cloned from the template
	local function rebuild()
		for _, r in rows do
			r.frame:Destroy()
		end
		table.clear(rows)
		for i in order do
			local f = template:Clone()
			f.Name = "Row" .. i
			f.LayoutOrder = i
			f.Visible = true
			f.Parent = hud.panel
			table.insert(rows, {
				frame = f,
				edge = f:FindFirstChild("KitEdge") :: Frame,
				key = f:FindFirstChild("KitKey") :: TextLabel,
				name = f:FindFirstChild("KitName") :: TextLabel,
				count = f:FindFirstChild("KitCount") :: TextLabel,
			})
			rows[i].key.Text = tostring(i)
		end
		drawn = ""
	end

	-- what the soldier carries now, into the slots (a slot once carried stays for the life)
	local function scan()
		local character, backpack = holders()
		local tools: { Tool } = {}
		for _, holder in { backpack :: Instance?, character :: Instance? } do
			for _, t in if holder then holder:GetChildren() else {} do
				if t:IsA("Tool") then
					table.insert(tools, t)
				end
			end
		end
		local seen: { [string]: boolean } = {}
		local added = false
		for _, tool in tools do
			local weapon = tool:GetAttribute("Weapon")
			local w = if type(weapon) == "string" then W[weapon] else nil
			local key = if w then w.slot else tool.Name
			if not seen[key] then
				seen[key] = true
				local count = tool:GetAttribute("Count")
				local s = slots[key]
				if not s then
					arrivals += 1
					s = { slot = key, first = arrivals, name = "", tool = nil, count = nil }
					slots[key] = s
					added = true
				end
				s.tool = tool
				s.name = if w then w.display else tool.Name
				s.count = if type(count) == "number" then count else nil
				if not watched[tool] then
					watched[tool] = true
					tool:GetAttributeChangedSignal("Count"):Connect(function()
						scan()
						changed()
					end)
				end
			end
		end
		for key, s in slots do
			if not seen[key] then
				s.tool = nil
				if s.count then
					s.count = 0 -- (the last grenade thrown: the server destroyed the Tool)
				end
			end
		end
		if added then
			local list: { Rules.Row } = {}
			for _, s in slots do
				table.insert(list, s)
			end
			order = Rules.sort(list, K.order) :: any
			rebuild()
		end
	end

	local function team(character: Model?): (Color3, Color3)
		local t = character and C.Teams[character:GetAttribute("Kit")]
		if t then
			return color(t.field), color(t.rim)
		end
		return rgb("field"), rgb("brass")
	end

	-- the rows' look at visibility `alpha`
	local function draw(alpha: number)
		local character = holders()
		local held = character and character:FindFirstChildOfClass("Tool")
		local now = os.clock()
		if pending and (pending.Parent == character or now - pendingAt > Stow.time + K.wait) then
			pending = nil
		end
		local chosen = held or pending
		local field, rim = team(character)
		local sig = string.format("%.3f|%s|%s|%s", alpha, tostring(chosen), tostring(field), tostring(rim))
		for _, s in order do
			sig ..= `|{s.name}:{s.count or -1}:{s.tool ~= nil}`
		end
		if sig == drawn then
			return
		end
		drawn = sig
		hud.gui.Enabled = alpha > 0
		local hide = 1 - alpha
		for i, s in order do
			local r = rows[i]
			local on = chosen ~= nil and s.tool == chosen
			local empty = s.tool == nil
			r.frame.BackgroundColor3 = field
			r.frame.BackgroundTransparency = 1 - (1 - (if on then K.fieldHeld else K.field)) * alpha
			r.edge.BackgroundColor3 = rim
			r.edge.BackgroundTransparency = if on then 1 - (1 - (if held then 0 else K.pending)) * alpha else 1
			r.key.TextColor3 = if on then rim else rgb("kitKey")
			r.name.Text = s.name
			r.name.TextColor3 = if empty then rgb("kitEmpty") elseif on then rgb("readout") else rgb("kitName")
			r.count.Visible = s.count ~= nil
			r.count.Text = string.format(K.count, s.count or 0)
			r.count.TextColor3 = if s.count == 0 then rgb("countLow") else rgb("count")
			for _, l in { r.key, r.name, r.count } do
				l.TextTransparency = hide
			end
		end
	end

	-- an item into or out of the hands or the backpack
	local function toolMoved(child: Instance)
		if child:IsA("Tool") then
			scan()
			changed()
		end
	end

	-- a new life: a new list (the backpack is a new one each life too)
	local function spawned(character: Model)
		table.clear(slots)
		table.clear(order)
		pending = nil
		rebuild()
		character.ChildAdded:Connect(toolMoved)
		character.ChildRemoved:Connect(toolMoved)
		scan()
		changed()
	end
	local function hookBackpack(child: Instance)
		if child:IsA("Backpack") then
			child.ChildAdded:Connect(toolMoved)
			child.ChildRemoved:Connect(toolMoved)
			scan()
		end
	end
	player.ChildAdded:Connect(hookBackpack)
	for _, c in player:GetChildren() do
		hookBackpack(c)
	end
	player.CharacterAdded:Connect(spawned)
	if player.Character then
		task.spawn(spawned, player.Character)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		local n = table.find(K.keys, input.KeyCode.Name)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if processed or not n or not character or not humanoid or humanoid.Health <= 0 then
			return
		end
		changed()
		local s = order[n]
		local tool = s and s.tool
		local action = Rules.press(n, #order, tool == nil, tool ~= nil and tool.Parent == character)
		if action == "draw" then
			humanoid:EquipTool(tool :: Tool)
			pending, pendingAt = tool, os.clock()
		elseif action == "stow" then
			pending = nil
			humanoid:UnequipTools()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 or #order == 0 then
			if hud.gui.Enabled then
				hud.gui.Enabled = false
				drawn = ""
			end
			return
		end
		draw(Rules.alpha(os.clock() - changedAt, Build.active(), character:GetAttribute("Aiming") == true, K))
	end)
end

return KitList
