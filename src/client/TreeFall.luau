--!strict
-- Felled trees fall and sink here, on each client (src/server/Trees tags them; no physics, nothing replicated per
-- frame): a "FallingTree" turns from where it stands to its "FallTo" over "FallTime" s, speeding up like a real fall;
-- a "SinkingTree" goes down "SinkDepth" studs over "SinkTime" s before the server removes it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.TreeSway)

local TreeFall = {}

-- moves `tree` from `from` by `shape(a)` toward `to` over `time` s
local function animate(tree: Model, from: CFrame, to: CFrame, time: number, shape: (number) -> number)
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not tree.Parent then
			conn:Disconnect()
			return
		end
		local a = math.clamp((os.clock() - start) / math.max(time, 1e-3), 0, 1)
		tree:PivotTo(from:Lerp(to, shape(a)))
		if a >= 1 then
			conn:Disconnect()
		end
	end)
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
	local time = tree:GetAttribute("FallTime")
	if typeof(to) == "CFrame" then
		animate(tree, tree:GetPivot(), to, if type(time) == "number" then time else 2, function(a)
			return a * a -- starts slow, crashes down
		end)
	end
end

local function sink(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local depth, time = inst:GetAttribute("SinkDepth"), inst:GetAttribute("SinkTime")
	local from = inst:GetPivot()
	local d = if type(depth) == "number" then depth else 6
	animate(inst, from, from - Vector3.yAxis * d, if type(time) == "number" then time else 2, function(a)
		return a
	end)
end

function TreeFall.start()
	CollectionService:GetInstanceAddedSignal(Cfg.FallingTag):Connect(function(inst)
		task.spawn(fall, inst)
	end)
	CollectionService:GetInstanceAddedSignal(Cfg.SinkingTag):Connect(sink)
end

return TreeFall
