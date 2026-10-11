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
	["every soldier has the face"] = function()
		assert(type(U.Face) == "number" and U.Face > 0, "face image id missing")
		assert(type(U.FaceClosed) == "number" and U.FaceClosed > 0, "closed face image id missing")
		assert(fs.isFile("assets/characters/faces/face_dots.png"), "face source missing")
		assert(fs.isFile("assets/characters/faces/face_dots_closed.png"), "closed face source missing")
	end,
}
