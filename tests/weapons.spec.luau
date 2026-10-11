--!strict
local A = require("../src/shared/Config/Assets")
local U = require("../src/shared/Config/Uniforms")
local M = require("../src/shared/Config/Metrics")
local Sway = require("../src/shared/Config/Sway")
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
			local height = (aim[2] - muzzle[2]) * w.scale[2]
			assert(height > 0.02 and height < 0.15, `{name}: sight height {height} outside 0.02-0.15 studs`)
			assert(aim[3] > muzzle[3], `{name}: the eye must be behind the muzzle`)
		end
	end,
	["weapons are scaled up to the chunky R6 look, not shrunk"] = function()
		for name, w in W do
			assert(#w.scale == 3, `{name}: scale is per axis {"{"}x, y, z{"}"}`)
			for _, k in w.scale do
				assert(k >= 1 and k <= 3, `{name}: scale {k} outside 1-3`)
			end
			assert(w.scale[1] >= w.scale[3], `{name}: thicken more than lengthen (chunky, not long)`)
		end
	end,
	["stowed weapons sit muzzle-up with a square frame"] = function()
		for name, w in W do
			local s = w.stow
			assert(#s.at == 3, `{name}: stow position is not a point`)
			local m, d = s.muzzle, s.side
			local function len(v: { number }): number
				return math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
			end
			assert(math.abs(len(m) - 1) < 1e-3 and math.abs(len(d) - 1) < 1e-3, `{name}: stow axes must be unit length`)
			assert(math.abs(m[1] * d[1] + m[2] * d[2] + m[3] * d[3]) < 1e-3, `{name}: stow muzzle and side not square`)
			assert(m[2] > 0.5, `{name}: a slung weapon points its muzzle up`)
		end
	end,
	["every weapon has a loadout slot"] = function()
		for name, w in W do
			assert(w.slot == "Primary", `{name}: unknown slot {w.slot}`)
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
	["every weapon has its hold animations, in third and first person"] = function()
		for name, w in W do
			for _, hold in { "ready", "walk", "carry", "aim", "equip" } do
				local id = w.holds[hold] :: number
				assert(type(id) == "number" and id > 0, `{name}: no {hold} hold animation`)
			end
			for _, hold in { "ready", "carry", "aim", "equip" } do
				local first = (w.firstPerson :: any)[hold]
				assert(type(first) == "number" and first > 0, `{name}: no first-person {hold} hold animation`)
				assert((w.holds :: any)[hold] ~= first, `{name}: first and third person share the {hold} animation`)
			end
		end
	end,
	["the aimed muzzle sits at the AimMuzzleHeight metric"] = function()
		local torsoCentre = M.Character.LegLength + 1 -- R6: legs, then half the 2-stud torso
		for name, w in W do
			local eye = torsoCentre + w.shouldered[2]
			local muzzle = eye - (w.attachments.Aim[2] - w.attachments.Muzzle[2]) * w.scale[2]
			assert(math.abs(eye - M.Character.EyeHeight) < 0.1, `{name}: aimed eye at {eye}, not at eye height`)
			assert(math.abs(muzzle - M.Character.AimMuzzleHeight) < 0.1, `{name}: aimed muzzle at {muzzle}`)
		end
	end,
	["every weapon belongs to a class with a sway weight"] = function()
		for name, w in W do
			local weight = Sway.Classes[w.class]
			assert(weight, `{name}: class {w.class} is not in Config/Sway.Classes`)
			assert(weight > 0 and weight <= 2, `{name}: weight {weight} outside 0-2`)
		end
	end,
}
