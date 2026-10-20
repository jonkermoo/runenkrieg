--!strict
-- The ONLY place remote names are declared. Server and client both go through this module.
-- Add a name to Remotes/Functions below; never create RemoteEvents anywhere else.

local RunService = game:GetService("RunService")

local Remotes: { string } = {
	-- server -> clients: (position: Vector3, radius: number, strength: number?) visual response; from a real-scaled blast
	-- the radius is its reach (src/server/Damage.blast), from which clients work out the churned ground
	"Explosion",
	-- server -> clients: ({ { tree: Model, at: Vector3, react: number } }) a staff beam through or near canopies: shake
	-- them and drop leaves at `at`, scaled by `react` (src/server/Trees.beam, src/client/Impacts)
	"LeavesHit",
	"DevTeleport", -- client -> server: (destinationId: string); server checks the DevTools attribute
	"DevGiveWeapon", -- client -> server: (weapon: string) make it the player's loadout pick; DevTools attribute checked
	-- client -> server: (action: string, value: any, aim: Vector3?) a test action from the dev panels (dummies, blasts,
	-- health, god mode, test shooters, undo destruction); src/server/DevTools checks the DevTools attribute, the action
	-- and its value (Rules/DevActions) and the aim point's reach
	"DevAction",
	-- server -> clients: (position: Vector3, stage: number?, kg: number?) a dev blast's explosion to show
	-- (src/client/Vfx/Blast)
	"DevBlast",
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
	-- server -> clients: (shooter: Model, action: "Bolt" | "Reload" | "Reload2" | "Load" | "LoadStop", out: string?, from, to,
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
	-- The head's turn toward the look, shown to soldiers nearby (src/client/LookTilt, src/server/LookTilt;
	-- Config/Locomotion.LookTilt.Head): client -> server: (yaw: number) degrees from the torso's facing; server ->
	-- clients within Head.Send.Range: (character: Model, yaw: number) clamped and quantized, throttled per soldier
	-- (0 once a watcher leaves the range, so the head doesn't stay turned)
	"HeadYaw",
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
	-- owner throws the body
	"Knock",
	-- client -> server: (knock: string, direction: Vector3) knock myself (Config/Ragdoll.SelfKnocks: the staff's
	-- recoil, the float fall); rate limited
	"KnockSelf",
	-- client -> server: ({ [key]: value }) the player's settings to save in their profile (src/client/Settings sends,
	-- src/server/Profile keeps only valid entries, Rules/Settings.clean; rate limited)
	"SaveSettings",
	-- Healing (H1; src/client/Healing asks, src/server/Healing checks and heals; Config/Healing, Rules/Healing):
	-- client -> server: ("Start", patient: Model) heal the hurt soldier in reach (never yourself), or ("Stop") stop.
	-- The healer's "Healing" attribute ("Bandage" | "MedPack", nil when not) and "HealPatient" ObjectValue say how it goes.
	"Heal",
	-- Grenades (src/client/Grenades sends, src/server/Grenades checks and throws; Config/Grenades, Rules/Grenade):
	-- client -> server: (direction: Vector3) throw the held grenade along this look (the server throws it from its own
	-- view of the head)
	"GrenadeThrow",
	-- server -> clients: (position: Vector3, kg: number) a grenade went off: its explosion (src/client/Vfx/Blast)
	"GrenadeBlast",
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
