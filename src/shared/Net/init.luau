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
	"Reload", -- client -> server: () load a clip
	-- server -> clients: (shooter: Model, weapon: string, origin: Vector3, hit: Vector3, normal: Vector3?, part: BasePart?)
	-- an accepted shot, for everyone's effects (the shooter has already shown its own)
	"Shot",
	-- server -> clients: (shooter: Model, action: "Bolt" | "Reload", out: string?, from: number, to: number,
	-- delay: number?) the action's parts moving and sounds, for everyone else; out = what the bolt throws from the
	-- chamber ("Casing"); from / to = the share of the action's timeline to play (a bolt held open stops at its back
	-- point, a reload from an open bolt starts there, a resumed action plays its rest); delay = wait this long first
	-- (a rifle drawn again plays out its interrupted action after the draw)
	"WeaponAction",
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
