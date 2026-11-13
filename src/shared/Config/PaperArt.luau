--!strict
-- The front strip's and the sketch map's drawn pieces (src/client/PaperArt places them; src/client/ModeHud,
-- src/client/SketchMap; user 2026-11-12: art "we design ourselves", drawn outside Roblox and imported; the strip a map
-- ribbon with wax seals and the map in a leather case, "Both B"). One sheet; each `rect` x, y, width, height on it,
-- `slice` a nine-slice's middle (px on the sprite): `ribbon` the strip's paper, `wax` a seal and `disc` the capture
-- shown over its face (both white: tinted), `loop` a pencil ring (white: tinted), `dash` the inked track, `stroke` a
-- brush stroke (white: tinted), `arrow` the map's "you", `dot` a map marker (white: tinted), `case` the leather map case.
-- To redraw them: tools/gunart (local tooling, build_strip.py).
local PaperArt: { image: number, sprites: { [string]: { rect: { number }, slice: { number }? } } } = {
	image = 114850861081478,
	sprites = {
		ribbon = { rect = { 0, 0, 512, 128 }, slice = { 96, 36, 416, 92 } },
		wax = { rect = { 516, 0, 128, 128 } },
		disc = { rect = { 648, 0, 128, 128 } },
		loop = { rect = { 780, 0, 192, 192 } },
		dash = { rect = { 0, 196, 256, 16 } },
		stroke = { rect = { 260, 196, 256, 24 } },
		arrow = { rect = { 520, 196, 96, 96 } },
		dot = { rect = { 620, 196, 64, 64 } },
		case = { rect = { 688, 196, 192, 192 }, slice = { 52, 52, 140, 140 } },
	},
}

return table.freeze(PaperArt)
