--!strict
-- Other players' staff casts as this player sees and hears them (user 2026-10-16: "the staff audio and visual for other
-- users"; Net "StaffCast" relayed by src/server/StaffCast from each caster's src/client/StaffAttack; Config/Spells.Send,
-- Rules/StaffNet). Visual and audio only.
-- - The cast is Vfx/Zoltraak at full size and solid (no veil: that's the caster's own view), opening from the staff's
--   head on the caster's body and turned to the caster's crosshair point (eased, Send.Follow). While charging, the
--   charge runs on from each "Aim" (at most Send.Ahead, never into a stage not paid for), the circles open and the
--   build-up runs as for the caster, and the dashed laser points at the crosshair.
-- - Shots: "Hip" opens and fires at once; "Pulse" fires stage 1 from the held circle, which stays; "Release" fires the
--   stage and closes the cast (a cast not seen opening is opened to that stage first). The beam is aimed at where it
--   landed for the caster.
-- - Sounds as the caster hears them, but from this listener's place: the circles' bursts, the ready braam, the shots,
--   the impacts and the stage 3 knockback come late by the distance and duller far off (Config/Audio.Heard,
--   Rules/ShotAudio, as gunshots); the charge hums, the laser and the float drone play on the caster (close by only:
--   their Hum falloff).
-- - Drawn only within Send.Range of the caster (a shot: of the caster or of where it lands). A muted soldier (the
--   showcase's dummies) is skipped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Audio)
local Cfg = require(Shared.Config.Spells)
local VfxCfg = require(Shared.Config.Vfx)
local W = require(Shared.Config.Weapons)
local Net = require(Shared.Net)
local Spells = require(Shared.Rules.Spells)
local Heard = require(Shared.Rules.ShotAudio)
local Rules = require(Shared.Rules.StaffNet)
local SoundFx = require(script.Parent.SoundFx)
local Vfx = require(script.Parent.Vfx)
local Pointer = require(script.Parent.Vfx.Pointer)
local Zoltraak = require(script.Parent.Vfx.Zoltraak)

local StaffSeen = {}

local S = Cfg.Staff
local Send = Cfg.Send
local H = A.Heard
local Snd = VfxCfg.Sounds
local LAST = #Cfg.Stages
local HOLDS, OPENS = {}, {}
for i, s in Cfg.Stages do
	HOLDS[i] = s.hold
	OPENS[i] = s.hold - ((VfxCfg.Cast.Stages[i] :: any).lead or 0)
end

type Seen = {
	cast: Zoltraak.Cast?,
	target: Vector3?, -- the crosshair point last received
	aimed: Vector3?, -- where the held cast points now (easing to target)
	held: number?, -- the charge time last received (nil: not charging)
	heldAt: number,
	cap: number,
	floating: boolean,
	pointer: Pointer.Handle?,
	charge: SoundFx.Loop?,
	chargeStage: number,
	laser: SoundFx.Loop?,
	float: SoundFx.Loop?,
}

-- how a sound at `at` reaches this listener: late by the distance, duller far off
local function heard(at: Vector3): SoundFx.Mods?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local d = (camera.CFrame.Position - at).Magnitude
	local lo, mid, hi = Heard.air(d, H.air)
	return { delay = Heard.delay(d, H.speed), eq = { lo, mid, hi } }
end

local function near(at: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - at).Magnitude <= Send.Range
end

-- the staff's head on the caster's body, if a staff is in the hands of a living caster
local function staffHead(character: Model): Attachment?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local tool = character:FindFirstChildOfClass("Tool")
	local name = tool and tool:GetAttribute("Weapon")
	if not humanoid or humanoid.Health <= 0 or type(name) ~= "string" or not W[name] or W[name].class ~= "Staff" then
		return nil
	end
	return (tool :: Tool):FindFirstChild("Muzzle", true) :: Attachment?
end

local function rootOf(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function ignoreFor(character: Model): { Instance }
	return { character, workspace.CurrentCamera }
end

function StaffSeen.start()
	local seen: { [Model]: Seen } = {}
	local scheme = (VfxCfg.Schemes :: any)[S.Scheme]

	local function stateOf(character: Model): Seen
		local s = seen[character]
		if not s then
			s = {
				cast = nil,
				target = nil,
				aimed = nil,
				held = nil,
				heldAt = 0,
				cap = LAST,
				floating = false,
				pointer = nil,
				charge = nil,
				chargeStage = 0,
				laser = nil,
				float = nil,
			}
			seen[character] = s
		end
		return s :: Seen
	end

	-- the held cast's tip: the staff's head, looking at where it aims (the body's facing before any aim came in)
	local function tipOf(character: Model, s: Seen, head: Attachment): CFrame
		local from = head.WorldPosition
		local to = s.aimed or s.target
		if not to or (to - from).Magnitude < 1 then
			local root = rootOf(character)
			return CFrame.lookAt(from, from + (if root then root.CFrame.LookVector else Vector3.zAxis))
		end
		return CFrame.lookAt(from, to)
	end

	local function stopLoops(s: Seen)
		if s.charge then
			s.charge.stop(Snd.Charge.fade)
			s.charge = nil
		end
		s.chargeStage = 0
		if s.laser then
			s.laser.stop(Snd.Laser.fadeOut or 0.15)
			s.laser = nil
		end
		if s.pointer then
			s.pointer.hide()
		end
	end

	local function close(s: Seen)
		local c = s.cast
		if c then
			c.cancel()
		end
		s.cast, s.held = nil, nil
		stopLoops(s)
	end

	local function forget(character: Model)
		local s = seen[character]
		if not s then
			return
		end
		close(s)
		if s.float then
			s.float.stop(Snd.Float.fadeOut or 0.5)
		end
		if s.pointer then
			s.pointer.free()
		end
		seen[character] = nil
	end

	local function open(character: Model, s: Seen, head: Attachment)
		close(s)
		s.aimed = s.target
		s.cast = Vfx.Zoltraak.begin(tipOf(character, s, head), HOLDS, S.Scheme, 1, 1, heard)
	end

	local function fire(character: Model, s: Seen, stage: number, target: Vector3, mode: string)
		local head = staffHead(character)
		if not head then
			return
		end
		s.target, s.aimed = target, target
		local tip = CFrame.lookAt(head.WorldPosition, target)
		local shown = near(head.WorldPosition) or near(target)
		if mode == "Pulse" and s.cast then
			local c = s.cast :: Zoltraak.Cast
			c.aim(tip)
			c.pulse(ignoreFor(character))
			s.held = nil
			return
		end
		local c = if mode ~= "Hip" then s.cast else nil
		s.cast, s.held = nil, nil
		stopLoops(s)
		if not c and shown then
			c = Vfx.Zoltraak.begin(tip, HOLDS, S.Scheme, 1, 1, heard)
			if mode == "Release" then
				(c :: Zoltraak.Cast).update(HOLDS[stage]) -- not seen opening: opened to the stage at once
			end
		end
		if c then
			c.aim(tip)
			c.release(if mode == "Release" then stage else 1, ignoreFor(character))
		end
		local root = rootOf(character)
		if stage == LAST and mode == "Release" and root and shown then
			SoundFx.play(Snd.Knock, root, nil, heard(root.Position)) -- thrown back by the shot
		end
	end

	Net.event("StaffCast").OnClientEvent:Connect(function(character: any, kind: any, a: any, b: any, c: any)
		if
			typeof(character) ~= "Instance"
			or not character:IsA("Model")
			or character == Players.LocalPlayer.Character
		then
			return
		end
		local m = character :: Model
		if m:GetAttribute("Muted") == true then
			return
		end
		local s = stateOf(m)
		local head = staffHead(m)
		if kind == "Open" then
			if head and near(head.WorldPosition) then
				open(m, s, head)
			end
		elseif kind == "Aim" and typeof(a) == "Vector3" then
			s.target = a
			s.held = if type(b) == "number" then b else nil
			s.heldAt = os.clock()
			s.cap = if type(c) == "number" then c else LAST
			if not s.cast and head and near(head.WorldPosition) then
				open(m, s, head) -- a cast already held when it came into view
			end
		elseif kind == "Fire" and type(a) == "number" and typeof(b) == "Vector3" and type(c) == "string" then
			fire(m, s, a, b, c)
		elseif kind == "Drop" then
			close(s)
		elseif kind == "Float" then
			s.floating = a == true
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		for character, s in seen do
			if not character.Parent then
				forget(character)
				continue
			end
			local head = staffHead(character)
			local root = rootOf(character)
			if not head or not root then
				close(s)
				s.floating = false
			elseif s.cast and not near(head.WorldPosition) then
				close(s) -- out of range
			end
			-- floating: a low drone on the caster
			if s.floating and root and not s.float then
				s.float = SoundFx.loop(Snd.Float, root)
			elseif not s.floating and s.float then
				s.float.stop(Snd.Float.fadeOut or 0.5)
				s.float = nil
			end
			local c = s.cast
			if not c or not head or not root then
				continue
			end
			-- the held cast turns to the crosshair point, charging as received
			local target = s.target
			if target then
				local k = 1 - math.exp(-Send.Follow * math.min(dt, 0.1))
				s.aimed = if s.aimed then (s.aimed :: Vector3):Lerp(target, k) else target
			end
			local tip = tipOf(character, s, head)
			c.aim(tip)
			local held = if s.held then Rules.heldNow(s.held, now - s.heldAt, Send.Ahead, OPENS, s.cap) else nil
			c.update(held or 0)
			-- the laser to the crosshair while charging
			if held and target then
				if not s.pointer then
					s.pointer = Vfx.Pointer.new(scheme.pointer, scheme.core)
				end
				(s.pointer :: Pointer.Handle).set(tip.Position, target)
			elseif s.pointer then
				s.pointer.hide()
			end
			-- the charge's hum per stage reached, louder as it builds; the laser's crackle
			local want = if held then Spells.stage(Cfg.Stages, held) else 0
			if want ~= s.chargeStage then
				if s.charge then
					s.charge.stop(Snd.Charge.fade)
					s.charge = nil
				end
				local entry = Snd.Charge.stages[want]
				if entry then
					s.charge = SoundFx.loop(entry, root)
				end
				s.chargeStage = want
			end
			if s.charge and held then
				local low = Snd.Charge.low
				s.charge.set(low + (1 - low) * Spells.charge(Cfg.Stages, held))
			end
			if held and not s.laser then
				s.laser = SoundFx.loop(Snd.Laser, root)
			elseif not held and s.laser then
				s.laser.stop(Snd.Laser.fadeOut or 0.15)
				s.laser = nil
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		if character then
			forget(character)
		end
	end)
end

return StaffSeen
