--!strict
-- Thrown grenades (docs/MILESTONES.md G1; user 2026-10-18). One per team, each a Config/Weapons entry of class
-- "Grenade" in the "Grenade" slot; Rules/Grenade works the numbers, src/server/Grenades throws and sets them off,
-- src/client/Grenades shows the arc and sends the throw. Data only.
-- - Pull the pin and throw: the fuse starts as it leaves the hand, the same for all three, no cooking (user).
-- - Hold the throw button to see a faint line to where it lands (user: "Arc preview line"); release throws.
-- - It can't be picked up or thrown back (user).
-- - The blast is the real charge through Damage.blast (TNT equivalent), plus its fragments (user: "Real + fragments").
--   It only strips leaves and shakes trees, never fells them (user 2026-10-18).

local Grenades = {
	Fuse = 3, -- seconds from leaving the hand (user: "3s, no throwing back")
	Carried = 2, -- per life, refilled at respawn (user: "2 per life, own slot")
	Cooldown = 1, -- seconds before the next one can be thrown (the next grenade into the hand)
	Own = 1, -- the share of its blast and fragments that hurts the thrower (user 2026-10-19: "Yes, grenades only")

	-- The throw: along the camera's look, lifted `loft` degrees (so a level look still lobs it), at the grenade's own
	-- `speed` (studs/s, below). From the head, `from` studs out in the camera's space (+X right, +Y up, -Z forward): the
	-- throwing hand over the right shoulder. No drag (Roblox has none); gravity is workspace.Gravity.
	Throw = {
		loft = 10,
		from = { 0.8, 0.6, -0.8 },
		-- the server takes the throw only from near the soldier's head (studs) and looking where it can (a unit vector)
		reach = 4,
		-- a wall between the head and the hand: the throw starts this far short of it (never through it)
		gap = 0.3,
		spin = 8, -- tumbling in flight, radians/s
		-- seconds into the throw animation the grenade leaves the hand (Config/Weapons grenade holds `throw`;
		-- tools/animation/grenade.luau RELEASE): the throw is sent to the server then
		release = 0.22,
		length = 0.6, -- the throw animation's length (seconds): the view stays first person through it ("Throwing")
	},
	-- The pin (user 2026-10-19: "make the character pull a pin before letting go of the grenade"): left click plays the
	-- pin pull (Config/Weapons grenade holds `pin`, `time` seconds: the left hand pulls it at `out`, the right draws back
	-- into the wind-up); let go before it's done and the throw goes the moment it is. Switching weapons before the
	-- grenade leaves the hand cancels it all (user: "switching to your gun will cancel the throw sequence").
	Pin = { time = 0.45, out = 0.15 }, -- (out: as the left hand starts pulling; at 0.25 it was already 1.8 studs off, Studio)

	-- The thrown grenade (user: "bounces and rolls a little"; 2026-10-20: the old 0.6-stud ball "seems to float and roll
	-- on the ground, not abiding matter and physics"): its body is the grenade's own bounding box (src/server/Grenades),
	-- cast iron on dirt: heavy, gripping, a dull bounce. It tumbles end over end in flight (Throw.spin), and on the
	-- ground it tumbles and slides to a stop by its own friction.
	Body = {
		density = 2,
		friction = 0.8,
		elasticity = 0.2,
		-- Where it first hits anything (the ground or a wall: its velocity jumps by more than `impact` studs/s in a frame)
		-- it thuds, keeping `land` of its speed (Studio round 2: off a wall it flew 14 studs back). Swept each frame from
		-- where it was, so it can't pass through thin ground.
		impact = 20,
		land = 0.25,
		-- the blast goes off this far above where the body lies (out of the ground it rests on)
		lift = 0.3,
		-- the Mills's lever flying off: the throw's velocity times `carry`, plus `pop` studs/s up, tumbling `spin`
		-- radians/s; gone after `life` seconds
		lever = { carry = 0.5, pop = 15, spin = 20, life = 1.5 },
	},

	-- The arc preview (src/client/Grenades): one line (user 2026-10-18: "make the preset line a singular line and not
	-- dots") along the throw's path from where it is `near` studs from the eye (the hand is over the right shoulder, so
	-- it comes in from the top right of the view) to the first thing it would hit, or `time` seconds. Found by stepping
	-- `spacing` studs at a time; drawn `width` studs wide in `segments` pieces, see-through (Palette.Grenades.Arc).
	Arc = {
		spacing = 2.5,
		near = 2,
		time = 4,
		width = 0.12,
		segments = 40,
		transparency = 0.25,
	},

	-- Per grenade (Config/Weapons name):
	-- speed: studs/s at the throw. At 45 degrees it lands v^2 / g away: 128 -> ~84 studs (about 30 m, a Mills bomb
	-- thrown well; 0.357 m per stud), the stick's handle throws further (35 m).
	-- kg: the filling as TNT (Damage.blast, Config/Damage.Blast): Mills ~71 g, SIPE ~100 g, the M1917 stick ~170 g.
	-- fragments: the casing's splinters on soldiers the blast can see (the same cover lines, Config/Damage.Blast.Cover):
	-- `max` damage within `lethal` studs, then `near` falling to `far` at `wound`, none beyond (user: "lethal within
	-- about 8 studs, wounding to about 28"). The cast-iron Mills and SIPE throw fragments; the stick's thin can is mostly
	-- blast, so its fragments reach less.
	Types = {
		grenade_mills = {
			speed = 128,
			kg = 0.071,
			fragments = { lethal = 8, wound = 28, max = 100, near = 60, far = 10 },
			pitch = 1.1, -- its bang's pitch (Sound below)
		},
		grenade_sipe = {
			speed = 128,
			kg = 0.1,
			fragments = { lethal = 7, wound = 25, max = 100, near = 60, far = 10 },
			pitch = 1, -- its bang's pitch (Sound below)
		},
		grenade_stick = {
			speed = 139,
			kg = 0.17,
			-- (lethal 4 -> 5, user 2026-10-23: a stick 3-4 studs off on the ground left ~50; the torso is ~2.7 up)
			fragments = { lethal = 5, wound = 14, max = 100, near = 50, far = 10 },
			pitch = 0.9, -- its bang's pitch (Sound below)
		},
	},

	-- The explosion (src/client/Vfx/Blast, shared with the staff and later cannons): a plain one sized by the charge, in
	-- the fire scheme (Config/Vfx.Schemes).
	Vfx = { scheme = "Ember" },
	-- Its bang (src/client/SoundFx entries, played to their own ends; user 2026-10-19: "make they're sound way more
	-- realistic (explosion wise). make sure there is no audio cutting"): two takes of a dirt explosion layered, Pro Sound
	-- Effects (licensed through Roblox, found with the toolbox search filtered to their account, ASSETS_LICENSES.md), each
	-- grenade pitched by its charge (Types above: the Mills highest, the stick lowest). Dry at every distance (user
	-- 2026-10-23: "grenades have the same echoing issue as cannons ... it's also the same sound, which shouldn't be"; was
	-- the field gun's Explosions 4 and Dirt Explosion 2 under the flanged Explosive Boom 2 tail; the user picked these two).
	Sound = {
		{ id = 9114086424, volume = 1, profile = "Explosion" }, -- Dirt Explosion 2, take a
		{ id = 9114086744, volume = 0.9, profile = "Explosion" }, -- Dirt Explosion 2, take b
	},
	-- How far off it is heard (Rules/Grenade.heard): late at the speed of sound (Config/Audio.Heard.speed), and
	-- duller with distance: highs cut and lows lifted (dB), from nothing at `dullFrom` to all of it at `dullFull` studs.
	Heard = { dullFrom = 60, dullFull = 600, highCut = -14, lowBoost = 4 },
}

return Grenades
