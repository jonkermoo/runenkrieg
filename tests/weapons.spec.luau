--!strict
local A = require("../src/shared/Config/Assets")
local U = require("../src/shared/Config/Uniforms")
local W = require("../src/shared/Config/Weapons")

local function rgb(c: { number }): boolean
	return #c == 3 and c[1] >= 0 and c[1] <= 255 and c[2] >= 0 and c[2] <= 255 and c[3] >= 0 and c[3] <= 255
end

return {
	["every weapon is a registered Weapons asset with colors for its parts"] = function()
		for name, w in W do
			local e = A.Entries[w.asset]
			assert(e and e.category == "Weapons", `{name}: asset {w.asset} is not a Weapons entry`)
			for part, c in w.parts do
				assert(rgb(c), `{name}: bad color for {part}`)
			end
			for part, p in w.moving do
				assert(w.parts[part], `{name}: moving part {part} has no color`)
				assert(#p == 3, `{name}: pivot of {part} is not a position`)
			end
			for _, part in w.hidden do
				assert(w.parts[part], `{name}: hidden part {part} unknown`)
			end
			for _, att in { "Muzzle", "Aim", "Eject" } do
				assert(w.attachments[att], `{name}: missing attachment {att}`)
			end
		end
	end,
	["line of sight is parallel to the line of fire (the aiming contract)"] = function()
		for name, w in W do
			local aim, muzzle = w.attachments.Aim, w.attachments.Muzzle
			assert(aim[1] == 0 and muzzle[1] == 0, `{name}: Aim and Muzzle must be centred (x = 0)`)
			local height = aim[2] - muzzle[2]
			assert(height > 0.02 and height < 0.1, `{name}: sight height {height} outside 0.02-0.1 studs`)
			assert(aim[3] > muzzle[3], `{name}: the eye must be behind the muzzle`)
		end
	end,
	["kit weapons exist"] = function()
		for kit, k in U.Kits do
			local wname = (k :: any).weapon
			if wname then
				assert(W[wname], `{kit}: unknown weapon {wname}`)
			end
		end
	end,
}
