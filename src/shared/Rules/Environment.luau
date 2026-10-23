--!strict
-- Time of day and weather (Config/Environment): the clock from the time since the server's day start, how much
-- daylight that clock has, the weather roll, an event's strength over its fades, and the light and haze they make.
-- Pure; the server keeps the clock and rolls the weather (src/server/Environment), each client draws it
-- (src/client/Environment).

local Environment = {}

export type Look = {
	brightness: number,
	ambient: { number },
	outdoorAmbient: { number },
	exposure: number,
	density: number,
	haze: number,
	color: { number },
	decay: { number },
	cloudCover: number,
	cloudColor: { number },
	wet: number, -- terrain colors x this
	rain: number, -- 0-1, the drops and the sound
}

export type Haze = { density: number, haze: number, color: { number }, decay: { number } }

local function lengths(day: any): (number, number, number, number)
	local dayHours = day.sunset - day.sunrise
	local dayLen = day.length * day.dayShare
	return dayHours, 24 - dayHours, dayLen, day.length - dayLen
end

-- Real seconds from sunrise to `clock`.
function Environment.phaseOf(clock: number, day: any): number
	local dayHours, nightHours, dayLen, nightLen = lengths(day)
	local h = (clock - day.sunrise) % 24
	if h <= dayHours then
		return h / dayHours * dayLen
	end
	return dayLen + (h - dayHours) / nightHours * nightLen
end

-- The clock (hours, 0-24) `elapsed` seconds after the server's day start, when it read `day.startClock`.
function Environment.clockAt(elapsed: number, day: any): number
	local dayHours, nightHours, dayLen, nightLen = lengths(day)
	local p = (Environment.phaseOf(day.startClock, day) + elapsed) % day.length
	local h = if p < dayLen
		then day.sunrise + p / dayLen * dayHours
		else day.sunset + (p - dayLen) / nightLen * nightHours
	return h % 24
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- 1 in full day, 0 in full night, easing over `twilight` hours either side of sunrise and sunset.
function Environment.daylight(clock: number, day: any): number
	local tw = day.twilight
	local rise = smooth((clock - (day.sunrise - tw)) / (2 * tw))
	local set = 1 - smooth((clock - (day.sunset - tw)) / (2 * tw))
	return math.min(rise, set)
end

-- The weather a roll `u` (0-1) gives: "Fog", "Rain" or "Clear".
function Environment.pick(u: number, odds: any): string
	if u < odds.Fog then
		return "Fog"
	elseif u < odds.Fog + odds.Rain then
		return "Rain"
	end
	return "Clear"
end

-- A length from `range` ({min, max}) by a roll `u` (0-1).
function Environment.span(u: number, range: any): number
	return range.min + math.clamp(u, 0, 1) * (range.max - range.min)
end

-- An event's strength at `now`: 0 before `from` and after `to`, easing in and out over `fade` seconds.
function Environment.strength(now: number, from: number, to: number, fade: number): number
	if now <= from or now >= to then
		return 0
	end
	local f = math.min(fade, (to - from) / 2)
	if f <= 0 then
		return 1
	end
	return smooth(math.min(now - from, to - now) / f)
end

local function mix(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function mixColor(a: { number }, b: { number }, t: number): { number }
	return { mix(a[1], b[1], t), mix(a[2], b[2], t), mix(a[3], b[3], t) }
end

local function scaled(c: { number }, k: number): { number }
	return { c[1] * k, c[2] * k, c[3] * k }
end

-- The light and haze for `daylight` (0-1) and weather `kind` at strength `w`, over the map's clear-sky `base` haze.
function Environment.look(daylight: number, kind: string, w: number, base: Haze, cfg: any): Look
	local L, W = cfg.Light, cfg.Weather
	local d = math.clamp(daylight, 0, 1)
	local ev = W[kind]
	local s = if ev then math.clamp(w, 0, 1) else 0
	local night = 1 - d

	local density, haze, color, decay = base.density, base.haze, base.color, base.decay
	local sun, cover, wet = 1, W.clouds.cover, 1
	if ev then
		density, haze = mix(density, ev.density, s), mix(haze, ev.haze, s)
		color, decay = mixColor(color, ev.color, s), mixColor(decay, ev.decay, s)
		sun, cover = mix(1, ev.brightness, s), mix(cover, ev.clouds, s)
		wet = if ev.wet then mix(1, ev.wet, s) else 1
	end
	local rain = if kind == "Rain" then s else 0
	local cloud = mixColor(W.clouds.color, W.clouds.rainColor, rain)
	local glow = 4 * d * night * L.dusk.strength * (1 - s) -- (none under fog or rain)

	return {
		brightness = mix(L.night.brightness, L.day.brightness, d) * sun,
		ambient = mixColor(L.night.ambient, L.day.ambient, d),
		outdoorAmbient = mixColor(L.night.outdoorAmbient, L.day.outdoorAmbient, d),
		exposure = mix(L.night.exposure, L.day.exposure, d),
		density = density,
		haze = haze,
		color = mixColor(mixColor(color, L.nightHaze.color, night), L.dusk.color, glow),
		decay = mixColor(mixColor(decay, L.nightHaze.decay, night), L.dusk.decay, glow),
		cloudCover = cover,
		cloudColor = scaled(cloud, mix(0.25, 1, d)),
		wet = wet,
		rain = rain,
	}
end

return Environment
