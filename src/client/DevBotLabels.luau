--!strict
-- The admin panel's bot state labels (Config/DevTools.Admin.BotState): while Workspace has the attribute, a label over
-- each bot showing the text src/server/Bots sets on its model once a commander tick (its order and sector, squad phase
-- and role, post, act, gun, danger). Only for players the server marked with the DevTools attribute; off in the
-- admin panel's Game view and with the cinematic "Dev buttons" hidden (src/client/DevCinematic).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local BotsCfg = require(Shared.Config.Bots)
local DevCinematic = require(script.Parent.DevCinematic)

local DevBotLabels = {}

local S = Cfg.Admin.BotState
local EVERY = 0.5 -- seconds between looks at the bots (the server's text changes once a second)

local function make(head: BasePart, parent: Instance): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "DevBotLabel"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(S.width, S.tall)
	gui.StudsOffsetWorldSpace = Vector3.new(0, S.height, 0)
	gui.MaxDistance = S.range
	gui.ResetOnSpawn = false
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = S.size
	text.TextColor3 = Color3.new(1, 1, 0.85)
	text.TextStrokeTransparency = 0.3
	text.TextWrapped = true
	text.Parent = gui
	gui.Parent = parent
	return gui, text
end

function DevBotLabels.start()
	local player = Players.LocalPlayer
	local shown: { [Model]: { gui: BillboardGui, text: TextLabel } } = {}
	local holder: Folder? = nil
	task.spawn(function()
		while true do
			task.wait(EVERY)
			local on = workspace:GetAttribute(S.attribute) == true
				and player:GetAttribute(Cfg.Attribute) == true
				and not DevCinematic.gameView(player)
				and not DevCinematic.hidden(player, "DevUi")
			local bots = on and workspace:FindFirstChild(BotsCfg.Folder)
			local seen: { [Model]: boolean } = {}
			if bots then
				if not holder or not holder.Parent then
					local f = Instance.new("Folder")
					f.Name = "DevBotLabels"
					f.Parent = player:WaitForChild("PlayerGui")
					holder = f
				end
				for _, m in bots:GetChildren() do
					local label = m:GetAttribute(S.label)
					local head = m:FindFirstChild("Head")
					if m:IsA("Model") and type(label) == "string" and head and head:IsA("BasePart") then
						seen[m] = true
						local s = shown[m]
						if not s or not s.gui.Parent or s.gui.Adornee ~= head then
							if s then
								s.gui:Destroy()
							end
							local gui, text = make(head, holder :: Folder)
							s = { gui = gui, text = text }
							shown[m] = s
						end
						(s :: any).text.Text = label
					end
				end
			end
			for m, s in shown do
				if not seen[m] then
					s.gui:Destroy()
					shown[m] = nil
				end
			end
		end
	end)
end

return DevBotLabels
