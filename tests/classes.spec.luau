--!strict
local R = require("../src/shared/Rules/Classes")
local B = require("../src/shared/Rules/Build")
local C = require("../src/shared/Config/Classes")
local U = require("../src/shared/Config/Uniforms")
local W = require("../src/shared/Config/Weapons")
local A = require("../src/shared/Config/Assets")
local BuildCfg = require("../src/shared/Config/Build")
local ShovelCfg = require("../src/shared/Config/Shovel")

-- the classes with the Engineer locked again (a class shown but not picked yet)
local LOCKED = table.clone(C.Defs)
LOCKED.Engineer = table.clone(C.Defs.Engineer)
LOCKED.Engineer.locked = true

-- the pieces only the Engineer builds
local ENGINEER = { Gun = true, Nest = true, Dugout = true }

return {
	["the user's prices (2026-11-12): unlocks 100 / 200 / 200 / 100 / 300, then 50 / 100 / 100 / 50 / 150 a respawn"] = function()
		local want = {
			Rifleman = { 0, 0 },
			Grenadier = { 100, 50 },
			AutoRifler = { 200, 100 },
			Shotgunner = { 200, 100 },
			Engineer = { 100, 50 },
			Mage = { 300, 150 },
		}
		for key, p in want do
			local d = C.Defs[key]
			assert(d and d.unlock == p[1] and d.fee == p[2], `{key} unlocks for {p[1]}, then {p[2]} a life`)
		end
		assert(not C.Defs.Engineer.locked, "the engineer is open to players (user 2026-11-01)")
		assert(R.price(C.Defs[C.Default]) == 0 and not C.Defs[C.Default].locked, "the default is free and pickable")
		for _, key in { "Grenadier", "Engineer" } do
			assert(R.price(C.Defs[key]) <= C.Start, `the start pays a first life as the {key}`)
		end
		assert(R.price(C.Defs.Grenadier) + R.price(C.Defs.Engineer) > C.Start, "but not both")
		for _, key in C.List do
			local d = C.Defs[key]
			for _, o in C.Defs do
				if o.unlock > d.unlock then
					assert(o.fee >= d.fee, `{key}: a dearer unlock never has a smaller fee`)
				end
			end
		end
		for _, key in C.List do
			assert(C.Defs[key], `listed class {key} exists`)
		end
	end,
	["a pick is paid only when it can be"] = function()
		local key, cost = R.resolve("Mage", 300, C.Defs, C.Default)
		assert(key == "Mage" and cost == 300, "exactly enough: the unlock, which pays the first life")
		key, cost = R.resolve("Mage", 299, C.Defs, C.Default)
		assert(key == C.Default and cost == 0, "short: the free default")
		key, cost = R.resolve("Engineer", 1000, C.Defs, C.Default)
		assert(key == "Engineer" and cost == 100, "the engineer, unlocked and paid")
		key, cost = R.resolve("Engineer", 1000, LOCKED, C.Default)
		assert(key == C.Default and cost == 0, "locked: the default")
		key, cost = R.resolve("Nope", 1000, C.Defs, C.Default)
		assert(key == C.Default and cost == 0, "unknown: the default")
		key, cost = R.resolve(nil, 0, C.Defs, C.Default)
		assert(key == C.Default and cost == 0, "no pick: the default")
	end,
	["only real, unlocked classes can be picked"] = function()
		assert(R.pickable("Grenadier", C.Defs))
		assert(R.pickable("Engineer", C.Defs))
		assert(not R.pickable("Engineer", LOCKED), "locked")
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
	["the engineer carries its team's own pistol, a different one per team"] = function()
		local seen = {}
		for _, kitName in U.Teams do
			local g = R.gear("Engineer", kitName, C.Defs, U.Kits, C.Gear)
			assert(W[g.Primary].class == "Pistol", `{kitName}: {g.Primary} is a pistol`)
			assert(not seen[g.Primary], `{kitName}: {g.Primary} is another team's too`)
			seen[g.Primary] = true
		end
	end,
	["the engineer wears its team's soft cap, no one else a soft one (user: a cap that isnt bullet proof)"] = function()
		for _, kitName in U.Teams do
			for key in C.Defs do
				local g = R.gear(key, kitName, C.Defs, U.Kits, C.Gear)
				local fit = A.Entries[g.headwear].fit :: any
				assert((fit.soft == true) == (key == "Engineer"), `{key} {kitName}: soft only on the engineer`)
				assert(fit.shell and fit.brim, `{key} {kitName}: a shell and a brim`)
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
	["shotgunner: the team's pump shotgun, the shell-band helmet, no grenades, small builds (trenches, sandbags, wire, Hesco barriers, bridges)"] = function()
		assert(C.Defs.Shotgunner and not C.Defs.Shotgunner.locked, "pickable")
		assert(table.find(C.List, "Shotgunner"), "in the menu")
		for _, kitName in U.Teams do
			local kit = U.Kits[kitName] :: any
			local s = R.gear("Shotgunner", kitName, C.Defs, U.Kits, C.Gear)
			local w = W[s.Primary :: string] :: any
			assert(w.class == "Shotgun" and w.slot == "Primary", kitName .. " the pump shotgun")
			assert(s.Grenade == nil and s.Shovel == kit.shovel, kitName .. " no grenades, the shovel")
			local h = A.Entries[s.headwear :: string] :: any
			assert(
				s.headwear ~= kit.headwear and string.find(s.headwear :: string, "_ammo$"),
				kitName .. " shell helmet"
			)
			assert(h.folder == A.Entries[kit.headwear].folder, kitName .. " the team's own helmet")
			assert(h.fit.shell == (A.Entries[kit.headwear] :: any).fit.shell, kitName .. " fits the kit's hair")
		end
		for _, kind in { "Trench", "Foxhole", "Sandbags", "Wire", "Hesco", "Bridge" } do
			assert(R.mayBuild("Shotgunner", kind, C.Defs, C.Default), kind)
		end
		for kind in ENGINEER do
			assert(not R.mayBuild("Shotgunner", kind, C.Defs, C.Default), kind .. ": the engineer's")
		end
		local key, cost = R.resolve("Shotgunner", 199, C.Defs, C.Default)
		assert(key == C.Default and cost == 0, "short: the free default")
		key, cost = R.resolve("Shotgunner", 200, C.Defs, C.Default)
		assert(key == "Shotgunner" and cost == 200, "paid")
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
	-- (Hesco barriers and sandbag piles everyone's again, user 2026-11-02: "allow sandbags and barriers to be built by
	-- ordinary soldiers too")
	["only the engineer builds guns, MG nests and dugouts; everyone builds trenches, sandbags, wire, Hesco barriers and bridges"] = function()
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
			assert(n > 0 and n <= R.price(C.Defs.Grenadier), `{reason}: {n}`)
		end
		assert(C.Earn.Win == nil, "no Win award (user 2026-11-05: drop)")
		assert(C.Pay == 1, "the awards as written (user 2026-11-12: four times the old quarter, with the new prices)")
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
			assert(card.cost == R.price(d) and card.unlocked == (d.unlock == 0), card.key)
			assert(card.affordable == (not d.locked and card.cost <= 60), card.key)
		end
		local after = R.state(50, "Mage", nil, C.List, C.Defs, { Mage = true })
		for _, card in after.classes do
			if card.key == "Mage" then
				assert(card.unlocked and card.cost == 150 and not card.affordable, "unlocked: only the fee")
			end
		end
	end,
	["an unlocked class costs only its fee for the rest of the match"] = function()
		local unlocked = {}
		local key, cost = R.resolve("Mage", 300, C.Defs, C.Default, nil, unlocked)
		assert(key == "Mage" and cost == 300, "the first life: the unlock")
		unlocked[key] = true
		key, cost = R.resolve("Mage", 150, C.Defs, C.Default, nil, unlocked)
		assert(key == "Mage" and cost == 150, "later lives: the fee")
		key, cost = R.resolve("Mage", 149, C.Defs, C.Default, nil, unlocked)
		assert(key == C.Default and cost == 0, "short of the fee: the free default")
		key, cost = R.resolve("AutoRifler", 150, C.Defs, C.Default, nil, unlocked)
		assert(key == C.Default and cost == 0, "another class still needs its unlock")
	end,
	["support pays: heals by health healed, a drag once per knock-down and far enough"] = function()
		assert(R.healPay(C.HealPer, C.Earn.Heal, C.HealPer) == C.Earn.Heal, "a full heal's worth")
		assert(R.healPay(25, 8, 100) == 2 and R.healPay(-5, 8, 100) == 0)
		assert(R.dragPays(C.DragPay.least, C.DragPay.least, false), "far enough")
		assert(not R.dragPays(C.DragPay.least - 0.1, C.DragPay.least, false), "too short")
		assert(not R.dragPays(100, C.DragPay.least, true), "already paid this knock-down")
		assert(C.Earn.Drag and C.Earn.Repair and C.Earn.Heal)
	end,
	["building pays by the time spent at it, a fighter's rate (user 2026-11-06)"] = function()
		local full = ShovelCfg.Dig.length
		assert(B.swingSpent(10, nil, full) == 1, "a first swing: a full one")
		assert(math.abs(B.swingSpent(10, 10 - full / 2, full) - 0.5) < 1e-9, "a quick chip: half")
		assert(B.swingSpent(100, 10, full) == 1, "after a pause: one full swing, no more")
		assert(C.Earn.Trench == nil, "the per-square award is folded into Work")
		local perMinute = 60 / full * C.Earn.Work * C.Pay
		-- (a fighter's ~27 since 2026-11-12, four times the old ~6)
		assert(perMinute > 20 and perMinute < 28, `nonstop building pays {perMinute} a minute, a fighter's ~27`)
	end,
	["an admin's pinned class wins, locked or not, and is free"] = function()
		local key, cost = R.resolve("Mage", 300, C.Defs, C.Default, "Engineer")
		assert(key == "Engineer" and cost == 0, "pinned engineer, free")
		key, cost = R.resolve("Mage", 300, C.Defs, C.Default, "Nope")
		assert(key == "Mage" and cost == 300, "an unknown pin is ignored")
		key, cost = R.resolve("Mage", 300, C.Defs, C.Default, nil)
		assert(key == "Mage" and cost == 300, "no pin: as before")
	end,
}
