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
			-- every item has a Muzzle (where shots or spells leave, and the line the first-person hip turn aims); guns also
			-- their sights and ejection port
			assert(w.attachments.Muzzle, `{name}: missing attachment Muzzle`)
			if w.ammo then
				for _, att in { "Aim", "Eject" } do
					assert(w.attachments[att], `{name}: missing attachment {att}`)
				end
			end
		end
	end,
	["line of sight is parallel to the line of fire (the aiming contract)"] = function()
		for name, w in W do
			local aim, muzzle = w.attachments.Aim, w.attachments.Muzzle
			if not aim then
				continue -- no sights (the staff)
			end
			assert(aim[1] == 0 and muzzle[1] == 0, `{name}: Aim and Muzzle must be centred (x = 0)`)
			local height = (aim[2] - muzzle[2]) * w.scale[2]
			-- up to 0.2: the SMLE's sights sit high (0.186 in game, user 2026-10-12: the blade must stand out of the cap)
			assert(height > 0.02 and height < 0.2, `{name}: sight height {height} outside 0.02-0.2 studs`)
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
			if not s then
				assert(w.class == "Grenade", `{name}: only grenades show nothing on the body when put away`)
				continue
			end
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
			assert(w.slot == "Primary" or w.slot == "Grenade" or w.slot == "Shovel", `{name}: unknown slot {w.slot}`)
			assert(
				(w.slot == "Grenade") == (w.class == "Grenade"),
				`{name}: grenades, and only they, go in the Grenade slot`
			)
			assert(
				(w.slot == "Shovel") == (w.class == "Shovel"),
				`{name}: shovels, and only they, go in the Shovel slot`
			)
		end
	end,
	["kit weapons exist"] = function()
		for kit, k in U.Kits do
			local wname = (k :: any).weapon
			if wname then
				assert(W[wname], `{kit}: unknown weapon {wname}`)
			end
			local gname = (k :: any).grenade
			if gname then
				assert(W[gname] and W[gname].slot == "Grenade", `{kit}: unknown grenade {gname}`)
			end
			-- every soldier carries a shovel (user 2026-10-20)
			local sname = (k :: any).shovel
			assert(W[sname] and W[sname].slot == "Shovel", `{kit}: no shovel ({sname})`)
		end
	end,
	["every weapon has its hold animations, in third and first person"] = function()
		-- guns have the full set; any item at least ready and equip (a missing hold plays the ready)
		local ALL = { "ready", "walk", "carry", "aim", "equip", "crouchReady", "crouchWalk", "crouchAim" }
		local ALL_FIRST = { "ready", "carry", "aim", "equip", "aimIn", "aimOut" }
		-- unequip; the staff's; a grenade's; the shovel's
		local OPTIONAL = {
			"unequip",
			"tuck", -- folded in with the barrel blocked (src/client/Tuck)
			"crouchTuck",
			"aimTwo",
			"charge",
			"airCharge",
			"chargeTwo",
			"airChargeTwo",
			"pin",
			"windup",
			"throw",
			"dig",
			"chip",
			"strike", -- a gun's butt stroke (src/client/Melee)
		}
		for name, w in W do
			for _, hold in if w.ammo then ALL else { "ready", "equip" } do
				local id = (w.holds :: any)[hold]
				assert(type(id) == "number" and id > 0, `{name}: no {hold} hold animation`)
			end
			for hold, id in w.holds do
				local known = table.find(ALL, hold) or table.find(OPTIONAL, hold)
				assert(known and type(id) == "number" and id > 0, `{name}: bad {hold} hold`)
			end
			for _, hold in if w.ammo then ALL_FIRST else { "ready", "equip" } do
				local first = (w.firstPerson :: any)[hold]
				assert(type(first) == "number" and first > 0, `{name}: no first-person {hold} hold animation`)
			end
			for hold, first in w.firstPerson do
				local known = table.find(ALL_FIRST, hold) or table.find(OPTIONAL, hold)
				assert(known and first > 0, `{name}: bad first-person {hold} hold`)
				assert((w.holds :: any)[hold] ~= first, `{name}: first and third person share the {hold} animation`)
			end
			-- aiming needs both aim holds; a gun also its sights and the shouldered eye
			if w.holds.aim then
				assert(w.firstPerson.aim, `{name}: no first-person aim`)
				assert(not w.ammo or (w.attachments.Aim and w.shouldered), `{name}: aims without sights`)
			end
		end
	end,
	["guns have their whole action; other items none of it"] = function()
		for name, w in W do
			local parts = { w.action, w.reload, w.bolt, w.shouldered }
			for i = 1, 4 do
				assert((parts[i] ~= nil) == (w.ammo ~= nil), `{name}: gun fields must come with ammo, and only with it`)
			end
		end
	end,
	["the aimed muzzle sits at the AimMuzzleHeight metric"] = function()
		local torsoCentre = M.Character.LegLength + 1 -- R6: legs, then half the 2-stud torso
		for name, w in W do
			if not w.shouldered then
				continue
			end
			local eye = torsoCentre + w.shouldered[2]
			local muzzle = eye - (w.attachments.Aim[2] - w.attachments.Muzzle[2]) * w.scale[2]
			assert(math.abs(eye - M.Character.EyeHeight) < 0.1, `{name}: aimed eye at {eye}, not at eye height`)
			assert(math.abs(muzzle - M.Character.AimMuzzleHeight) < 0.1, `{name}: aimed muzzle at {muzzle}`)
		end
	end,
	["a weapon borrowing holds names the weapon whose holds they are"] = function()
		for name, w in W do
			if w.holdsOf then
				local ref = W[w.holdsOf]
				assert(ref and not ref.holdsOf, `{name}: holdsOf {w.holdsOf} is not a weapon with its own holds`)
				for hold, id in w.holds do
					assert((ref.holds :: any)[hold] == id, `{name}: {hold} is not {w.holdsOf}'s`)
				end
				for hold, id in w.firstPerson do
					assert((ref.firstPerson :: any)[hold] == id, `{name}: first-person {hold} is not {w.holdsOf}'s`)
				end
			end
		end
	end,
	["every weapon belongs to a class with a sway weight"] = function()
		for name, w in W do
			local weight = Sway.Classes[w.class]
			assert(weight, `{name}: class {w.class} is not in Config/Sway.Classes`)
			assert(weight > 0 and weight <= 2, `{name}: weight {weight} outside 0-2`)
		end
	end,
	["the semi-automatics sway more on the move, the biggest magazine most"] = function()
		local m, r, w = W.rifle_mondragon, W.rifle_remington8, W.rifle_winchester1907
		assert(m.stride and r.stride and w.stride, "each semi-automatic has its own stride sway")
		assert(m.stride > 1 and m.stride < r.stride and r.stride < w.stride, "8 < 10 < 15 rounds: more sway each")
		for name, x in W do
			assert(not x.stride or x.stride >= 1 and x.stride <= 3, `{name}: stride {x.stride} outside 1-3`)
		end
	end,
	["every team has its staff, all one model, every part colored"] = function()
		for _, team in { "grey", "olive", "white" } do
			local w = W["staff_" .. team]
			assert(w and w.class == "Staff" and w.asset == "staff", `no {team} staff`)
			for _, part in { "Wood", "Iron", "Accent", "Wrap", "Ribbon" } do
				assert(w.parts[part], `{team} staff: no color for {part}`)
			end
		end
	end,
}
