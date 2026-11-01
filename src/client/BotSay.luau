--!strict
-- A bot soldier's callout (src/server/Bots, Config/Bots.Callouts; user 2026-11-01: "make bots say stuff in chat (doesnt
-- appear in actual chat, just above their person)"): the server sends it only to players near the bot (Net "BotSay"),
-- shown here as a chat bubble over its head (TextChatService:DisplayBubble: the players' own bubble look, src/client/
-- ChatBubbles), never in the chat log.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local BotSay = {}

function BotSay.start()
	Net.event("BotSay").OnClientEvent:Connect(function(bot: any, text: any)
		if typeof(bot) ~= "Instance" or type(text) ~= "string" then
			return
		end
		local head = (bot :: Instance):FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			pcall(function()
				TextChatService:DisplayBubble(head, text)
			end)
		end
	end)
end

return BotSay
