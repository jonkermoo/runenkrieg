--!strict
local fs = require("@lune/fs")
local U = require("../src/shared/Config/Uniforms")
local A = require("../src/shared/Config/Assets")

return {
	["the default kit exists and every kit has its sources and ids"] = function()
		assert(U.Kits[U.Default], "default kit missing")
		for name, k in U.Kits do
			assert(fs.isFile(k.source), `{name}: spec missing`)
			local stem = string.gsub(k.source, "%.json$", "")
			assert(fs.isFile(stem .. "_shirt.png") and fs.isFile(stem .. "_pants.png"), `{name}: templates missing`)
			assert(k.shirt > 0 and k.pants > 0 and #k.skin == 3, `{name}: ids or skin missing`)
			if k.headwear then
				local e = A.Entries[k.headwear]
				assert(
					e and e.fit and e.fit.attachment == "HatAttachment",
					`{name}: headwear {k.headwear} is not wearable gear`
				)
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
			assert(fs.isFile(stem .. ".png") and fs.isFile(stem .. "_closed.png"), `{f.name}: images missing`)
		end
		assert(U.Faces[#U.Faces].above == 0, "the last face covers down to 0")
	end,
}
