--!strict
-- A glowing ring from pooled pieces: four curved beams (quarter circles) between four attachments, so a ring costs
-- four beams instead of a drawn surface. Ring.place sets its centre, facing and radius each frame it moves.

local Pool = require(script.Parent.Pool)

local Ring = {}

export type Ring = { atts: { Attachment }, beams: { Beam }, width: number }

local K = 0.5523 -- a quarter circle as a cubic Bezier: control arms of K x the radius
local SEGMENTS = 6 -- per quarter

function Ring.new(color: Color3, width: number, brightness: number, transparency: number?): Ring
	local atts, beams = {}, {}
	for i = 1, 4 do
		atts[i] = Pool.att(Vector3.zero)
	end
	for i = 1, 4 do
		local b = Pool.beam(atts[i], atts[i % 4 + 1], color, width, width, transparency or 0, brightness)
		b.Segments = SEGMENTS
		table.insert(beams, b)
	end
	return { atts = atts, beams = beams, width = width }
end

-- Centre `c`, the ring's plane facing `normal`, radius `r`; `widthScale` thins the line, `transparency` fades it.
function Ring.place(ring: Ring, c: Vector3, normal: Vector3, r: number, widthScale: number?, transparency: number?)
	local n = normal.Unit
	local x = n:Cross(Vector3.yAxis)
	if x.Magnitude < 1e-3 then
		x = n:Cross(Vector3.xAxis)
	end
	x = x.Unit
	local y = n:Cross(x)
	for i = 1, 4 do
		local ang = (i - 1) * math.pi / 2
		local radial = x * math.cos(ang) + y * math.sin(ang)
		local tangent = -x * math.sin(ang) + y * math.cos(ang)
		-- the attachment's Axis (its X) runs along the ring, so each beam leaves and arrives tangent to it
		ring.atts[i].CFrame = CFrame.fromMatrix(c + radial * r, tangent, n)
	end
	local w = ring.width * (widthScale or 1)
	for _, b in ring.beams do
		b.CurveSize0, b.CurveSize1 = K * r, K * r
		b.Width0, b.Width1 = w, w
		if transparency then
			b.Transparency = NumberSequence.new(transparency)
		end
	end
end

function Ring.free(ring: Ring)
	for _, b in ring.beams do
		Pool.freeBeam(b)
	end
	for _, a in ring.atts do
		Pool.freeAtt(a)
	end
	table.clear(ring.beams)
	table.clear(ring.atts)
end

return Ring
