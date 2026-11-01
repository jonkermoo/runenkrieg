--!strict
-- The results screen at a match's end (src/shared/ui/Results.json, Config/Results, Rules/MatchStats; user 2026-10-31:
-- Normal "R3 map table", FFA "F1 standings ledger"). Net "MatchResults" (src/server/MatchStats) opens it: the winner
-- (Normal: the nation in its colour; FFA: the player), TAKES THE FIELD, the three honours with their runes, your own
-- line and the next match's countdown; on the right Normal's sketch map replaying the match's captures
-- (src/client/SketchMap.replay) or FFA's standings, each row's bar filling in turn. It closes when the next match is
-- due.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Results)
local FrontCfg = require(Shared.Config.Frontline)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local Net = require(Shared.Net)
local Spec = require(Shared.ui.Results) :: any
local Ink = require(script.Parent.Ink)
local Menus = require(script.Parent.Menus) :: any
local SketchMap = require(script.Parent.SketchMap)

local Results = {}

local GR = (Palette.UI :: any).Grimoire
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- 1240 -> "1,240"
local function commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", c.R * 255, c.G * 255, c.B * 255)
end

function Results.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Menus.build(Spec, "Results", playerGui)
	screen.gui.DisplayOrder = Cfg.DisplayOrder
	local N = screen.node
	local youLabel, nextLabel, takes = N.You :: TextLabel, N.Next :: TextLabel, N.Takes :: TextLabel
	local map = SketchMap.new(N.MapHolder, FrontCfg.MapKey, {})
	local runes = {}
	for i = 1, #Cfg.Honours do
		runes[i] = Ink.canvas(N["Rune" .. i])
	end
	local template = N.LedgerRow
	template.Visible = false
	local rows: { Frame } = {}
	local endsAt = 0
	local standings: { { [string]: any } } = {}
	local shownAt = 0

	-- FFA's standings: a row per entry under the template, each bar filling in turn from when the screen opened
	local function placeRows()
		for _, r in rows do
			r:Destroy()
		end
		table.clear(rows)
		local top = standings[1] and standings[1].value or 0
		for k, e in standings do
			local row = template:Clone()
			row.Name = "Row" .. k
			row.Visible = true
			row.Position = template.Position + UDim2.fromOffset(0, (k - 1) * template.Size.Y.Offset * 1.1)
			local place = row:FindFirstChild("Place") :: TextLabel
			local name = row:FindFirstChild("Name") :: TextLabel
			local value = row:FindFirstChild("Value") :: TextLabel
			place.Text = tostring(e.place)
			name.Text = e.name
			value.Text = commas(e.value)
			if e.me then
				local pick = Instance.new("UIStroke")
				pick.Color = rgb(GR.pencil)
				pick.Thickness = 2
				pick.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				pick.Parent = name
			end
			local track = row:FindFirstChild("Track") :: Frame
			local bar = Instance.new("Frame")
			bar.Name = "Bar"
			bar.BorderSizePixel = 0
			bar.BackgroundColor3 = rgb(GR.ink)
			local share = if top > 0 then math.clamp(e.value / top, 0, 1) else 0
			local L = Cfg.Ledger
			local start = shownAt + L.lead + (k - 1) * L.stagger
			local done = math.clamp((os.clock() - start) / L.fill, 0, 1)
			bar.Size = UDim2.fromScale(share * done, 1)
			bar.Parent = track
			if done < 1 then
				TweenService:Create(
					bar,
					TweenInfo.new(
						L.fill * (1 - done),
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.Out,
						0,
						false,
						math.max(start - os.clock(), 0)
					),
					{ Size = UDim2.fromScale(share, 1) }
				):Play()
			end
			row.Parent = template.Parent
			table.insert(rows, row)
		end
	end
	screen.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(function()
			if screen.gui.Enabled and #standings > 0 then
				placeRows()
			end
		end)
	end)

	local function close()
		screen.gui.Enabled = false
		map.stopReplay()
	end

	Net.event("MatchResults").OnClientEvent:Connect(function(r: any)
		if type(r) ~= "table" then
			return
		end
		local normal = r.mode == "Normal"
		-- the winner: Normal's nation in its colour, FFA's player in amber
		local winner = N.Winner :: TextLabel
		local kit = normal and r.winner and (U.Kits :: any)[r.winner]
		if kit then
			winner.Text = string.upper(kit.team)
			winner.TextColor3 = rgb(GR.Name and GR.Name[r.winner] or GR.text)
		elseif not normal and type(r.winner) == "string" then
			winner.Text = r.winner
			winner.TextColor3 = rgb(GR.amber)
		else
			winner.Text = Cfg.NoWinner
			winner.TextColor3 = rgb(GR.text)
		end
		takes.Visible = winner.Text ~= Cfg.NoWinner
		-- the honours
		local dim = hex(rgb(GR.dim))
		for i, h in Cfg.Honours do
			local got = r.honours and r.honours[h.key]
			local line = N["Honour" .. i] :: TextLabel
			local value = N["Value" .. i] :: TextLabel
			if got then
				line.Text = `{got.name} <font color="{dim}" size="20">{h.word}</font>`
				value.Text = commas(got.value)
			else
				line.Text = `<font color="{dim}">Nobody · {h.word}</font>`
				value.Text = ""
			end
			runes[i].set(function(holder, w, hh)
				Ink.rune(holder, h.rune, 0, 0, w, hh, math.max(1, w * 0.14), rgb(GR.amber))
			end)
		end
		-- your line
		local you = r.you or {}
		if normal then
			youLabel.Text = `You · {you.Kills or 0} kills · {commas(you.Healed or 0)} HP healed · {commas(
				you.Built or 0
			)} HP built · +{commas(you.Earned or 0)}`
		else
			local mine = nil
			for _, e in r.standings or {} do
				if e.me then
					mine = e
				end
			end
			youLabel.Text = if mine
				then `You · {mine.place}. · {you.Kills or 0} kills · {commas(mine.value)} points`
				else `You · {you.Kills or 0} kills`
		end
		-- the right: the replay or the standings
		endsAt = type(r.endsAt) == "number" and r.endsAt or workspace:GetServerTimeNow() + FrontCfg.ResultsSeconds
		shownAt = os.clock()
		N.MapHolder.Visible = normal
		N.Ledger.Visible = not normal
		standings = if normal then {} else (r.standings or {})
		screen.gui.Enabled = true
		screen.relayout()
		if normal then
			map.replay(r.log or {}, r.winner ~= nil)
		else
			placeRows()
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not screen.gui.Enabled then
			return
		end
		local left = endsAt - workspace:GetServerTimeNow()
		if left <= -0.5 then
			close()
			return
		end
		nextLabel.Text = `Next match in {math.max(math.ceil(left), 0)}`
	end)
end

return Results
