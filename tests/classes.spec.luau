--!strict
local R = require("../src/shared/Rules/Classes")
local B = require("../src/shared/Rules/Build")
local C = require("../src/shared/Config/Classes")
local U = require("../src/shared/Config/Uniforms")
local W = require("../src/shared/Config/Weapons")
local A = require("../src/shared/Config/Assets")
local BuildCfg = require("../src/shared/Config/Build")

-- the pieces only the Engineer builds
local ENGINEER = { Gun = true, Hesco = true, Sandbags = true }

return {
	["the user's prices: rifleman free, grenadier 50, auto rifler 100, engineer 150 (locked), mage 200"] = function()
		local want = { Rifleman = 0, Grenadier = 50, AutoRifler = 100, Engineer = 150, Mage = 200 }
		for key, cost in want do
			assert(C.Defs[key] and C.Defs[key].cost == cost, `{key} costs {cost}`)
		end
		assert(C.Defs.Engineer.locked == true, "the engineer is coming later")
		assert(C.Defs[C.Default].cost == 0 and not C.Defs[C.Default].locked, "the default is free and pickable")
		assert(C.Start == 0, "every match starts at 0")
		for _, key in C.List do
			assert(C.Defs[key], `listed class {key} exists`)
		end
	end,
	["a pick is paid only when it can be"] = function()
		local key, cost = R.resolve("Mage", 200, C.Defs, C.Default)
		assert(key == "Mage" and cost == 200, "exactly enough")
		key, cost = R.resolve("Mage", 199, C.Defs, C.Default)
		assert(key == C.Default and cost == 0, "short: the free default")
		key, cost = R.resolve("Engineer", 1000, C.Defs, C.Default)
		assert(key == C.Default and cost == 0, "locked: the default")
		key, cost = R.resolve("Nope", 1000, C.Defs, C.Default)
		assert(key == C.Default and cost == 0, "unknown: the default")
		key, cost = R.resolve(nil, 0, C.Defs, C.Default)
		assert(key == C.Default and cost == 0, "no pick: the default")
	end,
	["only real, unlocked classes can be picked"] = function()
		assert(R.pickable("Grenadier", C.Defs))
		assert(not R.pickable("Engineer", C.Defs), "locked")
		assert(not R.pickable("Nope", C.Defs) and not R.pickable(3, C.Defs) and not R.pickable(nil, C.Defs))
	end,
	["every class's gear exists in every team's kit"] = function()
		for _, kitName in U.Teams do
			for key in C.Defs do
				local g = R.gear(key, kitName, C.Defs, U.Kits, C.Gear)
				assert(g.Primary and W[g.Primary] and W[g.Primary].slot == "Primary", `{key} {kitName} primary`)
				assert(g.Shovel and W[g.Shovel].slot == "Shovel", `{key} {kitName} shovel`)
				assert(g.headwear and A.Entries[g.headwear], `{key} {kitName} helmet`)
				if g.Grenade then
					assert(W[g.Grenade].slot == "Grenade", `{key} {kitName} grenade`)
				end
			end
		end
	end,
	["rifleman: the kit's bolt rifle, no grenades; grenadier adds them"] = function()
		for _, kitName in U.Teams do
			local kit = U.Kits[kitName] :: any
			local r = R.gear("Rifleman", kitName, C.Defs, U.Kits, C.Gear)
			assert(r.Primary == kit.weapon and W[r.Primary].class == "BoltRifle" and r.Grenade == nil, kitName)
			-- user 2026-10-27: "the plated helmets should only be on soldiers with semi auto rifles"
			assert(r.headwear == kit.headwear, "the default helmet")
			local g = R.gear("Grenadier", kitName, C.Defs, U.Kits, C.Gear)
			assert(g.Primary == kit.weapon and g.Grenade == kit.grenade, kitName)
		end
	end,
	["auto rifler: the team's semi-auto and alternate helmet; mage: the team's staff"] = function()
		for _, kitName in U.Teams do
			local kit = U.Kits[kitName] :: any
			local a = R.gear("AutoRifler", kitName, C.Defs, U.Kits, C.Gear)
			assert(W[a.Primary :: string].class == "SemiRifle", kitName .. " semi")
			assert(a.headwear ~= kit.headwear, kitName .. " alternate helmet")
			-- the alternate helmet is the team's own: the same family of shell folder as the kit's helmet
			assert(A.Entries[a.headwear :: string].folder == A.Entries[kit.headwear].folder, kitName .. " team helmet")
			local m = R.gear("Mage", kitName, C.Defs, U.Kits, C.Gear)
			assert(W[m.Primary :: string].class == "Staff", kitName .. " staff")
			-- user 2026-10-27: "goggles on mage, armored on rifle"
			assert(m.headwear and m.headwear:find("_goggles$"), kitName .. " mage goggles")
			assert(A.Entries[m.headwear :: string].folder == A.Entries[kit.headwear].folder, kitName .. " team goggles")
			local g = R.gear("Grenadier", kitName, C.Defs, U.Kits, C.Gear)
			assert(g.headwear == kit.headwear, kitName .. " grenadier keeps the default helmet")
		end
	end,
	["katzlings and fenneks wear every class helmet with ear holes (user 2026-10-27)"] = function()
		local Looks = require("../src/shared/Rules/Looks")
		local S = require("../src/shared/Config/Species")
		for kitName, species in S.Kits do
			if species == "katzling" or species == "fennek" then
				for key in C.Defs do
					local h = R.gear(key, kitName, C.Defs, U.Kits, C.Gear).headwear :: string
					local worn = Looks.helmetEntry(h, species, A.Entries)
					assert(worn == `{h}_{species}`, `{key} {kitName}: {h} has a {species} version`)
					assert(A.Entries[worn].fit.shell == A.Entries[h].fit.shell, `{worn} keeps the shell`)
				end
			end
		end
	end,
	-- (Hesco barriers and sandbag piles too since round 7, user 2026-10-27: "hesco barriers should and sandbags should be
	-- engineer only")
	["only the engineer builds guns, Hesco barriers and sandbags; everyone builds trenches, wire and bridges"] = function()
		local kinds: { [string]: boolean } = {}
		for _, p in BuildCfg.Pieces do
			kinds[p.kind] = true
		end
		assert(kinds.Gun, "guns are a build piece")
		for key in C.Defs do
			for kind in kinds do
				local want = ENGINEER[kind] == nil or key == "Engineer"
				assert(R.mayBuild(key, kind, C.Defs, C.Default) == want, `{key} {kind}`)
			end
		end
		assert(not R.mayBuild(nil, "Gun", C.Defs, C.Default) and R.mayBuild(nil, "Trench", C.Defs, C.Default))
	end,
	["the build cycle leaves out what the class can't build, in the menu's order"] = function()
		for key in C.Defs do
			local list = R.buildable(key, BuildCfg.Pieces, C.Defs, C.Default)
			assert(#list > 0, key .. " builds something")
			local at = 0
			for _, p in list do
				local i = table.find(BuildCfg.Pieces, p) :: number
				assert(i > at, key .. " keeps the order")
				at = i
				assert(ENGINEER[p.kind] == nil or key == "Engineer", `{key} shows {p.key}`)
			end
			local theirs = 0
			for _, p in BuildCfg.Pieces do
				theirs += if ENGINEER[p.kind] then 1 else 0
			end
			assert(#list == #BuildCfg.Pieces - (if key == "Engineer" then 0 else theirs), key .. " shows the rest")
		end
	end,
	["the build gate refuses before anything else"] = function()
		local base = {
			piece = BuildCfg.Pieces[1],
			distance = 0,
			reach = 10,
			slope = 0,
			maxSlope = 10,
			ground = true,
			water = false,
			overlap = false,
			mine = 0,
			team = 0,
			perPlayer = 5,
			perTeam = 5,
		} :: any
		assert(B.canPlace(base), "no gate: fine")
		base.allowed = true
		assert(B.canPlace(base), "allowed: fine")
		base.allowed = false
		local ok, why = B.canPlace(base)
		assert(not ok and why == "Engineers only", tostring(why))
	end,
	["the kill goes to the last hitter, assists to others who did enough, within the window"] = function()
		local hits = {
			{ by = 1, amount = 40, at = 0 }, -- too old by the end
			{ by = 2, amount = 30, at = 10 },
			{ by = 3, amount = 10, at = 12 }, -- too little
			{ by = 4, amount = 25, at = 14, zone = "Head" },
			{ by = 9, amount = 50, at = 14.5 }, -- the victim's own
		}
		local killer, head, assists = R.credit(hits, 9, 20, 15, 20)
		assert(killer == 4 and head, "the last enemy, headshot")
		assert(#assists == 1 and assists[1] == 2, `assists {table.concat(assists, ",")}`)
		local k2, h2, a2 = R.credit({ { by = 2, amount = 30, at = 0 }, { by = 2, amount = 70, at = 1 } }, 9, 2, 15, 20)
		assert(k2 == 2 and not h2 and #a2 == 0, "one hitter: the kill, never also an assist")
		local k3 = R.credit({ { by = 2, amount = 100, at = 0 } }, 9, 30, 15, 20)
		assert(k3 == nil, "nobody within the window")
		local k4 = R.credit({ { by = 9, amount = 100, at = 0 } }, 9, 1, 15, 20)
		assert(k4 == nil, "only yourself")
	end,
	["earnings are scaled to the prices and points never go below 0"] = function()
		for reason, n in C.Earn do
			assert(n > 0 and n <= C.Defs.Grenadier.cost, `{reason}: {n}`)
		end
		assert(R.earn(5, C.Earn.Kill) == 5 + C.Earn.Kill)
		assert(R.earn(5, -10) == 0)
	end,
	["the menu state: every class in order, locked and affordable flags"] = function()
		local s = R.state(60, "Grenadier", "Rifleman", C.List, C.Defs)
		assert(s.points == 60 and s.picked == "Grenadier" and s.current == "Rifleman")
		assert(#s.classes == #C.List)
		for i, card in s.classes do
			assert(card.key == C.List[i], "in order")
			local d = C.Defs[card.key]
			assert(card.locked == (d.locked == true))
			assert(card.affordable == (not d.locked and d.cost <= 60), card.key)
		end
	end,
	["an admin's pinned class wins, locked or not, and is free"] = function()
		local key, cost = R.resolve("Mage", 200, C.Defs, C.Default, "Engineer")
		assert(key == "Engineer" and cost == 0, "pinned engineer, free")
		key, cost = R.resolve("Mage", 200, C.Defs, C.Default, "Nope")
		assert(key == "Mage" and cost == 200, "an unknown pin is ignored")
		key, cost = R.resolve("Mage", 200, C.Defs, C.Default, nil)
		assert(key == "Mage" and cost == 200, "no pin: as before")
	end,
}
