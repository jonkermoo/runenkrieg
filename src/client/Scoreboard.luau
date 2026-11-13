--!strict
-- The Tab scoreboard (user 2026-11-12: "Holding Tab shows a scoreboard and tints or blurs the screen behind it"):
-- while Tab is held, the match behind darkened and blurred, both sides side by side (src/shared/ui/Scoreboard.json
-- Board, Config/Hud.Board), each soldier's kills, assists, HP healed and HP built this match, most kills first, your
-- own row lit, bots as "[BOT] Name". A Normal match lists each side under its own army (yours on the left); a mode
-- without sides (FFA) splits everyone across the two panels by rank. The rows come from the server while Tab is held
-- (Net "Scores", src/server/MatchStats.board). Roblox's own player list is off (it took Tab too).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudCfg = require(Shared.Config.Hud) :: any
local ModesCfg = require(Shared.Config.Modes)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local Net = require(Shared.Net)
local Spec = require(Shared.ui.Scoreboard) :: any
local HudKit = require(script.Parent.HudKit)

local Scoreboard = {}

local TEAMS = (Palette.UI :: any).Hud.Teams :: { [string]: { field: { number }, rim: { number } } }
local NAMES = ((Palette.UI :: any).Grimoire.Name or {}) :: { [string]: { number } }
local COLS = { "Name", "K", "A", "Heal", "Built" }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

type Row = { id: number, name: string, kit: string?, Kills: number, Assists: number, Healed: number, Built: number }

-- most kills first, then assists, then the name
local function sorted(rows: { Row }): { Row }
	table.sort(rows, function(a, b)
		if a.Kills ~= b.Kills then
			return a.Kills > b.Kills
		elseif a.Assists ~= b.Assists then
			return a.Assists > b.Assists
		end
		return a.name < b.name
	end)
	return rows
end

function Scoreboard.start()
	local B = HudCfg.Board
	local player = Players.LocalPlayer
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	local board = HudKit.panel("Board", "Scoreboard", false, Spec)
	board.gui.DisplayOrder = 20 -- (over the HUD)
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BorderSizePixel = 0
	shade.BackgroundColor3 = HudKit.rgb("window")
	shade.BackgroundTransparency = B.shade
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 1
	shade.Parent = board.gui
	local blur = Instance.new("BlurEffect")
	blur.Name = "ScoreboardBlur"
	blur.Size = B.blur
	blur.Enabled = false
	blur.Parent = Lighting

	local n = board.node
	local sides = {
		{ panel = n.Left :: Frame, name = n.LeftName :: TextLabel, total = n.LeftTotal :: TextLabel, row = n.LeftRow },
		{
			panel = n.Right :: Frame,
			name = n.RightName :: TextLabel,
			total = n.RightTotal :: TextLabel,
			row = n.RightRow,
		},
	}
	local made: { GuiObject } = {}
	for _, s in sides do
		s.row.Visible = false
	end

	-- one side's panel: its title, colours and rows
	local function fill(s: any, title: string, kit: string?, rows: { Row })
		local team = kit and TEAMS[kit]
		s.panel.BackgroundColor3 = if team then rgb(team.field) else HudKit.rgb("field")
		local stroke = s.panel:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if team then rgb(team.rim) else HudKit.rgb("brass")
		end
		local tint = kit and NAMES[kit]
		s.name.Text = title
		s.name.TextColor3 = if tint then rgb(tint) else HudKit.rgb("readout")
		local kills = 0
		for i, r in rows do
			kills += r.Kills
			if i > B.rows then
				continue
			end
			local line = s.row:Clone() :: Frame
			line.Visible = true
			line.Position = s.row.Position + UDim2.fromOffset(0, (i - 1) * B.rowGap)
			local mine = r.id == player.UserId
			if mine then
				line.BackgroundColor3 = HudKit.rgb("brassDark")
				line.BackgroundTransparency = 0.35
			end
			local values = { r.name, r.Kills, r.Assists, r.Healed, r.Built }
			for c, key in COLS do
				local l = line:FindFirstChild(s.row.Name .. key) :: TextLabel?
				if l then
					l.Text = tostring(values[c])
					l.TextColor3 = HudKit.rgb(if mine then "kitHeld" else "readout")
				end
			end
			line.Parent = s.panel
			table.insert(made, line)
		end
		s.total.Text = if title == "" then "" else `{kills} kills`
	end

	local function show(rows: { Row })
		for _, l in made do
			l:Destroy()
		end
		table.clear(made)
		local mode = workspace:GetAttribute(ModesCfg.Attribute)
		if mode == "Normal" then
			-- each side under its army, yours on the left
			local mine: string? = nil
			local character = player.Character
			local k = character and character:GetAttribute("Kit")
			for _, r in rows do
				if r.id == player.UserId and r.kit then
					mine = r.kit
				end
			end
			mine = if type(k) == "string" then k else mine
			local kits: { string } = {}
			local by: { [string]: { Row } } = {}
			for _, r in rows do
				local kit = r.kit
				if kit then
					if not by[kit] then
						by[kit] = {}
						table.insert(kits, kit)
					end
					table.insert(by[kit], r)
				end
			end
			table.sort(kits, function(a, b)
				if a == mine or b == mine then
					return a == mine
				end
				return a < b
			end)
			for i, s in sides do
				local kit = kits[i]
				local def = kit and (U.Kits :: any)[kit]
				fill(s, if def then def.team else "", kit, if kit then sorted(by[kit]) else {})
			end
		else
			-- no sides: everyone by rank across both panels
			local all = sorted(rows)
			local half = math.ceil(#all / 2)
			local left, right = {}, {}
			for i, r in all do
				table.insert(if i <= half then left else right, r)
			end
			fill(sides[1], "Soldiers", nil, left)
			fill(sides[2], "", nil, right)
		end
	end

	Net.event("Scores").OnClientEvent:Connect(function(rows: any)
		if type(rows) ~= "table" then
			return
		end
		local clean: { Row } = {}
		for _, r in rows do
			if type(r) == "table" and type(r.id) == "number" and type(r.name) == "string" then
				table.insert(clean, {
					id = r.id,
					name = r.name,
					kit = if type(r.kit) == "string" then r.kit else nil,
					Kills = tonumber(r.Kills) or 0,
					Assists = tonumber(r.Assists) or 0,
					Healed = tonumber(r.Healed) or 0,
					Built = tonumber(r.Built) or 0,
				})
			end
		end
		show(clean)
	end)

	local held, opened = false, 0
	local function open(on: boolean)
		held = on
		board.gui.Enabled = on
		blur.Enabled = on
		if on then
			opened += 1
			local this = opened
			task.spawn(function()
				while held and opened == this do
					Net.event("Scores"):FireServer()
					task.wait(B.every)
				end
			end)
		end
	end
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.Tab and not processed and not held then
			open(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Tab and held then
			open(false)
		end
	end)
end

return Scoreboard
