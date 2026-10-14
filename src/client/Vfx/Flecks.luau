--!strict
-- Glowing flecks: small flat-colored squares that break off a disintegrating effect (the magic circle closing, a
-- beam crumbling), tumble along their velocity, ease off, shrink and fade. Pooled parts, all moved by one Driver step
-- while any are alive.

local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)

local Flecks = {}

type Fleck = { part: Part, p0: Vector3, v: Vector3, born: number, life: number, size: number, spin: Vector3 }

local rng = Random.new()
local flecks: { Fleck } = {}
local running = false

local function step(now: number): boolean
	local i = 1
	while i <= #flecks do
		local f = flecks[i]
		local a = (now - f.born) / f.life
		if a >= 1 then
			Pool.freePart(f.part)
			flecks[i] = flecks[#flecks]
			flecks[#flecks] = nil
		else
			local t = now - f.born
			local r = f.spin * t
			f.part.CFrame = CFrame.new(f.p0 + f.v * t * (1 - a * 0.5)) * CFrame.Angles(r.X, r.Y, r.Z)
			f.part.Size = Vector3.one * math.max(f.size * (1 - a), 0.01)
			f.part.Transparency = a * a
			i += 1
		end
	end
	running = #flecks > 0
	return running
end

-- One fleck at `pos` flying at `v` (studs/s), `size` studs, living `life` seconds.
function Flecks.spawn(pos: Vector3, v: Vector3, color: Color3, size: number, life: number)
	table.insert(flecks, {
		part = Pool.part(Enum.PartType.Block, color, Vector3.one * size, CFrame.new(pos)),
		p0 = pos,
		v = v,
		born = os.clock(),
		life = life,
		size = size,
		spin = rng:NextUnitVector() * 7,
	})
	if not running then
		running = true
		Driver.add(step)
	end
end

return Flecks
