--!strict
local fs = require("@lune/fs")
local A = require("../src/shared/Config/Assets")
local B = require("../src/shared/Config/Buildings")
local Props = require("../src/shared/Config/Props")
local F = require("../src/shared/Config/Foliage")
local S = require("../src/shared/Config/Settings")
local G = require("../src/shared/Rules/Grass")
local U = require("../src/shared/Config/Uniforms")

-- assets/ and tools/ are local only (not in git): without them (CI) the file checks pass and the rest still runs
local LOCAL = fs.isDir("assets")
local function isFile(path: string): boolean
	return not LOCAL or fs.isFile(path)
end

return {
	["every registry entry has a valid category, id and existing source file"] = function()
		for name, e in A.Entries do
			assert(table.find(A.Categories, e.category), `{name}: unknown category {e.category}`)
			if e.generator then
				assert(isFile(e.generator), `{name}: missing generator {e.generator}`)
			end
			if e.uniform then
				-- a uniform: its Shirt + Pants come from Config/Uniforms (image ids), nothing uploaded here
				assert(U.Kits[e.uniform], `{name}: unknown uniform kit {e.uniform}`)
				assert(e.source == U.Kits[e.uniform].source, `{name}: source differs from the kit's`)
				assert(isFile(e.source), `{name}: missing source {e.source}`)
			elseif e.prop then
				assert(table.find(Props.Kinds, e.prop), `{name}: unknown prop {e.prop}`)
			elseif e.template then
				-- procedural: built from a template, nothing uploaded
				assert(B.Templates[e.template], `{name}: unknown template {e.template}`)
				assert(B.Templates[e.template].folder == e.folder, `{name}: folder differs from the template's`)
			else
				assert(type(e.id) == "number" and e.id > 0, `{name}: bad id`)
				assert(e.source and isFile(e.source), `{name}: missing source {e.source}`)
				assert(
					string.find(e.source, "assets/" .. string.lower(e.category) .. "/", 1, true) == 1,
					`{name}: source not under assets/{string.lower(e.category)}/`
				)
			end
		end
	end,
	["team gear and weapons sit in their team's library folder, as in the repo"] = function()
		for name, e in A.Entries do
			local team = e.source and string.match(e.source, "^assets/teams/(%w+)/")
				or e.source and string.match(e.source, "^assets/weapons/(%w+)/")
			if team then
				local want = string.upper(string.sub(team, 1, 1)) .. string.sub(team, 2) .. "/"
				assert(string.find(e.folder, want, 1, true) == 1, `{name}: folder {e.folder} should start with {want}`)
			end
		end
	end,
	["every helmet knows its shell and where the shell part sits"] = function()
		for name, e in A.Entries do
			if e.fit and e.fit.attachment == "HatAttachment" then
				assert(type(e.fit.shell) == "string", `{name}: no fit.shell`)
				assert(e.fit.center and #e.fit.center == 3, `{name}: fit.center needs 3 numbers`)
				-- a helmet's or a soft cap's (fit.soft: the Engineer's caps) own shell
				local kind = if e.fit.soft then "cap_" else "helmet_"
				assert(
					string.find(name, kind .. e.fit.shell, 1, true) == 1,
					`{name}: shell {e.fit.shell} isn't its own`
				)
			end
		end
	end,
	["every repo asset category folder exists"] = function()
		for _, c in A.Categories do
			assert(not LOCAL or fs.isDir("assets/" .. string.lower(c)), `missing assets/{string.lower(c)}`)
		end
	end,
	["every prop kind is in the library"] = function()
		for _, kind in Props.Kinds do
			local found = false
			for _, e in A.Entries do
				if e.prop == kind then
					found = true
				end
			end
			assert(found, `prop {kind} has no library entry`)
		end
		for _, k in Props.BoundaryKinds do
			assert(table.find(Props.Kinds, k), `boundary kind {k} is not a prop`)
		end
		for _, k in Props.YardKinds do
			assert(table.find(Props.Kinds, k), `yard kind {k} is not a prop`)
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
	["the blade layer: own cells, levels grow, cells fill the chunk"] = function()
		local B = F.Blades
		assert(B.ChunkSize % B.Cell == 0 and F.ChunkSize == B.ChunkSize, "blade cells must tile the chunk")
		local prev = -1
		for _, name in F.Order do
			local l = B.Levels[name]
			assert(l, `blades: missing level {name}`)
			assert(l.density >= prev, "blades: density must grow with quality")
			prev = l.density
		end
		assert(B.Levels.Off.radius == 0, "blades: Off draws nothing")
		local tufts = G.chunk(4, 4, 1, F)
		local blades = G.chunk(4, 4, 1, B)
		assert(#blades == (B.ChunkSize / B.Cell) ^ 2, "density 1: a blade patch per cell")
		assert(tufts[1].x ~= blades[1].x, "blades share the tufts' positions")
	end,
	["chunksAround covers the radius, nearest first"] = function()
		local list = G.chunksAround(10, 10, 90, F.ChunkSize)
		assert(#list > 20, "too few chunks")
		for i = 2, #list do
			assert(list[i][3] >= list[i - 1][3], "not sorted by distance")
		end
		assert(#G.chunksAround(0, 0, 0, F.ChunkSize) == 0, "Off should load nothing")
	end,
	["no grass under a fallen trunk: near its line, not beside it"] = function()
		local G = require("../src/shared/Rules/Grass")
		assert(G.nearSegment(5, 1, 0, 0, 10, 0, 2), "beside the middle")
		assert(not G.nearSegment(5, 3, 0, 0, 10, 0, 2), "too far off")
		assert(G.nearSegment(11, 0, 0, 0, 10, 0, 2), "just past the end")
		assert(not G.nearSegment(13, 0, 0, 0, 10, 0, 2), "well past the end")
		assert(G.nearSegment(0, 1, 0, 0, 0, 0, 2), "a zero-length line")
	end,
}
