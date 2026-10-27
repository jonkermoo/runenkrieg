--!strict
-- Barbed wire shakes and rattles each tick someone pushes through it, either team (user 2026-10-27: "add a shaking
-- animation for whenever it ticks damage to players", "add a chain / wire sound for each damage tick (the damage tick
-- animation should still go off on teammates and the sound cue goes off)"): src/server/Wire sets the wire's
-- "RattleFrom" and "ShakeAt"; here its shown meshes wobble on this client only (Rules/Build.wireShake, Config/Build.Wire),
-- the pickets less than the wire, then go back to where the server put them, and one of Wire.sounds plays from there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local Rules = require(Shared.Rules.Build)
local SoundFx = require(script.Parent.SoundFx)

type Shake = {
	started: number,
	parts: { { part: BasePart, rest: CFrame, dir: Vector3, k: number } },
}

local WireShake = {}

local shaking: { [Model]: Shake } = {}
local stepping: RBXScriptConnection? = nil

local function settle(s: Shake)
	for _, p in s.parts do
		p.part.CFrame = p.rest
	end
end

local function step()
	local now = os.clock()
	for model, s in shaking do
		local t = now - s.started
		if t >= C.Wire.shake or not model.Parent then
			settle(s)
			shaking[model] = nil
		else
			local d = Rules.wireShake(t, C.Wire)
			for _, p in s.parts do
				p.part.CFrame = p.rest + p.dir * (d * p.k)
			end
		end
	end
	if next(shaking) == nil and stepping then
		stepping:Disconnect()
		stepping = nil
	end
end

local function shake(model: Model)
	local holder = model:FindFirstChild("Wire")
	if not holder then
		return
	end
	local s = shaking[model]
	if s then
		s.started = os.clock() -- (shaken again while shaking: from where its parts rest)
	else
		s = { started = os.clock(), parts = {} }
		local frame = model:GetAttribute("Frame")
		local along = if typeof(frame) == "CFrame" then frame.RightVector else Vector3.xAxis
		for _, p in holder:GetChildren() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				-- each mesh sways across the line and a little up and down, the pickets `picket` as far
				local k = if string.find(p.Name, "Pickets") then C.Wire.picket else 1
				local dir = (along:Cross(Vector3.yAxis) * (if #s.parts % 2 == 0 then 1 else -0.7) + Vector3.yAxis * 0.4).Unit
				table.insert(s.parts, { part = p, rest = p.CFrame, dir = dir, k = k })
			end
		end
		shaking[model] = s
	end
	if not stepping then
		stepping = RunService.RenderStepped:Connect(step)
	end
end

local function watch(model: Instance)
	if model:IsA("Model") and model:GetAttribute("Piece") == "Wire" then
		model:GetAttributeChangedSignal("ShakeAt"):Connect(function()
			shake(model)
			local from = model:GetAttribute("RattleFrom")
			local sounds = C.Wire.sounds
			if typeof(from) == "Vector3" then
				SoundFx.play(sounds[math.random(#sounds)], from)
			end
		end)
	end
end

function WireShake.start()
	task.spawn(function()
		local folder = workspace:WaitForChild(C.Folder)
		for _, m in folder:GetChildren() do
			watch(m)
		end
		folder.ChildAdded:Connect(watch)
	end)
end

return WireShake
