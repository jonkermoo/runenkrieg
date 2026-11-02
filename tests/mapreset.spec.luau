--!strict
-- Putting the map back only where it changed (Rules/MapReset, src/server/DevWorld; user 2026-11-02).
local Cfg = require("../src/shared/Config/DevTools").World
local R = require("../src/shared/Rules/MapReset")

return {
	["chunks: a point's chunk, a box's chunks (either corner first), cut to the saved box"] = function()
		local s = Cfg.Chunk
		local ix, iz = R.chunkOf(-1, s + 1, s)
		assert(ix == -1 and iz == 1)
		local a = R.chunksIn(0, 0, s - 1, s - 1, s)
		assert(#a == 1 and a[1] == R.key(0, 0), "a box inside one chunk")
		local b = R.chunksIn(s + 10, 10, -10, -10, s)
		assert(#b == 3 * 2, `{#b} chunks for a box over 3 x 2`)
		local c = R.chunkRect(0, 0, s, { 10, -5, 30, 100 })
		assert(c[1] == 10 and c[2] == 0 and c[3] == 30 and c[4] == s)
	end,
	["fingerprints: the same thing matches; a lost piece, a hit, an open door or a move doesn't"] = function()
		local f = R.fingerprint(40, 1000, 0, 1, 2, 3)
		assert(R.fingerprint(40, 1000, 0, 1.01, 2, 3) == f, "a hair's move is no change")
		assert(R.fingerprint(39, 1000, 0, 1, 2, 3) ~= f)
		assert(R.fingerprint(40, 990, 0, 1, 2, 3) ~= f)
		assert(R.fingerprint(40, 1000, 1, 1, 2, 3) ~= f)
		assert(R.fingerprint(40, 1000, 0, 1, 2.5, 3) ~= f)
	end,
	["every saved terrain box is whole chunks of a sane size"] = function()
		assert(Cfg.Chunk >= 16 and Cfg.Chunk % 4 == 0, "a chunk is whole 4-stud voxels")
	end,
}
