--!strict
-- Low-poly trees from rotated blocks (faceted look). Placeholder until Blender meshes replace them.
-- Trunks collide; canopies block shots/sight (CanQuery) but not movement.

local Parts = require(script.Parent.Parts)

local Trees = {}

local PINE = { Color3.fromRGB(44, 88, 52), Color3.fromRGB(52, 98, 58), Color3.fromRGB(38, 78, 50) }
local LEAF = { Color3.fromRGB(78, 140, 56), Color3.fromRGB(92, 150, 60), Color3.fromRGB(70, 126, 52) }
local BIRCH_LEAF = { Color3.fromRGB(130, 165, 70), Color3.fromRGB(118, 156, 62) }
local BARK = Color3.fromRGB(96, 70, 50)
local BIRCH_BARK = Color3.fromRGB(222, 220, 210)

local function pick(list: { Color3 }, v: number): Color3
	return list[v % #list + 1]
end

local function canopy(parent: Instance, cf: CFrame, size: Vector3, color: Color3)
	local p = Parts.box(parent, "Canopy", cf, size, color)
	p.CanCollide = false
	p.CanTouch = false
end

local function trunk(
	parent: Instance,
	x: number,
	gy: number,
	z: number,
	w: number,
	h: number,
	color: Color3,
	yaw: number
)
	Parts.box(parent, "Trunk", CFrame.new(x, gy - 1 + h / 2, z) * CFrame.Angles(0, yaw, 0), Vector3.new(w, h, w), color)
end

function Trees.build(parent: Instance, map: any, MT: any): number
	local placements = MT.trees(map)
	local count = 0
	local bucket: Instance? = nil
	for i, t in placements do
		if (i - 1) % 400 == 0 then
			bucket = Parts.folder(parent, "Trees_" .. math.floor(i / 400))
		end
		local model = Instance.new("Model")
		model.Name = t.kind
		local gy = MT.heightAt(map, t.x, t.z)
		local yaw = math.rad(t.yaw)
		local v = t.variant
		local function r(k: number): number -- deterministic [-1, 1)
			return MT.hash01(v, k, 9) * 2 - 1
		end

		if t.kind == "Pine" then
			local H = 34 * t.scale
			trunk(model, t.x, gy, t.z, 1.4 * t.scale, H * 0.45, BARK, yaw)
			local tiers = if t.far then 2 else 4
			local y0 = gy + H * 0.22
			for k = 0, tiers - 1 do
				local w = H * 0.42 * (1 - k * (0.8 / tiers))
				local th = H * 0.16
				local cf = CFrame.new(t.x, y0 + k * H * (0.68 / tiers) + th / 2, t.z)
					* CFrame.Angles(math.rad(4 * r(k)), yaw + math.rad(45 * k), math.rad(4 * r(k + 10)))
				canopy(model, cf, Vector3.new(w, th, w), pick(PINE, v + k))
			end
		elseif t.kind == "Broadleaf" then
			local H = 26 * t.scale
			trunk(model, t.x, gy, t.z, 2 * t.scale, H * 0.6, BARK, yaw)
			local blocks = if t.far then 1 else 3
			for k = 1, blocks do
				local s = H * (0.42 + 0.08 * r(k))
				local off = if blocks == 1
					then Vector3.zero
					else Vector3.new(r(k + 3), r(k + 6) * 0.5, r(k + 9)) * H * 0.13
				local cf = CFrame.new(Vector3.new(t.x, gy + H * 0.66, t.z) + off)
					* CFrame.Angles(math.rad(35 * r(k + 12)), math.rad(180 * r(k + 15)), math.rad(35 * r(k + 18)))
				canopy(model, cf, Vector3.new(s, s * 0.8, s), pick(LEAF, v + k))
			end
		else -- Birch
			local H = 24 * t.scale
			trunk(model, t.x, gy, t.z, 1 * t.scale, H * 0.75, BIRCH_BARK, yaw)
			local blocks = if t.far then 1 else 2
			for k = 1, blocks do
				local s = H * 0.3
				local cf = CFrame.new(t.x + r(k) * 1.5, gy + H * (0.55 + 0.15 * k), t.z + r(k + 4) * 1.5)
					* CFrame.Angles(math.rad(30 * r(k + 8)), math.rad(180 * r(k + 11)), math.rad(30 * r(k + 14)))
				canopy(model, cf, Vector3.new(s, s * 1.2, s), pick(BIRCH_LEAF, v + k))
			end
		end
		model.Parent = bucket
		count += 1
	end
	return count
end

return Trees
