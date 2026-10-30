--!strict
-- An bot soldier's third-person animation, played from the server (src/server/Bots). A bot is a server-owned Humanoid,
-- so tracks played on its Animator here replicate to every client for free, with no per-client code (a player's
-- src/client/Locomotion runs on their own client and leans on its input, camera and Backpack). The same cycles and
-- holds as a player's: idle / walk / sprint by speed at the Config/Locomotion pace, and the weapon's hold over them
-- (ready, walk, carry while sprinting, aim; the equip once on spawning and on getting up), Action priority. The hold goes on the "Hold"
-- attribute (src/client/GunFx picks the bolt's body animation by it) and the look pitch out to every client like a
-- player's tilt (Net "LookPitch", src/client/LookTilt poses the torso, arms and gun).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loco = require(Shared.Config.Locomotion)
local CameraCfg = require(Shared.Config.Camera)
local W = require(Shared.Config.Weapons)
local MovementSet = require(Shared.Rules.MovementSet)
local Net = require(Shared.Net)

local Anims = MovementSet.animations(Loco)
local Send = Loco.LookTilt.Send

local Animate = {}

export type Handle = {
	update: (speed: number, hold: string, pitch: number) -> (),
	equip: () -> (), -- the draw once over the hold (spawning, getting up from a knock)
}

local function load(animator: Animator, id: number, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. id
	local t = animator:LoadAnimation(anim)
	t.Priority = priority
	t.Looped = looped
	return t
end

-- The soldier `m` holding `weapon` animated from now on; `update` each brain step with its flat speed, the hold it
-- wants ("ready", "walk", "carry" or "aim") and the look pitch (degrees).
function Animate.attach(m: Model, weapon: string): Handle
	local humanoid = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local a = animator :: Animator
	local base: { [string]: AnimationTrack } = {}
	for _, name in { "idle", "walk", "sprint" } do
		base[name] = load(
			a,
			(Anims :: any)[name].id,
			if name == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Core,
			true
		)
	end
	local holds: { [string]: AnimationTrack } = {}
	for hold, id in MovementSet.holds(Loco, weapon, W[weapon].holds) do
		if hold == "ready" or hold == "walk" or hold == "carry" or hold == "aim" or hold == "equip" then
			holds[hold] = load(a, id, Enum.AnimationPriority.Action, hold ~= "equip")
		end
	end

	local current: string? = nil
	local held: string? = nil
	local sent = { pitch = math.huge, follow = math.huge, at = -math.huge }

	local function equip()
		if holds.equip then
			holds.equip:Play(0.1)
		end
	end
	equip()

	local function update(speed: number, hold: string, pitch: number)
		-- the ground cycle by speed, at its game pace
		local name = if speed < Loco.IdleBelow then "idle" elseif speed > Loco.SprintAbove then "sprint" else "walk"
		if name ~= current then
			if current then
				base[current]:Stop(Loco.Fade)
			end
			base[name]:Play(Loco.Fade)
			current = name
		end
		local rate = 1
		local c = (Anims :: any)[name]
		if c.speed and c.keyed and c.cycle then
			rate = math.clamp(speed / c.speed, Loco.PlaybackMin, Loco.PlaybackMax) * c.keyed / c.cycle
			base[name]:AdjustSpeed(rate)
		end
		-- the weapon's hold over it (the walk and carry kept in step with the legs)
		local want = if holds[hold] then hold else "ready"
		if want ~= held then
			if held and holds[held] then
				holds[held]:Stop(Loco.HoldFade)
			end
			if holds[want] then
				holds[want]:Play(Loco.HoldFade)
			end
			held = want
			m:SetAttribute("Hold", want)
		end
		if (want == "walk" or want == "carry") and holds[want] then
			holds[want]:AdjustSpeed(rate)
		end
		-- the look tilt, to everyone (as src/server/LookTilt relays a player's), when it changed enough
		local follow = (CameraCfg.Follow :: any)[want] or 0
		local p = math.floor(pitch / Send.Step + 0.5) * Send.Step
		local now = os.clock()
		if
			(math.abs(p - sent.pitch) >= 1 or follow ~= sent.follow) and now - sent.at >= 1 / Send.Rate
			or (p ~= sent.pitch and now - sent.at >= 0.5)
		then
			sent.pitch, sent.follow, sent.at = p, follow, now
			Net.event("LookPitch"):FireAllClients(m, p, follow, 0, 0)
		end
	end

	return { update = update, equip = equip }
end

return Animate
