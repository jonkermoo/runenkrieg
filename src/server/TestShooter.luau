--!strict
-- Far shooters at the test range (Config/DevTools.TestShooter), to hear shots from the other end (src/client/ShotAudio):
-- soldiers at the range's far end fire back up it in turn while Workspace has the attribute set. Their shots go out
-- like a player's ("Shot", with real hits). DEV place only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools).TestShooter
local FiringCfg = require(Shared.Config.Firing)
local Range = require(Shared.Config.Range)
local ShowcaseCfg = require(Shared.Config.Showcase)
local Net = require(Shared.Net)
local Firing = require(script.Parent.Firing)
local Showcase = require(script.Parent.Showcase)

local TestShooter = {}

local function shoot(m: Model, tool: Tool, target: Vector3)
	local gun = tool:FindFirstChild("Gun") :: BasePart?
	local muzzle = gun and gun:FindFirstChild("Muzzle") :: Attachment?
	if not muzzle then
		return
	end
	local origin = muzzle.WorldPosition
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { m }
	local name = tool:GetAttribute("Weapon") :: string
	local hits = {}
	for _, line in Firing.lines(name, (target - origin).Unit, math.random(1, 2147483646)) do
		local r = workspace:Raycast(origin, line * FiringCfg.Range, params)
		table.insert(
			hits,
			{ if r then r.Position else origin + line * FiringCfg.Range, r and r.Normal, r and r.Instance }
		)
	end
	local first = table.remove(hits, 1) :: any
	Net.event("Shot"):FireAllClients(m, name, origin, first[1], first[2], first[3], if #hits > 0 then hits else nil)
end

function TestShooter.start()
	if game.PlaceId ~= ShowcaseCfg.PlaceId then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "DevTestShooter"
	folder.Parent = workspace
	local O = Vector3.new(Range.Origin[1], Range.Origin[2], Range.Origin[3])
	local target = O + Vector3.new(Cfg.aim[1], Cfg.aim[2], 0)
	local soldiers = {}
	for i, s in Cfg.Shooters do
		local pos = O + Vector3.new(s.x, 3, s.z) -- the root's height over the floor
		local m = Showcase.dummy(`Test shooter {i}`, CFrame.lookAt(pos, Vector3.new(target.X, pos.Y, target.Z)), folder)
		m:SetAttribute("Muted", nil) -- heard, unlike the showcase's
		table.insert(soldiers, { m = m, tool = Showcase.arm(m, s.weapon) })
	end
	task.spawn(function()
		local turn = 0
		while true do
			task.wait(Cfg.every)
			if workspace:GetAttribute(Cfg.Attribute) == true then
				turn = turn % #soldiers + 1
				shoot(soldiers[turn].m, soldiers[turn].tool, target)
			end
		end
	end)
end

return TestShooter
