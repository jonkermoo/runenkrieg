--!strict
-- The marker over each squadmate (Config/Squads.Marker; user 2026-11-06: "always leaves an indicator above your squad
-- mate"): on this client only, a BillboardGui over the head of every living soldier in your squad but you (players and
-- the admin panel's test mates), drawn over everything (AlwaysOnTop) at any distance and the same size on screen: a
-- gold diamond with an ink edge, red while knocked down, the name over it. Gone for the fallen, during the match
-- cutscenes and while the admin panel hides the game HUD.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cfg = require(Shared.Config.Squads)
local Palette = require(Shared.Config.Palette)
local Squad = require(script.Parent.Squad)
local MatchCutscene = require(script.Parent.MatchCutscene)
local DevCinematic = require(script.Parent.DevCinematic)

local SquadMarkers = {}

local M = Cfg.Marker
local P = (Palette.UI :: any).Squad

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

type Marker = { gui: BillboardGui, diamond: Frame, name: TextLabel }

local markers: { [Model]: Marker } = {}

local function newMarker(parent: Instance): Marker
	local gui = Instance.new("BillboardGui")
	gui.Name = "SquadMarker"
	gui.AlwaysOnTop = true
	gui.MaxDistance = math.huge
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Size = UDim2.fromOffset(M.Width, M.Height)
	gui.StudsOffset = Vector3.new(0, M.Above, 0)
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, M.TextSize + 4)
	name.Font = Enum.Font.SourceSansBold
	name.TextSize = M.TextSize
	name.TextColor3 = rgb(P.name)
	name.TextStrokeColor3 = rgb(P.edge)
	name.TextStrokeTransparency = M.NameStroke
	name.Parent = gui
	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond"
	diamond.AnchorPoint = Vector2.new(0.5, 1)
	diamond.Position = UDim2.new(0.5, 0, 1, -M.Edge - 2)
	diamond.Size = UDim2.fromOffset(M.Diamond, M.Diamond)
	diamond.Rotation = 45
	diamond.BorderSizePixel = 0
	diamond.BackgroundColor3 = rgb(P.mate)
	local edge = Instance.new("UIStroke")
	edge.Thickness = M.Edge
	edge.Color = rgb(P.edge)
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = diamond
	diamond.Parent = gui
	gui.Parent = parent
	return { gui = gui, diamond = diamond, name = name }
end

local function refresh(holder: Instance)
	local me = Players.LocalPlayer
	local key = Squad.key()
	local want: { [Model]: { name: string, down: boolean, head: BasePart } } = {}
	if key and not MatchCutscene.playing() and not DevCinematic.hidden(me, "Hud") then
		for _, e in Squad.everyone() do
			local m = e.model
			local head = m and (m:FindFirstChild("Head") or m.PrimaryPart) :: BasePart?
			if
				e.key == key
				and not e.me
				and m
				and head
				and m:IsDescendantOf(workspace)
				and (e.status == "Action" or e.status == "Down" or e.status == "Wave")
			then
				want[m] = { name = e.name, down = e.status == "Down", head = head }
			end
		end
	end
	for m, mk in markers do
		if not want[m] then
			mk.gui:Destroy()
			markers[m] = nil
		end
	end
	for m, w in want do
		local mk = markers[m] or newMarker(holder)
		markers[m] = mk
		mk.gui.Adornee = w.head
		mk.name.Text = w.name
		mk.diamond.BackgroundColor3 = rgb(if w.down then P.down else P.mate)
	end
end

function SquadMarkers.start()
	-- (each marker straight under PlayerGui: a layer collector inside a Folder may not draw)
	local holder = Players.LocalPlayer:WaitForChild("PlayerGui")
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < M.Refresh then
			return
		end
		acc = 0
		refresh(holder)
	end)
end

return SquadMarkers
