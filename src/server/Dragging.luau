--!strict
-- Dragging a downed teammate on the server (Config/Dragging, Rules/Dragging; user 2026-10-22). A soldier asks (Net
-- "Drag") to drag the knocked-down, living teammate they look at (Rules/Teams); the server checks it, takes the body's
-- physics (a player's body is its own client's while down: src/server/Ragdoll) and holds its Humanoid limp, and an
-- AlignPosition per leg pulls the body's ankles to the dragger's hands. Only the body is pulled, with a capped force, so it
-- slides head last and still catches on walls. (A one-attachment pull whose goal the server moves to the
-- hands every frame: a constraint between the two bodies would give both one network owner.) While "Dragged" is on, the body doesn't get up
-- (src/server/Ragdoll); once let go the usual settle and get-up wait starts over. The dragged soldier breaks free and
-- stands (Net "Drag" "Escape", Config/Settings Key_DragEscape) only once their knock's own stand-up time is over: the
-- drag never shortens it (src/server/Ragdoll.served).
-- It lets go (Rules/Dragging.keep) on the Drag key, the dragger knocked down or dead, the body dead or up, a weapon
-- drawn, a heal or a staff cast started, or the body caught Break studs behind; the player gets their body's physics
-- back, and the dragger takes out again what they held before the drag (hands still free). The dragger's "Dragging" attribute and "DragBody" ObjectValue tell the clients (src/client/Dragging: the slow
-- walk, no sprint, jump or aim, facing the body, the pull animation).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Dragging)
local DevCfg = require(Shared.Config.DevTools)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.Dragging)
local Teams = require(Shared.Rules.Teams)
local Kits = require(script.Parent.Kits)
local Ragdoll = require(script.Parent.Ragdoll)

local Dragging = {}

-- (`held`: the tool the dragger put away to drag, taken out again after)
type Drag = { dragger: Model, body: Model, pulls: { AlignPosition }, made: { Instance }, held: Tool? }

local PARTS = { "HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local drags: { [Model]: Drag } = {} -- by dragger
local lastAsk: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function soldier(m: Instance?): (Model?, Humanoid?)
	if not m or not m:IsA("Model") or not m:IsDescendantOf(workspace) then
		return nil, nil
	end
	if not (Players:GetPlayerFromCharacter(m) or CollectionService:HasTag(m, DevCfg.Dummies.Tag)) then
		return nil, nil
	end
	local h = m:FindFirstChildOfClass("Humanoid")
	return if h then m else nil, h
end

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function distance(a: Model, b: Model): number
	local ra, rb = a:FindFirstChild("HumanoidRootPart") :: BasePart?, b:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if ra and rb then (ra.Position - rb.Position).Magnitude else math.huge
end

-- (`starting`: whatever is in the hands is put away at the start; drawn during the drag, it lets go)
local function state(dragger: Model, dh: Humanoid, body: Model, bh: Humanoid, starting: boolean?): Rules.State
	local holding = not starting and dragger:FindFirstChildOfClass("Tool") ~= nil
	local busy = holding or dragger:GetAttribute("Healing") ~= nil or dragger:GetAttribute("Casting") == true
	return {
		same = dragger == body,
		team = Teams.same(Kits.of(dragger), Kits.of(body)),
		draggerHealth = dh.Health,
		draggerDown = Ragdoll.active(dragger),
		draggerBusy = busy,
		bodyHealth = bh.Health,
		bodyDown = Ragdoll.active(body),
		distance = distance(dragger, body),
	}
end

-- The body's physics: the server's while dragged, its player's again after (a dummy's stays the server's). Every part:
-- the loosened joints split a ragdoll into an assembly per limb (src/server/DevDummies, Studio round 2).
local function own(body: Model, server: boolean)
	local player = Players:GetPlayerFromCharacter(body)
	if not server and not player then
		return
	end
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") and not p.Anchored and p:IsDescendantOf(workspace) and p:CanSetNetworkOwnership() then
			p:SetNetworkOwner(if server then nil else player)
		end
	end
end

local function stop(dragger: Model)
	local d = drags[dragger]
	if not d then
		return
	end
	drags[dragger] = nil
	for _, i in d.made do
		i:Destroy()
	end
	dragger:SetAttribute("Dragging", nil)
	-- back to what they were doing: the tool put away for the drag, if the hands are still free and they're on their feet
	local dh = dragger:FindFirstChildOfClass("Humanoid")
	local player = Players:GetPlayerFromCharacter(dragger)
	if
		d.held
		and dh
		and dh.Health > 0
		and player
		and d.held.Parent == player:FindFirstChildOfClass("Backpack")
		and not dragger:FindFirstChildOfClass("Tool")
		and not Ragdoll.active(dragger)
		and dragger:GetAttribute("Healing") == nil
	then
		dh:EquipTool(d.held)
	end
	if d.body.Parent then
		d.body:SetAttribute("Dragged", nil)
		local h = d.body:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then
			own(d.body, false) -- (a dead body's physics stays the server's: src/server/Ragdoll)
		end
	end
end

local function start(player: Player, target: Model)
	local dragger, dh = soldier(player.Character)
	local body, bh = soldier(target)
	if not dragger or not dh or not body or not bh or drags[dragger] then
		return
	end
	if body:GetAttribute("Dragged") == true or not Rules.canStart(state(dragger, dh, body, bh, true), Cfg, true) then
		return -- (one dragger per body)
	end
	local root = dragger:FindFirstChild("HumanoidRootPart") :: BasePart?
	local legs: { BasePart } = {}
	for _, name in Cfg.Legs do
		local leg = body:FindFirstChild(name) :: BasePart?
		if leg then
			table.insert(legs, leg)
		end
	end
	if #legs == 0 or not root then
		return
	end
	local held = dragger:FindFirstChildOfClass("Tool")
	dh:UnequipTools()
	-- the body's physics to the server, held limp there (the server's Humanoid would otherwise try to stand it up)
	own(body, true)
	bh:ChangeState(Enum.HumanoidStateType.Physics)
	local made: { Instance } = {}
	local pulls: { AlignPosition } = {}
	for _, leg in legs do
		local ankle = Instance.new("Attachment")
		ankle.Name = "DragAnkle"
		ankle.Position = vec(Cfg.Ankle)
		ankle.Parent = leg
		local pull = Instance.new("AlignPosition")
		pull.Name = "DragPull"
		pull.Mode = Enum.PositionAlignmentMode.OneAttachment
		pull.Attachment0 = ankle
		pull.Position = root.CFrame:PointToWorldSpace(vec(Cfg.Grip))
		pull.ApplyAtCenterOfMass = false -- at the ankle: the body swings round behind it
		pull.MaxForce = Cfg.MaxForce / #legs
		pull.MaxVelocity = Cfg.MaxVelocity
		pull.Responsiveness = Cfg.Responsiveness
		pull.Parent = leg
		table.insert(pulls, pull)
		table.insert(made, ankle)
		table.insert(made, pull)
	end
	local link = Instance.new("ObjectValue")
	link.Name = "DragBody"
	link.Value = body
	link.Parent = dragger
	table.insert(made, link)
	drags[dragger] = { dragger = dragger, body = body, pulls = pulls, made = made, held = held }
	body:SetAttribute("Dragged", true)
	dragger:SetAttribute("Dragging", true)
end

local function tick()
	for dragger, d in drags do
		local _, dh = soldier(dragger)
		local _, bh = soldier(d.body)
		if not dh or not bh or not Rules.keep(state(dragger, dh, d.body, bh), Cfg) then
			stop(dragger)
			continue
		end
		-- the pull's goal: the dragger's hands
		local hands = dragger:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hands then
			local goal = hands.CFrame:PointToWorldSpace(vec(Cfg.Grip))
			for _, pull in d.pulls do
				pull.Position = goal
			end
		end
		-- the body's physics stays the server's for the whole drag
		for _, name in PARTS do
			local p = d.body:FindFirstChild(name) :: BasePart?
			if p and not p.Anchored and p:GetNetworkOwner() ~= nil then
				own(d.body, true)
				break
			end
		end
	end
end

function Dragging.start()
	Net.event("Drag").OnServerEvent:Connect(function(player: Player, action: unknown, body: unknown)
		local now = os.clock()
		if now - (lastAsk[player] or -math.huge) < Cfg.AskGap then
			return -- rate limited
		end
		lastAsk[player] = now
		if action == "Start" and typeof(body) == "Instance" and body:IsA("Model") then
			start(player, body)
		elseif action == "Stop" then
			local c = player.Character
			if c then
				stop(c)
			end
		elseif action == "Escape" then
			-- the dragged soldier breaks free, only once their knock's stand-up time is over (Ragdoll.served)
			local c = player.Character
			if c and c:GetAttribute("Dragged") == true and Ragdoll.served(c) then
				for dragger, d in drags do
					if d.body == c then
						stop(dragger)
					end
				end
				Ragdoll.rise(c)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local c = player.Character
		if not c then
			return
		end
		stop(c)
		for dragger, d in drags do
			if d.body == c then
				stop(dragger)
			end
		end
	end)
	RunService.Heartbeat:Connect(tick)
end

return Dragging
