--!strict
-- The ONLY place remote names are declared. Server and client both go through this module.
-- Add a name to Remotes/Functions below; never create RemoteEvents anywhere else.

local RunService = game:GetService("RunService")

local Remotes: { string } = {
	"Explosion", -- server -> clients: (position: Vector3, radius: number, strength: number?) visual response
	"DevTeleport", -- client -> server: (destinationId: string); server checks the DevTools attribute
	"DevGiveWeapon", -- client -> server: (weapon: string) make it the player's loadout pick; DevTools attribute checked
	"SectionBroken", -- server -> clients: (pieces: {{cf, size, color, t}}, origin: Vector3) debris to spawn
	-- Shooting (src/server/Firing, src/client/Firing; Rules/Firing decides on both sides):
	"Fire", -- client -> server: (origin: Vector3, direction: Vector3) a shot from the held weapon
	"WorkBolt", -- client -> server: () work the bolt after a shot
	"Reload", -- client -> server: () load a clip (or single rounds, a stripper-clip rifle with rounds left)
	"StopLoad", -- client -> server: () stop loading single rounds (after the round in the hand)
	-- server -> clients: (shooter: Model, weapon: string, origin: Vector3, hit: Vector3, normal: Vector3?, part: BasePart?)
	-- an accepted shot, for everyone's effects (the shooter has already shown its own)
	"Shot",
	-- (action "Load": single rounds, from = seconds into it, to = rounds going in or nil = until full; "LoadStop": to =
	-- the rounds going in now)
	-- server -> clients: (shooter: Model, action: "Bolt" | "Reload" | "Load" | "LoadStop", out: string?, from, to,
	-- delay: number?) the action's parts moving and sounds, for everyone else; out = what the bolt throws from the
	-- chamber ("Casing"); from / to = the share of the action's timeline to play (a bolt held open stops at its back
	-- point, a reload from an open bolt starts there, a resumed action plays its rest); delay = wait this long first
	-- (a rifle drawn again plays out its interrupted action after the draw)
	"WeaponAction",
	-- client -> server: () putting the held weapon away with its unequip animation (src/server/Armory keeps a copy in
	-- the hands meanwhile; Config/Locomotion.Stow)
	"Stow",
	-- The look tilt shown to other players (src/client/LookTilt, src/server/LookTilt; Config/Locomotion.LookTilt.Send):
	-- client -> server: (pitch: number, follow: number) the camera pitch in degrees and the gun's follow share
	-- server -> clients: (character: Model, pitch: number, follow: number) clamped and quantized, throttled per soldier
	"LookPitch",
	-- The staff cast shown to other players (src/client/StaffAttack sends, src/server/StaffCast checks and relays,
	-- src/client/StaffSeen shows; Config/Spells.Send, Rules/StaffNet). Visual and audio only.
	-- client -> server: (kind, ...) with kind and its arguments:
	--   "Open" ()                                           an aimed circle opens and is held
	--   "Aim" (target: Vector3, held: number?, cap: number) the crosshair point, the charge time (nil: not charging),
	--                                                       the stages paid for; at most Send.AimRate a second
	--   "Fire" (stage: number, target: Vector3, mode: "Hip" | "Pulse" | "Release") a shot and where it aims; the server
	--                                                       casts it (Config/Damage.Staff) and relays where it lands
	--   "Drop" ()                                           the held cast closes without firing
	--   "Float" (on: boolean)                               floating with the staff aimed, or not
	-- server -> clients: (caster: Model, kind, ...) the same, checked, to everyone but the caster
	"StaffCast",
	-- Knocks (M12; src/server/Ragdoll decides and loosens the joints for everyone, src/client/Ragdoll shows them;
	-- Config/Ragdoll.Knocks):
	-- server -> clients: (character: Model, knock: string, direction: Vector3, scale: number) a soldier knocked: its
	-- owner throws the body (or staggers it), everyone leans a stagger
	"Knock",
	-- client -> server: (knock: string, direction: Vector3) knock myself (Config/Ragdoll.SelfKnocks: the staff's
	-- recoil, the float fall); rate limited
	"KnockSelf",
}
local Functions: { string } = {}

local FOLDER_NAME = "Net"

local Net = {}

local function getFolder(): Folder
	local parent = script.Parent :: Instance
	if RunService:IsServer() then
		local folder = parent:FindFirstChild(FOLDER_NAME .. "Remotes") :: Folder?
		if not folder then
			local created = Instance.new("Folder")
			created.Name = FOLDER_NAME .. "Remotes"
			for _, name in Remotes do
				Instance.new("RemoteEvent", created).Name = name
			end
			for _, name in Functions do
				Instance.new("RemoteFunction", created).Name = name
			end
			created.Parent = parent
			folder = created
		end
		return folder :: Folder
	end
	return parent:WaitForChild(FOLDER_NAME .. "Remotes") :: Folder
end

-- Server: create the remotes folder at startup so clients never wait on it.
function Net.init()
	assert(RunService:IsServer(), "Net.init is server-only")
	getFolder()
end

function Net.event(name: string): RemoteEvent
	assert(table.find(Remotes, name), `Unknown remote event "{name}" - declare it in Net`)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	assert(table.find(Functions, name), `Unknown remote function "{name}" - declare it in Net`)
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Net
