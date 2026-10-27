--!strict
-- The art palette (docs/ART_STYLE.md). Flat colors only: every part is SmoothPlastic and terrain
-- materials are overridden with untextured MaterialVariants, so these RGB values ARE the look.
-- Tuned to references/style (semi-low-poly, soft olive greens, warm tan dirt, dark grey rock).

local Palette = {
	Terrain = {
		Grass = { 108, 142, 74 },
		LeafyGrass = { 94, 128, 66 }, -- under groves
		Ground = { 150, 126, 96 }, -- dirt patches, slopes, yards
		Sand = { 168, 146, 112 }, -- roads
		Mud = { 112, 94, 74 }, -- river bed, blasted and churned ground
		Basalt = { 74, 58, 44 }, -- the root balls of uprooted trees: darker than mud (user 2026-10-17)
		Rock = { 98, 94, 90 },
	},
	Water = { color = { 72, 124, 134 }, transparency = 0.35, reflectance = 0, waveSize = 0.05 },
	Trees = {
		Pine = { { 48, 84, 62 }, { 56, 94, 66 }, { 44, 78, 58 } },
		Broadleaf = { { 88, 132, 64 }, { 100, 142, 70 }, { 80, 122, 58 } },
		Birch = { { 132, 160, 82 }, { 120, 150, 72 } },
		Bark = { 98, 74, 58 },
		BirchBark = { 214, 210, 196 },
	},
	-- Grass tufts: a few shades around the terrain grass so tufts read as part of the ground.
	GrassTufts = { { 112, 148, 74 }, { 100, 136, 68 }, { 124, 156, 80 }, { 94, 128, 64 } },
	-- The thin blade patches (Config/Foliage.Blades): a touch lighter, like the terrain grass they replace.
	GrassBlades = { { 120, 156, 78 }, { 108, 146, 72 }, { 132, 164, 86 }, { 102, 138, 68 } },
	-- Buildings: copies of one template pick a color per role (walls/roof/trim/door) from these, so
	-- repeated shapes read as different houses. Muted, earthy, desaturated (Pordier-like; old English
	-- villages in references/village). Each wall/roof piece is also shaded a few % off by its Tone.
	Buildings = {
		Walls = {
			Whitewash = { 222, 216, 200 },
			Cream = { 212, 198, 168 },
			Ochre = { 196, 170, 124 },
			Stone = { 172, 164, 146 },
			Brick = { 148, 98, 78 },
			RedBrick = { 132, 84, 68 },
			BarnRed = { 126, 72, 58 },
			TarBoard = { 76, 68, 62 },
			WhiteBoard = { 212, 206, 190 },
		},
		Roofs = {
			Thatch = { 158, 128, 84 },
			ThatchDark = { 122, 98, 66 },
			ThatchWeathered = { 136, 124, 100 },
			DarkTile = { 90, 78, 72 },
			Slate = { 84, 86, 92 },
			RedTile = { 138, 86, 68 },
		},
		Trim = { { 82, 66, 54 }, { 104, 86, 68 }, { 70, 60, 54 } }, -- dark weathered wood
		Doors = { { 112, 88, 64 }, { 80, 92, 72 }, { 112, 62, 52 }, { 84, 92, 102 } },
		Floor = { 120, 96, 72 },
		Stairs = { 110, 88, 66 },
		Foundation = { 118, 114, 106 }, -- plinth stones
		Quoin = { 150, 144, 130 }, -- corner stones
		Chimney = { 136, 112, 96 }, -- old stone/brick stack
		Glass = { 138, 160, 166 },
		GlassTransparency = 0.4,
		Metal = { 54, 52, 50 }, -- iron hinges, handles
		Sign = { 210, 196, 162 },
		Wood = { 104, 82, 62 },
		ToneJitter = 0.04, -- +-4% per piece: hand-made, not factory-flat
		Dust = { 200, 192, 176 }, -- a pulverised section's puff (src/client/Debris), half way from its own colour
	},
	-- Village props (Config/Props), same muted, hand-made look as the houses.
	Props = {
		Stone = { 146, 140, 126 },
		StoneDark = { 118, 112, 100 },
		Wood = { 112, 88, 66 },
		WoodDark = { 84, 66, 52 },
		WoodPale = { 206, 198, 180 }, -- painted pickets
		Hedge = { 74, 108, 58 },
		HedgeDark = { 62, 92, 50 },
		Hay = { 182, 156, 96 },
		Metal = { 54, 52, 50 },
		Rubber = { 34, 32, 30 },
		Water = { 92, 124, 128 },
		Glass = { 120, 140, 146 },
		CarBodies = { { 72, 42, 40 }, { 40, 44, 42 }, { 56, 70, 58 }, { 62, 64, 72 } },
		ToneJitter = 0.05,
	},
	-- Bandages and the med pack (Config/Assets "Shared/Bandages", user 2026-10-18), coloured by mesh name; same for
	-- every team.
	Medical = {
		Cloth = { 226, 220, 202 }, -- bandage cloth: the rolls, the unrolling strip, the worn wraps
		Canvas = { 150, 136, 100 }, -- the med pack's canvas
		Thread = { 150, 62, 52 }, -- the red tear thread wrapped round the pack
		Cross = { 72, 140, 72 }, -- the green cross on the pack
	},
	-- Backpacks (Config/Assets "<Team>/Packs", user 2026-10-18/19), coloured by mesh name. Never the team's uniform
	-- colour (user 2026-10-20): tan / sand / khaki canvas bodies, brown leather, dark blanket rolls.
	Packs = {
		pack_tornister = {
			Body = { 150, 124, 88 },
			Flap = { 112, 80, 56 },
			Leather = { 54, 42, 34 },
			Roll = { 96, 92, 80 },
		},
		pack_zaino = { Body = { 170, 150, 108 }, Leather = { 112, 82, 58 }, Roll = { 120, 106, 80 } },
		pack_p08 = {
			Body = { 176, 160, 118 },
			Strap = { 150, 134, 96 },
			Roll = { 110, 104, 92 },
			Tin = { 128, 132, 136 },
		},
	},
	-- Rigs (Config/Uniforms.Rigs, user 2026-10-22: each team's in its own colors), by kit, colored by mesh name. Like
	-- the packs never the uniform's colour: each team's leather as its pack's. Grey: blackened German leather; olive:
	-- the zaino's brown leather; white: pale khaki British web, as the P08, with brass fittings.
	Rigs = {
		uniform1 = { Leather = { 54, 42, 34 }, Pouch = { 88, 66, 48 }, Metal = { 70, 66, 60 } },
		uniform2 = { Leather = { 112, 82, 58 }, Pouch = { 136, 104, 72 }, Metal = { 70, 66, 60 } },
		uniform3 = { Leather = { 150, 134, 96 }, Pouch = { 176, 160, 118 }, Metal = { 150, 126, 70 } },
	},
	-- Species ears and tails (Config/Species; user 2026-10-18): the fur takes the soldier's hair colour; these are the
	-- rest. Inner = the inside of an ear, Tip = the fennec tail's dark tip (user 2026-10-20), Cream = what the cup's fluff
	-- blends toward
	-- (FluffShare of the way from the hair colour) so it melts into the fur.
	Species = {
		Inner = { 226, 178, 160 },
		Tip = { 46, 34, 28 },
		Cream = { 236, 226, 204 },
		FluffShare = 0.45,
		-- until the looks arrive ("HairColor" / "SkinColor" unset), the fur and the elf ears take these
		FallbackHair = { 104, 70, 46 },
		FallbackSkin = { 214, 158, 108 },
	},
	-- Artillery (Config/Assets "Shared/Artillery", user 2026-10-18: one model each, painted per team), colored by mesh
	-- name: the painted parts take the team's Paint, the rest are the same for everyone. The runes and the crystal
	-- glow (Neon, the magic exception in docs/ART_STYLE.md); the crystal's colour will follow the gun's state.
	Artillery = {
		Paint = {
			Grey = { 82, 86, 88 }, -- slate, as the grey tunic
			Olive = { 98, 102, 66 },
			White = { 192, 190, 180 }, -- off-white, as the Brodie helmet
		},
		Painted = { "Carriage", "Wheels", "Mount", "Cradle", "Bed", "TraverseWheel", "ElevationWheel" },
		-- the small pieces (user 2026-10-26: "more micro designs and accents/secondary colors on the artillery ... make it
		-- different per team"): a mesh named <part><Role> (MountTrim, CarriageFittings, ...) takes its team's colour for
		-- that role: Trim bands and edging, Fittings rivets, bolts, caps, data plates and chains, Kit the tool and ammo
		-- boxes, Marking the team's stripe. Grey: black iron and oxblood (as its blackened leather); Olive: brown leather
		-- and ochre; White: khaki web, brass and navy. (User 2026-10-26: "make sure everything blends in well": the
		-- fittings and stripes toned toward the paint; were Grey 120 steel / 138,46,40, Olive 196,160,72, White
		-- 176,146,82 / 54,70,112.)
		Roles = { "Trim", "Fittings", "Kit", "Marking" },
		Team = {
			Grey = {
				Trim = { 36, 38, 40 },
				Fittings = { 100, 103, 107 },
				Kit = { 74, 58, 46 },
				Marking = { 120, 48, 42 },
			},
			Olive = {
				Trim = { 120, 88, 60 },
				Fittings = { 78, 72, 64 },
				Kit = { 136, 104, 72 },
				Marking = { 170, 140, 72 },
			},
			White = {
				Trim = { 150, 134, 96 },
				Fittings = { 160, 136, 86 },
				Kit = { 112, 90, 64 },
				Marking = { 70, 82, 112 },
			},
		},
		Tyres = { 58, 58, 60 },
		Barrel = { 96, 98, 102 },
		Breech = { 70, 72, 76 },
		RingGear = { 64, 64, 66 }, -- the howitzer's toothed ring (dark steel), and the pinions meshing it
		TraversePinion = { 64, 64, 66 },
		ElevationPinion = { 64, 64, 66 },
		Bore = { 8, 8, 8 },
		EarthBox = { 120, 86, 54 },
		Earth = { 112, 90, 62 },
		BedRunes = { 120, 200, 255 }, -- Magic.Glow
		BarrelRunes = { 120, 200, 255 },
		Crystal = { 175, 235, 255 },
		CrystalCracks = { 235, 250, 255 }, -- the cracks over the howitzer's gem (src/client/ArtilleryCrystal)
		Glowing = { "BedRunes", "BarrelRunes", "Crystal", "CrystalCracks" },
		-- a damaged gun is scorched toward this (Config/Artillery.Wreck), its glowing parts dead at `Dead`
		Scorched = { 34, 30, 28 },
		Hole = { 20, 18, 17 }, -- a shell hole's dark inside (Config/Artillery.Wreck)
		Dead = { 30, 36, 46 },
		-- the field gun's round (Config/Assets round_qf18): brass case, copper band, the HE shell's yellow, a steel fuze
		Case = { 204, 170, 96 },
		Band = { 184, 115, 72 },
		Shell = { 200, 168, 52 },
		Fuze = { 96, 98, 102 },
		-- the gunner's arc line and landing marker (src/client/Artillery, Config/Artillery.Arc)
		Arc = { 236, 230, 210 },
		Marker = { 255, 214, 120 },
	},
	-- The trench spade (Config/Assets "Shared/Shovels", user 2026-10-19): one model for every team, no team colors,
	-- brass the only accent; colored by mesh name.
	Shovel = {
		Wood = { 139, 94, 60 }, -- the D-grip and haft
		Iron = { 90, 92, 96 }, -- straps, socket, treads, the tongue on the back
		Blade = { 122, 124, 128 },
		Brass = { 184, 149, 90 }, -- the collar and rivets
	},
	-- Player-built pieces (Config/Build, src/server/Build): flat colours until the meshes come
	Build = {
		Sandbag = { 176, 156, 114 }, -- hessian; each bag's tone jittered by Config/Build.Sandbags.shade
		Plank = { 134, 102, 70 }, -- the plank steps on a trench's wood walls (meshes Wall<i>Planks, Wall<i>PlanksDark)
		PlankDark = { 98, 74, 52 },
		-- a trench's dirt pieces (tools/blender/trench) are the terrain's mud colour times these shades (user 2026-10-24:
		-- "match the color of the mud"): Wall<i> takes wall shade (i - 1) % 3 + 1 and its chunks the chunk shade of the
		-- same number, its parapet that shade too; Floor<i> and its chunks
		TrenchWall = { 1.0, 1.08, 0.93 },
		TrenchWallChunks = { 0.95, 1.03, 0.98 },
		TrenchParapet = { 0.9, 0.97, 0.92 },
		TrenchFloor = 0.92,
		TrenchFloorChunks = 0.98,
		-- a trench plan's markers (user 2026-10-24): the cord
		-- and the stakes with a painted top (`PegTop`)
		String = { 236, 232, 220 },
		PegTop = { 236, 230, 210 },
		-- the planner's chalk cord and reach circles (src/client/Build, Config/Build.Plan; Artillery.Arc's colour, so
		-- planning and gunnery read as one family), and their colour where the plan can't go
		Chalk = { 236, 230, 210 },
		ChalkBad = { 236, 120, 104 },
		-- the faint light on the trench square in focus (Config/Build.Focus): a dug one, and one still staked out
		-- (user 2026-10-25: "can the outline of strings be green instead of white, but keep trench outlines white")
		Focus = { 236, 230, 210 },
		FocusPlan = { 120, 214, 104 },
		IconDim = { 154, 166, 159 }, -- the planner's action icons: the stake's top, the trench piece
		-- the building site round a gun being built (Config/Build.Scaffold, Rules/Scaffold): weathered poles, paler boards,
		-- hemp rope, iron, the tool crate
		Scaffold = {
			Pole = { 112, 88, 64 },
			Board = { 150, 120, 84 },
			Rope = { 176, 152, 106 },
			Iron = { 58, 56, 54 },
			Crate = { 128, 98, 66 },
			CrateDark = { 96, 72, 50 },
		},
		Picket = { 84, 66, 52 },
		Wire = { 58, 56, 54 },
	},
	-- Magic (src/client/Vfx, Config/Vfx): the glowing spell colors. Effects draw them bright (LightEmission, HDR
	-- brightness) so the Bloom in Lighting makes them glow; still flat colors, no textures (docs/ART_STYLE.md).
	Magic = {
		Core = { 235, 250, 255 }, -- the white-hot centre of beams, orbs and flashes
		Glow = { 120, 200, 255 }, -- the light blue body (Zoltraak, the circle's lines)
		Deep = { 70, 90, 230 }, -- the deep blue edge
		Violet = { 150, 90, 255 }, -- the outer haze, sparkles
		Gold = { 255, 200, 80 }, -- light spikes, holy flashes
		Ember = { 255, 60, 50 }, -- red glints and bursts
		Bolt = { 80, 255, 190 }, -- lightning
		Smoke = { 196, 202, 214 }, -- pale grey (the staff explosion's cloud until 2026-10-17, now blue: Config/Vfx.Blast.Colors)
		Ash = { 118, 122, 130 }, -- explosion smoke (Config/Vfx.Blast.Smoke): grey, lit by the scene
		SmokeDark = { 84, 86, 92 }, -- darker explosion smoke (Config/Vfx.Blast.Smoke)
		Soot = { 48, 48, 52 }, -- the darkest explosion smoke
		Abyss = { 22, 26, 80 }, -- deep navy, flat (the explosion cloud's patches until 2026-10-17)
		-- the violet "hex" scheme (user reference 2026-10-13: a hot pink-violet capsule beam)
		HexCore = { 255, 228, 255 },
		Hex = { 240, 90, 255 },
		HexDeep = { 170, 40, 220 },
		HexEdge = { 90, 20, 140 },
		-- more looks for the magic (Config/Vfx.Schemes; user 2026-10-13: "different color magic ... be creative")
		EmberCore = { 255, 242, 220 }, -- fire
		Flame = { 255, 150, 60 },
		EmberDeep = { 225, 60, 25 },
		EmberEdge = { 120, 25, 15 },
		EmberGold = { 255, 205, 90 },
		VerdantCore = { 230, 255, 235 }, -- jade
		Verdant = { 90, 240, 150 },
		VerdantDeep = { 20, 165, 105 },
		VerdantEdge = { 10, 80, 70 },
		VerdantLime = { 200, 255, 90 },
		SolarCore = { 255, 252, 236 }, -- holy gold
		Solar = { 255, 214, 110 },
		SolarDeep = { 235, 160, 45 },
		SolarEdge = { 150, 90, 25 },
		VoidCore = { 245, 230, 255 }, -- dark magic
		Void = { 150, 70, 230 },
		VoidDeep = { 70, 20, 130 },
		VoidEdge = { 25, 5, 45 },
		VoidToxic = { 130, 255, 110 },
		-- the teams' magic (Config/Spells.Staff.Teams; user 2026-10-22: "make magic color different based on teams"): the
		-- grey team keeps the frost blue above (Core / Glow / Deep / Violet); the olive team a brass gold, a lemon gold
		-- kept off the orange of grenade and gun fire (Ember); the white-brown team a rose crimson, as its staff's red
		-- ribbon. Brightest gold, middle blue, darkest crimson: apart for red-green colour-blind eyes too.
		BrassCore = { 255, 250, 225 },
		Brass = { 255, 210, 70 },
		BrassDeep = { 215, 160, 25 },
		BrassEdge = { 140, 105, 20 },
		CrimsonCore = { 255, 235, 240 },
		Crimson = { 255, 70, 100 },
		CrimsonDeep = { 200, 20, 60 },
		CrimsonEdge = { 110, 10, 45 },
	},
	-- UI: flat panels, one outline thickness everywhere.
	UI = {
		panel = { 44, 50, 42 },
		button = { 64, 72, 60 },
		accent = { 120, 150, 80 },
		outline = { 24, 28, 22 },
		text = { 236, 232, 220 },
		stroke = 2,
		-- the build HUD panel (src/client/Build; user 2026-10-24): the panel, its edge (go / no-go / the shovel out, not
		-- planning), the title (red when it can't go), the line beside it, the key caps and their hints
		BuildHud = {
			panel = { 24, 29, 32 },
			ok = { 108, 191, 123 },
			bad = { 226, 96, 79 },
			idle = { 217, 180, 90 },
			title = { 238, 240, 234 },
			titleBad = { 255, 180, 168 },
			sub = { 201, 210, 204 },
			key = { 238, 240, 234 },
			keyText = { 32, 38, 42 },
			hint = { 184, 194, 188 },
		},
		-- the combat HUD, quartermaster's brass (Config/Hud, src/shared/ui/CombatHud.json): the panel's dark field, its
		-- brass rim and rivets, the name plate and its stamped letters, the count, the hint plate (red, the next thing to
		-- do), the stage lamps dark, the rock with no mana, the readouts
		Hud = {
			field = { 24, 28, 22 },
			window = { 14, 16, 13 },
			brass = { 196, 160, 84 },
			brassDark = { 120, 96, 50 },
			plateText = { 34, 28, 18 },
			count = { 222, 186, 104 },
			countLow = { 220, 96, 70 },
			hint = { 68, 30, 24 },
			hintEdge = { 210, 80, 60 },
			hintText = { 255, 214, 196 },
			lampOff = { 30, 34, 30 },
			crystalHollow = { 112, 116, 122 }, -- a crystal with no charge (Config/Hud.Crystal), and dead
			crystalDead = { 58, 60, 64 },
			readout = { 236, 232, 220 },
			ready = { 150, 200, 110 },
			-- the gun's cut-away (Config/Hud.Gun): its bolt and the bolt's darker steel, the magazine well and its edges,
			-- a clip; the gun's body as a flat shadow (lit by `shadowAmbient` only)
			bolt = { 150, 154, 160 },
			steel = { 92, 96, 102 },
			well = { 78, 82, 88 },
			wellEdge = { 110, 114, 120 },
			clip = { 120, 118, 112 },
			shadow = { 16, 18, 22 },
			shadowAmbient = { 255, 255, 255 },
			shadowLight = { 0, 0, 0 },
			-- each team's box (user 2026-10-26: "make it the team coloring"; by the "Kit": Config/Uniforms): its field,
			-- its rim and rivets, as the uniforms (grey: slate; olive: olive drab; white: chocolate and off-white)
			Teams = {
				uniform1 = { field = { 28, 31, 34 }, rim = { 128, 136, 144 }, rivet = { 84, 90, 96 } },
				uniform2 = { field = { 28, 32, 22 }, rim = { 150, 156, 96 }, rivet = { 98, 102, 62 } },
				uniform3 = { field = { 38, 29, 23 }, rim = { 200, 190, 170 }, rivet = { 120, 92, 70 } },
			},
			viewAmbient = { 150, 150, 150 },
			viewLight = { 255, 244, 224 },
		},
		-- the third-person crosshair's ring (src/client/Crosshair, Config/Camera.Crosshair), with a dark edge behind it
		crosshair = { 236, 232, 220 },
		-- the settings menu (src/client/SettingsMenu, src/shared/ui/SettingsMenu.json): gray slate, no hue (user
		-- 2026-10-19); the picked choice is lighter with a silver line. Lines are `thin`, the panel border `stroke`.
		Settings = {
			panel = { 24, 25, 27 },
			field = { 34, 35, 38 },
			line = { 74, 76, 81 },
			lineStrong = { 138, 141, 148 },
			text = { 214, 215, 218 },
			textDim = { 128, 131, 138 },
			title = { 228, 229, 232 },
			selFill = { 58, 60, 64 },
			selLine = { 201, 203, 208 },
			selText = { 255, 255, 255 },
			accent = { 228, 229, 232 },
			backdrop = { 0, 0, 0 },
			backdropTransparency = 0.55,
			stroke = 2,
			thin = 1,
		},
	},
	Atmosphere = { color = { 206, 218, 226 }, decay = { 126, 146, 160 } },
	-- the grenades' arc preview (src/client/Grenades, Config/Grenades.Arc): a faint pale line
	Grenades = { Arc = { 236, 230, 210 } },
}

return table.freeze(Palette)
