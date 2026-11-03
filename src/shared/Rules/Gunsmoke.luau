--!strict
-- The machine gun's burst haze (Config/Vfx.Gunsmoke.Haze, src/client/Vfx/Gunsmoke): a gun's heat, one a shot and
-- falling `decay` a second, and the haze's puffs a second from it.

local Gunsmoke = {}

-- the heat after `dt` s cooling and `shots` more shots, at most `cap`
function Gunsmoke.heat(heat: number, dt: number, shots: number, decay: number, cap: number): number
	return math.clamp(heat - dt * decay + shots, 0, cap)
end

-- the haze's puffs a second at `heat`: none below `start`, growing to `rate` at `full`
function Gunsmoke.haze(heat: number, start: number, full: number, rate: number): number
	if full <= start then
		return if heat >= full then rate else 0
	end
	return rate * math.clamp((heat - start) / (full - start), 0, 1)
end

return Gunsmoke
