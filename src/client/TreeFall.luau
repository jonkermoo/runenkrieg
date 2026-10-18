--!strict
-- Felled and stripped trees, on each client (src/server/Trees tags them; no physics, nothing replicated per frame):
-- - FallingTag: the tree turns from where it stands to its "FallTo" over "FallTime" s, speeding up like a real fall;
-- - SinkingTag: it goes down "SinkDepth" studs over "SinkTime" s and fades out, before the server removes it;
-- - FallingTag ends with a small bounce back off the ground about "FallHinge" (Fall.bounce);
-- - ShedTag: its canopy fades out over "ShedTime" s while
--   leaves fall from all over it (Config/Firing.Effects.Impacts.
--   Shed), before the server removes the canopy. Not sudden (user 2026-10-17).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.TreeSway)
local Damage = require(Shared.Config.Damage)
local Firing = require(Shared.Config.Firing)
local Impacts = require(script.Parent.Impacts)

local TreeFall = {}

local Fall = Damage.Trees.Fall
local Shed = Firing.Effects.Impacts.Shed

-- calls `step(a)` each frame with a running from 0 to 1 over `time` s, while `inst` is in the world
local function over(inst: Instance, time: number, step: (number, number) -> ())
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if not inst.Parent then
			conn:Disconnect()
			return
		end
		local a = math.clamp((os.clock() - start) / math.max(time, 1e-3), 0, 1)
		step(a, dt)
		if a >= 1 then
			conn:Disconnect()
		end
	end)
end

local function number(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	return if type(v) == "number" then v else default
end

local function fall(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local tree = inst
	local to = tree:GetAttribute("FallTo")
	if typeof(to) ~= "CFrame" then
		tree:GetAttributeChangedSignal("FallTo"):Wait()
		to = tree:GetAttribute("FallTo")
	end
	if typeof(to) == "CFrame" then
		local from = tree:GetPivot()
		local hinge, axis = tree:GetAttribute("FallHinge"), tree:GetAttribute("FallAxis")
		over(tree, number(tree, "FallTime", Fall.time), function(a)
			tree:PivotTo(from:Lerp(to, a * a)) -- starts slow, crashes down
			if a >= 1 and typeof(hinge) == "Vector3" and typeof(axis) == "Vector3" then
				-- it bounces back a little off the ground and settles
				over(tree, Fall.bounceTime, function(u)
					local back = math.rad(Fall.bounce) * math.sin(math.pi * u) * (1 - u)
					tree:PivotTo(CFrame.new(hinge) * CFrame.fromAxisAngle(axis, -back) * CFrame.new(-hinge) * to)
				end)
			end
		end)
	end
end

local function sink(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local from = inst:GetPivot()
	local depth = number(inst, "SinkDepth", Fall.sinkDepth)
	local parts = {}
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, { d, d.Transparency })
		end
	end
	over(inst, number(inst, "SinkTime", Fall.sinkTime), function(a)
		inst:PivotTo(from - Vector3.yAxis * depth * a)
		for _, p in parts do
			p[1].Transparency = p[2] + (1 - p[2]) * a
		end
	end)
end

local function shed(inst: Instance)
	local canopy = inst:FindFirstChild("Canopy") :: BasePart?
	if not canopy then
		return
	end
	local owed = 0
	over(canopy, number(inst, "ShedTime", Damage.Trees.Leaves.shedTime), function(a, dt)
		canopy.Transparency = a
		owed += Shed.perSecond * dt * (1 - a * (1 - Shed.endRate))
		while owed >= 1 do
			owed -= 1
			local s = canopy.Size * Shed.spread
			local at = canopy.CFrame
				* Vector3.new((math.random() - 0.5) * s.X, (math.random() - 0.5) * s.Y, (math.random() - 0.5) * s.Z)
			Impacts.leaves(at, canopy.Color, 1)
		end
	end)
end

function TreeFall.start()
	CollectionService:GetInstanceAddedSignal(Cfg.FallingTag):Connect(function(inst)
		task.spawn(fall, inst)
	end)
	CollectionService:GetInstanceAddedSignal(Cfg.SinkingTag):Connect(sink)
	CollectionService:GetInstanceAddedSignal(Cfg.ShedTag):Connect(shed)
end

return TreeFall
