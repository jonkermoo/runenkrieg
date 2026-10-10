--!strict
local fs = require("@lune/fs")
local A = require("../src/shared/Config/Assets")
local B = require("../src/shared/Config/Buildings")
local F = require("../src/shared/Config/Foliage")
local S = require("../src/shared/Config/Settings")
local G = require("../src/shared/Rules/Grass")

return {
	["every registry entry has a valid category, id and existing source file"] = function()
		for name, e in A.Entries do
			assert(table.find(A.Categories, e.category), `{name}: unknown category {e.category}`)
			if e.generator then
				assert(fs.isFile(e.generator), `{name}: missing generator {e.generator}`)
			end
			if e.template then
				-- procedural: built from a template, nothing uploaded
				assert(B.Templates[e.template], `{name}: unknown template {e.template}`)
				assert(B.Templates[e.template].folder == e.folder, `{name}: folder differs from the template's`)
			else
				assert(type(e.id) == "number" and e.id > 0, `{name}: bad id`)
				assert(e.source and fs.isFile(e.source), `{name}: missing source {e.source}`)
				assert(
					string.find(e.source, "assets/" .. string.lower(e.category) .. "/", 1, true) == 1,
					`{name}: source not under assets/{string.lower(e.category)}/`
				)
			end
		end
	end,
	["every repo asset category folder exists"] = function()
		for _, c in A.Categories do
			assert(fs.isDir("assets/" .. string.lower(c)), `missing assets/{string.lower(c)}`)
		end
	end,
	["every building template is in the library"] = function()
		for name in B.Templates do
			local found = false
			for _, e in A.Entries do
				if e.template == name then
					found = true
				end
			end
			assert(found, `template {name} has no library entry`)
		end
	end,
	["grass quality levels are ordered and the settings offer exactly them"] = function()
		local prev = -1
		for _, name in F.Order do
			local l = F.Levels[name]
			assert(l, `missing level {name}`)
			assert(l.density >= prev, "density must grow with quality")
			prev = l.density
		end
		local opt = S.Options.GrassQuality
		for _, v in opt.values do
			assert(F.Levels[v], `setting value {v} has no foliage level`)
		end
		assert(table.find(opt.values, opt.default) and table.find(opt.values, opt.defaultTouch), "bad defaults")
	end,
	["higher quality only adds tufts (lower levels are subsets)"] = function()
		local low = G.chunk(3, -7, F.Levels.Low.density, F)
		local high = G.chunk(3, -7, F.Levels.High.density, F)
		assert(#high > #low, "High should have more tufts")
		local seen = {}
		for _, t in high do
			seen[t.x .. ":" .. t.z] = true
		end
		for _, t in low do
			assert(seen[t.x .. ":" .. t.z], "a Low tuft is missing at High")
		end
	end,
	["tufts stay inside their chunk and density matches"] = function()
		local n = (F.ChunkSize / F.Cell) ^ 2
		local total = 0
		for cx = 0, 9 do
			local tufts = G.chunk(cx, 2, 0.5, F)
			total += #tufts
			for _, t in tufts do
				assert(t.x >= cx * F.ChunkSize and t.x < (cx + 1) * F.ChunkSize, "tuft outside chunk")
			end
		end
		local frac = total / (n * 10)
		assert(frac > 0.42 and frac < 0.58, `density {frac}`)
	end,
	["chunksAround covers the radius, nearest first"] = function()
		local list = G.chunksAround(10, 10, 90, F.ChunkSize)
		assert(#list > 20, "too few chunks")
		for i = 2, #list do
			assert(list[i][3] >= list[i - 1][3], "not sorted by distance")
		end
		assert(#G.chunksAround(0, 0, 0, F.ChunkSize) == 0, "Off should load nothing")
	end,
}
