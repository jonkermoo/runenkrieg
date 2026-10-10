--!strict
-- The asset library registry. One entry per uploaded asset, grouped by category. Each category
-- mirrors three places:
--   repo:    assets/<category>/...                      (sources + generator scripts)
--   Studio:  ReplicatedStorage.Assets.<Category>.<Sub>   (synced by src/dev/Library from this table)
--   gallery: Workspace.DevGallery                       (dev-only showroom, src/dev/Library)
-- Conventions: assets/README.md. Uploads: tools/opencloud/upload_asset.py (creator 180563380).

export type Entry = {
	id: number, -- Open Cloud asset id (a Model containing the meshes)
	category: string, -- top-level library folder
	folder: string, -- subfolder inside the category
	source: string, -- repo path of the uploaded file
	generator: string?, -- script that regenerates the source
	description: string,
	variants: { [string]: { string } }?, -- named mesh groups inside the kit
}

local Assets = {
	Categories = { "Foliage", "Buildings", "Props", "Vehicles", "Weapons", "Characters", "VFX" },

	Entries = {
		TreeKit = {
			id = 78828564935129,
			category = "Foliage",
			folder = "Trees",
			source = "assets/foliage/trees/tree_kit.fbx",
			generator = "tools/blender/trees.py",
			description = "Low-poly trees: 3 pines, 3 broadleaf, 2 birch. Meshes <Variant>_Trunk/_Canopy.",
			variants = {
				Pine = { "PineA", "PineB", "PineC" },
				Broadleaf = { "BroadleafA", "BroadleafB", "BroadleafC" },
				Birch = { "BirchA", "BirchB" },
			},
		},
		GrassKit = {
			id = 84469552965997,
			category = "Foliage",
			folder = "Grass",
			source = "assets/foliage/grass/grass_kit.fbx",
			generator = "tools/blender/grass.py",
			description = "Low-poly grass tufts GrassA..D for the client grass system (Config/Foliage).",
			variants = { Tuft = { "GrassA", "GrassB", "GrassC", "GrassD" } },
		},
	} :: { [string]: Entry },

	-- Tree placement: height in studs (trunk base to canopy top) at scale 1.
	TreeTargetHeight = { Pine = 40, Broadleaf = 30, Birch = 27 },
}

return table.freeze(Assets)
