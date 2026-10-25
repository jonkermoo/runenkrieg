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

	-- The thrown grenade (user: "bounces and rolls a little"; 2026-10-25: "i still want it to move a little, just
	-- realistically. small bounce and rolling"): its whole path is worked out on the server at the throw
	-- (src/server/GrenadeFlight, Rules/Grenade.hit / roll / rests) and played back on every client, not left to Roblox's
	-- physics (its box spun wildly off contacts, then, damped, stopped dead, 2026-10-20 / 25).
	Body = {
		-- the blast goes off this far above where the body lies (out of the ground it rests on)
		lift = 0.3,
		-- the Mills's lever flying off: the throw's velocity times `carry`, plus `pop` studs/s up, tumbling `spin`
		-- radians/s; gone after `life` seconds
		lever = { carry = 0.5, pop = 15, spin = 20, life = 1.5 },
	},

	-- Its flight, bounces and roll (src/server/GrenadeFlight; per grenade: Types[name].motion below). In the air it flies
	-- the throw's arc (workspace.Gravity, as the arc preview), tumbling end over end along the throw. Each thing it hits
	-- bounces it off at the type's `bounce` share of its speed into the surface (times `wall` off a surface steeper than
	-- `ground`), keeping `first` of its speed along the surface on the first hit and `keep` on later ones, its tumble
	-- times `spinKeep`. Once a bounce off the ground would be slower than `settle` it lies on its side, its long axis
	-- across the way it goes (turning to it over `blend` seconds), and rolls: slowed by `resist` studs/s per second,
	-- downhill pulled at real gravity (`gravity`: Roblox's 196 is ~7x real and rolled it off every slope), sliding
	-- along its long axis slowed by `slide`. It rests once slower than `stop` on ground no steeper than `grip` (the
	-- slope's sine, ~21 degrees); on steeper ground it rolls on down.
	Motion = {
		step = 1 / 120, -- seconds per step of the server's working-out
		sample = 1 / 30, -- seconds between the frames sent to clients (every hit gets its own frame too)
		ground = 0.6, -- a surface whose normal is at least this far up is ground (~53 degrees); steeper is a wall
		wall = 0.6,
		gravity = 27.5, -- 9.81 m/s^2 at 0.357 m per stud
		blend = 0.12,
		stop = 0.8,
		grip = 0.36,
		skin = 0.02, -- studs kept off a surface it touches
		probe = 0.4, -- studs past its radius it looks under itself for the ground while rolling
	},

	-- The thunk where it hits something (user 2026-10-25: "add a thunk sound for when a grenade hits something"): one of
	-- `sounds` (src/client/SoundFx entries) at random, louder the harder it hits: none below `quiet` studs/s into the
	-- surface (rolling along never thunks), `soft` of the volume just above it, full from `loud`; pitched by the grenade's own
	-- `pitch` (Types below) times a random share within `pitchRange`. Pro Sound Effects (licensed through Roblox,
	-- ASSETS_LICENSES.md): a rock on hard dirt, three takes, each one clean hit.
	Thunk = {
		quiet = 5,
		loud = 80,
		soft = 0.25,
		late = 0.25, -- seconds: a thunk reached later than this (the path arrived late) isn't played
		pitchRange = { 0.92, 1.08 },
		sounds = {
			{ id = 9118616114, volume = 1, profile = "Footstep" }, -- Rock Impact Dirt Hard Muted Thuds 1
			{ id = 9118616398, volume = 1, profile = "Footstep" }, -- Rock Impact Dirt Hard Muted Thuds 2
			{ id = 9118598240, volume = 0.9, profile = "Footstep" }, -- Rock Hit Dirt Impact 12
		},
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
	-- motion: its tumble in the air (`spin`, radians/s) and how it bounces and rolls (Motion above): the stick turns end
	-- over end fast and rolls only a little across its handle; the egg-shaped Mills and the round SIPE spin slowly and
	-- roll further.
	Types = {
		grenade_mills = {
			speed = 128,
			kg = 0.071,
			fragments = { lethal = 8, wound = 28, max = 100, near = 60, far = 10 },
			pitch = 1.1, -- its bang's pitch (Sound below)
			motion = {
				spin = 5,
				first = 0.2,
				keep = 0.7,
				bounce = 0.3,
				settle = 8,
				spinKeep = 0.5,
				resist = 9,
				slide = 30,
			},
		},
		grenade_sipe = {
			speed = 128,
			kg = 0.1,
			fragments = { lethal = 7, wound = 25, max = 100, near = 60, far = 10 },
			pitch = 1, -- its bang's pitch (Sound below)
			motion = {
				spin = 4,
				first = 0.22,
				keep = 0.7,
				bounce = 0.3,
				settle = 8,
				spinKeep = 0.5,
				resist = 7,
				slide = 7,
			},
		},
		grenade_stick = {
			speed = 139,
			kg = 0.17,
			-- (lethal 4 -> 6, user 2026-10-23: a stick 3-4 studs off on the ground left ~50; the torso is ~2.4-3.3 up)
			fragments = { lethal = 6, wound = 14, max = 100, near = 50, far = 10 },
			pitch = 0.9, -- its bang's pitch (Sound below)
			motion = {
				spin = 12,
				first = 0.15,
				keep = 0.6,
				bounce = 0.25,
				settle = 8,
				spinKeep = 0.4,
				resist = 14,
				slide = 40,
			},
		},
	},

	-- The explosion (src/client/Vfx/Blast, shared with the staff and the artillery): sized by the charge, in the fire
	-- scheme (Config/Vfx.Schemes); `pop`: the grenade's own small explosion (Config/Vfx.Blast.Pop; user 2026-10-25: "a
	-- quick explosion, less aggressive and 'fiery' looking", then "the grenade needs more blast and effects")
	Vfx = { scheme = "Ember", pop = true },
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
