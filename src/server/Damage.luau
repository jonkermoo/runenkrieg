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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Damage)
local Metrics = require(Shared.Config.Metrics)
local W = require(Shared.Config.Weapons)
local Blast = require(Shared.Rules.Blast)
local Rules = require(Shared.Rules.Damage)
local Destruction = require(script.Parent.Destruction)
local Ragdoll = require(script.Parent.Ragdoll)
local Trees = require(script.Parent.Trees)

local Damage = {}

-- one ray's hit: the part, where, the ray's direction, how far it flew, whether it took the helmet off
export type RayHit = { part: Instance?, point: Vector3, direction: Vector3, distance: number, helmet: boolean }

-- the player's soldier a part belongs to (its character and Humanoid), or nil (the DEV showcase and test-shooter
-- dummies aren't players: never hurt)
local function victim(part: Instance?): (Model?, Humanoid?)
	local model = part and part.Parent
	if not model or not model:IsA("Model") or not Players:GetPlayerFromCharacter(model) then
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
	humanoid.Health = left
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

local VOXEL = 4 -- terrain voxel size (studs)

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

-- The crater of a `kg` charge at `position` (Rules/Blast.craterPlan): a low rim of earth where there is ground near,
-- the hole, then the ground around churned to blasted earth (the grass on it goes at once: src/client/GrassFoliage).
-- Terrain changes are voxels: they stay and cost nothing after.
local function crater(position: Vector3, kg: number)
	local C = Cfg.Blast.Crater
	local plan = Blast.craterPlan(kg, C)
	if not plan then
		return
	end
	local terrain = workspace.Terrain
	local churnTo = (Enum.Material :: any)[C.churnTo]
	for _, b in plan.rim do
		local over = position + Vector3.new(b.dx, plan.radius, b.dz)
		local hit = workspace:Raycast(over, Vector3.yAxis * -plan.radius * 3, terrainOnly)
		if hit then
			terrain:FillBall(hit.Position - Vector3.yAxis * b.sink, b.radius, churnTo)
		end
	end
	terrain:FillBall(position - Vector3.yAxis * plan.sink, plan.radius, Enum.Material.Air)
	-- churn: the voxels near the blast's height within `churn` across
	local from: { [Enum.Material]: boolean } = {}
	for _, m in C.churnFrom do
		from[(Enum.Material :: any)[m]] = true
	end
	local reach = Vector3.new(plan.churn, plan.radius * C.churnDepth, plan.churn)
	local region = Region3.new(position - reach, position + reach):ExpandToGrid(VOXEL)
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return
	end
	local size = mats.Size
	local corner = region.CFrame.Position - region.Size / 2
	local changed = false
	for ix = 1, size.X do
		for iz = 1, size.Z do
			local x, z = corner.X + (ix - 0.5) * VOXEL, corner.Z + (iz - 0.5) * VOXEL
			if (x - position.X) ^ 2 + (z - position.Z) ^ 2 <= plan.churn * plan.churn then
				for iy = 1, size.Y do
					if from[mats[ix][iy][iz]] then
						mats[ix][iy][iz] = churnTo
						changed = true
					end
				end
			end
		end
	end
	if changed then
		terrain:WriteVoxels(region, VOXEL, mats, occs)
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
	-- soldiers (players' characters)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local torso = character and character:FindFirstChild("Torso") :: BasePart?
		if character and humanoid and torso then
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
	Trees.blast(position, reach, kpaAt)
	crater(position, kg)
end

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
