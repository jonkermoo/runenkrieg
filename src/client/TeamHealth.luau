--!strict
-- Teammates' health over their heads while the map key is held (Config/TeamHealth, Rules/TeamHealth; user 2026-11-03:
-- "can we add teammate HP being visible (when close) when holding M?"): a small flat bar over each teammate in range
-- (players and bot soldiers of the viewer's kit, Rules/Teams), red with Down over it when knocked down (the
-- "Ragdolled" attribute, src/server/Ragdoll), amber when hurt enough for a bandage. Never an enemy's. Off on the title
-- and loadout screens and in the match's cutscenes. Client only: the Humanoid's health is already replicated.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.TeamHealth)
local BotsCfg = require(Shared.Config.Bots)
local HealCfg = require(Shared.Config.Healing)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.TeamHealth)
local Teams = require(Shared.Rules.Teams)
local Settings = require(script.Parent.Settings)

local TeamHealth = {}

local C = Palette.UI.Hud :: any
local function tok(name: string): Color3
	local c = C[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end
local FILL: { [Rules.Look]: Color3 } = { Ok = tok("healthOk"), Low = tok("healthLow"), Down = tok("healthDown") }
local SCREENS = { "TitleScreen", "LoadoutMenu", "MatchCutscene", "EndScenes" } -- (any of these on: no bars)

type Bar = { gui: BillboardGui, fill: Frame, down: TextLabel }

local function newBar(parent: Instance): Bar
	local B, D = Cfg.Bar, Cfg.Down
	local g = Instance.new("BillboardGui")
	g.Name = "TeamHealth"
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.ResetOnSpawn = false
	g.Size = UDim2.fromOffset(B.width, B.height + D.tall)
	g.StudsOffset = Vector3.new(0, Cfg.Bar.above, 0)
	g.MaxDistance = Cfg.Range * 1.5 -- (the range check is the loop's; this only stops a far one drawing)
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.fromScale(0.5, 1)
	track.Size = UDim2.fromOffset(B.width, B.height)
	track.BackgroundColor3 = tok("healthTrack")
	track.BorderSizePixel = 0
	local edge = Instance.new("UIStroke")
	edge.Thickness = B.edge
	edge.Color = tok("healthEdge")
	edge.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = track
	track.Parent = g
	local down = Instance.new("TextLabel")
	down.Name = "Down"
	down.BackgroundTransparency = 1
	down.Size = UDim2.new(1, 0, 0, D.tall)
	down.Font = Enum.Font.GothamBold
	down.TextSize = D.size
	down.Text = D.text
	down.TextColor3 = tok("healthDown")
	down.TextStrokeColor3 = tok("healthEdge")
	down.TextStrokeTransparency = 0.2
	down.Parent = g
	g.Parent = parent
	return { gui = g, fill = fill, down = down }
end

function TeamHealth.start()
	local me = Players.LocalPlayer
	local playerGui = me:WaitForChild("PlayerGui")
	local holder = Instance.new("Folder")
	holder.Name = "TeamHealth"
	holder.Parent = playerGui
	local bars: { [Model]: Bar } = {}
	local function screenOn(): boolean
		for _, name in SCREENS do
			local g = playerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") and g.Enabled then
				return true
			end
		end
		return false
	end
	local function drop(m: Model)
		local b = bars[m]
		if b then
			b.gui:Destroy()
			bars[m] = nil
		end
	end
	-- the key read every frame, so the bars go the moment it is let go (they come at the next look)
	local held = false
	RunService.RenderStepped:Connect(function()
		held = Settings.held("Key_Map")
		if not held then
			for m in bars do
				drop(m)
			end
		end
	end)
	task.spawn(function()
		while true do
			local mine = me.Character
			local root = mine and mine:FindFirstChild("HumanoidRootPart") :: BasePart?
			local on = held and root ~= nil and not screenOn()
			local seen: { [Model]: boolean } = {}
			if on then
				local kit = (mine :: Model):GetAttribute("Kit")
				local ffa = workspace:GetAttribute(ZoneCfg.FreeForAllAttribute) == true
				local function consider(m: Instance?)
					if not m or m == mine or not m:IsA("Model") or seen[m] then
						return
					end
					local head = m:FindFirstChild("Head")
					local their = m:FindFirstChild("HumanoidRootPart")
					local h = m:FindFirstChildOfClass("Humanoid")
					if not (head and head:IsA("BasePart") and their and their:IsA("BasePart") and h) then
						return
					end
					local far = ((their :: BasePart).Position - (root :: BasePart).Position).Magnitude
					if not Rules.shown(Teams.same(kit, m:GetAttribute("Kit"), ffa), h.Health, far, Cfg.Range) then
						return
					end
					seen[m] = true
					local b = bars[m] or newBar(holder)
					bars[m] = b
					b.gui.Adornee = head
					local share, look = Rules.look(h.Health, h.MaxHealth, m:GetAttribute("Ragdolled") == true, HealCfg)
					b.fill.Size = UDim2.fromScale(share, 1)
					b.fill.BackgroundColor3 = FILL[look]
					b.down.Visible = look == "Down"
				end
				for _, p in Players:GetPlayers() do
					if p ~= me then
						consider(p.Character)
					end
				end
				for _, m in CollectionService:GetTagged(BotsCfg.Tag) do
					consider(m)
				end
			end
			for m in bars do
				if not seen[m] then
					drop(m)
				end
			end
			task.wait(Cfg.Refresh)
		end
	end)
end

return TeamHealth
