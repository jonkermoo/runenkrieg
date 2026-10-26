--!strict
-- The building site round a gun being built (Config/Build.Scaffold; src/server/Build stands it, user 2026-10-26: "include
-- building structures (scaffolds, tools, etc) while the artillery is under construction"). Pure: every piece is a box
-- from `a` to `b` (gun space on the floor the gun stands on: right +X, up +Y, back +Z), `w` across and `h` high with
-- its top toward `up`, coloured Palette.Build.Scaffold[`color`].

local Scaffold = {}

export type Vec = { number }
export type Piece = { a: Vec, b: Vec, w: number, h: number, up: Vec, color: string }

local UP = { 0, 1, 0 }

local function add(out: { Piece }, a: Vec, b: Vec, w: number, h: number, color: string, up: Vec?)
	table.insert(out, { a = a, b = b, w = w, h = h, up = up or UP, color = color })
end

-- a point `lx`, `ly`, `lz` in a frame at (x, z) turned `yaw` degrees (Roblox's: + turns left)
local function at(x: number, z: number, yaw: number, lx: number, ly: number, lz: number): Vec
	local r = math.rad(yaw)
	local c, s = math.cos(r), math.sin(r)
	return { x + lx * c + lz * s, ly, z - lx * s + lz * c }
end

-- a box centred at local (lx, ly, lz) in that frame, `sx` x `sy` x `sz`
local function box(out: { Piece }, x: number, z: number, yaw: number, l: Vec, s: Vec, color: string)
	add(out, at(x, z, yaw, l[1], l[2], l[3] - s[3] / 2), at(x, z, yaw, l[1], l[2], l[3] + s[3] / 2), s[1], s[2], color)
end

-- every piece of a gun's site (`spec`: a Config/Build.Scaffold entry; `sizes`: Config/Build.Scaffold.Sizes)
function Scaffold.pieces(spec: { [string]: any }, sizes: { [string]: any }): { Piece }
	local out: { Piece } = {}
	local S = sizes
	local f = spec.frame
	if f then
		-- posts at the corners and down the long sides, ledgers round them at each level, walk boards along the long
		-- sides, a brace across each bay of the long sides
		local hx = f.width / 2
		local zs = {}
		for k = 0, f.bays do
			table.insert(zs, f.z - f.depth / 2 + f.depth * k / f.bays)
		end
		for _, sx in { -1, 1 } do
			for _, z in zs do
				add(out, { f.x + sx * hx, 0, z }, { f.x + sx * hx, f.height, z }, S.post, S.post, "Pole", { 1, 0, 0 })
			end
			for _, y in f.levels do
				add(out, { f.x + sx * hx, y, zs[1] }, { f.x + sx * hx, y, zs[#zs] }, S.ledger, S.ledger, "Pole")
				local bx = f.x + sx * (hx - S.board / 2 - S.post / 2)
				add(
					out,
					{ bx, y + S.ledger / 2 + S.plank / 2, zs[1] },
					{ bx, y + S.ledger / 2 + S.plank / 2, zs[#zs] },
					S.board,
					S.plank,
					"Board"
				)
			end
			for k = 1, #zs - 1 do
				local lo, hi = if k % 2 == 1 then 0 else f.levels[1], if k % 2 == 1 then f.levels[1] else 0
				add(
					out,
					{ f.x + sx * (hx + S.post), lo + 0.3, zs[k] },
					{ f.x + sx * (hx + S.post), hi + 0.3, zs[k + 1] },
					S.ledger,
					S.ledger,
					"Pole"
				)
			end
		end
		for _, z in { zs[1], zs[#zs] } do
			for _, y in f.levels do
				add(out, { f.x - hx, y, z }, { f.x + hx, y, z }, S.ledger, S.ledger, "Pole")
			end
		end
	end
	local t = spec.tripod
	if t then
		-- three poles lashed at the top, a block and a rope down to the hook
		local apex = { t.x, t.height, t.z }
		for k = 0, 2 do
			local r = math.rad(t.turn + 120 * k)
			local foot = { t.x + math.cos(r) * t.spread, 0, t.z + math.sin(r) * t.spread }
			local d = { apex[1] - foot[1], apex[2] - foot[2], apex[3] - foot[3] }
			local over = S.overshoot / math.sqrt(d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2)
			add(
				out,
				foot,
				{ apex[1] + d[1] * over, apex[2] + d[2] * over, apex[3] + d[3] * over },
				S.pole,
				S.pole,
				"Pole"
			)
		end
		add(
			out,
			{ t.x, t.height - S.lash, t.z },
			{ t.x, t.height + S.lash, t.z },
			S.pole * 1.6,
			S.pole * 1.6,
			"Rope",
			{ 1, 0, 0 }
		)
		add(
			out,
			{ t.x, t.height - S.lash - S.block, t.z },
			{ t.x, t.height - S.lash, t.z },
			S.block * 0.6,
			S.block * 0.4,
			"Iron",
			{ 1, 0, 0 }
		)
		add(out, { t.x, t.hook, t.z }, { t.x, t.height - S.lash - S.block, t.z }, S.rope, S.rope, "Rope", { 1, 0, 0 })
		add(out, { t.x, t.hook - S.hook, t.z }, { t.x, t.hook, t.z }, S.hook * 0.5, S.hook * 0.25, "Iron", { 1, 0, 0 })
	end
	for _, c in spec.crates or {} do
		-- a tool crate, its lid, two battens and a mallet lying on it
		local s = c.size
		box(out, c.x, c.z, c.yaw, { 0, s[2] / 2, 0 }, s, "Crate")
		box(out, c.x, c.z, c.yaw, { 0, s[2] + S.plank / 2, 0 }, { s[1] + 0.06, S.plank, s[3] + 0.06 }, "CrateDark")
		for _, lx in { -s[1] * 0.3, s[1] * 0.3 } do
			box(out, c.x, c.z, c.yaw, { lx, s[2] / 2, 0 }, { 0.12, s[2] - 0.1, s[3] + 0.04 }, "CrateDark")
		end
		local top = s[2] + S.plank
		add(
			out,
			at(c.x, c.z, c.yaw, -s[1] * 0.35, top + 0.06, -s[3] * 0.1),
			at(c.x, c.z, c.yaw, s[1] * 0.15, top + 0.06, s[3] * 0.15),
			0.1,
			0.1,
			"Pole"
		)
		box(out, c.x, c.z, c.yaw + 30, { 0.1, top + 0.15, 0.22 }, { 0.5, 0.3, 0.3 }, "Pole")
	end
	for _, p in spec.planks or {} do
		-- a pile of planks, each a little off the one under it
		for k = 0, p.count - 1 do
			box(
				out,
				p.x,
				p.z,
				p.yaw + (k % 2) * 4 - 2,
				{ (k % 3 - 1) * 0.08, S.plank * (k + 0.5), 0 },
				{ S.board, S.plank, p.length },
				"Board"
			)
		end
	end
	for _, h in spec.sawhorses or {} do
		-- a beam on two pairs of splayed legs
		local half, y = S.horse.length / 2, S.horse.height
		box(out, h.x, h.z, h.yaw, { 0, y, 0 }, { S.horse.beam, S.horse.beam, S.horse.length }, "Pole")
		for _, lz in { -half + 0.2, half - 0.2 } do
			for _, sx in { -1, 1 } do
				add(
					out,
					at(h.x, h.z, h.yaw, sx * S.horse.splay, 0, lz),
					at(h.x, h.z, h.yaw, 0, y, lz),
					0.12,
					0.12,
					"Pole"
				)
			end
		end
	end
	return out
end

return Scaffold
