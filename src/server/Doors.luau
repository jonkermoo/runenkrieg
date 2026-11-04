--!strict
-- Openable doors: every Model tagged Config.Destruction.DoorTag (in Workspace) has a ProximityPrompt on
-- its panel. Triggering swings the door about its Hinge (panel-space attribute) by SwingAngle. State is
-- the "Open" attribute, so toggle() is stateless and safe to call from anywhere on the server. The prompt is drawn in
-- the game's own look (Style Custom, tagged Config/Prompts.Tag: src/client/Prompts), reach Config/Prompts.Door.
-- Pathfinding goes through a shut door: every part of one gets a PathfindingModifier (Config/Indoors.Door, cost
-- Config/Indoors.PathCosts), passing through while it is shut; open, it stands in the room and paths go round it
-- (user 2026-11-04 play test: "opening the door breaks their path finding"). For a soldier who isn't a player
-- (Rules/Indoors):
--   Doors.nearest(at, within) -> Model?    the nearest door still standing, by its shut place
--   Doors.isOpen(door) -> boolean
--   Doors.openFor(model, door) -> boolean    opens it if the model's root is in the prompt's reach (true if it is open
--                                            or opening now; never shuts it)
--   Doors.passage(door) -> (Vector3, Vector3)?    the points outside and inside its doorway (its PathfindingLink's ends:
--                                                 src/server/Indoors)
--   Doors.onSwung(fn(door))    after any door has swung open or shut (the bots' paths near it go stale)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local D = require(Shared.Config.Destruction)
local IndoorsCfg = require(Shared.Config.Indoors)
local PromptCfg = require(Shared.Config.Prompts)
local Rules = require(Shared.Rules.Indoors)

local Indoors = require(script.Parent.Indoors)

local Doors = {}

local SWING_TIME = 0.35

local swung: { (Model) -> () } = {}

function Doors.onSwung(fn: (Model) -> ())
	table.insert(swung, fn)
end

-- pathfinding goes through the door while it is shut (a path goes through it and the soldier opens it on the way), and
-- round it while it is open
local function passable(door: Instance)
	local through = door:GetAttribute("Open") ~= true
	for _, part in door:GetDescendants() do
		if part:IsA("BasePart") then
			local m = part:FindFirstChildWhichIsA("PathfindingModifier")
			if not m then
				m = Instance.new("PathfindingModifier")
				m.Label = IndoorsCfg.Door.label
				m.Parent = part
			end
			(m :: PathfindingModifier).PassThrough = through
		end
	end
end

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
			passable(door)
			for _, fn in swung do
				task.spawn(fn, door)
			end
			local prompt = door:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt then
				prompt.ActionText = if opening then "Close" else "Open"
			end
		end
	end)
end

local function p(v: Vector3): Rules.P
	return { x = v.X, y = v.Y, z = v.Z }
end

local function standing(door: Instance): boolean
	return door:IsA("Model") and door:IsDescendantOf(workspace) and door.PrimaryPart ~= nil
end

-- where the door's panel is when shut (it swings away from the doorway when open)
local function shutAt(door: Model): Vector3
	local closed = door:GetAttribute("ClosedPanel")
	return if typeof(closed) == "CFrame" then closed.Position else (door.PrimaryPart :: BasePart).Position
end

function Doors.nearest(at: Vector3, within: number): Model?
	local doors: { Model } = {}
	local points: { Rules.P } = {}
	for _, d in CollectionService:GetTagged(D.DoorTag) do
		if standing(d) then
			table.insert(doors, d :: Model)
			table.insert(points, p(shutAt(d :: Model)))
		end
	end
	local i = Rules.nearest(points, p(at), within)
	return if i then doors[i] else nil
end

function Doors.isOpen(door: Model): boolean
	return door:GetAttribute("Open") == true
end

function Doors.openFor(model: Model, door: Model): boolean
	if not standing(door) then
		return false
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not (root and root:IsA("BasePart")) then
		return false
	end
	-- the prompt's rule: within its reach of the panel where it is now
	if not Rules.reaches(p(root.Position), p((door.PrimaryPart :: BasePart).Position), PromptCfg.Door.reach) then
		return false
	end
	if door:GetAttribute("Busy") then
		return not Doors.isOpen(door) -- swinging open already, or shutting
	end
	if not Doors.isOpen(door) then
		Doors.toggle(door)
	end
	return true
end

function Doors.passage(door: Model): (Vector3?, Vector3?)
	local section = door.Parent
	local l = section and section:FindFirstChild("DoorwayLink")
	if l and l:IsA("PathfindingLink") and l.Attachment0 and l.Attachment1 then
		return l.Attachment0.WorldPosition, l.Attachment1.WorldPosition
	end
	local piece = section and Indoors.piece(section)
	if not (piece and piece.kind == "door") then
		return nil, nil
	end
	local outside, inside = Rules.passage(piece, IndoorsCfg.Links)
	return Vector3.new(outside.x, outside.y, outside.z), Vector3.new(inside.x, inside.y, inside.z)
end

local function hook(door: Instance)
	if not door:IsA("Model") or not door:IsDescendantOf(workspace) then
		return
	end
	passable(door)
	if door:GetAttribute("DoorHooked") then
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
