--!strict
-- Relays each caster's staff cast (src/client/StaffAttack) to the other players, who draw and hear it
-- (src/client/StaffSeen). A shot is cast here (src/server/Damage.staff, M12: damage, knock, the full beam's blast) and
-- relayed with where it really lands. Nothing a client sends is trusted as
-- sent (Rules/StaffNet, Config/Spells.Send): the sender must be alive with a staff in the hands; every message type and
-- value is checked; points must be near the caster's head; "Aim" goes at most AimRate a second, everything else
-- through a token bucket of Events a second; a "Fire" must wait out the last shot's cooldown (less CooldownSlack), be
-- charged long enough since its circle opened (Rules/StaffNet.charged) and be paid for from the server's own copy of
-- the caster's mana (Rules/Spells; a new life starts full).
-- Bot soldiers (src/server/Bots) cast through the same checks from the server: StaffCast.openAs / aimAs / castAs /
-- dropAs on the model holding the staff, with no slack (the server keeps the time), its own mana per life
-- (StaffCast.manaOf) and cooldown (StaffCast.readyIn); a quick fire spreads in Config/Spells.Staff.Hip's cone and a
-- stage 3 shot knocks the bot back (Staff.Recoil), as a player's client does for its own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Spells = require(Shared.Config.Spells)
local DevCfg = require(Shared.Config.DevTools)
local M = require(Shared.Config.Metrics)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.StaffNet)
local SpellRules = require(Shared.Rules.Spells)
local Damage = require(script.Parent.Damage)
local Ragdoll = require(script.Parent.Ragdoll)

local Send = Spells.Send
local S = Spells.Staff
local LAST = #Spells.Stages

local StaffCast = {}

type State = {
	bucket: Rules.Bucket,
	aimAt: number,
	fireAt: number?,
	fireStage: number?,
	staffAt: number,
	openAt: number?, -- when the held circle opened ("Open"), nil once released or dropped
	mana: SpellRules.Mana,
	manaAt: number, -- when the mana was last refilled
	life: Model, -- the character the mana belongs to
}

local remote: RemoteEvent? = nil
local states: { [Player]: State } = {}
local botStates: { [Model]: State } = {} -- a bot's model is one life
local random = Random.new()

-- `character` alive, its head; and whether a staff is drawn
local function caster(character: Model?): (Model?, BasePart?, boolean)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local tool = character and character:FindFirstChildOfClass("Tool")
	local name = tool and tool:GetAttribute("Weapon")
	if not character or not humanoid or humanoid.Health <= 0 or not head then
		return nil, nil, false
	end
	local w = type(name) == "string" and W[name]
	return character, head, w ~= nil and w ~= false and w.class == "Staff"
end

-- a point near the caster's head, or nil
local function point(v: unknown, head: BasePart): Vector3?
	if typeof(v) ~= "Vector3" then
		return nil
	end
	local p = v :: Vector3
	if not (Rules.finite(p.X) and Rules.finite(p.Y) and Rules.finite(p.Z)) then
		return nil
	end
	return if (p - head.Position).Magnitude <= Send.Reach then p else nil
end

local function newState(character: Model, now: number): State
	return {
		bucket = { tokens = Send.Events, at = now },
		aimAt = -math.huge,
		fireAt = nil,
		fireStage = nil,
		staffAt = -math.huge,
		openAt = nil,
		mana = SpellRules.mana(Spells.Mana),
		manaAt = now,
		life = character,
	}
end

-- to every player but `from` (a bot's: to everyone)
local function relay(from: Player?, character: Model, ...: any)
	local r = remote
	if not r then
		return
	end
	for _, other in Players:GetPlayers() do
		if other ~= from then
			r:FireClient(other, character, ...)
		end
	end
end

-- the mana refilled up to now
local function refill(s: State, now: number)
	SpellRules.refill(s.mana, Spells.Mana, now, now - s.manaAt)
	s.manaAt = now
end

-- A "Fire" of `stage` at `target` by `mode`, checked (cooldown less `cooldownSlack`, charge less `chargeSlack`, mana)
-- and cast; `free`: the admin panel's no cooldown. Returns where it landed, or nil if refused.
local function fire(
	s: State,
	character: Model,
	stage: number,
	target: Vector3,
	mode: string,
	free: boolean,
	cooldownSlack: number,
	chargeSlack: number,
	from: Player?
): Vector3?
	local now = os.clock()
	if not free and not Rules.cooled(s.fireAt, s.fireStage, now, S.Cooldown, cooldownSlack) then
		return nil
	end
	if not Rules.charged(stage, mode, s.openAt, now, Spells.Stages, chargeSlack) then
		return nil
	end
	refill(s, now)
	if free then
		SpellRules.fill(s.mana, Spells.Mana)
	end
	if not SpellRules.spend(s.mana, Spells.Mana, stage, now) then
		return nil
	end
	if mode == "Release" then
		s.openAt = nil
	end
	s.fireAt, s.fireStage = now, stage
	local landed = Damage.staff(character, stage, target) or target
	relay(from, character, "Fire", stage, landed, mode)
	return landed
end

-- a bot's state for this life, and its head, if it is alive with a staff in the hands
local function bot(model: Model): (State?, BasePart?)
	local character, head, staff = caster(model)
	if not character or not head or not staff then
		return nil, nil
	end
	local now = os.clock()
	local s = botStates[model]
	if not s then
		s = newState(model, now)
		botStates[model] = s
		model.Destroying:Once(function()
			botStates[model] = nil
		end)
	end
	local st = s :: State
	st.staffAt = now
	return st, head
end

-- Opens a held circle on bot soldier `model` (the charge starts now); false without a staff in its hands or with one
-- already open.
function StaffCast.openAs(model: Model): boolean
	local s = bot(model)
	if not s or s.openAt then
		return false
	end
	s.openAt = os.clock()
	relay(nil, model, "Open")
	return true
end

-- Points `model`'s held circle at `aimPoint`, charging as long as it has been open (other players see the charge
-- build and stop at the stages its mana pays for); call it as often as wanted, it goes out at most Send.AimRate a
-- second. False with no circle open or a point out of reach.
function StaffCast.aimAs(model: Model, aimPoint: Vector3): boolean
	local s, head = bot(model)
	if not s or not head or not s.openAt then
		return false
	end
	local target = point(aimPoint, head)
	if not target then
		return false
	end
	local now = os.clock()
	if not Rules.due(s.aimAt, now, Send.AimRate, 1) then
		return true
	end
	s.aimAt = now
	refill(s, now)
	local held = Rules.heldSince(s.openAt, now, Send.MaxHeld)
	relay(nil, model, "Aim", target, held, SpellRules.affordable(s.mana, Spells.Mana))
	return true
end

-- Fires a `stage` shot from bot soldier `model` at `aimPoint`, by the same rules as a player's: stage 1 with no circle
-- open is a quick fire (spread in the hip cone, wider walking), stage 1 from an open circle a pulse (it stays open),
-- stage 2 or 3 the open circle's release once it has been open that stage's hold. True if it fired.
function StaffCast.castAs(model: Model, stage: number, aimPoint: Vector3): boolean
	local s, head = bot(model)
	local n = Rules.stage(stage, LAST)
	if not s or not head or not n then
		return false
	end
	local target = point(aimPoint, head)
	if not target then
		return false
	end
	local mode = Rules.botMode(n, s.openAt ~= nil)
	local direction = (target - head.Position).Unit
	if mode == "Hip" then
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local v = if root then root.AssemblyLinearVelocity else Vector3.zero
		local walking = Vector3.new(v.X, 0, v.Z).Magnitude / M.Movement.WalkSpeed
		local tilt, spin = Rules.cone(SpellRules.spread(S.Hip, walking), random:NextNumber(), random:NextNumber())
		local cf = CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, spin) * CFrame.Angles(tilt, 0, 0)
		direction = cf.LookVector
		target = head.Position + direction * (target - head.Position).Magnitude
	end
	if not fire(s, model, n, target, mode, false, 0, 0, nil) then
		return false
	end
	if n == LAST and mode == "Release" then
		Ragdoll.knock(model, S.Recoil, -Vector3.new(direction.X, 0, direction.Z)) -- thrown back by the shot
	end
	return true
end

-- Closes bot soldier `model`'s held circle without firing.
function StaffCast.dropAs(model: Model)
	local s = botStates[model]
	if s and s.openAt then
		s.openAt = nil
		relay(nil, model, "Drop")
	end
end

-- Bot soldier `model`'s mana now: the bar (quick-shot units, of Config/Spells.Mana.max), the highest stage it pays for
-- (0: none), and whether a mega shot has burnt it out (nothing fires until it's full again). A fresh life is full.
function StaffCast.manaOf(model: Model): (number, number, boolean)
	local s = botStates[model]
	if not s then
		return Spells.Mana.max, SpellRules.affordable(SpellRules.mana(Spells.Mana), Spells.Mana), false
	end
	refill(s, os.clock())
	return s.mana.value, SpellRules.affordable(s.mana, Spells.Mana), s.mana.locked
end

-- Seconds until bot soldier `model` may fire again (its last shot's cooldown; 0: now).
function StaffCast.readyIn(model: Model): number
	local s = botStates[model]
	return if s then Rules.readyIn(s.fireAt, s.fireStage, os.clock(), S.Cooldown) else 0
end

function StaffCast.start()
	local r = Net.event("StaffCast")
	remote = r

	r.OnServerEvent:Connect(function(player, kind, a, b, c)
		local character, head, staff = caster(player.Character)
		if not character or not head or type(kind) ~= "string" then
			return
		end
		local now = os.clock()
		local s = states[player]
		if not s then
			s = newState(character, now)
			states[player] = s
		end
		if s.life ~= character then
			s.life, s.mana, s.manaAt, s.openAt = character, SpellRules.mana(Spells.Mana), now, nil -- a new life: full
		end
		if staff then
			s.staffAt = now
		elseif not (kind == "Fire" and now - s.staffAt <= Send.Grace) then
			return -- no staff in the hands (a shot just after it was put away still counts)
		end
		if kind == "Aim" then
			if not Rules.due(s.aimAt, now, Send.AimRate, Send.AimSlack) then
				return
			end
			local target, held, cap = point(a, head), Rules.held(b, Send.MaxHeld), Rules.cap(c, LAST)
			if not target or held == false or not cap then
				return
			end
			s.aimAt = now
			relay(player, character, "Aim", target, held, cap)
			return
		end
		if not Rules.take(s.bucket, now, Send.Events) then
			return
		end
		if kind == "Open" or kind == "Drop" then
			s.openAt = if kind == "Open" then now else nil
			relay(player, character, kind)
		elseif kind == "Float" then
			if type(a) == "boolean" then
				relay(player, character, "Float", a)
			end
		elseif kind == "Fire" then
			local stage, target, mode = Rules.stage(a, LAST), point(b, head), Rules.mode(c)
			if not stage or not target or not mode then
				return
			end
			-- (the admin panel's no cooldown: none, the mana full again; src/client/StaffAttack does the same)
			local free = player:GetAttribute(DevCfg.Attribute) == true
				and player:GetAttribute(DevCfg.Admin.AmmoAttribute) == true
			fire(s, character, stage, target, mode, free, Send.CooldownSlack, Send.ChargeSlack, player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return StaffCast
