--!strict
-- Animates trees near the camera: idle wind sway (canopy pivots on the trunk top, trunk on its base)
-- plus spring response to explosions (Net "Explosion"). Visual only; trees stay static on the server.
-- The player's "Tree sway" setting Off (src/client/Settings) stops it: every moved tree goes back to its static pose.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.TreeSway)
local S = require(Shared.Rules.TreeSway)
local Net = require(Shared.Net)
local Settings = require(script.Parent.Settings)

type Tree = {
	model: Model,
	trunk: BasePart,
	canopy: BasePart,
	base: Vector3,
	top: Vector3,
	trunk0: CFrame,
	canopy0: CFrame,
	trunkSpring: S.Spring,
	canopySpring: S.Spring,
	active: boolean,
	kicked: boolean,
	cell: string,
}

local TreeSwayClient = {}

local trees: { [Model]: Tree } = {}
local grid: { [string]: { [Model]: Tree } } = {}

local function cellKey(x: number, z: number): string
	return math.floor(x / Cfg.GridCell) .. ":" .. math.floor(z / Cfg.GridCell)
end

local function add(inst: Instance)
	if not inst:IsA("Model") or trees[inst] then
		return
	end
	local trunk = inst:FindFirstChild("Trunk") :: BasePart?
	local canopy = inst:FindFirstChild("Canopy") :: BasePart?
	if not trunk or not canopy then
		return -- parts not streamed in yet; DescendantAdded below retries
	end
	local base = inst:GetPivot().Position
	local t: Tree = {
		model = inst,
		trunk = trunk,
		canopy = canopy,
		base = base,
		top = (trunk.CFrame * CFrame.new(0, trunk.Size.Y / 2, 0)).Position,
		trunk0 = trunk.CFrame,
		canopy0 = canopy.CFrame,
		trunkSpring = S.newSpring(),
		canopySpring = S.newSpring(),
		active = false,
		kicked = false,
		cell = cellKey(base.X, base.Z),
	}
	trees[inst] = t
	grid[t.cell] = grid[t.cell] or {}
	grid[t.cell][inst] = t
end

local function remove(inst: Instance)
	local t = trees[inst :: Model]
	if t then
		trees[inst :: Model] = nil
		local c = grid[t.cell]
		if c then
			c[inst :: Model] = nil
		end
	end
end

local function rotation(tx: number, tz: number): CFrame
	local a = math.sqrt(tx * tx + tz * tz)
	if a < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(Vector3.new(tz, 0, -tx) / a, a)
end

local function about(point: Vector3, r: CFrame): CFrame
	return CFrame.new(point) * r * CFrame.new(-point)
end

-- Explosion at `position`: kick every registered tree within `radius`, visible or not.
function TreeSwayClient.explode(position: Vector3, radius: number, strength: number?)
	local k = math.rad(Cfg.Explosion.maxKick) * (strength or 1)
	local r = math.ceil(radius / Cfg.GridCell)
	local cx, cz = math.floor(position.X / Cfg.GridCell), math.floor(position.Z / Cfg.GridCell)
	for ix = cx - r, cx + r do
		for iz = cz - r, cz + r do
			for _, t in grid[ix .. ":" .. iz] or {} do
				S.kick(t.trunkSpring, t.base.X, t.base.Z, position.X, position.Z, radius, k * Cfg.Trunk.impulseScale)
				S.kick(t.canopySpring, t.base.X, t.base.Z, position.X, position.Z, radius, k * Cfg.Canopy.impulseScale)
				t.kicked = true
			end
		end
	end
end

function TreeSwayClient.start()
	for _, inst in CollectionService:GetTagged(Cfg.Tag) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(Cfg.Tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Cfg.Tag):Connect(remove)
	-- streaming: a tagged model can arrive before its parts
	workspace.DescendantAdded:Connect(function(d)
		local m = d.Parent
		if m and m:IsA("Model") and not trees[m] and CollectionService:HasTag(m, Cfg.Tag) then
			add(m)
		end
	end)

	Net.event("Explosion").OnClientEvent:Connect(function(position: Vector3, radius: number, strength: number?)
		TreeSwayClient.explode(position, radius, strength)
	end)

	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local acc = 0
	local eps = math.rad(Cfg.SleepAngle)
	local trunkMax, canopyMax = math.rad(Cfg.Trunk.maxLean), math.rad(Cfg.Canopy.maxLean)

	RunService.RenderStepped:Connect(function(dt)
		if Settings.get("TreeSway") ~= "On" then
			-- off: put back what moved, once
			table.clear(parts)
			table.clear(cframes)
			for _, t in trees do
				if t.active or t.kicked then
					table.insert(parts, t.trunk)
					table.insert(cframes, t.trunk0)
					table.insert(parts, t.canopy)
					table.insert(cframes, t.canopy0)
					t.active, t.kicked = false, false
					t.trunkSpring, t.canopySpring = S.newSpring(), S.newSpring()
				end
			end
			if #parts > 0 then
				workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			end
			return
		end
		acc += dt
		if acc < 1 / Cfg.UpdateHz then
			return
		end
		local step = acc
		acc = 0
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local now = os.clock()
		local wind = workspace.GlobalWind
		local strength, dx, dz = S.wind(wind.X, wind.Z, Cfg)
		local p = cam.CFrame.Position
		local r2 = Cfg.ActiveRadius * Cfg.ActiveRadius
		table.clear(parts)
		table.clear(cframes)

		for _, t in trees do
			local near = (t.base.X - p.X) ^ 2 + (t.base.Z - p.Z) ^ 2 < r2
			if near or t.kicked then
				S.step(t.trunkSpring, Cfg.Trunk.stiffness, Cfg.Trunk.damping, step)
				S.step(t.canopySpring, Cfg.Canopy.stiffness, Cfg.Canopy.damping, step)
				S.clamp(t.trunkSpring, trunkMax)
				S.clamp(t.canopySpring, canopyMax)
				if t.kicked and S.asleep(t.trunkSpring, eps) and S.asleep(t.canopySpring, eps) then
					t.kicked = false
				end
			end
			if near then
				local itx, itz = S.idleTilt(now, t.base.X, t.base.Z, strength, dx, dz, Cfg.Trunk, Cfg.Gust)
				local icx, icz = S.idleTilt(now + 0.15, t.base.X, t.base.Z, strength, dx, dz, Cfg.Canopy, Cfg.Gust)
				local trunkRot = about(t.base, rotation(itx + t.trunkSpring.x, itz + t.trunkSpring.z))
				local top = trunkRot * t.top
				local canopyRot = about(top, rotation(icx + t.canopySpring.x, icz + t.canopySpring.z))
				table.insert(parts, t.trunk)
				table.insert(cframes, trunkRot * t.trunk0)
				table.insert(parts, t.canopy)
				table.insert(cframes, canopyRot * trunkRot * t.canopy0)
				t.active = true
			elseif t.active then
				-- left the active radius: restore the static pose once
				table.insert(parts, t.trunk)
				table.insert(cframes, t.trunk0)
				table.insert(parts, t.canopy)
				table.insert(cframes, t.canopy0)
				t.active = false
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return TreeSwayClient
