--!strict
local U = require("../src/shared/Config/Uniforms")
local A = require("../src/shared/Config/Assets")
local Looks = require("../src/shared/Rules/Looks")

return {
	["skin and hair pools: rgb colors, positive weights, unique names"] = function()
		for pool, list in { Skins = U.Skins, HairColors = U.HairColors } do
			assert(#list >= 2, `{pool}: at least two to rotate`)
			local seen = {}
			for _, l in list do
				assert(not seen[l.name], `{pool}: {l.name} twice`)
				seen[l.name] = true
				assert(l.weight > 0, `{pool}: {l.name} weight`)
				assert(#l.color == 3, `{pool}: {l.name} color`)
				for _, c in l.color do
					assert(c >= 0 and c <= 255 and c == math.floor(c), `{pool}: {l.name} color out of range`)
				end
			end
		end
	end,
	["rolls spread by weight"] = function()
		local pool = {
			{ name = "a", color = { 0, 0, 0 }, weight = 1 },
			{ name = "b", color = { 0, 0, 0 }, weight = 3 },
		}
		assert(Looks.pick(pool, 0) == 1, "the start: the first")
		assert(Looks.pick(pool, 0.24) == 1, "under its share: the first")
		assert(Looks.pick(pool, 0.26) == 2, "past its share: the second")
		assert(Looks.pick(pool, 0.999) == 2, "the end: the last")
	end,
	["never last life's color again"] = function()
		for _, pool in { U.Skins, U.HairColors } do
			for avoid = 1, #pool do
				for k = 0, 99 do
					assert(Looks.pick(pool, k / 100, avoid) ~= avoid, "rolled last life's color")
				end
			end
		end
	end,
	["white, ash and blood red are the rare hair colors, about 1 in 13 together"] = function()
		local rareNames = { white = true, ash = true, blood_red = true }
		local total, rare, found = 0, 0, 0
		for _, l in U.HairColors do
			total += l.weight
			if rareNames[l.name] then
				rare += l.weight
				found += 1
			end
		end
		assert(found == 3, `rare colors found: {found}`)
		assert(math.abs(rare / total - 1 / 13) < 0.01, `rare share {rare / total}`)
		for _, l in U.HairColors do
			if rareNames[l.name] then
				assert(l.weight / total < 0.05, `{l.name} is not rare: {l.weight / total}`)
			else
				assert(l.weight / total > 0.2, `{l.name} should be common: {l.weight / total}`)
			end
		end
	end,
	["every hairstyle has its original and a helmet-on hair for every kit's helmet shell"] = function()
		for _, h in U.Hairs do
			assert(h.weight > 0, `{h.name}: weight`)
			if h.name ~= "bald" then
				local bare = Looks.hairEntry(h.name, nil) :: string
				assert(A.Entries[bare] and A.Entries[bare].hair, `{bare}: missing`)
				for kit, k in U.Kits do
					local shell = k.headwear and A.Entries[k.headwear].fit.shell
					local on = Looks.hairEntry(h.name, shell) :: string
					local e = A.Entries[on]
					assert(e and e.hair and (e.hair.bones or #e.hair.center == 3), `{kit}: {on} missing`)
				end
			end
		end
		assert(Looks.hairEntry("bald", "stahl") == nil, "bald wears no hair")
	end,
	["a species wears its ear-hole helmet when there is one"] = function()
		assert(Looks.helmetEntry("helmet_stahl", "katzling", A.Entries) == "helmet_stahl_katzling", "katzling: holes")
		assert(Looks.helmetEntry("helmet_stahl", nil, A.Entries) == "helmet_stahl", "human: the plain helmet")
		assert(Looks.helmetEntry("helmet_m33", "alb", A.Entries) == "helmet_m33", "no holed version: the plain one")
		local S = require("../src/shared/Config/Species")
		for kit, species in S.Kits do
			local k = U.Kits[kit]
			local e = k and k.headwear and A.Entries[Looks.helmetEntry(k.headwear, species, A.Entries)]
			assert(
				not k or not k.headwear or (e and e.fit and e.fit.shell == A.Entries[k.headwear].fit.shell),
				`{kit}: the species' helmet keeps the kit's shell (its helmet-on hairs fit)`
			)
		end
	end,
	["a player spawns in one of the team kits, kept for the life"] = function()
		assert(#U.Teams >= 2, "kits to roll from")
		for _, k in U.Teams do
			assert(U.Kits[k], `{k}: Teams names a missing kit`)
		end
		local seen = {}
		for i = 0, 99 do
			local k = Looks.kit(nil, nil, U.Teams, i / 100, U.Kits)
			assert(U.Kits[k], "rolled a missing kit")
			seen[k] = true
		end
		for _, k in U.Teams do
			assert(seen[k], `{k}: never rolled`)
		end
		assert(Looks.kit(nil, nil, U.Teams, 0.9999, U.Kits) == U.Teams[#U.Teams], "the end of the roll: the last")
		assert(Looks.kit("uniform3", "uniform1", U.Teams, 0, U.Kits) == "uniform3", "this life's kit stays")
		assert(Looks.kit(nil, "uniform3", U.Teams, 0, U.Kits) == "uniform3", "the player's pinned kit")
		assert(Looks.kit("nope", 7, U.Teams, 0, U.Kits) == U.Teams[1], "junk attributes: rolled")
	end,
	["the helmet covers the top half of the head's hitbox"] = function()
		assert(Looks.onHelmet({ X = 0.9, Y = 0.01, Z = -0.5 }), "just above the middle: helmet")
		assert(not Looks.onHelmet({ X = 0, Y = -0.01, Z = -0.5 }), "just below: head")
	end,
	["a shot meets a helmet's crown where it stands out of the head"] = function()
		local function v(x: number, y: number, z: number)
			return { X = x, Y = y, Z = z }
		end
		local half = v(1, 0.6, 1.1) -- about a Stahlhelm's box (head space, Studio 2026-10-22)
		local function near(a: number?, b: number)
			return a ~= nil and math.abs(a - b) < 1e-6
		end
		-- straight on at the centre: the front of the shell, half.Z short of the box's middle
		assert(near(Looks.crownAt(v(0, 0, -20), v(0, 0, 1), half), 20 - 1.1), "head on: the front of the shell")
		-- over the top of the head's own box (y 0.5 in head space is the box's 0.3 here): still on the dome
		assert(Looks.crownAt(v(0, 0.5, -20), v(0, 0, 1), half) ~= nil, "a crown shot hits the dome")
		-- from the side through the brim edge
		assert(Looks.crownAt(v(-20, 0, 0), v(1, 0, 0), half) ~= nil, "from the side")
		-- above the dome, and past its sides: a miss
		assert(Looks.crownAt(v(0, 0.61, -20), v(0, 0, 1), half) == nil, "over the top: miss")
		assert(Looks.crownAt(v(1.01, 0, -20), v(0, 0, 1), half) == nil, "beside it: miss")
		-- pointing away, or starting inside: nothing
		assert(Looks.crownAt(v(0, 0, -20), v(0, 0, -1), half) == nil, "pointing away")
		assert(Looks.crownAt(v(0, 0, 0), v(0, 0, 1), half) == nil, "from inside")
		assert(Looks.crownAt(v(0, 0, -20), v(0, 0, 1), v(0, 1, 1)) == nil, "a flat box: nothing")
	end,
	["FFA headwear: every kit's own and its class gear, each a real asset entry; bare now and then"] = function()
		local Classes = require("../src/shared/Config/Classes")
		local Z = require("../src/shared/Config/ZoneMatch")
		local pool = Looks.headwearPool(U.Kits, Classes.Gear, Z.Headwear.gear)
		assert(#pool >= #U.Teams * 2, "kit helmets and more")
		local seen = {}
		for _, name in pool do
			assert(A.Entries[name], name)
			assert(not seen[name], "once each: " .. name)
			seen[name] = true
		end
		for _, k in U.Teams do
			assert(seen[U.Kits[k].headwear], k)
		end
		assert(Looks.headwear(pool, 0, Z.Headwear.bare) == 0)
		assert(Looks.headwear(pool, Z.Headwear.bare, Z.Headwear.bare) == 1)
		assert(Looks.headwear(pool, 0.999999, Z.Headwear.bare) == #pool)
		assert(Looks.headwear({}, 0.9, 0.1) == 0, "nothing to wear")
		local hit = {}
		for k = 0, 999 do
			hit[Looks.headwear(pool, k / 1000, Z.Headwear.bare)] = true
		end
		for i = 0, #pool do
			assert(hit[i], `{i} reachable`)
		end
	end,
}
