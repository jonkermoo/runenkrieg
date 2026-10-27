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
	-- the trench square you're working, extending or branching off is lit faintly (a Highlight in Palette.Build.Focus:
	-- its fill and outline transparency; user 2026-10-25: "a slight slight indicator for which segment you are focused on")
	Focus = { fill = 0.93, outline = 0.6 },
	-- swings faster than this share of the shortest time between two strikes (Rules/Build.strikeGap) are ignored
	SwingSlack = 0.8,
	-- a blueprint nobody has worked on goes after this (seconds)
	BlueprintLife = 120,
	-- live pieces (blueprints count) per player and per team
	PerPlayer = 8,
	PerTeam = 150,
	-- where the pieces live (a Folder in Workspace)
	Folder = "Structures",
	-- blueprint look: its parts this transparent until it stands
	GhostTransparency = 0.75,
	-- the ghost in build mode (src/client/Build): fill colours where it can / can't go
	Ghost = { ok = { 120, 200, 120 }, bad = { 220, 80, 70 }, transparency = 0.55 },
	-- a gun's ghost (src/client/Build; user 2026-10-27: "reduce the red space for a howitzer ... just make it the size
	-- of the actual howizer with the trench. infact, make the outline a rough estimate of what the model would look like
	-- when constructed"): the gun itself, see-through in Ghost ok / bad, standing as it will (a dug-in gun on its pit's
	-- floor), and a dug-in gun's pit and ramp outlined flat on the ground, `outline` studs thick, `outlineSee`
	-- see-through
	GunGhost = { outline = 0.3, outlineSee = 0.7 },
	-- the trench planner's ghost (src/client/Build; user 2026-10-24: "make the entire planning thing better and more
	-- stylish"), a preview of the stakes and cord the
	-- server lays: per square a faint fill (Ghost ok / bad, `fill` see-through) with the dug floor's band in it
	-- (`floor`), a chalk cord round it (`cord` wide, `cordSee` see-through; Palette.Build.Chalk, ChalkBad when it can't
	-- go), `gap` between squares, ghost stakes (`peg`: width, height, one at the cursor before the
	-- first click; no flags, user 2026-10-24: "lets just do the stakes"); squares fade in and out at `fade` per second. Reach circles (Trench.firstReach) dashed on the ground: `dashes`
	-- dashes, each `dash` of its step, `ringWidth` wide; the one you stand in `near` see-through, the other `far`. The
	-- length tag floats `tag` studs over the end.
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
		tag = 4.6,
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
		-- unless you're extending"; 32 since the parapets: two trenches' parapets just meet)
		spacing = 32,
		maxBend = 135,
		maxSlope = 22, -- degrees of ground slope along the run
		planLife = 180, -- seconds an undug plan stays
		-- a swing works the square whose line is this close, in front of you (19: from anywhere on its dirt, out to the
		-- skirt past its heap, joins.heapReach; user 2026-10-25: "can you extend the trench hitbox")
		swingReach = 19,
		-- a square's HP: a Build swing adds `swing` (up to `max`), a Destroy swing takes `destroy` off; blasts take HP by
		-- their overpressure at the square (Blast below). Once dug full it is buried by what it loses: full depth down to
		-- `hold`% HP, then filled in with the rest (80%: a little earth in it; 5-10%: nearly level, unusable), its pieces
		-- under the fill (user 2026-10-24: "an 80% trench should start visibly filling a little bit, but not an unusable
		-- amount"; "way way more durable")
		-- (5 Build swings dig a square: "make building take a bit longer", user 2026-10-24)
		-- (a square buried under `bare`% HP loses its dirt pieces: it just fills with earth, its neighbours add no walls,
		-- user 2026-10-25: "just make it fill, no need to add additional walls"; dug back up past it, they return)
		hp = { max = 100, swing = 20, destroy = 4, hold = 95, bare = 75 },
		-- the shape: floor half width, depth, walls at `wallAngle` (Metrics MaxSlopeAngle decides whether you can walk
		-- up them), earth thrown up as a bank along both edges (the pit's rim) under each wall's parapet (Config/Assets
		-- trench_pieces Wall<i>Parapet: a thick heap of dirt just behind the wall's top edge, about 2.1 to 2.5 over the
		-- ground, a 74 degree face toward the trench: too steep to walk up, chest high cover to shoot over)
		-- (carved in 4-stud voxels the floor rounds into a bowl and the walls soften: Studio round t1023-2101 measured a
		-- 6-wide floor as a narrow bowl and 60 degree walls as 45-55, so the carve is wider at the floor and steeper)
		floor = 4.25, -- (user 2026-10-23: 1.5x wider, then "a little more narrow")
		depth = 5.5,
		-- (user 2026-10-23: "just make it a wall with less slope ... no invisible steps": no wall grip)
		-- (user 2026-10-23: steeper, 70, "it could be either deeper or less slopy"; 2026-10-24: "make this less steep
		-- (just a bit) so our character can walk out of (not smoothly and easily of course)", 48, then "make the slope
		-- more aggressive. have an inbetween from what we had before and now")
		wallAngle = 59,
		bank = { width = 5, height = 1.2 },
		-- a bullet meeting the ground this close round a square's hole, walls and banks hits the square (studs; the
		-- terrain is carved in 4-stud voxels, so a shot at a wall often meets the ground just in front of its slab)
		shotSlack = 2,
		-- a filled-in block leaves a scar: a lumpy dip this deep, churned earth, no grass
		scar = { depth = 0.6 },
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
		pieces = { segment = 8, walls = 8, floors = 4, wood = { 5, 6, 7, 8 }, woodChance = 0.25 },
		-- where pieces meet (src/server/Trenches; user 2026-10-24: "make sure that the joints connect by the walls"): how far
		-- out past a wall's top edge its dirt heap and the skirt behind it reach (they keep that whole depth out of other
		-- trenches; the skirt since 2026-10-25, trench_pieces v8 Wall<i>Apron), and how much further the side heaps run on
		-- round a dead end and its heap reaches past the side walls' tops
		joins = { heapReach = 11, deadEndHeap = 3 },
		-- the skirt behind a heap (Wall<i>Apron, low slabs meant to lie half sunk in the ground) is laid only where the
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
		wireHP = 100,
		-- (bridges, user 2026-10-27, as drafted: bullets pass the planks, two grenades bring it down to its first stage and
		-- four take it away, a shell drops it)
		bullet = { hit = 0.2, wire = 0, bridge = 0 }, -- (about 500 hits bury a trench)
		grenade = { hit = 3, reach = 6, wire = 15, bridge = 25 },
		staff1 = { hit = 2, reach = 4, wire = 0, bridge = 0 },
		staff2 = { hit = 6, reach = 6, wire = 15, bridge = 5 },
		staff3 = { hit = 18, reach = 10, wire = 50, bridge = 25 }, -- (two full beams cut wire)
		field = { hit = 33, reach = 10, edge = 3, wire = 100, bridge = 100 }, -- (three bury a trench)
		howitzer = { hit = 93, reach = 20, edge = 8, wire = 100, bridge = 100 }, -- (buries it at once, 7% left)
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
		-- The sandbag pile (user 2026-10-27: pillow bags, "layer 1 2 bags, layer 2 1 bag", "make it even smaller ... ads
		-- still wont work", "make the sandbags longer"; the old low and high walls removed: "remove the old sand bag piles
		-- completely, keep the present ones"): Config/Assets `asset`'s meshes, one section for the whole pile, built and
		-- worn on HP (Sandbags.hp below), `bags` standing by its share of HP (with their ties, `<bag>Cord`).
		-- `width` x `height` x `depth` its footprint (the bags 3.6 long, ties out past them; the top 3.68: under the
		-- aimed muzzle, over the low cover line, Config/Metrics).
		{
			key = "SandbagPile",
			name = "Sandbag pile",
			kind = "Sandbags",
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
			name = "Hesco barrier",
			kind = "Hesco",
			asset = "hesco", -- (Config/Assets)
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
			name = "Bridge",
			kind = "Bridge",
			work = 2, -- (it is built on HP: Bridge.hp below)
			width = 8,
			depth = 19.2,
			height = 3.1,
		},
		-- (user 2026-10-27: a section 8 long, 4 wide, 3/5 of a soldier high (3.1), stood in 2 swings; laid on its own, no
		-- chaining or planner; the look: Config/Assets barbed_wire, Wire below)
		{
			key = "Wire",
			name = "Barbed wire",
			kind = "Wire",
			work = 2,
			width = 8,
			depth = 4,
			height = 3.1,
			maxSlope = 30,
		},
		-- The guns (user 2026-10-26: "add building the artilleries to shovels"; Config/Artillery.Guns `gun`, src/server/
		-- Artillery stands them): every team builds both, in its own paint (Guns.paint). The blueprint is the gun
		-- see-through; `work` Build swings stand it (user: field 20, howitzer 40), the howitzer's pit (its Config/
		-- Artillery `dig`) dug deeper at each of `stages` (user: "deeper with each stage"). A gun keeps `spacing` studs from
		-- every other gun of its kind, any team's (user: "cannons cant be placed within certain distances of another,
		-- howitzer with howitzer": 60 and 120), and `clear` + the other's `clear` from any gun. `width` x `depth` (`height`
		-- high) is the ground it needs clear and gentle, its centre `back` studs behind the gun (the howitzer's: its pit to
		-- the wall tops and the ramp behind); no trench within `trenchGap` of it (the howitzer's: its earth rim).
		{
			key = "FieldGun",
			name = "Field gun",
			kind = "Gun",
			gun = "artillery_qf18",
			work = 20,
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
		{
			key = "Howitzer",
			name = "Magic howitzer",
			kind = "Gun",
			gun = "artillery_howitzer",
			work = 40,
			stages = 8,
			width = 44,
			depth = 78,
			height = 6,
			back = 17,
			maxSlope = 12,
			spacing = 120,
			clear = 36,
			trenchGap = 14,
		},
	},

	-- Built guns: a gun stands once its work is full and stays (manned, firing) until Destroy swings take its work down to
	-- `standsFrom` of it (user 2026-10-26: Destroy takes a gun apart like any piece); then it is a blueprint again, its
	-- pit filling back as the work falls, gone at 0. `paint`: each kit's gun paint (Config/Palette.Artillery.Paint).
	Guns = {
		standsFrom = 0.75,
		paint = { uniform1 = "Grey", uniform2 = "Olive", uniform3 = "White" },
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
		artillery_howitzer = {
			frame = { x = 0, z = 0.3, width = 16, depth = 18, bays = 2, height = 5.2, levels = { 4.2 } },
			crates = { { x = -10.5, z = -2, yaw = 10, size = { 1.6, 0.9, 1.1 } } },
			planks = { { x = 10.5, z = 5, yaw = 10, count = 3, length = 5 } },
			sawhorses = { { x = -10.5, z = 6, yaw = 0 } },
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
	-- (Pieces `stage1`); each Build swing fills a bag, every `swing` of HP a bag (0, 34, 68, 100: no bag, one, two, all
	-- three; Rules.pileBags).
	Sandbags = { hp = { max = 100, place = 0, swing = 34, destroy = 10 }, shade = 0.06, sink = 0.15 },

	-- Hesco barriers (src/server/Build, Rules.hescoStage): only the dirt blocks (user 2026-10-27: "only the dirt in the
	-- barriers block stuff. meaning stage 1 and 2 barriers will provide little to no protection"): the wire, liner and
	-- flaps stop nothing, bullets and soldiers pass. On HP like every structure (user 2026-10-27: "all strucuttres use
	-- HP rule, not how many digs", "stage 1 should always be when its placed ... like a cannon, where if its placed,
	-- something will always be down"; round 5: "hesco barriers should still start at 0 HP. make another flat model for
	-- when it has just been placed"): laid at `hp.place`, its stage 0 down at once (the scraped ground and the unit
	-- lying folded flat), a Build swing of its team adds `hp.swing` up to `hp.max` (repairs too), a Destroy swing takes
	-- `hp.destroy`, weapons take `soak` of what they take from a sandbag pile (Structures above); its stage stands by HP
	-- (the dirt slumps as it wears); a Destroy swing or a hit at 0 and it is gone, no rubble (user: "remove the crumble.
	-- 0 hp should just disappear"). (0: laid flat; up to 25, 50, 75, 100: stages 1-4; 8 Build swings from laid to full,
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
	-- free square between). It falls in once the square under it is buried under Trench.hp.bare%. An unseen `plate` (its
	-- thickness) along the deck's top is what you walk on: the boards don't collide (nobody snags on a gap or a tipped
	-- board) and bullets pass them. The build mode ghost: a slab `ghost` thick along the deck.
	-- (25, 65, 100: stage 1 when laid, stage 2 after a swing, whole after two)
	Bridge = {
		hp = { max = 100, place = 25, swing = 40, destroy = 25 },
		variants = 6,
		dug = 95,
		maxBend = 20,
		spacing = 12,
		plate = 0.3,
		ghost = 0.4,
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
	-- Bullets pass (its parts aren't queried). Once standing it has Structures.wireHP: blasts wear it (Structures above), a
	-- Destroy swing takes `destroy` HP (user: 2 swings, broken then gone); under `broken` of its HP it lies scattered on
	-- the ground and does nothing (Wreck*, user: "a broken stage (less than 50) will make the fence ineffective and
	-- scatter it on the ground. once it hits 0 it will despawn"); one Build swing of its team stands a broken wire back up
	-- at full HP. The grass goes from under it (Net GroundDug, `grass` studs round its centre) as it is laid. A
	-- Destroy swing on a wire that never stood takes its work down; at 0 it is gone.
	Wire = {
		speed = 3,
		damage = 4,
		moving = 1,
		tick = 0.25,
		destroy = 60, -- (over half: the first swing breaks it, the second takes it away)
		broken = 0.5,
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
