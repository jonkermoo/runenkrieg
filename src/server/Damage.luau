--!strict
-- Health, damage, death and respawn on the server (M12; Config/Damage, Rules/Damage, Rules/Blast; docs/MILESTONES.md
-- M12). The server is the only one that hurts anyone:
-- - Damage.shot: a gun's hits from src/server/Firing's own raycast: by weapon class and zone (head, torso, limbs; the
--   helmet hit never fatal by itself), the pellets' falloff; then the knock by the zone that took the most
--   (src/server/Ragdoll).
-- - Damage.staff: a staff shot (src/server/StaffCast): a sphere cast as wide as the beam, as long as the stage's range,
--   from the caster's head toward its aim; the stage's damage and knock, no zones, no falloff; where it lands, the
--   stage's blast (only the full beam has one).
-- - Damage.blast: a real-scaled blast (Rules/Blast): soldiers hurt and knocked by the overpressure at their torso, map
--   sections by their class (src/server/Destruction.blast), trees by their HP (src/server/Trees), a crater with a rim
--   and churned earth round it.
-- No one hurts themselves (their blast still knocks them). Health 100 and no regeneration (src/character/Health);
-- a death is a limp ragdoll (the death face: src/server/Bodies); respawn after Config/Metrics.Combat.RespawnDelay.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Damage)
local DevCfg = require(Shared.Config.DevTools)
local Metrics = require(Shared.Config.Metrics)
local W = require(Shared.Config.Weapons)
local Blast = require(Shared.Rules.Blast)
local Rules = require(Shared.Rules.Damage)
local TreeRules = require(Shared.Rules.Trees)
local Destruction = require(script.Parent.Destruction)
local Ragdoll = require(script.Parent.Ragdoll)
local Ground = require(script.Parent.Ground)
local Trees = require(script.Parent.Trees)

local Damage = {}

-- DEV test tools (src/server/DevDummies, src/server/DevTools; Config/DevTools): target dummies (tagged) are hurt like
-- players' soldiers; a player in god mode is knocked but never hurt.
local Dev = {
	dummy = function(model: Model): boolean
		return CollectionService:HasTag(model, DevCfg.Dummies.Tag)
	end,
	god = function(character: Model): boolean
		local player = Players:GetPlayerFromCharacter(character)
		return player ~= nil and player:GetAttribute(DevCfg.Admin.GodAttribute) == true
	end,
	-- every soldier a blast can reach: the players' characters and the dummies
	soldiers = function(): { Model }
		local out: { Model } = {}
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(out, player.Character)
			end
		end
		for _, m in CollectionService:GetTagged(DevCfg.Dummies.Tag) do
			if m:IsA("Model") and m:IsDescendantOf(workspace) then
				table.insert(out, m)
			end
		end
		return out
	end,
}

-- one ray's hit: the part, where, the ray's direction, how far it flew, whether it took the helmet off
export type RayHit = { part: Instance?, point: Vector3, direction: Vector3, distance: number, helmet: boolean }

-- the player's soldier (or DEV target dummy) a part belongs to (its character and Humanoid), or nil (the DEV showcase
-- and test-shooter dummies aren't players: never hurt)
local function victim(part: Instance?): (Model?, Humanoid?)
	local model = part and part.Parent
	if not model or not model:IsA("Model") or not (Players:GetPlayerFromCharacter(model) or Dev.dummy(model)) then
		return nil, nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid then model else nil, humanoid
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

-- Hurts one soldier: the knock first (so a death goes down with its own knock), then the health.
local function hurt(character: Model, humanoid: Humanoid, left: number, knock: string?, direction: Vector3)
	if humanoid.Health <= 0 then
		if knock then
			Ragdoll.knock(character, knock, direction) -- a body thrown about
		end
		return
	end
	if knock then
		Ragdoll.knock(character, knock, direction)
	end
	humanoid.Health = if Dev.god(character) then humanoid.Health else left
end

function Damage.shot(shooter: Model, weapon: string, hits: { RayHit })
	local w = W[weapon]
	local t = w and Cfg.Weapons[w.class]
	if not t then
		return
	end
	local pellets = w.pellets
	local per: { [Model]: { hits: { Rules.Hit }, humanoid: Humanoid, direction: Vector3 } } = {}
	for _, h in hits do
		local character, humanoid = victim(h.part)
		local zone = h.part and Rules.zone(h.part.Name)
		if not character then
			Trees.shot(h.part, w.class, h.direction) -- a trunk is chipped (src/server/Trees)
		end
		if character and humanoid and zone and character ~= shooter then
			local share = if pellets then Rules.falloff(h.distance, pellets.full, pellets.none) else 1
			local z = if h.helmet then "Helmet" else zone
			local entry = per[character]
			if not entry then
				entry = { hits = {}, humanoid = humanoid, direction = h.direction }
				per[character] = entry
			end
			table.insert(entry.hits, { zone = z, amount = Rules.amount(t, z, share) })
		end
	end
	for character, e in per do
		local total, helmet, top = Rules.sum(e.hits)
		if total > 0 or helmet > 0 then
			local left = Rules.after(e.humanoid.Health, total, helmet, Cfg.HelmetFloor)
			hurt(character, e.humanoid, left, Rules.knock(top, left <= 0, Cfg.Knocks), flat(e.direction))
		end
	end
end

-- A `kg` charge going off at `position` (Config/Damage.Blast). `by`: whose it is (hurt by it, never killed: knocked).
function Damage.blast(position: Vector3, kg: number, by: Model?)
	local B = Cfg.Blast
	if kg <= 0 then
		return
	end
	local reach = Blast.studsAt(B.Reach, kg, B.MetresPerStud)
	local function kpaAt(d: number): number
		return Blast.kpa(d, kg, B)
	end
	-- soldiers (players' characters, DEV dummies)
	for _, character in Dev.soldiers() do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local torso = character:FindFirstChild("Torso") :: BasePart?
		if humanoid and torso then
			local d = (torso.Position - position).Magnitude
			if d <= reach then
				local kpa = kpaAt(d)
				local amount = if character == by then 0 else Blast.soldierDamage(kpa, B.Soldier)
				local left = math.max(humanoid.Health - amount, 0)
				local knock = Blast.knock(kpa, B.Knocks)
				if left <= 0 then
					knock = B.Knocks[1].knock -- killed by a blast: thrown
				end
				if knock or amount > 0 then
					hurt(character, humanoid, left, knock, flat(torso.Position - position))
				end
			end
		end
	end
	-- the map: buildings and props, by their class
	Destruction.blast(position, reach, function(d, class, maxHP)
		local fail = class and (B.Fail :: any)[class] or B.FailDefault
		return Blast.sectionDamage(kpaAt(d), fail, maxHP, B.Weaken)
	end)
	-- the crater first, so the trees it fells lie on the ground as it is after
	Ground.crater(position, Blast.craterPlan(kg, B.Crater), B.Crater)
	Trees.blast(position, reach, kpaAt)
end

-- A tree landing on soldiers (src/server/Trees): everyone whose torso is within `radius` of the line `a` - `b` (and not
-- far above or under it) takes `amount` and the `knock`, pushed to the side of the line they stand on.
function Damage.crush(a: Vector3, b: Vector3, radius: number, amount: number, knock: string)
	for _, character in Dev.soldiers() do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local torso = character:FindFirstChild("Torso") :: BasePart?
		if humanoid and torso then
			local p = torso.Position
			local d, side = TreeRules.offSegment(p.X, p.Z, a.X, a.Z, b.X, b.Z)
			local y = math.max(a.Y, b.Y)
			if d <= radius and p.Y <= y + radius * 2 and p.Y >= math.min(a.Y, b.Y) - radius * 2 then
				local along = flat(b - a)
				local away = Vector3.new(-along.Z, 0, along.X) * side
				hurt(character, humanoid, math.max(humanoid.Health - amount, 0), knock, away)
			end
		end
	end
end
Trees.onCrush(Damage.crush)

-- A staff shot of `stage` from `caster` toward `target`: returns where it lands (the end of its range if it hits
-- nothing).
function Damage.staff(caster: Model, stage: number, target: Vector3): Vector3?
	local S = Cfg.Staff
	local head = caster:FindFirstChild("Head") :: BasePart?
	local range, radius = S.Range[stage], S.Radius[stage]
	if not head or not range or not radius then
		return nil
	end
	local origin = head.Position
	local aim = target - origin
	if aim.Magnitude < 1e-3 then
		return nil
	end
	local direction = aim.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { caster }
	local result = workspace:Spherecast(origin, radius, direction * range, params)
	local landed = if result then result.Position else origin + direction * range
	local character, humanoid = victim(result and result.Instance)
	if character and humanoid and humanoid.Health > 0 then
		local left, knock = Rules.staff(stage, humanoid.Health, S)
		if left then
			hurt(character, humanoid, left, knock, flat(direction))
		end
	end
	Trees.direct(result and result.Instance, stage, direction) -- a trunk hit straight on (src/server/Trees)
	Trees.beam(origin, landed, stage) -- the leaves it passes through or near
	if result then
		Damage.blast(landed, S.Charge[stage] or 0, caster)
	end
	return landed
end

function Damage.start()
	Players.RespawnTime = Metrics.Combat.RespawnDelay
	local function spawned(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		humanoid.BreakJointsOnDeath = false -- the head stays on: the death is a ragdoll
		humanoid.MaxHealth = Cfg.Health
		humanoid.Health = Cfg.Health
		humanoid.Died:Connect(function()
			task.wait() -- (a hit's own knock comes with its death: let it land first)
			if not Ragdoll.active(character) then
				-- died some other way (a fall, a reset): just drops
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				Ragdoll.knock(character, Cfg.Knocks.Other, if root then -root.CFrame.LookVector else Vector3.zero)
			end
		end)
	end
	local function hook(player: Player)
		player.CharacterAdded:Connect(spawned)
		if player.Character then
			task.spawn(spawned, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return Damage
