--!strict
-- The spell effects library (Config/Vfx; user 2026-10-13: bright, highly animated, reusable, and no lag). Each effect
-- plays on this client only, from engine pieces (no uploaded images), borrowing its pieces from Pool and moved by
-- the one Driver loop. Spells combine them (Zoltraak).
--   Circle.open(cf, diameter?, color?) -> { close } / Circle.play(cf, hold?)   the magic circle
--   Charge.start(pos, t?) -> { release } / Charge.play(pos, t?)                 gathering charge
--   Ray.play(from, to, { scheme?, hold?, normal?, hitColor?, impact? })          the beam (+ its impact)
--   Burst.play(pos, { scheme?, normal?, debrisColor? })                         impact burst
--   Blast.play(pos, { scheme?, normal?, debrisColor?, stage? })                 the staff beam's explosion
--   Muzzle.play(origin, direction, scale?)                                      a gun's muzzle blast
--   Shockwave.play(center, normal), Star.play(pos), Spikes.play(pos)            rings and flashes
--   Lightning.bolt(from, to, t?), Aura.play(partOrPoint, t)                     lightning
--   Zoltraak.play(tipCFrame, ignore?, scheme?)                                   the full spell
--   Pointer.new() -> { set(from, to), hide, free }                               the aiming laser
--   Orbits.new(count, diameter) -> { move(cf), veil(v), stop(linger?) }          curves orbiting a circle
--   Util.cast(from, dir, range, ignore?) -> (point, normal, color?)              where a spell lands
-- Building blocks: Arc (a lightning zigzag), Ring (a ring of curved beams), Pool, Driver.
-- Colors are Config/Palette.Magic names; schemes are Config/Vfx.Schemes.

return {
	Util = require(script.Util),
	Pool = require(script.Pool),
	Driver = require(script.Driver),
	Arc = require(script.Arc),
	Ring = require(script.Ring),
	Circle = require(script.Circle),
	Charge = require(script.Charge),
	Ray = require(script.Ray),
	Burst = require(script.Burst),
	Blast = require(script.Blast),
	Muzzle = require(script.Muzzle),
	Shockwave = require(script.Shockwave),
	Star = require(script.Star),
	Spikes = require(script.Spikes),
	Lightning = require(script.Lightning),
	Aura = require(script.Aura),
	Zoltraak = require(script.Zoltraak),
	Pointer = require(script.Pointer),
	Orbits = require(script.Orbits),
}
