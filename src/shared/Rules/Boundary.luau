--!strict
-- Pure math for the out-of-bounds panel fade.
local Boundary = {}

-- 0 = invisible, 1 = fully visible, linear between far and near.
function Boundary.fade(distance: number, near: number, far: number): number
	if far <= near then
		return if distance <= near then 1 else 0
	end
	return math.clamp((far - distance) / (far - near), 0, 1)
end

-- Horizontal distance from a point to a panel centered at (cx, cz), spanning `width` along (dx, dz).
function Boundary.distanceToPanel(
	px: number,
	pz: number,
	cx: number,
	cz: number,
	dx: number,
	dz: number,
	width: number
): number
	local rx, rz = px - cx, pz - cz
	local along = math.clamp(rx * dx + rz * dz, -width / 2, width / 2)
	local qx, qz = cx + dx * along, cz + dz * along
	return math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2)
end

return Boundary
