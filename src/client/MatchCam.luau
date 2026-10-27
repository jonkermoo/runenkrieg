--!strict
-- The menus' background (user 2026-10-27: "the background of every menu should be the current match going on"): the
-- camera circles a spot of the map, cutting to a new random one every few seconds (Config/Classes.Cam; user: "for this
-- FFA mode, just show the random points of the map"). TODO: the most contested capture point once a mode has them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Classes).Cam
local Map = require(Shared.Config.Maps.Map1)

local MatchCam = {}

local running = false
local focus: Vector3? = nil
local angle = 0
local lookedAt = -math.huge

-- The ground under (x, z), and whether it is open ground (terrain, not a roof or a treetop).
local function ground(x: number, z: number): (Vector3, boolean)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local chars = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	params.FilterDescendantsInstances = chars
	local hit = workspace:Raycast(Vector3.new(x, Cfg.RayTop, z), Vector3.new(0, -Cfg.RayDepth, 0), params)
	if not hit then
		return Vector3.new(x, 0, z), false
	end
	return hit.Position, hit.Instance:IsA("Terrain")
end

-- A random spot of the playable area (Config/Classes.Cam.Inset studs in from its edges) on open ground (a few
-- tries, so it is rarely a treetop or a roof).
local function anywhere(): Vector3
	local b, inset = Map.bounds, Cfg.Inset
	local spot = Vector3.zero
	for _ = 1, Cfg.Tries do
		local x = b.minX + inset + math.random() * (b.maxX - b.minX - 2 * inset)
		local z = b.minZ + inset + math.random() * (b.maxZ - b.minZ - 2 * inset)
		local open
		spot, open = ground(x, z)
		if open then
			break
		end
	end
	return spot
end

function MatchCam.start()
	if running then
		return
	end
	running = true
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep("MatchCam", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local now = os.clock()
		if now - lookedAt >= Cfg.Every or not focus then
			lookedAt = now
			focus = anywhere() -- a cut to the next spot
			angle = math.random() * 2 * math.pi
		end
		local f = focus :: Vector3
		angle += dt * Cfg.Turn
		local eye = f + Vector3.new(math.cos(angle) * Cfg.Distance, Cfg.Height, math.sin(angle) * Cfg.Distance)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(eye, f + Vector3.new(0, Cfg.LookUp, 0))
	end)
end

function MatchCam.stop()
	if not running then
		return
	end
	running = false
	RunService:UnbindFromRenderStep("MatchCam")
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local c = Players.LocalPlayer.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if h then
		camera.CameraSubject = h
	end
end

return MatchCam
