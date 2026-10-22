--!strict
local fs = require("@lune/fs")
local U = require("../src/shared/Config/Uniforms")
local A = require("../src/shared/Config/Assets")

-- assets/ and tools/ are local only (not in git): without them (CI) the file checks pass and the rest still runs
local LOCAL = fs.isDir("assets")
local function isFile(path: string): boolean
	return not LOCAL or fs.isFile(path)
end

return {
	["the default kit exists and every kit has its sources and ids"] = function()
		assert(U.Kits[U.Default], "default kit missing")
		for name, k in U.Kits do
			assert(isFile(k.source), `{name}: spec missing`)
			local stem = string.gsub(k.source, "%.json$", "")
			assert(isFile(stem .. "_shirt.png") and isFile(stem .. "_pants.png"), `{name}: templates missing`)
			assert(k.shirt > 0 and k.pants > 0 and #k.skin == 3, `{name}: ids or skin missing`)
			if k.headwear then
				local e = A.Entries[k.headwear]
				assert(
					e and e.fit and e.fit.attachment == "HatAttachment",
					`{name}: headwear {k.headwear} is not wearable gear`
				)
			end
			if k.pack then
				local e = A.Entries[k.pack]
				assert(e and string.find(e.folder, "/Packs$"), `{name}: pack {k.pack} is not a pack entry`)
			end
		end
	end,
	["every pack has a palette color for each of its parts"] = function()
		local P = require("../src/shared/Config/Palette")
		for name, e in A.Entries do
			if string.find(e.folder, "/Packs$") then
				local c = P.Packs[name]
				assert(c and c.Body and c.Roll, `{name}: Config/Palette.Packs colors missing`)
			end
		end
	end,
	["every rig is a rig entry and every kit colors each of its parts"] = function()
		local P = require("../src/shared/Config/Palette")
		assert(#U.Rigs > 0, "no rigs")
		for _, r in U.Rigs do
			local e = A.Entries[r.name]
			assert(e and e.folder == "Shared/Rigs" and r.weight > 0, `{r.name}: not a rig entry`)
			for part in (e.fit :: any).parts do
				for kit in U.Kits do
					local c = P.Rigs[kit] and P.Rigs[kit][part]
					assert(c and #c == 3, `{kit}: Config/Palette.Rigs has no {part} color`)
				end
			end
		end
	end,
	["a face per health third, each with its closed face"] = function()
		local files = { healthy = "face_dots", hurt = "face_dots_hurt", wounded = "face_dots_wounded" }
		assert(#U.Faces == 3, "three health faces")
		local last = 1
		for _, f in U.Faces do
			assert(f.open > 0 and f.closed > 0 and f.open ~= f.closed, `{f.name}: ids missing`)
			assert(f.above < last, `{f.name}: tiers must go down in health`)
			last = f.above
			local stem = "assets/characters/faces/" .. files[f.name]
			assert(isFile(stem .. ".png") and isFile(stem .. "_closed.png"), `{f.name}: images missing`)
		end
		assert(U.Faces[#U.Faces].above == 0, "the last face covers down to 0")
	end,
}
