--!strict
-- Healing on the server (H1; Config/Healing, Rules/Healing; docs/MILESTONES.md H1). The only place health goes up:
-- - Heals: a soldier asks (Net "Heal") to heal the hurt soldier they look at; never themselves (user 2026-10-18). The
--   server checks reach and that the patient is hurt and alive, picks the item by the patient's health (med pack from
--   70, bandage below), welds it to the healer's right hand and fills the patient's health a share at a time to full.
--   It stops (the health healed so far stays) when the healer is hit, the two move Break studs apart, either dies,
--   the healer asks to stop or draws a weapon. A finished bandage heal puts the patient's next wrap on (left arm,
--   right leg, head; then no more); the head wrap gives them the helmet-on hair (src/server/Helmets.shortHair).
--   The healer's "Healing" attribute (the item) and "HealPatient" ObjectValue tell the clients (src/client/Healing:
--   the crouch, the animations, facing the patient).
-- - Slow recovery: every soldier (players and DEV dummies) regains Recovery.rate a second up to Recovery.cap, from
--   Recovery.delay seconds after their health last dropped (DEV dummies only with Recovery.dummies, so they keep
--   their damage for tests).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Assets)
local Cfg = require(Shared.Config.Healing)
local DevCfg = require(Shared.Config.DevTools)
local Palette = require(Shared.Config.Palette)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.Healing)
local Helmets = require(script.Parent.Helmets)
local Ragdoll = require(script.Parent.Ragdoll)

local Healing = {}

type Heal = { healer: Model, patient: Model, kind: string, held: Model?, link: ObjectValue }

local heals: { [Model]: Heal } = {} -- by healer
local lastHit: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastHealth: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
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

-- A healer must be on their feet: not knocked down (src/server/Ragdoll) and not casting the staff.
local function able(healer: Model): boolean
	return not Ragdoll.active(healer) and healer:GetAttribute("Casting") ~= true
end

local function distance(a: Model, b: Model): number
	local ra, rb = a:FindFirstChild("HumanoidRootPart") :: BasePart?, b:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if ra and rb then (ra.Position - rb.Position).Magnitude else math.huge
end

-- The library model of a Config/Assets entry (ReplicatedStorage.Assets, kept by the Library sync), or nil.
local function library(name: string): Model?
	local e = A.Entries[name]
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and f:FindFirstChild(e.category)
	for _, part in string.split(e.folder, "/") do
		f = f and f:FindFirstChild(part)
	end
	local m = f and f:FindFirstChild(name)
	if not m then
		warn(`[Healing] {name} is not in the asset library: run the Library sync`)
	end
	return m :: Model?
end

-- A copy of an entry worn on `part`: its Origin on the part's centre moved by `offset` (part axes); each piece keeps
-- its imported rotation (the FBX pivot is rotated: never PivotTo), coloured from Palette.Medical, welded, no hits.
local function attach(entry: string, part: BasePart, offset: CFrame, name: string): Model?
	local src = library(entry)
	if not src then
		return nil
	end
	local model = src:Clone()
	local origin = model:FindFirstChild("Origin", true) :: BasePart?
	if not origin then
		warn(`[Healing] {entry}: no Origin marker`)
		return nil
	end
	local at = origin.Position
	origin:Destroy()
	model.Name = name
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CFrame = part.CFrame * offset * CFrame.new(p.Position - at) * p.CFrame.Rotation
			local c = Palette.Medical[p.Name]
			if c then
				p.Color = Color3.fromRGB(c[1], c[2], c[3])
			end
			p.Material = Enum.Material.SmoothPlastic
			p.Anchored = false
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			p.CastShadow = false
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = part, p
			w.Parent = p
		end
	end
	model.Parent = part.Parent
	return model
end

local function stop(healer: Model)
	local h = heals[healer]
	if not h then
		return
	end
	heals[healer] = nil
	if h.held then
		h.held:Destroy()
	end
	h.link:Destroy()
	healer:SetAttribute("Healing", nil)
end

-- The patient's next wrap after a finished bandage heal (none after the third).
local function wrap(patient: Model)
	local count = patient:GetAttribute("Wraps")
	local w = Rules.nextWrap(if type(count) == "number" then count else 0, Cfg)
	local part = w and patient:FindFirstChild(w.part) :: BasePart?
	if not w or not part then
		return
	end
	patient:SetAttribute("Wraps", (if type(count) == "number" then count else 0) + 1)
	attach(w.entry, part, CFrame.new(), "Wrap_" .. string.gsub(w.part, " ", ""))
	if w.part == "Head" then
		patient:SetAttribute("HeadWrap", true)
		Helmets.shortHair(patient)
	end
end

local function start(player: Player, patient: Model)
	local healer, hh = soldier(player.Character)
	local target, th = soldier(patient)
	if not healer or not hh or not target or not th or target == healer or heals[healer] then
		return
	end
	if hh.Health <= 0 or not able(healer) or not Rules.inReach(distance(healer, target), Cfg.Range, Cfg.StartSlack) then
		return
	end
	for _, other in heals do
		if other.patient == target then
			return -- one healer at a time
		end
	end
	local kind = Rules.kind(th.Health, th.MaxHealth, Cfg)
	if not kind then
		return
	end
	hh:UnequipTools()
	local arm = healer:FindFirstChild("Right Arm") :: BasePart?
	local g = Cfg.Held[kind]
	local held = arm and attach(g.entry, arm, CFrame.new(g.grip[1], g.grip[2], g.grip[3]), "HealItem")
	local link = Instance.new("ObjectValue")
	link.Name = "HealPatient"
	link.Value = target
	link.Parent = healer
	heals[healer] = { healer = healer, patient = target, kind = kind, held = held, link = link }
	healer:SetAttribute("Healing", kind)
end

-- Every hit that hurts (src/server/Damage): a healer hit stops healing. (The recovery's wait starts again from any
-- drop in health, wherever it came from: see tick.)
function Healing.hit(character: Model)
	stop(character)
end

local function tick(dt: number)
	for healer, h in heals do
		local _, hh = soldier(healer)
		local _, th = soldier(h.patient)
		if
			not hh
			or not th
			or hh.Health <= 0
			or th.Health <= 0
			or healer:FindFirstChildOfClass("Tool")
			or not able(healer)
			or not Rules.inReach(distance(healer, h.patient), Cfg.Break)
		then
			stop(healer)
			continue
		end
		th.Health = Rules.step(th.Health, th.MaxHealth, dt, Cfg)
		if th.Health >= th.MaxHealth then
			stop(healer)
			if h.kind == "Bandage" then
				wrap(h.patient)
			end
		end
	end
	local now = os.clock()
	local function recover(m: Model?)
		local _, hum = soldier(m)
		if m and hum then
			-- any drop in health (a hit, a fall, a dev tool) starts the wait again
			if hum.Health < (lastHealth[m] or hum.Health) - 1e-6 then
				lastHit[m] = now
			end
			local since = now - (lastHit[m] or -math.huge)
			local healing = false
			for _, h in heals do
				healing = healing or h.patient == m
			end
			if not healing then
				local v = Rules.recover(hum.Health, since, dt, Cfg)
				if v ~= hum.Health then
					hum.Health = v
				end
			end
			lastHealth[m] = hum.Health
		end
	end
	for _, p in Players:GetPlayers() do
		recover(p.Character)
	end
	if Cfg.Recovery.dummies then
		for _, m in CollectionService:GetTagged(DevCfg.Dummies.Tag) do
			recover(m)
		end
	end
end

function Healing.start()
	Net.event("Heal").OnServerEvent:Connect(function(player: Player, action: unknown, patient: unknown)
		local now = os.clock()
		if now - (lastAsk[player] or -math.huge) < Cfg.AskGap then
			return -- rate limited
		end
		lastAsk[player] = now
		if action == "Start" and typeof(patient) == "Instance" and patient:IsA("Model") then
			start(player, patient)
		elseif action == "Stop" then
			local c = player.Character
			if c then
				stop(c)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			stop(player.Character)
		end
	end)
	RunService.Heartbeat:Connect(tick)
end

return Healing
