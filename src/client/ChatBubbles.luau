--!strict
-- Keeps the chat bubbles (TextChatService.BubbleChatConfiguration) reading the same by day and night: their colours
-- (Config/ChatBubbles) are scaled down by Lighting.ExposureCompensation, which src/client/Environment lifts at night
-- and which would otherwise brighten the bubbles with the rest of the 3D view. Local only.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.ChatBubbles)

local ChatBubbles = {}

local function scaled(c: { number }, k: number): Color3
	return Color3.fromRGB(c[1] * k, c[2] * k, c[3] * k)
end

function ChatBubbles.start()
	local bubbles = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
	if not bubbles then
		return
	end
	local config = bubbles :: BubbleChatConfiguration
	config.BackgroundTransparency = Cfg.transparency

	local function apply()
		local k = 2 ^ -Lighting.ExposureCompensation
		config.BackgroundColor3 = scaled(Cfg.background, k)
		config.TextColor3 = scaled(Cfg.text, k)
	end

	apply()
	Lighting:GetPropertyChangedSignal("ExposureCompensation"):Connect(apply)
end

return ChatBubbles
