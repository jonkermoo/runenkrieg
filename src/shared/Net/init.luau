--!strict
-- The ONLY place remote names are declared. Server and client both go through this module.
-- Add a name to Remotes/Functions below; never create RemoteEvents anywhere else.

local RunService = game:GetService("RunService")

local Remotes: { string } = {
	"Explosion", -- server -> clients: (position: Vector3, radius: number, strength: number?) visual response
	"DevTeleport", -- client -> server: (destinationId: string); server checks the DevTools attribute
	"SectionBroken", -- server -> clients: (pieces: {{cf, size, color, t}}, origin: Vector3) debris to spawn
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
