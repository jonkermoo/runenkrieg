--!strict
-- Openable doors: every Model tagged Config.Destruction.DoorTag (in Workspace) has a ProximityPrompt on
-- its panel. Triggering swings the door about its Hinge (panel-space attribute) by SwingAngle. State is
-- the "Open" attribute, so toggle() is stateless and safe to call from anywhere on the server. The prompt is drawn in
-- the game's own look (Style Custom, tagged Config/Prompts.Tag: src/client/Prompts), reach Config/Prompts.Door.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local D = require(Shared.Config.Destruction)
local PromptCfg = require(Shared.Config.Prompts)

local Doors = {}

local SWING_TIME = 0.35

function Doors.toggle(door: Model)
	if door:GetAttribute("Busy") or not door.Parent then
		return
	end
	door:SetAttribute("Busy", true)
	local panel = door.PrimaryPart
	if not panel then
		door:SetAttribute("Busy", nil)
		return
	end
	if door:GetAttribute("ClosedPivot") == nil then
		door:SetAttribute("ClosedPivot", door:GetPivot())
		door:SetAttribute("ClosedPanel", panel.CFrame)
	end
	local closed = door:GetAttribute("ClosedPivot") :: CFrame
	-- rotate about the hinge line (Hinge attribute, panel space) by SwingAngle around the panel's up axis
	local closedPanel = door:GetAttribute("ClosedPanel") :: CFrame
	local hinge = closedPanel * CFrame.new(door:GetAttribute("Hinge") or Vector3.zero)
	local full = math.rad(door:GetAttribute("SwingAngle") or -90)
	local function at(angle: number): CFrame
		return hinge * CFrame.Angles(0, angle, 0) * hinge:Inverse() * closed
	end
	local opening = not door:GetAttribute("Open")
	local a0, a1 = if opening then 0 else full, if opening then full else 0
	local t = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		t = math.min(1, t + dt / SWING_TIME)
		local a = 1 - (1 - t) ^ 3 -- ease out
		if door.Parent then
			door:PivotTo(at(a0 + (a1 - a0) * a)) -- follow the hinge arc
		end
		if t >= 1 then
			conn:Disconnect()
			door:SetAttribute("Open", opening)
			door:SetAttribute("Busy", nil)
			local prompt = door:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt then
				prompt.ActionText = if opening then "Close" else "Open"
			end
		end
	end)
end

local function hook(door: Instance)
	if not door:IsA("Model") or not door:IsDescendantOf(workspace) or door:GetAttribute("DoorHooked") then
		return
	end
	local prompt = door:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		door:SetAttribute("DoorHooked", true)
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.MaxActivationDistance = PromptCfg.Door.reach
		CollectionService:AddTag(prompt, PromptCfg.Tag)
		prompt.Triggered:Connect(function()
			Doors.toggle(door)
		end)
	end
end

function Doors.start()
	for _, d in CollectionService:GetTagged(D.DoorTag) do
		hook(d)
	end
	CollectionService:GetInstanceAddedSignal(D.DoorTag):Connect(hook)
	-- doors in templates moved into Workspace later (e.g. map build) get hooked when they arrive
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			local model = d:FindFirstAncestorWhichIsA("Model")
			while model and not CollectionService:HasTag(model, D.DoorTag) do
				model = model:FindFirstAncestorWhichIsA("Model")
			end
			if model then
				hook(model)
			end
		end
	end)
end

return Doors
