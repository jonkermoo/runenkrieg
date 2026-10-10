--!strict
local fs = require("@lune/fs")
local U = require("../src/shared/Config/Uniforms")

return {
	["the default kit exists and every kit has its sources and ids"] = function()
		assert(U.Kits[U.Default], "default kit missing")
		for name, k in U.Kits do
			assert(fs.isFile(k.source), `{name}: spec missing`)
			local stem = string.gsub(k.source, "%.json$", "")
			assert(fs.isFile(stem .. "_shirt.png") and fs.isFile(stem .. "_pants.png"), `{name}: templates missing`)
			assert(k.shirt > 0 and k.pants > 0 and #k.skin == 3, `{name}: ids or skin missing`)
		end
	end,
}
