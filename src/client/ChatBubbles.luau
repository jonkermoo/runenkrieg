--!strict
-- The chat bubbles over heads (TextChatService.BubbleChatConfiguration, Config/ChatBubbles).
-- Roblox's own player bubbles are off: it lifts a player's bubble over the top of everything in the character (the
-- rifle slung on the back raised it far over the head), so each chat message a player sends shows here instead, on a
-- small invisible marker just over the speaker's head (outside the character, so nothing worn counts), only when the
-- speaker is within range of the camera. Bot callouts (src/client/BotSay) show the same way.
-- Their colours are scaled down by Lighting.ExposureCompensation, which src/client/Environment lifts at night and which
-- would otherwise brighten the bubbles with the rest of the 3D view. Local only.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.ChatBubbles)

local ChatBubbles = {}

local function scaled(c: { number }, k: number): Color3
	return Color3.fromRGB(c[1] * k, c[2] * k, c[3] * k)
end

-- each speaking model's marker over its head
local anchors: { [Model]: BasePart } = {}
local folder: Folder? = nil

local function anchorOf(model: Model): BasePart
	local made = anchors[model]
	if made then
		return made
	end
	if not folder then
		local f = Instance.new("Folder")
		f.Name = Cfg.anchor
		f.Parent = workspace
		folder = f
	end
	local a = Instance.new("Part")
	a.Name = model.Name
	a.Anchored = true
	a.CanCollide, a.CanQuery, a.CanTouch = false, false, false
	a.Transparency = 1
	a.CastShadow = false
	a.Size = Vector3.one * Cfg.anchorSize
	a.Parent = folder
	anchors[model] = a
	return a
end

local function head(model: Model): BasePart?
	local h = model:FindFirstChild("Head")
	return if h and h:IsA("BasePart") then h else nil
end

-- Shows `text` in a bubble over `model`'s head, if it is within range of the camera.
function ChatBubbles.say(model: Model, text: string)
	local h = head(model)
	local camera = workspace.CurrentCamera
	if not h or not camera or (h.Position - camera.CFrame.Position).Magnitude > Cfg.range then
		return
	end
	local a = anchorOf(model)
	a.Position = h.Position + Vector3.new(0, Cfg.lift, 0)
	pcall(function()
		TextChatService:DisplayBubble(a, text)
	end)
end

function ChatBubbles.start()
	local bubbles = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
	if not bubbles then
		return
	end
	local config = bubbles :: BubbleChatConfiguration
	config.BackgroundTransparency = Cfg.transparency
	config.MaxDistance = Cfg.range
	config.MinimizeDistance = Cfg.minimize

	local function apply()
		local k = 2 ^ -Lighting.ExposureCompensation
		config.BackgroundColor3 = scaled(Cfg.background, k)
		config.TextColor3 = scaled(Cfg.text, k)
	end

	apply()
	Lighting:GetPropertyChangedSignal("ExposureCompensation"):Connect(apply)

	-- players' messages: Roblox's bubbles off (DisplayBubble still shows), each message on the speaker's marker
	config.Enabled = false
	TextChatService.MessageReceived:Connect(function(message: TextChatMessage)
		local source = message.TextSource
		local speaker = source and Players:GetPlayerByUserId(source.UserId)
		local character = speaker and speaker.Character
		if character and message.Text ~= "" then
			ChatBubbles.say(character, message.Text)
		end
	end)

	-- the markers follow their heads; a body gone from the world takes its marker with it
	RunService.RenderStepped:Connect(function()
		for model, a in anchors do
			local h = head(model)
			if not model.Parent then
				anchors[model] = nil
				a:Destroy()
			elseif h then
				a.Position = h.Position + Vector3.new(0, Cfg.lift, 0)
			end
		end
	end)
end

return ChatBubbles
