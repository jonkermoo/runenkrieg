--!strict
-- The trench wall grip on the local client (Config/Build.Trench.grip; user 2026-10-23: walls you can't walk out of, you
-- jump out, "as long as players dont slide off"). A trench's carved walls (src/server/Trenches) are steeper than a
-- soldier can walk (Metrics MaxSlopeAngle 50), so Roblox would slide you down them. Standing on one inside a trench
-- block, you stop where you are instead: you can edge along the wall at `along` x your walk speed, pushing down the
-- wall lets go (you slide down), and jump hops you up it (`hopUp` up, `hopIn` into the wall), so you climb out in a few
-- jumps and can stand near the top to shoot over the bank. The client owns its character's physics, so this is all
-- local; others see it through the normal character replication.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local Rules = require(Shared.Rules.Build)
local Survey = require(Shared.BuildSurvey)

local TrenchWall = {}

local T = C.Trench
local G = T.grip
local TOP = Rules.trenchTop(T)

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

-- whether `p` (a point on the ground) is on a trench block's wall: within its top width of its line, below its edge
-- and clear of its floor
local function inTrench(p: Vector3): boolean
	local f = workspace:FindFirstChild(C.Folder)
	if not f then
		return false
	end
	for _, m in f:GetChildren() do
		local a, b = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" and (m:GetAttribute("HP") :: number? or 0) > 0 then
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local u = math.clamp(Vector3.new(p.X - a.X, 0, p.Z - a.Z):Dot(flat.Unit) / flat.Magnitude, 0, 1)
			local line = a.Y + (b.Y - a.Y) * u
			local floor = line - T.depth
			if Survey.toSegment(p, a, b) <= TOP + 1 and p.Y < line - 0.3 and p.Y > floor + G.floorClear then
				return true
			end
		end
	end
	return false
end

local function attach(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local att = Instance.new("Attachment")
	att.Name = "TrenchGrip"
	att.Parent = root
	local hold = Instance.new("LinearVelocity")
	hold.Name = "TrenchGrip"
	hold.Attachment0 = att
	hold.RelativeTo = Enum.ActuatorRelativeTo.World
	hold.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	hold.MaxForce = 1e6
	hold.VectorVelocity = Vector3.zero
	hold.Enabled = false
	hold.Parent = root

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local wall: RaycastResult? = nil
	local freeUntil = 0
	local lostAt = 0 -- when the wall was last lost under the grip (it keeps hold for G.grace)

	local step = RunService.Heartbeat:Connect(function()
		if humanoid.Health <= 0 or character:GetAttribute("Ragdolled") == true or os.clock() < freeUntil then
			wall = nil
			hold.Enabled = false
			return
		end
		-- the wall lost under you (edging along its lumps): keep hold a moment before letting go
		local function lose()
			if hold.Enabled then
				if lostAt == 0 then
					lostAt = os.clock()
				end
				if os.clock() - lostAt < G.grace then
					return -- (still holding, as it was)
				end
			end
			wall = nil
			hold.Enabled = false
			lostAt = 0
		end
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -G.reach, 0), terrainOnly)
		if not hit then
			lose()
			return
		end
		local angle = math.deg(math.acos(math.clamp(hit.Normal.Y, -1, 1)))
		if angle < G.minAngle or angle > G.maxAngle or not inTrench(hit.Position) then
			lose()
			return
		end
		lostAt = 0
		wall = hit
		-- the wall's run along it (flat) and its way down (flat)
		local down = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
		down = if down.Magnitude > 1e-3 then down.Unit else Vector3.xAxis
		local along = Vector3.new(-down.Z, 0, down.X)
		local move = humanoid.MoveDirection
		if move:Dot(down) > 0.5 then
			-- pushing down the wall: let go and slide
			hold.Enabled = false
			freeUntil = os.clock() + G.regrip
			return
		end
		hold.VectorVelocity = along * move:Dot(along) * humanoid.WalkSpeed * G.along
		hold.Enabled = true
	end)
	local jump = UserInputService.JumpRequest:Connect(function()
		local w = wall
		if not w or not hold.Enabled then
			return
		end
		-- hop up the wall
		local up = Vector3.new(-w.Normal.X, 0, -w.Normal.Z)
		up = if up.Magnitude > 1e-3 then up.Unit else Vector3.zero
		hold.Enabled = false
		freeUntil = os.clock() + G.regrip
		root.AssemblyLinearVelocity = Vector3.new(0, G.hopUp, 0) + up * G.hopIn
	end)
	character.Destroying:Connect(function()
		step:Disconnect()
		jump:Disconnect()
	end)
end

function TrenchWall.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(attach)
	if player.Character then
		task.spawn(attach, player.Character)
	end
end

return TrenchWall
