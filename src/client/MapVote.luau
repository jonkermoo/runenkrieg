--!strict
-- The map vote between Normal matches (user 2026-11-02, Vote A "Campaign Table"; src/shared/ui/MapVote.json,
-- Config/Cutscenes.Vote, src/server/MapVote): while Workspace.Frontline's Phase is "Vote" the maps on offer
-- (VoteOffer) lie as sketch-map sheets on the table, each with its name and region, the wax seals of everyone who voted
-- for it (Votes_<key>: each voter's nation, its land colour and rune) and the count. A click on a sheet votes for it
-- (Net "MapVote"; changeable), its pencil edge marks your vote. The fuse along the bottom burns down to the vote's end;
-- then the losing sheets go and the winner (VotePick), alone in the middle, is stamped NEXT. The HUD, the dev pins, the
-- menus' contents and the soldier's controls are off meanwhile (MatchCutscene.cover); the mouse is free.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Cutscenes).Vote
local FrontCfg = require(Shared.Config.Frontline)
local Palette = require(Shared.Config.Palette)
local LiveMap = require(Shared.LiveMap)
local Net = require(Shared.Net)
local Spec = require(Shared.ui.MapVote) :: any
local Ink = require(script.Parent.Ink)
local MatchCutscene = require(script.Parent.MatchCutscene)
local Menus = require(script.Parent.Menus) :: any
local SketchMap = require(script.Parent.SketchMap)

local MapVote = {}

local GR = (Palette.UI :: any).Grimoire
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local player = Players.LocalPlayer
local SLOTS = 3 -- the spec's sheets (Card1..Card3)

function MapVote.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Menus.build(Spec, "MapVote", playerGui)
	screen.gui.DisplayOrder = Cfg.DisplayOrder
	local N = screen.node
	local scaleOf = function(): number
		local T = Spec.theme.scale
		return math.clamp(screen.gui.AbsoluteSize.Y / T.referenceHeight, T.min, T.max)
	end
	-- the sheets side by side in the middle, however many are on offer
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = N.Cards
	-- the fuse: its burnt line and the spark at the burning end
	local fuse = Instance.new("Frame")
	fuse.Name = "Line"
	fuse.AnchorPoint = Vector2.new(0, 0.5)
	fuse.Position = UDim2.fromScale(0, 0.5)
	fuse.BackgroundColor3 = rgb(GR.paper)
	fuse.BorderSizePixel = 0
	fuse.Parent = N.Fuse
	local spark = Instance.new("Frame")
	spark.Name = "Spark"
	spark.AnchorPoint = Vector2.new(0.5, 0.5)
	spark.BackgroundColor3 = rgb(GR.amber)
	spark.BorderSizePixel = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = spark
	spark.Parent = N.Fuse

	type Slot = { card: TextButton, key: string?, art: any, seals: { Frame }, drawn: string }
	local slots: { Slot } = {}
	for i = 1, SLOTS do
		local card = N["Card" .. i] :: TextButton
		card.LayoutOrder = i
		card.Modal = true -- (frees the mouse in first person while the vote shows)
		slots[i] = { card = card, key = nil, art = nil, seals = {}, drawn = "" }
	end
	local mine: string? = nil
	for _, s in slots do
		s.card.Activated:Connect(function()
			if s.key and screen.gui.Enabled then
				mine = s.key
				Net.event("MapVote"):FireServer(s.key)
			end
		end)
	end

	local function relayout()
		local s = scaleOf()
		list.Padding = UDim.new(0, Cfg.gap * s)
		fuse.Size = UDim2.new(fuse.Size.X.Scale, 0, 0, Cfg.fuse.thick * s)
		spark.Size = UDim2.fromOffset(Cfg.fuse.spark * s, Cfg.fuse.spark * s)
	end
	screen.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

	-- a sheet's wax seals, one per voter in vote order (drawn again only when the list changes)
	local function drawSeals(s: Slot, i: number, kits: { string })
		local text = table.concat(kits, ",")
		if text == s.drawn then
			return
		end
		s.drawn = text
		for _, f in s.seals do
			f:Destroy()
		end
		table.clear(s.seals)
		local holder = N["Seals" .. i] :: Frame
		local size = Cfg.seal.size * scaleOf()
		local step = size + Cfg.seal.gap * scaleOf()
		for k, kit in kits do
			local col, row = (k - 1) % Cfg.seal.perRow, (k - 1) // Cfg.seal.perRow
			local disc = Instance.new("Frame")
			disc.Name = "Seal" .. k
			disc.Size = UDim2.fromOffset(size, size)
			disc.Position = UDim2.fromOffset(col * step, row * step)
			disc.BackgroundColor3 = rgb(GR.Wash[kit] or GR.neutral)
			disc.BorderSizePixel = 0
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = disc
			local edge = Instance.new("UIStroke")
			edge.Color = rgb(GR.ink)
			edge.Thickness = 1.5
			edge.Parent = disc
			local box = Instance.new("Frame")
			box.BackgroundTransparency = 1
			box.AnchorPoint = Vector2.new(0.5, 0.5)
			box.Position = UDim2.fromScale(0.5, 0.5)
			box.Size = UDim2.fromScale(0.36, 0.6)
			box.Parent = disc
			disc.Parent = holder
			local rune = Cfg.Rune[kit]
			if rune then
				Ink.draw(box, function(h, w, hh)
					Ink.rune(h, rune, 0, 0, w, hh, math.max(1, hh * 0.14), rgb(GR.ink))
				end)
			end
			table.insert(s.seals, disc)
		end
	end

	local function fill(offer: { string })
		for i, s in slots do
			local key = offer[i]
			s.card.Visible = key ~= nil
			if key ~= s.key then
				if s.art then
					s.art.destroy()
					s.art = nil
				end
				s.key = key
				s.drawn = "-"
				if key then
					s.art = SketchMap.new(N["Art" .. i], key, { still = true })
				end
			end
			local stamp = N["Stamp" .. i] :: TextLabel
			stamp.Visible = false
			if key then
				local name, region = N["Name" .. i] :: TextLabel, N["Region" .. i] :: TextLabel
				name.Text = LiveMap.get(key).name
				region.Text = Cfg.Regions[key] or ""
			end
		end
	end

	local open = false
	local picked: string? = nil
	local function close()
		if not open then
			return
		end
		open = false
		screen.gui.Enabled = false
		MatchCutscene.cover(false)
	end

	RunService.RenderStepped:Connect(function()
		local folder = workspace:FindFirstChild(FrontCfg.FolderName)
		local phase = folder and folder:GetAttribute("Phase")
		local offerText = folder and folder:GetAttribute("VoteOffer")
		if phase ~= "Vote" or type(offerText) ~= "string" then
			close()
			return
		end
		local f = folder :: Instance
		local offer = string.split(offerText, ",")
		if not open then
			open = true
			mine, picked = nil, nil
			fill(offer)
			screen.gui.Enabled = true
			screen.relayout()
			relayout()
			MatchCutscene.cover(true)
		end
		-- the votes so far
		for i, s in slots do
			if s.key then
				local text = f:GetAttribute(`Votes_{s.key}`)
				local kits = if type(text) == "string" and text ~= "" then string.split(text, ",") else {}
				drawSeals(s, i, kits)
				local count = N["Count" .. i] :: TextLabel
				count.Text = tostring(#kits)
				local edge = s.card:FindFirstChild("Pick") :: UIStroke?
				if edge then
					edge.Enabled = mine == s.key
					edge.Thickness = 3 * scaleOf()
				end
			end
		end
		-- the fuse burning down
		local endsAt = f:GetAttribute("PhaseEndsAt")
		local left = if type(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
		local share = math.clamp(left / FrontCfg.VoteSeconds, 0, 1)
		fuse.Size = UDim2.new(share, 0, 0, fuse.Size.Y.Offset)
		spark.Position = UDim2.fromScale(share, 0.5)
		spark.Visible = share > 0
		spark.BackgroundTransparency = if math.floor(os.clock() / Cfg.fuse.flicker) % 2 == 0 then 0 else 0.35
		local clock = N.Clock :: TextLabel
		clock.Text = tostring(if left > 0 then math.ceil(left) else 0)
		-- the pick: the others go, the winner stamped
		local pick = f:GetAttribute("VotePick")
		if type(pick) == "string" and pick ~= picked then
			picked = pick
			for i, s in slots do
				local won = s.key == pick
				local stamp = N["Stamp" .. i] :: TextLabel
				s.card.Visible = won
				stamp.Visible = won
			end
		end
	end)
end

return MapVote
