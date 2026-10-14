--!strict
-- A lightning arc from pooled pieces: a zigzag line of `n` segments, each a solid colored beam with a thin glowing
-- white core beam inside (the anime look). Place it with Arc.zig (a zigzag between two points) or Arc.place (exact points);
-- give the pieces back with Arc.free.

local Pool = require(script.Parent.Pool)

local Arc = {}

export type Arc = { atts: { Attachment }, beams: { Beam }, n: number, width: number }

local rng = Random.new()

function Arc.new(n: number, color: Color3, core: Color3, width: number, brightness: number, zOffset: number?): Arc
	local atts, beams = {}, {}
	for i = 1, n + 1 do
		atts[i] = Pool.att(Vector3.zero)
	end
	for i = 1, n do
		table.insert(beams, Pool.beam(atts[i], atts[i + 1], color, width, width, 0, brightness, 0)) -- solid color edge
		table.insert(beams, Pool.beam(atts[i], atts[i + 1], core, width * 0.35, width * 0.35, 0, brightness))
	end
	for k, b in beams do
		b.ZOffset = (zOffset or 0) + (if k % 2 == 0 then 0.1 else 0) -- the white core in front of its glow
	end
	return { atts = atts, beams = beams, n = n, width = width }
end

-- Lays the arc along a zigzag from a to b: the ends stay put, the middle wanders up to `jag` sideways (sharpest in
-- the middle); `side` (optional) biases the wander to one side, e.g. off a beam's surface.
function Arc.zig(arc: Arc, a: Vector3, b: Vector3, jag: number, side: Vector3?)
	local d = b - a
	local s = d:Cross(Vector3.yAxis)
	if s.Magnitude < 1e-3 then
		s = d:Cross(Vector3.xAxis)
	end
	s = s.Unit
	local u = d:Cross(s).Unit
	local n = arc.n
	for i = 0, n do
		local f = i / n
		local env = math.sin(f * math.pi)
		local off = (s * rng:NextNumber(-1, 1) + u * rng:NextNumber(-1, 1)) * jag * env
		if side then
			off += side * jag * env * 0.5
		end
		arc.atts[i + 1].Position = a + d * f + off
	end
end

-- Exact points (#points must be n + 1).
function Arc.place(arc: Arc, points: { Vector3 })
	for i, p in points do
		arc.atts[i].Position = p
	end
end

-- Shows or hides it; `scale` thins it (1 = full width).
function Arc.show(arc: Arc, on: boolean, scale: number?)
	local w = arc.width * (scale or 1)
	for i, b in arc.beams do
		b.Enabled = on
		local bw = if i % 2 == 0 then w * 0.35 else w
		b.Width0, b.Width1 = bw, bw
	end
end

-- See-through by `v` (0 = solid, 1 = gone): the caster's own charge in first person (Config/Spells.Staff.Veil).
function Arc.veil(arc: Arc, v: number)
	local t = NumberSequence.new(v)
	for _, b in arc.beams do
		b.Transparency = t
	end
end

function Arc.free(arc: Arc)
	for _, b in arc.beams do
		Pool.freeBeam(b)
	end
	for _, a in arc.atts do
		Pool.freeAtt(a)
	end
	table.clear(arc.beams)
	table.clear(arc.atts)
end

return Arc
