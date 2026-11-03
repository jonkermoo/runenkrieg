--!strict
-- Teammates' health as a coloured outline (Config/TeamHealth, Rules/TeamHealth): the nearest living teammates (the
-- same "Kit" as your soldier, Rules/Teams: players, bot soldiers and the admin panel's dummies; nobody in a
-- free-for-all) each get a Highlight on this client only, adorning their character, its outline shaded from green at
-- full health to red when badly hurt (Palette.UI.TeamHealth). Roblox draws at most 31 Highlights at once, so only
-- Cfg.MaxOutlines of them, the nearest. Off during the match cutscenes and while the admin panel hides the game HUD.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cfg = require(Shared.Config.TeamHealth)
local BotsCfg = require(Shared.Config.Bots)
local DevCfg = require(Shared.Config.DevTools)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.TeamHealth)
local Teams = require(Shared.Rules.Teams)
local MatchCutscene = require(script.Parent.MatchCutscene)
local DevCinematic = require(script.Parent.DevCinematic)

local TeamHealth = {}

local outlines: { [Model]: Highlight } = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function newOutline(model: Model): Highlight
	local h = Instance.new("Highlight")
	h.Name = "TeamHealth"
	h.FillTransparency = Cfg.FillTransparency
	h.OutlineTransparency = Cfg.OutlineTransparency
	h.DepthMode = (Enum.HighlightDepthMode :: any)[Cfg.DepthMode]
	h.Adornee = model
	h.Parent = workspace.CurrentCamera -- (client only)
	return h
end

-- the living teammates to outline now (nearest first, at most the cap), each with its humanoid
local function wanted(me: Player): { [Model]: Humanoid }
	local out: { [Model]: Humanoid } = {}
	local mine = me.Character
	if
		not mine
		or me:GetAttribute(Cfg.OffAttribute) == true
		or MatchCutscene.playing()
		or DevCinematic.hidden(me, "Hud")
	then
		return out
	end
	local kit = mine:GetAttribute("Kit")
	local ffa = workspace:GetAttribute(ZoneCfg.FreeForAllAttribute) == true
	local andMe = me:GetAttribute(Cfg.SelfAttribute) == true
	local eye = workspace.CurrentCamera.CFrame.Position
	local candidates: { { key: Model, dist: number } } = {}
	local humanoids: { [Model]: Humanoid } = {}
	local function consider(m: Model?)
		if not m or not m:IsDescendantOf(workspace) then
			return
		end
		if m == mine then
			if not andMe then
				return
			end
		elseif not Teams.same(kit, m:GetAttribute("Kit"), ffa) then
			return
		end
		local h = m:FindFirstChildOfClass("Humanoid")
		local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if h and root and h.Health > 0 then
			humanoids[m] = h
			table.insert(candidates, { key = m, dist = (root.Position - eye).Magnitude })
		end
	end
	for _, p in Players:GetPlayers() do
		consider(p.Character)
	end
	for _, tag in { BotsCfg.Tag, DevCfg.Dummies.Tag } do -- (bot soldiers; the admin panel's target dummies)
		for _, m in CollectionService:GetTagged(tag) do
			if m:IsA("Model") then
				consider(m)
			end
		end
	end
	for _, m in Rules.pick(candidates, Cfg.MaxOutlines, Cfg.MaxDistance) do
		out[m] = humanoids[m]
	end
	return out
end

local function refresh()
	local want = wanted(Players.LocalPlayer)
	for m, h in outlines do
		if not want[m] then
			h:Destroy()
			outlines[m] = nil
		end
	end
	for m, humanoid in want do
		local h = outlines[m] or newOutline(m)
		outlines[m] = h
		h.OutlineColor = rgb(Rules.shade(humanoid.Health, humanoid.MaxHealth, Palette.UI.TeamHealth))
	end
end

function TeamHealth.start()
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= Cfg.Rate then
			since = 0
			refresh()
		end
	end)
end

return TeamHealth
