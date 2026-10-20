--!strict
-- Digging with the shovel on the server (docs/MILESTONES.md SV1; Config/Shovel, Rules/Shovel). The digger's client
-- says when the blade strikes (Net "Dig", src/client/Shovel); the server checks the shovel is in the hands and a dig's
-- length has passed since the last, finds where the blade lands from its own view of the soldier (ahead of the root,
-- the ground under it within reach of the feet), lowers the ground there a step (src/server/Ground.bowl, never deeper
-- than Dig.maxDepth below the ground as it first was, per Dig.cell: a neighbouring dig's bowl can take a cell up to
-- one step further), and tells everyone where, for the dirt chips (Net "Dug").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Shovel)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Shovel)
local Net = require(Shared.Net)
local Ground = require(script.Parent.Ground)

local Shovel = {}

local D = Cfg.Dig

function Shovel.start()
	local last: { [Player]: number } = {}
	local first: { [string]: number } = {} -- each cell's ground height before its first dig
	Net.event("Dig").OnServerEvent:Connect(function(player: Player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local tool = character and character:FindFirstChildOfClass("Tool")
		local name = tool and tool:GetAttribute("Weapon")
		if not root or not humanoid or humanoid.Health <= 0 or type(name) ~= "string" then
			return
		end
		if not W[name] or W[name].class ~= "Shovel" then
			return
		end
		local now = os.clock()
		if now - (last[player] or -math.huge) < D.length * D.slack then
			return
		end
		last[player] = now
		local look = root.CFrame.LookVector
		local p = root.Position
		local x, z = Rules.spot(p.X, p.Z, look.X, look.Z, D.forward)
		local feet = p.Y - D.feet
		local h = Ground.heightAt(x, z, feet + D.above, D.above + D.below)
		if not h or not Rules.inReach(h, feet, D.above, D.below) then
			return
		end
		local key = Rules.cell(x, z, D.cell)
		first[key] = first[key] or h
		local lower = Rules.lower(h, first[key], D.depth, D.maxDepth)
		if lower <= 0 then
			return -- as deep as it goes here
		end
		Ground.bowl(Vector3.new(x, h, z), D.radius, lower)
		Net.event("Dug"):FireAllClients(Vector3.new(x, h, z))
	end)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
end

return Shovel
