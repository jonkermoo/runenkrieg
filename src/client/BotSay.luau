--!strict
-- A bot soldier's callout (src/server/Bots, Config/Bots.Callouts; user 2026-11-01: "make bots say stuff in chat (doesnt
-- appear in actual chat, just above their person)"): the server sends it only to players near the bot (Net "BotSay"),
-- shown here as a chat bubble over its head (src/client/ChatBubbles.say: the players' own bubbles), never in the chat
-- log.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local ChatBubbles = require(script.Parent.ChatBubbles)

local BotSay = {}

function BotSay.start()
	Net.event("BotSay").OnClientEvent:Connect(function(bot: any, text: any)
		if typeof(bot) ~= "Instance" or type(text) ~= "string" then
			return
		end
		if (bot :: Instance):IsA("Model") then
			ChatBubbles.say(bot :: Model, text)
		end
	end)
end

return BotSay
