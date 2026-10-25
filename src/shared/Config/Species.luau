--!strict
-- Species (user 2026-10-18): animal or elf ears, and a tail where the species has one, on top of the plain soldier.
-- Germanic folk names: Katzling (cat folk), Alb (elves), Fennek (fennec folk); plain humans have none. A species
-- belongs to a nation once nations exist; until then each team's uniform kit has one (`Kits`). Models: Config/Assets
-- `ears_<species>` / `tail_<species>` (tools/blender/gear/species.py), worn by src/server/Species, moved by
-- src/client/SpeciesMotion (procedural, nothing replicates). Colours: Rules/Species.color, Config/Palette.Species.

export type Kind = {
	ears: string, -- Config/Assets entry
	tail: string?, -- Config/Assets entry
	-- each ear's pivot (its root on the head, head-local studs, Roblox axes): the ear swings round it
	earPivots: { [string]: { number } },
	-- how many bones (Tail1..) bend the tail's skinned mesh
	tailBones: number?,
	-- how much of Motion.Ear this species' ears move (the elf blades barely)
	earMotion: number,
}

local Species = {
	-- uniform kit (Config/Uniforms.Kits) -> species; kits not listed are plain humans. Testing: a player's "Species"
	-- attribute (a Kinds name or "human") wins, applied at the next spawn.
	Kits = {
		uniform1 = "katzling", -- grey
		uniform2 = "alb", -- olive
		uniform3 = "fennek", -- white
	} :: { [string]: string },
	Kinds = {
		katzling = {
			ears = "ears_katzling",
			tail = "tail_katzling",
			earPivots = { EarR = { 0.64, 0.74, -0.08 }, EarL = { -0.64, 0.74, -0.08 } },
			tailBones = 5,
			earMotion = 1,
		},
		fennek = {
			ears = "ears_fennek",
			tail = "tail_fennek",
			earPivots = { EarR = { 0.64, 0.7, -0.08 }, EarL = { -0.64, 0.7, -0.08 } },
			tailBones = 5,
			earMotion = 1,
		},
		alb = {
			ears = "ears_alb",
			earPivots = { EarR = { 0.6, -0.12, 0.06 }, EarL = { -0.6, -0.12, 0.06 } },
			earMotion = 0.35,
		},
	} :: { [string]: Kind },
	-- Procedural motion (degrees, seconds, studs/s). Characters farther than `Range` studs from the camera hold still.
	Motion = {
		Range = 120,
		Ear = {
			swayDeg = 2.5, -- idle drift, each ear on its own slow rhythm: the ears' only motion
			swayHz = 0.35,
			swayTilt = 0.6, -- how much of the drift tilts the ear back and forth, and how much swivels it
			swaySwivel = 0.4,
			follow = 10, -- how fast the ears ease toward where they want to be (per second)
		},
		Tail = {
			swayDeg = 7, -- an idle side to side sway, travelling down the tail
			swayHz = 0.45,
			phasePerSegment = 0.6, -- radians later per bone
			liftPerSpeed = 1.2, -- moving forward lifts it, up to `liftMax`
			liftMax = 20,
			lagPerSpeed = 2.5, -- moving sideways swings it the other way, up to `lagMax`
			lagMax = 25,
			deadDroopDeg = 12, -- each bone hangs this much lower once dead, with no sway
			follow = 6,
		},
	},
}

return Species
