--!strict
-- Health, damage, death and respawn on the server (M12; Config/Damage, Rules/Damage, Rules/Blast; docs/MILESTONES.md
-- M12). The server is the only one that hurts anyone:
-- - Damage.shot: a gun's hits from src/server/Firing's own raycast: by weapon class and zone (head, torso, limbs; the
--   helmet hit never fatal by itself), the pellets' falloff; then the knock by the zone that took the most
--   (src/server/Ragdoll).
-- - Damage.staff: a staff shot (src/server/StaffCast): a sphere cast as wide as the beam, as long as the stage's range,
--   from the caster's head toward its aim; the stage's damage and knock, no zones, no falloff; where it lands, the
--   stage's blast (Damage.staffBlast: stage 2 a light one for the map only, the full beam a big one).
-- - Damage.blast: a real-scaled blast (Rules/Blast): soldiers hurt and knocked by the overpressure at their torso, map
--   sections by their class (src/server/Destruction.blast), trees by their HP (src/server/Trees), a crater with a rim
--   and churned earth round it.
-- No one hurts themselves (their blast still knocks them). Health 100; the only regeneration is src/server/Healing's
-- slow recovery to 70 (Roblox's own Health script is replaced, src/character/Health);
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
local GrenadeRules = require(Shared.Rules.Grenade)
local MeleeRules = require(Shared.Rules.Melee)
local Rules = require(Shared.Rules.Damage)
local TreeRules = require(Shared.Rules.Trees)
local Destruction = require(script.Parent.Destruction)
local Ragdoll = require(script.Parent.Ragdoll)
local Ground = require(script.Parent.Ground)
local Healing = require(script.Parent.Healing)
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

-- every soldier a shot or blast can reach (src/server/Firing: the helmets' crowns)
Damage.soldiers = Dev.soldiers

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
local function hurt(
	character: Model,
	humanoid: Humanoid,
	left: number,
	knock: string?,
	direction: Vector3,
	scale: number?
)
	if humanoid.Health <= 0 then
		if knock then
			Ragdoll.knock(character, knock, direction, scale) -- a body thrown about
		end
		return
	end
	if knock then
		Ragdoll.knock(character, knock, direction, scale)
	end
	if not Dev.god(character) then
		Healing.hit(character) -- a healer hit stops healing (Config/Healing)
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
			local z = if h.helmet then Rules.helmetZone(h.distance, Cfg.HelmetLethal[w.class]) else zone
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

-- A butt stroke (src/server/Melee) from `striker` on the body part `part` in `zone` (a helmet hit already took the
-- helmet off), along `direction`: Config/Damage.Melee's damage and knock. True when it hurt a soldier.
function Damage.melee(striker: Model, part: BasePart, zone: string, direction: Vector3): boolean
	local character, humanoid = victim(part)
	if not character or not humanoid or character == striker or humanoid.Health <= 0 then
		return false
	end
	local left, knock = MeleeRules.hit(zone, humanoid.Health, Cfg.Melee, Cfg.Knocks.Killed, Cfg.HelmetFloor)
	hurt(character, humanoid, left, knock, flat(direction))
	return true
end

-- What a blast does (Config/Damage.Staff.Blasts); nil: everything, in full. fell = false: trees only lose leaves and
-- shake, never fall (a grenade's, Config/Grenades); fragments: a casing's splinters on soldiers, on top of the blast,
-- through the same cover (Rules/Grenade.fragments); own: the share of it that hurts whoever set it off (nil: 0, your own
-- blast never hurts you; a grenade's, Config/Grenades.Own).
export type BlastOpts = {
	soldiers: boolean?,
	trees: boolean?,
	fell: boolean?,
	fragments: GrenadeRules.Fragments?,
	own: number?,
	ownFling: boolean?, -- false: the one who set it off isn't thrown by it either (the staff's)
	crater: boolean?,
	wear: number?,
	wearFull: number?,
	wearReach: number?,
	breaks: { [string]: boolean }?,
}

-- The share of `character`'s body a blast at `position` has a clear line to (Config/Damage.Blast.Cover): soldiers never
-- shield each other; whatever is within `skip` studs of the blast (the wall it went off against) is passed through.
function Damage.exposure(position: Vector3, character: Model, soldiers: { Model }): number
	local C = Cfg.Blast.Cover
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local clear, total = 0, 0
	for _, name in C.parts do
		local p = character:FindFirstChild(name) :: BasePart?
		if p then
			total += 1
			local skip = table.clone(soldiers)
			params.FilterDescendantsInstances = skip
			local line = p.Position - position
			local hit = workspace:Raycast(position, line, params)
			local tries = 0
			while hit and hit.Distance <= C.skip and tries < 3 do
				table.insert(skip, hit.Instance)
				params.FilterDescendantsInstances = skip
				hit = workspace:Raycast(position, line, params)
				tries += 1
			end
			if not hit then
				clear += 1
			end
		end
	end
	return Blast.exposure(clear, total, C.minShare)
end

-- A `kg` charge going off at `position` (Config/Damage.Blast). `by`: whose it is (hurt by it only by `opts.own`;
-- flung all the same).
function Damage.blast(position: Vector3, kg: number, by: Model?, opts: BlastOpts?)
	local B = Cfg.Blast
	if kg <= 0 then
		return
	end
	local o: BlastOpts = opts or {}
	local reach = Blast.studsAt(B.Reach, kg, B.MetresPerStud)
	local function kpaAt(d: number): number
		return Blast.kpa(d, kg, B)
	end
	-- the map: buildings and props, by their class
	Destruction.blast(position, reach, function(d, class, maxHP, kind, hp)
		return Blast.sectionHit(kpaAt(d), {
			fail = class and (B.Fail :: any)[class] or B.FailDefault,
			maxHP = maxHP,
			hp = hp,
			weaken = B.Weaken,
			wear = if class and o.breaks and o.breaks[class] then nil else o.wear,
			wearFull = o.wearFull,
			wearReach = o.wearReach,
			distance = d,
			keep = kind ~= nil and (B.WearOnly :: any)[kind] == true,
			brittle = class ~= nil and (B.Brittle :: any)[class] == true,
		})
	end, function(class)
		return Blast.reachOf(class and (B.Fail :: any)[class] or B.FailDefault, kg, B)
	end)
	-- the crater first, so the trees it fells lie on the ground as it is after
	if o.crater ~= false then
		Ground.crater(position, Blast.craterPlan(kg, B.Crater), B.Crater)
	end
	if o.trees ~= false then
		Trees.blast(position, reach, kpaAt, o.fell)
	end
	-- soldiers (players' characters, DEV dummies), last: the map's damage first, so cover it broke is no cover
	local soldiers: { Model } = if o.soldiers == false then {} else Dev.soldiers()
	for _, character in soldiers do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local torso = character:FindFirstChild("Torso") :: BasePart?
		if humanoid and torso then
			local d = (torso.Position - position).Magnitude
			if d <= reach or (o.fragments and d <= o.fragments.wound) then
				local kpa = kpaAt(d)
				-- behind cover only what reaches them (cast now: cover the blast broke is gone)
				local share = Damage.exposure(position, character, soldiers)
				-- flung as hard as what gets past cover hurts (your own blast hurts you only by `o.own`, but flings you as
				-- hard as it would have); a grenade's fragments add to it, through the same cover
				local splinters = if o.fragments then GrenadeRules.fragments(d, o.fragments) else 0
				local full = (Blast.soldierDamage(kpa, B.Soldier) + splinters) * share
				local own = character == by
				local amount = if own then full * (o.own or 0) else full
				local left = math.max(humanoid.Health - amount, 0)
				local scale = if left <= 0 then 1 else Blast.fling(full, B.Soldier.max, B.Fling.least)
				if own and o.ownFling == false and left > 0 then
					scale = nil -- (user 2026-10-21: a point-blank staff blast threw its own caster to their death)
				end
				if scale then
					hurt(character, humanoid, left, B.Fling.knock, flat(torso.Position - position), scale)
				end
			end
		end
	end
end

-- A staff stage's blast at `position` (Config/Damage.Staff.Charge and Blasts), set off by `by`.
function Damage.staffBlast(position: Vector3, stage: number, by: Model?)
	local S = Cfg.Staff
	Damage.blast(position, S.Charge[stage] or 0, by, S.Blasts[stage])
end

-- A tree landing on soldiers (src/server/Trees): everyone whose torso is within `radius` of the line `a` - `b` (and not
-- far above or under it) takes `amount` and the `knock`, pushed to the side of the line they stand on.
-- when each caster's last staff shot was fired (os.clock): what falls out of it can't hurt them for a while
local castAt: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

function Damage.crush(a: Vector3, b: Vector3, radius: number, amount: number, knock: string)
	local now = os.clock()
	for _, character in Dev.soldiers() do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local torso = character:FindFirstChild("Torso") :: BasePart?
		-- (a tree your own shot felled lands on you: unhurt, Config/Damage.Staff.SelfSafe)
		local own = now - (castAt[character] or -math.huge) <= Cfg.Staff.SelfSafe
		if humanoid and torso and not own then
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
	castAt[caster] = os.clock()
	local character, humanoid = victim(result and result.Instance)
	if character and humanoid and character ~= caster and humanoid.Health > 0 then
		local left, knock = Rules.staff(stage, humanoid.Health, S)
		if left then
			hurt(character, humanoid, left, knock, flat(direction))
		end
	end
	Trees.direct(result and result.Instance, stage, direction) -- a trunk hit straight on (src/server/Trees)
	Trees.beam(origin, landed, stage) -- the leaves it passes through or near
	if result then
		Damage.staffBlast(landed, stage, caster)
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
			-- your own staff never kills you (Config/Damage.Staff.SelfSafe): if a caster dies soon after their own shot
			-- anyway, say how, so the way through is found (user 2026-10-21)
			local since = os.clock() - (castAt[character] or -math.huge)
			if since <= Cfg.Staff.SelfSafe then
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local at = if root then tostring(root.Position) else "no root (fell out of the world?)"
				local after = string.format("%.1f", since)
				local limp = Ragdoll.active(character)
				warn(
					`[Damage] {character.Name} died {after} s after their own staff shot: at {at}, health {humanoid.Health}, ragdolled {limp}`
				)
			end
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
