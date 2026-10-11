--!strict
-- Replaces Roblox's default Animate script (same name in StarterCharacterScripts). Runs on each spawn of the
-- local character and hands it to src/client/Locomotion.
local Players = game:GetService("Players")

local client = (Players.LocalPlayer :: Player):WaitForChild("PlayerScripts"):WaitForChild("Client")
require(client:WaitForChild("Locomotion") :: any).attach(script.Parent :: Model)
