--!strict
-- The menus' background (user 2026-10-27: "the background of every menu should be the current match going on"): the
-- camera circles the hottest fight, the living soldier with the most enemies and friends close by (Config/Classes.Cam;
-- a soldier's side is its "Kit"), looked at again every few seconds and glided to. With nobody fighting it circles
-- the busiest soldier, with nobody alive the map's neutral sector. TODO: weigh the contested capture points too once
-- the sectors are captured in play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Classes).Cam
local Map = require(Shared.Config.Maps.Map1)

local MatchCam = {}

local running = false
local focus: Vector3? = nil
local goal = Vector3.zero
local angle = 0
local lookedAt = -math.huge

local function ground(x: number, z: number): Vector3
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
	return if hit then hit.Position else Vector3.new(x, 0, z)
end

local function fallback(): Vector3
	for _, s in Map.sectors do
		if s.startOwner == "Neutral" then
			return ground(s.x, s.z)
		end
	end
	return ground(0, 0)
end

-- The hottest fight now: each living soldier scored by the enemies and friends within Cfg.Radius.
local function hottest(): Vector3
	local soldiers: { { at: Vector3, side: any } } = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if c and h and h.Health > 0 and root then
			table.insert(soldiers, { at = root.Position, side = c:GetAttribute("Kit") })
		end
	end
	local best, bestScore = nil, -1
	for _, a in soldiers do
		local foes, friends = 0, 0
		for _, b in soldiers do
			if b ~= a and (b.at - a.at).Magnitude <= Cfg.Radius then
				if b.side == a.side then
					friends += 1
				else
					foes += 1
				end
			end
		end
		local score = foes * (friends + 1) * Cfg.Fight + foes + friends
		if score > bestScore then
			best, bestScore = a.at, score
		end
	end
	return if best then ground(best.X, best.Z) else fallback()
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
		if now - lookedAt >= Cfg.Every then
			lookedAt = now
			goal = hottest()
		end
		local f = focus or goal
		f = f:Lerp(goal, 1 - math.exp(-dt * Cfg.Glide))
		focus = f
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
