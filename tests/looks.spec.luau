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
	["white hair is the rare one, about 1 in 15"] = function()
		local total, rare = 0, 0
		for _, l in U.HairColors do
			total += l.weight
			if l.name == "white" then
				rare += l.weight
			end
		end
		assert(math.abs(rare / total - 1 / 15) < 0.01, `rare share {rare / total}`)
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
					assert(e and e.hair and #e.hair.center == 3, `{kit}: {on} missing`)
				end
			end
		end
		assert(Looks.hairEntry("bald", "stahl") == nil, "bald wears no hair")
	end,
	["the helmet covers the top half of the head's hitbox"] = function()
		assert(Looks.onHelmet({ X = 0.9, Y = 0.01, Z = -0.5 }), "just above the middle: helmet")
		assert(not Looks.onHelmet({ X = 0, Y = -0.01, Z = -0.5 }), "just below: head")
	end,
}
