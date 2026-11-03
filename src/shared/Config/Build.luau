--!strict
-- Player building (phase 4.4, stage 1; user 2026-10-22: everyone builds with the shovel, the cost is shovel swings
-- plus caps, trenches carved in the terrain, the pieces flat-coloured code-built shapes until meshes are approved).
-- Rules/Build decides, src/server/Build builds, src/client/Build shows build mode. Data only.
--
-- Build mode: the shovel in the hands, Key_Build toggles it; Key_BuildPrev / Key_BuildNext (Q / E) pick a piece,
-- Key_BuildTurn turns it, a click lays its blueprint. The shovel's mode (Key_Reload toggles Build / Destroy, user
-- 2026-10-23): a Build swing at a piece of your team adds one unit of work; at `work` it stands (at any team's standing
-- gun it repairs it: src/server/Artillery.repair). A Destroy swing at any piece, any team's, takes one off; at 0 it is
-- torn down (a trench falls in). Destroy swings also chop trees (Config/Damage.Trees.Chop).

local Build = {
	-- how far from the builder's root a piece can be laid, and a swing reach its piece (studs, to the piece's footprint)
	Reach = 14,
	SwingReach = 8,
	-- a piece keeps this far from anything solid round its footprint, from the ground up (buildings, props, trunks, low
	-- walls, rubble; other pieces go by footprint, Survey.onPiece; soldiers only on it) (user 2026-11-02: "make it a
	-- generous stud margin", "i want to adjust them so it stops colliding with stuff")
	Margin = 2,
	-- the structure your shovel would work (a trench square, any piece; a standing gun itself), or the trench square
	-- you're extending or branching off, is lit faintly (a Highlight in Palette.Build.Focus: its fill and outline
	-- transparency; user 2026-10-25: "a slight slight indicator for which segment you are focused on"; 2026-10-27: "be
	-- sure to give all structures the white border that the trenches have when near with a shovel")
	Focus = { fill = 0.93, outline = 0.6 },
	-- swings faster than this share of the shortest time between two strikes (Rules/Build.strikeGap) are ignored
	SwingSlack = 0.8,
	-- what one swing does, against each piece's own amounts below (hp.swing, hp.destroy, a gun's repair share): a
	-- Build swing `build` of it, and a class in `class` that much again on both its Build and Destroy swings
	-- (Rules/Build.swingPower; user 2026-11-02: "let's half the building power of both soldiers and engineers",
	-- "apply building buff to destruction as well for engineers")
	Power = { build = 0.5, class = { Engineer = 1.5 } :: { [string]: number } },
	-- a blueprint nobody has worked on goes after this (seconds)
	BlueprintLife = 120,
	-- live pieces (blueprints count) per player and per team: a piece with its own `playerCap` (Pieces) counts only
	-- against that, of its own key; every other piece against PerPlayer together; every piece against PerTeam. A piece's
	-- `teamCap` caps its key per team, its `sectorCap` per team in each Map1 sector (Rules/Sectors.sectorAt)
	PerPlayer = 8,
	PerTeam = 300, -- (was 150; user 2026-11-01, with the per-player caps raised)
	-- where the pieces live (a Folder in Workspace)
	Folder = "Structures",
	-- the ghost in build mode (src/client/Build): fill colours where it can / can't go
	Ghost = { ok = { 120, 200, 120 }, bad = { 220, 80, 70 }, transparency = 0.55 },
	-- a gun's ghost (src/client/Build; user 2026-10-27: "reduce the red space for a howitzer ... just make it the size
	-- of the actual howizer with the trench. infact, make the outline a rough estimate of what the model would look like
	-- when constructed"; then: "dont show the actual model, i take that back. just show how much space it actually takes
	-- (the visible model with applicable trench)"): a box round the gun's visible model, see-through in Ghost ok / bad,
	-- standing as it will (a dug-in gun on its pit's floor), and a dug-in gun's pit and ramp outlined flat on the ground,
	-- `outline` studs thick, `outlineSee` see-through
	GunGhost = { outline = 0.3, outlineSee = 0.7 },
	-- the trench planner's ghost (src/client/Build; user 2026-10-24: "make the entire planning thing better and more
	-- stylish"), a preview of the stakes and cord the
	-- server lays: per square a faint fill (Ghost ok / bad, `fill` see-through) with the dug floor's band in it
	-- (`floor`), a chalk cord round it (`cord` wide, `cordSee` see-through; Palette.Build.Chalk, ChalkBad when it can't
	-- go), `gap` between squares, ghost stakes (`peg`: width, height, one at the cursor before the
	-- first click; no flags, user 2026-10-24: "lets just do the stakes"); squares fade in and out at `fade` per second. Reach circles (Trench.firstReach) dashed on the ground: `dashes`
	-- dashes, each `dash` of its step, `ringWidth` wide; the one you stand in `near` see-through, the other `far`.
	Plan = {
		fill = 0.82,
		floor = 0.7,
		cord = 0.14,
		cordSee = 0.1,
		gap = 0.3,
		peg = { 0.22, 1.0 },
		fade = 12,
		dashes = 44,
		dash = 0.55,
		ringWidth = 0.18,
		near = 0.2,
		far = 0.6,
		-- the action icon over each end (user 2026-10-24: "one icon for new trenches, one more extending"): a round badge
		-- `size` studs across on a chalk pin `height` studs tall
		badge = { height = 2.4, size = 1.4 },
	},
	-- the turn step (degrees) for Key_BuildTurn and a mouse wheel notch with Shift
	TurnStep = 15,

	-- Trenches v2 (user 2026-10-23): carved into the
	-- terrain like the howitzer's pit (user: "I really like how the mortar dug out is like ... make it like that"),
	-- src/server/Trenches. A plan is one straight run, click start, click end (src/client/Build), up to `maxPlan`
	-- studs, split into blocks of up to `block` studs (at least `minBlock`); the plan is pegged out with markers
	-- everyone sees. Each block is dug on its own: `work` swings, deeper at each stage. A plan's end on a free end of a
	-- trench joins it end to end (up to `maxBend` off straight); on a block's side, a T. A plan may not cross a trench
	-- (user: "connect the trench then continue from the other side").
	-- Segments (user 2026-10-23: "make each segment a fixed size", "make each segment distinct", "trenches should be
	-- treated like other structures. they have hp. how dug in they are are determined by hp"): a run is split into
	-- segments of `block` studs, each pegged out with its own string outline until it is dug full, and each with HP:
	-- its depth is HP / MaxHP of the full depth.
	Trench = {
		block = 8, -- (user 2026-10-23: fixed 8-stud segments; Rules.planBlocks for the leftover)
		minBlock = 2,
		maxPlan = 60,
		-- the first click this close to you, and when the plan is laid you within this of either end (you may walk along
		-- it while planning; the planner shows it red with the reason as soon as you're too far, user 2026-10-24)
		firstReach = 14,
		-- a plan's end this close to a free end joins it (8 since the wider 59 degree walls: 4 was easy to miss, user
		-- 2026-10-24: "the trenches dont connect")
		joinReach = 8,
		-- a new trench keeps this far (between centre lines) from every other trench, except near the end where it joins
		-- one (user 2026-10-24: "you shouldnt be able to build a new trench within a certain distance of another trench
		-- unless you're extending"; 32 since the parapets: two trenches' parapets just meet; 25 since the narrower trench,
		-- user 2026-11-02, "make it a little more narrow and less thick", option B)
		spacing = 25,
		maxBend = 135,
		maxSlope = 22, -- degrees of ground slope along the run
		-- the run's slope measured over this many studs (a voxel's step between two samples 3 studs apart read as too
		-- steep on gentle hills)
		slopeSpan = 8,
		-- a square lies tilted with the ground across it (user 2026-11-02: "make the terrain match the angle of the slope,
		-- not make it flat"): its hole, walls and pieces turned by the slope from one wall top to the other, refused
		-- over `maxCross` degrees there (sharp ground, craters)
		maxCross = 25,
		-- no piece stands over a square's open cut, dug or only planned, nor is a square planned under one (user
		-- 2026-11-02: "things cant be built if something is in its way, so floating sad bag shouldnt be possible"): the
		-- cut is its top edges (Rules.trenchTop) less this much a piece may hang over the edge from its bank
		overhang = 0.5,
		-- no square is planned with a standing tree's trunk (at its widest, the roots' flare) within its cut, on its walls
		-- or on its dirt heaps (Rules.trenchTop + joins.heapReach), nor within `treeClear` studs past them (user
		-- 2026-11-02: "also trees are going into trenches. increase the boundaries")
		treeClear = 2,
		-- nothing solid (buildings, props, fallen trunks) across a planned square's whole width out to its dirt heaps'
		-- edge (Rules.trenchTop + joins.heapReach), from its lowest ground to `wayHeight` over its highest, nor past its
		-- dead ends by its end heap (user 2026-11-02: "i want to adjust them so it stops colliding with stuff"; was a
		-- strip 4 either side of the line, 1 to 6 up)
		wayHeight = 6,
		planLife = 180, -- seconds an undug plan stays
		-- a swing works the square whose line is this close, in front of you (from anywhere on its dirt, out past its
		-- heap, joins.heapReach; user 2026-10-25: "can you extend the trench hitbox"; 19 to 13 with the narrower trench)
		swingReach = 13,
		-- a square's HP: a Build swing adds `swing` (up to `max`), a Destroy swing takes `destroy` off; blasts take HP by
		-- their overpressure at the square (Blast below). Once dug full it is buried by what it loses: full depth down to
		-- `hold`% HP, then filled in with the rest (80%: a little earth in it; 5-10%: nearly level, unusable), its pieces
		-- under the fill (user 2026-10-24: "an 80% trench should start visibly filling a little bit, but not an unusable
		-- amount"; "way way more durable")
		-- (Build swings dig a square: 10, an engineer's 7, since build power was halved (Power above; was 5: "make
		-- building take a bit longer", user 2026-10-24))
		-- (its neighbours add no walls round a buried square, user 2026-10-25: "just make it fill, no need to add
		-- additional walls")
		-- (user 2026-11-01: "always be slowly filled up and dug in as HP drops and only breaks at HP 0": its pieces stay
		-- to the end, the floor riding up on the fill and the dirt heaps sinking `heapSink` studs by 0 HP, so about 20 HP
		-- is barely any cover; the 75% cut-off where the pieces went is gone)
		hp = { max = 100, swing = 20, destroy = 4, hold = 95 },
		heapSink = 2.6,
		-- the shape: floor half width, depth, walls at `wallAngle` (Metrics MaxSlopeAngle decides whether you can walk
		-- up them), earth thrown up as a bank along both edges (the pit's rim) under each wall's parapet (Config/Assets
		-- trench_pieces Wall<i>Parapet: a thick heap of dirt just behind the wall's top edge, about 2.1 to 2.5 over the
		-- ground, a 74 degree face toward the trench: too steep to walk up, chest high cover to shoot over)
		-- (carved in 4-stud voxels the floor rounds into a bowl and the walls soften: Studio round t1023-2101 measured a
		-- 6-wide floor as a narrow bowl and 60 degree walls as 45-55, so the carve is wider at the floor and steeper)
		-- (user 2026-10-23: 1.5x wider, then "a little more narrow"; 4.25 to 3, user 2026-11-02, "make it a little more narrow and less thick", option B: the 6-stud floor of
		-- docs/METRICS.md, two soldiers can pass)
		floor = 3,
		depth = 5.5,
		-- (user 2026-10-23: "just make it a wall with less slope ... no invisible steps": no wall grip)
		-- (user 2026-10-23: steeper, 70, "it could be either deeper or less slopy"; 2026-10-24: "make this less steep
		-- (just a bit) so our character can walk out of (not smoothly and easily of course)", 48, then "make the slope
		-- more aggressive. have an inbetween from what we had before and now")
		wallAngle = 59,
		-- the terrain is cut this much deeper and wider than the pieces lie (their base slabs collide, so they are what
		-- you stand on; Studio round 2026-11-02: the 4-stud voxels rounded the floor into a bowl over the pieces)
		carve = { wider = 0.6, deeper = 0.8 },
		bank = { width = 3, height = 1.2 }, -- (width 5 to 3 with the narrower trench, under its smaller heap)
		-- a bullet meeting the ground this close round a square's hole, walls and banks hits the square (studs; the
		-- terrain is carved in 4-stud voxels, so a shot at a wall often meets the ground just in front of its slab)
		shotSlack = 2,
		-- a filled-in block leaves a scar: a lumpy dip this deep, churned earth, no grass
		scar = { depth = 0.6 },
		-- the soil a square is dug into (user 2026-11-01: "match the color of the terrain underneath (not the grass)"):
		-- the terrain's first material under the square's ground line that isn't in `skip`, else `fallback` (Map 1 is
		-- grass all the way down: Ground, Palette.Terrain); its fill, banks and bare rim are that material, its dirt
		-- pieces that material's colour (Palette.Build.Trench*)
		soil = { fallback = "Ground", skip = { "Grass", "LeafyGrass", "Air", "Water" } },
		-- no grass this far out past a dug square's wall tops (its dirt heap, joins.heapReach; 12 to 7 with the narrower
		-- trench): the terrain
		-- there is its soil until it is filled in to 0 HP (user 2026-11-01: "make sure the area outside the terrain has
		-- its grass removed too")
		grassClear = 7,
		-- the terrain reshaped a few voxel columns at a time (src/server/Trenches): `columns` across a step, steps for at
		-- most `budget` ms a frame, then the squares' pieces, one in a frame of its own; a square's reshape in one go was
		-- 2-8 ms
		reshape = { columns = 2, budget = 1 },
		-- markers (src/server/Trenches; user 2026-10-24): a
		-- stake (width, height) at each corner of a square, its top `top` studs painted (Palette.Build.PegTop), cord
		-- `string` wide between the stake tops sagging by `sag` of its length (a Beam's curve); no flags
		-- (user 2026-10-24: "i dont think we need a flag. lets just do the stakes"). (0.9 high pegs were lost in the tall grass, Studio round t1023-2101)
		markers = { peg = { 0.25, 1.6 }, top = 0.3, string = 0.08, sag = 0.035 },
		-- the dirt pieces of a square dug full (Config/Assets trench_pieces, tools/blender/trench/trench_pieces.py; user
		-- 2026-10-23: "make wide variety of random wall and floor segments ... and include wood on the wall ones"): one
		-- wall a side (Wall1..`walls`) and a floor (Floor1..`floors`), rolled from its seed (Rules.trenchPieces); the
		-- `wood` walls carry plank steps, rolled at `woodChance` a side, never on two squares in a row on one side. Made
		-- `segment` long, stretched along a shorter square; a dead end gets a plain wall across.
		-- (trench_pieces v12, tools/blender/trench/trench_wood.py; user 2026-11-02: "only use our old trench model
		-- again, but the one with wood on it and we make random variations of that": every one of the eight walls has
		-- plank steps, so none is set apart as `wood` and each side rolls any of them)
		pieces = { segment = 8, walls = 8, floors = 4, wood = {}, woodChance = 0 },
		-- the pieces' stages (Rules.trenchStage, % of hp.max): none while it is first dug (its markers and the cut
		-- deepening a swing at a time), the finished pieces at full HP, then destruction Hit1-3 under each of `hit`
		-- (boards working loose; the upper slabs and half the boards down; a few boards and one low slab left, earth
		-- slumped) while the fill rises (hp.hold)
		stages = { hit = { 75, 50, 25 } },
		-- where pieces meet (src/server/Trenches; user 2026-10-24: "make sure that the joints connect by the walls"): how far
		-- out past a wall's top edge its dirt heap reaches (it keeps that whole depth out of other trenches; 11 to 6 since
		-- trench_pieces v9, one lower heap and no skirt: user 2026-11-02, "make it a little more narrow and less thick",
		-- option B), and how much further the side heaps run on round a dead end and its heap reaches past the side
		-- walls' tops
		joins = { heapReach = 6, deadEndHeap = 3 },
		-- (trench_pieces v9 has no skirt; kept for a piece set that has one) the skirt behind a heap (Wall<i>Apron, low slabs meant to lie half sunk in the ground) is laid only where the
		-- ground under it comes within `apronHang` studs of its underside everywhere (Rules.thinPieceSits); where the
		-- trench pokes out over ground that falls away it would hang in the air as thin sheets, so the heap's full blocks
		-- stand alone there (user 2026-10-27: "i dont mind if blocks stick out in the air, as long as they are full
		-- blocks as they can somewhat blend in. this just looks glitched")
		apronHang = 0.3,
	},

	-- What each weapon does to built things (user 2026-10-24: "a revamp on damage to built structures ... rifles and
	-- weapons will do damage to a trench too, but just not a lot. most of it will be explosives. grenades and staffs
	-- should do the least, howitzer the most"): `hit`, the % of a trench square's or a sandbag pile's max HP it takes,
	-- in full within `edge` studs of it (the entry's own `edge` if it has one; a trench: its hole, walls and banks, so a blast on the bank counts; user:
	-- "make the ground around each segment to also be part of the trench hit box"), fading to nothing at `reach`;
	-- `wire`, the % of a barbed wire's HP; `bridge`, of a bridge's (Bridge below). Bullets only by a direct hit. A blast nobody named (DEV tools) by its
	-- charge: the first of `byCharge` it is no bigger than. (A Destroy swing is Trench.hp.destroy.)
	-- Staffs since 2026-10-27 (user: "staff beams should do a lot more damage to built structures overall. about 5-6
	-- should be able to sink/destroy a trench"): a full beam takes 18 (5 leave a trench nearly level, the 6th finishes
	-- it; a sandbag column the same), the lighter stages in the same proportion; wire about 3x what it was.
	Structures = {
		edge = 2,
		-- (bridges, user 2026-10-27, as drafted: bullets pass the planks, two grenades bring it down to its first stage and
		-- four take it away, a shell drops it)
		bullet = { hit = 0.2, wire = 0, bridge = 0 }, -- (about 500 hits bury a trench)
		grenade = { hit = 3, reach = 6, wire = 15, bridge = 25 },
		staff1 = { hit = 2, reach = 4, wire = 0, bridge = 0 },
		staff2 = { hit = 6, reach = 6, wire = 15, bridge = 5 },
		staff3 = { hit = 18, reach = 10, wire = 50, bridge = 25 }, -- (two full beams cut wire)
		-- (user 2026-11-03: "thats assuming its a direct hit. make it maximum 40 on a direct hit": 40 within `edge`, fading
		-- to nothing at `reach`; three direct hits bury a trench, a near miss less)
		field = { hit = 40, reach = 10, edge = 3, wire = 100, bridge = 100 },
		-- (user 2026-11-02, the damage rework: a smaller blast that still buries what it hits; was hit 93, reach 20, edge 8)
		howitzer = { hit = 100, reach = 14, edge = 5, wire = 100, bridge = 100 }, -- (buries it at once)
		byCharge = {
			{ kg = 0.5, source = "grenade" },
			{ kg = 5, source = "field" },
			{ kg = math.huge, source = "howitzer" },
		},
	},

	-- Every piece you can lay, in the order the build menu lists them.
	Pieces = {
		{
			key = "Trench",
			name = "Trench",
			kind = "Trench", -- planned by two clicks, dug block by block (Trench above)
			work = 8,
		},
		-- The foxhole (user 2026-11-02, design approved by the user): a one-man pit dug almost anywhere, cover for a
		-- soldier caught in the open (Foxhole below). Everyone builds it (Config/Classes SMALL). `width` x `depth` its
		-- footprint round the pit (the ground surveyed, kept off other pieces), `height` what must stand clear over it.
		{
			key = "Foxhole",
			name = "Foxhole",
			kind = "Foxhole",
			work = 1, -- one Build swing digs it (user 2026-11-02: no HP or progression)
			oneSwing = true, -- (whoever swings: Config Power doesn't cut it, Rules/Build.swingWork)
			-- no cap (user 2026-11-02: "no limits"): a cap of its own nothing reaches, so it never counts against
			-- PerPlayer either
			playerCap = math.huge,
			width = 8,
			depth = 8,
			height = 3,
			maxSlope = 25,
		},
		-- The sandbag pile (user 2026-10-27: pillow bags, "layer 1 2 bags, layer 2 1 bag", "make it even smaller ... ads
		-- still wont work", "make the sandbags longer"; the old low and high walls removed: "remove the old sand bag piles
		-- completely, keep the present ones"): Config/Assets `asset`'s meshes, one section for the whole pile, built and
		-- worn on HP (Sandbags.hp below), `bags` standing by its share of HP (with their ties, `<bag>Cord`).
		-- `width` x `height` x `depth` its footprint (the bags 3.6 long, ties out past them; the top 3.68: under the
		-- aimed muzzle, over the low cover line, Config/Metrics).
		{
			key = "SandbagPile",
			name = "Sandbags",
			kind = "Sandbags",
			-- per player, its own (PerPlayer above; user 2026-11-01: "essentially give player endless sand bags wires and
			-- barriers. maybe 25-30 each")
			playerCap = 30,
			asset = "sandbag_pile",
			bags = { "Bag1", "Bag2", "Bag3" },
			-- stage 1's meshes: the scraped ground (under it the whole time) and the empty sacks (until a bag is filled);
			-- neither blocks anything
			stage1 = { ground = "Patch", sacks = "Sacks" },
			width = 8.3,
			height = 3.68,
			depth = 1.7,
			maxSlope = 25,
		},
		-- The Hesco barrier (user 2026-10-27; Hesco below): a 6 x 6 basket of mesh and liner, `height` high (just over
		-- a standing soldier's 5.13: "it should be just barely the players height"; under full cover's 5.5), filled
		-- with dirt from the bottom up in `stages` (0: just laid, flat; 1: the empty perimeter; then a third of the dirt
		-- each), on HP
		-- (Hesco.hp below). Everyone builds it (a small asset: Config/Classes SMALL).
		{
			key = "Hesco",
			name = "Barrier",
			kind = "Hesco",
			asset = "hesco", -- (Config/Assets)
			playerCap = 30,
			stages = 4,
			width = 6,
			depth = 6,
			height = 5.25,
			maxSlope = 20,
		},
		{
			-- a plank bridge over a trench square (Bridge below): laid on the square under the cursor, as wide as it is
			-- long (`width` the full square's, stretched to the square's own), `depth` across from heap to heap, its deck
			-- `height` over the ground
			key = "Bridge",
			name = "Trench bridge",
			kind = "Bridge",
			work = 2, -- (it is built on HP: Bridge.hp below)
			width = 8,
			depth = 19.2,
			height = 3.1,
		},
		-- The dugout (user 2026-11-02, design approved): steps cut down through the wall of a dug trench square into a
		-- small timbered room under the ground (Dugout below). Engineers only (Config/Classes), `playerCap` each (user: "2
		-- per player"). Its room `width` along the trench x `height` x `depth` back (a standing soldier is 5.13), past its
		-- steps (Dugout.stair).
		{
			key = "Dugout",
			name = "Dugout",
			kind = "Dugout",
			playerCap = 2,
			width = 7,
			depth = 6,
			height = 6,
		},
		-- (user 2026-10-27: a section 8 long, 4 wide, 3/5 of a soldier high (3.1), stood in 2 swings, 4 since build power
		-- was halved (Wire below); laid on its own, no
		-- chaining or planner; the look: Config/Assets barbed_wire, Wire below)
		{
			key = "Wire",
			name = "Barbed wire",
			kind = "Wire", -- (built on HP: Wire.hp below)
			playerCap = 30,
			width = 8,
			depth = 4,
			height = 3.1,
			maxSlope = 30,
		},
		-- The MG nest (user 2026-10-27, design approved by the user): Engineers only
		-- (Config/Classes); four sandbag piles (Config/Assets `asset`'s bags) on a ring round the gunner, the M2
		-- (Config/Artillery.Guns `gun`) on its tripod on two mount bags (`mountBag`) in the point where the two front
		-- piles meet (Nest below). `width` x `depth` its footprint round the ring, `height` its top (the MG 08's shield
		-- set it; the 11-sided ring's 12.8 across and a bag's depth). (`stage1.sacks` unused here: a nest's empty sacks lie on their own spots, Nest.flat)
		{
			key = "MGNest",
			name = "MG nest",
			kind = "Nest",
			sectorCap = 3, -- per team in each sector (user 2026-11-01: "mg nest should be limited to 3 a sector")
			asset = "sandbag_pile",
			mountBag = "sandbag_m2",
			gun = "mg08",
			bags = { "Bag1", "Bag2", "Bag3" },
			-- stage 1's meshes from the pile (laid at 0 HP): the scraped ground under each pile, the empty sacks
			stage1 = { ground = "Patch", sacks = "Sacks" },
			width = 14.4,
			depth = 14.4,
			height = 4.6,
			maxSlope = 15,
		},
		-- The guns (user 2026-10-26: "add building the artilleries to shovels"; Config/Artillery.Guns `gun`, src/server/
		-- Artillery stands them): every team builds both, in its own paint (Guns.paint). On HP (Guns.hp below): laid at
		-- 0 with its first parts and the building site down, each Build swing adds `swing` HP (user: field 20 swings,
		-- howitzer 40; 40 and 80 since build power was halved, an engineer's 27 and 54: Power above), its parts fitted a quarter at a time and the howitzer's pit (its Config/Artillery `dig`) dug deeper
		-- at each of `stages` (user: "deeper with each stage"), standing at full HP. A gun keeps `spacing` studs from
		-- every other gun of its kind, any team's (user: "cannons cant be placed within certain distances of another,
		-- howitzer with howitzer": 60 and 120), and `clear` + the other's `clear` from any gun. `width` x `depth` (`height`
		-- high) is the ground it needs clear and gentle, its centre `back` studs behind the gun (the howitzer's: its pit to
		-- the wall tops and the ramp behind); no trench within `trenchGap` of it (the howitzer's: its earth rim).
		{
			key = "FieldGun",
			name = "Field gun",
			kind = "Gun",
			gun = "artillery_qf18",
			teamCap = 6, -- standing at once per team (user 2026-10-31: "limit to 6 friendly cannons and 2 friendly mortars")
			swing = 5, -- (40 swings, an engineer's 27)
			stages = 4,
			width = 7,
			depth = 15,
			height = 5,
			back = 2,
			maxSlope = 15,
			spacing = 60,
			clear = 9,
			trenchGap = 2,
		},
		-- (the Rune howitzer, user 2026-11-02; was the 42 cm "Rune mortar", 44 x 78 for its 15-stud pit, 4.5 earth rim and
		-- 40-stud ramp, 8 stages): its 3-deep pit and the sandbag ring round it (GunRing below, ~27 across), the pit's
		-- ramp out inside the ring
		{
			key = "Howitzer",
			name = "Rune howitzer",
			kind = "Gun",
			gun = "artillery_howitzer",
			ring = "artillery_howitzer", -- its sandbag ring (GunRing)
			teamCap = 2,
			swing = 2.5, -- (80 swings, an engineer's 54)
			stages = 4,
			width = 28,
			depth = 28,
			height = 6,
			back = 0,
			maxSlope = 12,
			spacing = 120,
			clear = 15,
			trenchGap = 2,
		},
	},

	-- Built guns, on HP like every structure (user 2026-10-27: "all structures follow an HP strucutre, not how many
	-- digs"; round 5: start at 0 HP with stage 1 down): `hp.max`, laid at `hp.place`; while it is built a Destroy swing
	-- takes its piece's `swing` off, at 0 it is gone. Once it stands its HP is the gun's own (Config/Artillery.Guns `hp`,
	-- Hits, Repair): shovel swings repair it or take Repair's share off. Weapons leave it a wreck at 0 that stays; a
	-- Destroy swing that takes it to 0, or at a wreck already at 0, and it is gone, nothing left (user 2026-10-27: "guns
	-- destroyed by weaponry and set to 0 hp will be placed, just with the extremely broken model. if a player destroys it
	-- with a shovel at 0 hp, it will disappear"), its pit filled back. `paint`: each kit's gun paint
	-- (Config/Palette.Artillery.Paint).
	Guns = {
		hp = { max = 100, place = 0 },
		paint = { uniform1 = "Grey", uniform2 = "Olive", uniform3 = "Brown" },
	},

	-- The building site round a gun being built (Rules/Scaffold, src/server/Build; user 2026-10-26: "include building
	-- structures (scaffolds, tools, etc) while the artillery is under construction"): it stands from the gun's laying
	-- out until the gun stands, and comes back when it is taken apart. Gun space on the floor the gun is built on (studs,
	-- right +X, back +Z; yaw degrees, + turns left). `frame`: a scaffold round it, posts `bays` bays down its long sides
	-- `height` high, ledgers and walk boards at each of `levels`; `tripod`: three poles over it lashed `height` up, their
	-- feet `spread` out (the first `turn` degrees from +X), a rope and hook hanging to `hook`; `crates` (`size` across,
	-- high, long), `planks` (`count` stacked, `length` long), `sawhorses`. Nothing in it can be stood on, touched or shot.
	Scaffold = {
		-- (user 2026-10-26: "make it more subtle please"; was a 7-stud tripod over the field gun, a 20-stud one and a
		-- two-level 10.5-stud scaffold round the howitzer, posts 0.35)
		Sizes = {
			post = 0.25, -- the frame's posts, ledgers, walk boards (`board` wide, `plank` thick)
			ledger = 0.15,
			board = 1,
			plank = 0.12,
			pole = 0.2, -- the tripod's poles, `overshoot` past their lashing, the lashing `lash` up and down, its block,
			overshoot = 0.4, -- the rope and the hook
			lash = 0.25,
			block = 0.4,
			rope = 0.07,
			hook = 0.35,
			braceLift = 0.3, -- the frame's braces start this far up a post
			lashWidth = 1.6, -- the lashing, block and hook across (x their size)
			blockShape = { 0.6, 0.4 },
			hookShape = { 0.5, 0.25 },
			-- a crate: its lid `lid` past it, battens `batten` thick `battenAt` of its width out, a mallet on top (its
			-- handle from x, z, at height, to x, z, as shares of the crate) and its head
			crate = {
				lid = 0.06,
				batten = 0.12,
				battenAt = 0.3,
				handle = { 0.35, 0.1, 0.06, 0.15, 0.15 },
				handleWidth = 0.1,
				head = { turn = 30, at = { 0.1, 0.22 }, size = { 0.5, 0.3, 0.3 } },
			},
			pile = { turn = 2, shift = 0.08 }, -- each plank turned and shifted off the one under it
			horse = { length = 1.8, height = 1.1, beam = 0.2, splay = 0.35, inset = 0.2, leg = 0.12 },
		},
		artillery_qf18 = {
			crates = { { x = -3, z = 2.6, yaw = 15, size = { 1.2, 0.7, 0.8 } } },
			planks = { { x = 2.9, z = 4.8, yaw = -6, count = 2, length = 3.5 } },
		},
		-- (in an MG nest: on the ground at the ring's middle, x right, z back from the gun; inside the bags, clear of the
		-- M2's two mount bags and the doorway at the back)
		mg08 = {
			crates = { { x = -2.6, z = 1.4, yaw = 20, size = { 1, 0.6, 0.7 } } },
			planks = { { x = 2.7, z = 1.0, yaw = -12, count = 2, length = 2.6 } },
		},
		-- (the Rune howitzer, 2026-11-02: on its pit's floor inside the sandbag ring, off its bed's corners; the 42 cm's
		-- scaffold frame round it is gone with its deep pit)
		artillery_howitzer = {
			crates = { { x = -7.5, z = 0, yaw = 10, size = { 1.4, 0.8, 1.0 } } },
			planks = { { x = 7.4, z = 1.5, yaw = 85, count = 3, length = 3.5 } },
			sawhorses = { { x = -1.5, z = -7.5, yaw = 90 } },
		},
	},

	-- Sandbag piles: one section of class "Sandbag" (Config/Damage.Blast.Fail) with `hp.max` HP, set `sink` studs into the
	-- ground (uneven ground shows no gap), each bag's tone jittered by `shade`. On HP, like every structure (user
	-- 2026-10-27: "all structures follow an HP strucutre, not how many digs", "stage 1 should always be when its placed
	-- ... like a cannon, where if its placed, something will always be down"): laid at `hp.place` (stage 1, below),
	-- a Build swing of its team adds `hp.swing` up to `hp.max` (repairs too), a Destroy swing takes `hp.destroy`;
	-- weapons take Structures above; its bags stand by HP (Rules.pileBags: one at least while it has any), gone at 0.
	-- Stage 1 (user 2026-10-27: "a new stage 1, where no sandbags are placed, that way we can have 1 new sandbag per
	-- dig"): laid at 0 HP (user 2026-10-27: "yes", like the Hesco), the pile is its scraped ground and empty sacks
	-- (Pieces `stage1`); a bag for every `swing` of HP begun (0, 34, 68, 100: no bag, one, two, all three;
	-- Rules.pileBags): each Build swing filled a bag, and since build power was halved (Power above) a bag every other
	-- swing, 6 to full, an engineer's 4.
	Sandbags = { hp = { max = 100, place = 0, swing = 34, destroy = 10 }, shade = 0.06, sink = 0.15 },

	-- Nothing is left hanging in the air (user 2026-11-02: "make sure floating parts are not possible"): after a blast,
	-- a sandbag pile, wire or Hesco barrier within `reach` of it whose ground under fewer than `share` of its footprint's
	-- samples is still within `gap` below where it was laid (Rules.supported) is gone, like a piece at 0 HP
	Support = { reach = 40, gap = 1.5, share = 0.6 },

	-- MG nests (Pieces kind "Nest"; user 2026-10-27, design approved by the user, Blender
	-- approved "besides that its good"): one section of class "Sandbag" (the bags; Sandbags.shade, Sandbags.sink).
	-- Built like every structure (user 2026-10-28: "4 stages of construction, 4 stages of destruction (becomes unusable
	-- at 50%). when things build or break off, it just becomes the next stage, no animation. look at how everything else
	-- is being built (especially other artilleries and the barrer)"): on HP, laid at `hp.place` with its stage 0 down at
	-- once, every bag an empty sack lying flat on its own spot (`flat` of its height; a top bag's over the sacks under
	-- it) and a building site in the ring (Scaffold mg08; user 2026-10-28: "not all the parts have to be present before
	-- its built ... they can just appear as its being built. just have some signs of "construction""); a Build swing
	-- of its team adds `hp.swing`, a Destroy swing takes `hp.destroy`, weapons take Structures as a sandbag pile's; its
	-- stage by HP as a Hesco barrier's (Rules.hescoStage: 25, 50, 75, 100 for stages 1-4), each stage's bags filled
	-- (`build[i].bags`: "bottom" the mount bag and the piles' bottom bags, "all") and gun quarters set up (`gun`, of
	-- `quarters`), the real gun standing at stage 4. Once it has stood it is the gun's (as a built field gun): its HP is
	-- the gun's own, worn by weapons, blasts at the bags and Destroy swings, fixed by Build swings (Config/Artillery
	-- Repair), its 4 stages the gun's Wreck stages (unusable under half its HP, Config/Artillery.Man), the share of the ring's bags still
	-- standing at each `wear[i]` (user 2026-10-29: "make the sandbags also destroy as part of each destruction phase":
	-- the top bags go first, then the bottom ones, scattered round the ring, Rules.nestWearOrder; the mount bags stay
	-- under the gun); hit at 0 it is gone.
	-- The ring (user: "make the nest more circular shaped ... smoother and even and symmetrical"; Rules.nestRing): the
	-- eight bottom bags of the four piles on a regular `ring.sides`-sided ring of `ring.bag`-stud sides, the side at the
	-- back left open as the doorway; each pile bent at its joint, its top bag over the bend on the bottom bags' line; the
	-- front point is where two piles' ends meet, the notch between their top bags the gun's window. `ring.piles`: each
	-- pile's ring vertices (an end, its bend, the other end; 0 the front point), in build order. The gun's pivot stands
	-- `gunBack` behind the point, gun space's origin `bagTop` over the ground under it (the MG 08's mount bag top; the
	-- M2's tripod stands lower, on its two bags), the mount bags' middle `mountBack` (the M2's pair: 0.65 behind the
	-- pivot; the MG 08's round bag was 1.86).
	Nest = {
		hp = { max = 100, place = 0, swing = 5, destroy = 10 },
		flat = 0.14,
		quarters = 4,
		build = {
			{ bags = "bottom", gun = 1 }, -- (the mount on its bag)
			{ bags = "all", gun = 2 }, -- (the gun on it)
			{ bags = "all", gun = 3 }, -- (the ammo can)
			{ bags = "all", gun = 4 }, -- (its belt: the real gun)
		},
		wear = { 1, 0.7, 0.45, 0.2 },
		-- (user 2026-11-01: "it should have nearly a 180 view angle (maybe 140) ... make sure players dont clip with the
		-- sandbag"; was 9 sides, the gun 1.66 behind the point, +-20 in the notch): 11 sides, the back three open as a
		-- wide doorway, the gun near the middle; the two front piles (`low`) one bag high so the barrel and its bullets
		-- clear the front across the whole traverse (Config/Artillery mg08 `traverse`; Rules.nestFit, `fit` below)
		ring = {
			sides = 11,
			bag = 3.6,
			piles = { { 0, 1, 2 }, { 0, 10, 9 }, { 2, 3, 4 }, { 9, 8, 7 } },
			low = { 1, 2 },
		},
		gunBack = 5.5,
		mountBack = 6.15,
		-- what must clear the bags at every lay (Rules.nestFit, tests/build.spec): the gunner's legs (`legs`, across and
		-- deep) against the bottom bags, the torso and arms out to the grips (`body`) against the top bags, the gun
		-- (`gun`: from `back` behind the pivot, `length` long, `width` across) and its bullets against the top bags; each
		-- bag `bag` long and deep (tools/blender/sandbags/pile.py), the gunner `crew` behind the pivot (Guns mg08 `crew`)
		fit = {
			legs = { 2, 1 },
			body = { 4, 1.2 },
			gun = { back = 1.4, length = 5.6, width = 0.6 },
			bag = { 3.6, 1.6 },
			margin = 0.2,
		},
		bagTop = 1.9,
		-- craters never carve its footprint or this many studs round it (Build.onNest; user 2026-10-29: "give the
		-- turret some ground. the ground beneath it shouldnt be be to be destroyed"), as a Hesco barrier's (Hesco.ground);
		-- a blast's earth heaps on it at most `heap` studs over how it lay (user 2026-10-29: "dont allow the turret to be
		-- fully submerged in terrain. only a little for visual"), read `snapshot` studs under and over its middle as it
		-- is laid and put back once it is fixed whole ("once its fixed its cleared")
		ground = 2,
		heap = 0.6,
		snapshot = { 8, 12 },
	},

	-- The sandbag ring round a dug-in gun (Pieces `ring`, keyed by it; src/server/Build; user 2026-11-02: "keep the
	-- howizer semi dugged, but have sandbags around it that behave similarily to how the mg nest sandbags behave"): the
	-- MG nest's bags (`asset`, its `bags`) on a bigger ring round the gun's pivot (Rules.nestRing: `ring.sides`-sided,
	-- `ring.bag`-stud sides, `ring.piles` each an end, its bend and its other end, 0 the front point), the back side left
	-- open as a doorway over the pit's ramp. Not a structure of its own: it goes up and comes down with the gun. Being
	-- built: by the gun's HP, a stage as a Hesco barrier's (Rules.hescoStage over `build`): first every bag lying as its
	-- empty sack (`flat` of its height), then "bottom" the piles' bottom bags filled, then "all". Once the gun has stood:
	-- by its Wreck stage, the share of the ring's bags still standing (`wear[i]`, the top bags first, Rules.nestWearOrder).
	-- Blasts never carve the ground under it (`ground` studs round its bags; Build.onNest).
	GunRing = {
		artillery_howitzer = {
			asset = "sandbag_pile",
			bags = { "Bag1", "Bag2", "Bag3" },
			flat = 0.14,
			build = { "none", "bottom", "all", "all" },
			wear = { 1, 0.7, 0.45, 0.2 },
			-- 22 sides of 3.6 (~12.65 out, ~27 across over the bags), the two at the back open (~7.1 wide), behind the pit's ramp
			ring = {
				sides = 22,
				bag = 3.6,
				piles = {
					{ 0, 1, 2 },
					{ 0, 21, 20 },
					{ 2, 3, 4 },
					{ 20, 19, 18 },
					{ 4, 5, 6 },
					{ 18, 17, 16 },
					{ 6, 7, 8 },
					{ 16, 15, 14 },
					{ 8, 9, 10 },
					{ 14, 13, 12 },
				},
			},
			ground = 2,
		},
	},

	-- Hesco barriers (src/server/Build, Rules.hescoStage): only the dirt blocks (user 2026-10-27: "only the dirt in the
	-- barriers block stuff. meaning stage 1 and 2 barriers will provide little to no protection"): the wire, liner and
	-- flaps stop nothing, bullets and soldiers pass. On HP like every structure (user 2026-10-27: "all strucuttres use
	-- HP rule, not how many digs", "stage 1 should always be when its placed ... like a cannon, where if its placed,
	-- something will always be down"; round 5: "hesco barriers should still start at 0 HP. make another flat model for
	-- when it has just been placed"): laid at `hp.place`, its stage 0 down at once (the scraped ground and the unit
	-- lying folded flat), a Build swing of its team adds `hp.swing` up to `hp.max` (repairs too), a Destroy swing takes
	-- `hp.destroy`, weapons take `soak` of what they take from a sandbag pile (Structures above); its stage stands by HP
	-- (the dirt slumps as it wears); a Destroy swing or a hit at 0 and it is gone, no rubble (user: "remove the crumble.
	-- 0 hp should just disappear"). (0: laid flat; up to 25, 50, 75, 100: stages 1-4; 16 Build swings from laid to full,
	-- an engineer's 11 (Power above),
	-- 10 Destroy swings from full to gone.) Craters never carve the ground under it or within `ground` studs round it:
	-- the barrier takes the blast instead (user round 5: "make sure that the ground below the barrier and the surround
	-- (the hitbox) does not break. it willbe obsorbed by the barrier").
	Hesco = {
		hp = { max = 100, place = 0, swing = 12.5, destroy = 10 },
		soak = 0.5,
		blocks = { "Earth" },
		ground = 2,
	},

	-- Trench bridges (user 2026-10-27, from the design drafts): loose planks over one
	-- trench square, resting on its two dirt heaps, as wide as the square, no ramps; Config/Assets bridge_pieces, `variants`
	-- board layouts rolled per bridge and turned round at random, each in two sets (Rules.bridgeStage): the frame and
	-- stage 1's boards, crossable, then the boards stage 2 adds, shown over half its HP. On HP like every structure (user
	-- 2026-10-27: "remember the all structures use HP rule, not how many digs"): laid at `hp.place` (stage 1 down at
	-- once), a Build swing of its team adds `hp.swing` up to `hp.max` (repairs too), a Destroy swing takes `hp.destroy`,
	-- weapons take Structures `bridge` above; at 0 it is simply gone, nothing falls (user: "remove the crumble. 0 hp should
	-- just disappear").
	-- Laid only on a square dug to at least `dug`% of its HP, with a trench square joined straight on at both ends (bent
	-- up to `maxBend` degrees) and none teed into its sides, `spacing` studs (centre to centre) from any other bridge (one
	-- free square between). It falls in once the square under it is buried under `fall`% of its HP (Rules.bridgeFalls; the
	-- old Trench.hp.bare's 75, from before trenches filled by HP all the way down). An unseen `plate` (its
	-- thickness) along the deck's top is what you walk on: the boards don't collide (nobody snags on a gap or a tipped
	-- board) and bullets pass them. The build mode ghost: a slab `ghost` thick along the deck.
	-- (0, 60, 100: stage 1 when laid, stage 2 after a swing, whole after two, as before laying started at 0 HP, user
	-- round 5: "should still start at 0 HP"; since build power was halved, Power above: stage 2 after two swings, whole
	-- after four, an engineer's three)
	Bridge = {
		hp = { max = 100, place = 0, swing = 60, destroy = 25 },
		variants = 6,
		dug = 95,
		fall = 75,
		maxBend = 20,
		spacing = 12,
		plate = 0.3,
		ghost = 0.4,
	},

	-- Foxholes (Pieces kind "Foxhole"; user 2026-11-02, design approved by the user; then "make foxhole dugouts not have
	-- HP or progression. it solely alters the map ... it will be treated just the same as terrain"): laid as a marked
	-- spot (a scraped `patch` lying on the ground, blocking nothing; gone after BlueprintLife untouched, or at a Destroy
	-- swing), one Build swing (Pieces `work`) carves it and the piece is gone: from then on it is only ground, worn by
	-- what wears the terrain. Carved round the grid corner its centre is snapped to (Rules.foxholeSnap), each 4-stud
	-- `voxel` column of its ground set to a height from the ground as it lay (src/server/Ground.shapeColumns): within
	-- `radius` of the centre (the four columns round the corner) a floor `depth` down, the wall at `wall` degrees (near
	-- upright: the terrain rounds it into a bowl about 6 across), and past the wall's top an earth heap `heap.height`
	-- high over the next `heap.width` studs, only toward its front (`heap.arc` degrees round the way it faces, fading
	-- at the arc's ends). (One column cut alone rendered 2 to 3.4 deep by how the ground lay in its voxel; four render
	-- the depth asked for, within 0.1: Studio 2026-11-02.)
	-- Its depth is a crouched soldier's (Config/Metrics: the head about 4.1): crouched, the head is at the ground's
	-- level; standing, the eyes (4.5) and the aimed muzzle (4.3) come just over it. The heap is added to part-full
	-- voxels, which the terrain renders lower than asked: 2.4 makes a lip about 1.2 over the ground in front. Crouched
	-- head and standing muzzle are only 0.2 apart, so the lip that hides one blocks the other; the user chose the middle
	-- (2026-11-02, "Balanced": from 18 enemy spots ahead, 15-40 studs off, a crouched head in sight of 7, a standing rifle
	-- clear to 6; a 1.6 heap: 13 and 13, a 3.2 heap: 2 and 2). `lip`: the lip as it renders (the build mode ghost's heap).
	-- Its ground, pit, walls and heap and all within its reach, is `soil`, a dark dirt of its own (user 2026-11-02: "give
	-- it a darker dirt to make obvious"; Config/Palette.Terrain, a material the map uses nowhere else): its `bare`
	-- materials turn to it, so no grass grows in it.
	Foxhole = {
		voxel = 4,
		radius = 3,
		depth = 4.2,
		wall = 89,
		heap = { height = 2.4, width = 4.5, arc = 140 },
		lip = 1.2,
		soil = "Salt",
		bare = { "Grass", "LeafyGrass", "Ground", "Mud", "Sand" },
		patch = { size = 6, thick = 0.1 },
	},

	-- Dugouts (Pieces kind "Dugout"; src/server/Build, Rules dugoutSpot). User 2026-11-02: "just a hole dug into a trench
	-- wall that goes lower into an empty dugout ... planks on the walls that acts as reinforcements"; from outside the
	-- trench it "shouldnt look much different". Config/Assets `asset` (tools/blender/dugout/dugout.py): timber steps cut
	-- down through the wall, `drop` studs over `stair`, `slot` wide, into a room (Pieces: `width` along the trench x
	-- `height` x `depth` back) under the ground; the ground over the room stays (4-stud voxels: its ceiling must lie a
	-- stud under the trench floor for whole voxels of earth to stay over it, Studio check 2026-11-02).
	-- The ground (src/server/Trenches.pocket): the slot cut down to the room's floor `slotCut` studs either side of it, the
	-- room hollowed `cut` studs past its walls and floor and `cutTop` past its ceiling (the meshes' dirt and planks hide
	-- the voxels); the trench's walls and heaps open over the slot from `openFront` in front of it. Craters keep `ground`
	-- studs off it.
	-- Laid in the wall of the square the cursor is on (within `reach` of the square's line past its wall tops), on a
	-- square dug to at least `dug`% and at least the dugout's width plus `spare` long, not in a wall another trench joins
	-- (an end within `teeGap` of its floor's edge), not on a square with a bridge (its middle within `bridgeGap`),
	-- `spacing` studs (middle to middle) from any other dugout (`same`: that one). It keeps its own HP: a square filled in
	-- leaves it standing, its steps opening on the fill.
	-- On HP like every structure: laid at `hp.place` (its timbers lying on the trench floor), a Build swing of its team
	-- adds `hp.swing` (repairs too), a Destroy swing takes `hp.destroy`, weapons take `soak` of what they take from a
	-- sandbag pile (Structures above, by how far they are from its slot and room; user: deep in the ground, "heavily
	-- reduced": a direct rune-mortar shell ~9%). While it is built, its stage by HP (Rules.hescoStage, the meshes of
	-- `build`[1..stage]; 0: `laid`); once it has stood, all of them, and as it wears it caves in (user: "as the HP goes
	-- down, it should cave it, forcing players to leave"): under each `cave`% of its HP the next of `falls` shows and its
	-- heap stands in the room (`heaps`: from, to back along the room as shares of its depth, how high as a share of its
	-- height). Soldiers inside a dugout that has stood are safe from every blast outside it (src/server/Damage.blast,
	-- Build.sheltered; user: "anything above them should not hurt them"); a blast in the room hurts as normal. At 0 it
	-- falls in, the ground filled back, and anyone inside is put `eject` studs over the trench floor in front of its
	-- steps, or over the ground above if the trench is gone (user: "kick the player into the attached trench or on the
	-- ground above if the trench fell too"). `walk`: the thickness of the unseen plates you walk and bump on (the meshes
	-- don't collide).
	Dugout = {
		hp = { max = 100, place = 0, swing = 10, destroy = 10 },
		asset = "dugout_pieces",
		laid = { "Pile", "PileDark" },
		build = {
			{ "SlotEarth", "Steps", "Risers" },
			{ "RoomEarth" },
			{ "Frames" },
			{ "Lining", "Ceiling", "Floorboards" },
		},
		-- the meshes' tones by name: the soil's (Trenches.soilColor) for these, the dark timber for these, else the plank
		soil = { "SlotEarth", "RoomEarth" },
		dark = { "PileDark", "Steps", "Frames", "Floorboards" },
		soak = 0.1,
		drop = 7,
		stair = 7.5,
		slot = 3.6,
		walk = 0.4,
		cut = 4,
		cutTop = 1,
		slotCut = 2,
		ground = 2,
		eject = 3,
		ejectRay = { 40, 80 }, -- (the ground over its room found from this high over its floor, this far down)
		dug = 95,
		spare = 1,
		-- (a square's measured length comes up this much short of whole: an 8-stud square on the flat reads 7.99993)
		lengthSlack = 0.01,
		spacing = 10,
		reach = 6,
		teeGap = 1,
		bridgeGap = 1,
		same = 1,
		openFront = 0.5,
		-- its doorway (dugout_pieces v3; user 2026-11-02: "redesign the dugout door to be build over a wall", "the dug
		-- out should be lined with the wall not sticking out"): cut in the wall's face under a lintel this high over the
		-- trench floor, the wall's heap whole over it, a roofed tunnel down (Rules.dugoutRoof); worn under `fillFrom`% HP
		-- (where it used to start caving in) it fills with earth from its room's floor up to the lintel by 0 HP
		-- (Rules.dugoutShown, Rules.dugoutFillHeight), anyone it reaches lifted onto it with
		-- `lift` over it (their root over their feet) while there is `headroom` between the earth and the roof, else put
		-- out; it fills again by a whole `fillStep` share at a time
		lintel = 3.4,
		fillFrom = 75,
		lift = 3,
		headroom = 5.2,
		fillStep = 0.1,
	},

	-- Barbed wire (user 2026-10-27): its meshes are
	-- Config/Assets barbed_wire in three looks (Rules/Build.wireLook): laid, the pickets and the coil lie bundled on the
	-- ground (Bundle*, from 0 work, user: "like the artilleries"), full work stands it (Pickets, Strands, Coil). Anyone inside its box (both teams) is "Wired":
	-- walks at `speed`, can't sprint or jump (src/client/Stance); only the enemy loses `damage` health a second while
	-- moving faster than `moving` studs/s (user: "slow, but only hurt enemies"). Each tick anyone (teammates too) moves
	-- through it that fast it shakes and rattles (user 2026-10-27: "the damage tick animation should still go off on
	-- teammates and the sound cue goes off"; src/client/WireShake: `shake` seconds, the wire `wobble` studs, the pickets
	-- `picket` of that, at `rate` Hz; one of `sounds` at random from where they push through: Pro Sound Effects "Chain
	-- Link Fence 3", its first and second rattles). It also shakes and rattles each time it takes damage, a Destroy swing
	-- or a blast (user 2026-10-27: "both"; src/server/Build).
	-- Bullets pass (its parts aren't queried). On HP like every structure (user 2026-10-27: "all structures follow an HP
	-- strucutre, not how many digs"; round 5: start at 0 HP with stage 1 down): laid at `hp.place`, bundled on the
	-- ground; a Build swing of its team adds `hp.swing` up to `hp.max` (repairs too), a Destroy swing takes `hp.destroy`,
	-- blasts Structures `wire`% of `hp.max`. Its look is its HP alone (user round 7: "barbwire should jsut hp"): under
	-- `stand` of its HP it lies bundled on the ground and does nothing, from there up it stands and works; a Destroy
	-- swing or a hit at 0 and it is gone, nothing left (user: "remove the crumble. 0 hp should just disappear"). (4 Build
	-- swings stand it, 8 make it whole, an engineer's 3 and 6 (Power above); a Destroy swing at a whole one knocks it
	-- down, the next takes it away.) The grass
	-- goes from under it (Net GroundDug, `grass` studs round its centre) as it is laid.
	Wire = {
		hp = { max = 100, place = 0, swing = 25, destroy = 60 },
		stand = 0.5,
		speed = 3,
		damage = 4,
		moving = 1,
		tick = 0.25,
		grass = 4.6,
		shake = 0.35,
		wobble = 0.12,
		picket = 0.3,
		rate = 14,
		sounds = {
			{ id = 9113758601, volume = 0.6, start = 0.08, stop = 0.6, fade = 0.25, profile = "Rattle" },
			{ id = 9113758601, volume = 0.6, start = 1.15, stop = 1.7, fade = 0.25, profile = "Rattle" },
		},
	},
}

return table.freeze(Build)
