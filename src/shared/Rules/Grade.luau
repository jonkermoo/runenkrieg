--!strict
-- The colour grade between day and night (Config/Look; src/client/Look). Pure: plain values only.

local Grade = {}

export type Tone = { saturation: number, contrast: number, brightness: number, tint: { number } }

-- How much of the day grade shows at this sun height (Lighting:GetSunDirection().Y): 0 below nightAt, 1 above dayAt,
-- eased between.
function Grade.dayShare(sunY: number, nightAt: number, dayAt: number): number
	local t = math.clamp((sunY - nightAt) / (dayAt - nightAt), 0, 1)
	return t * t * (3 - 2 * t)
end

-- The night and day tones blended by `share` (0 = night, 1 = day).
function Grade.mix(night: Tone, day: Tone, share: number): Tone
	local function lerp(a: number, b: number): number
		return a + (b - a) * share
	end
	return {
		saturation = lerp(night.saturation, day.saturation),
		contrast = lerp(night.contrast, day.contrast),
		brightness = lerp(night.brightness, day.brightness),
		tint = {
			lerp(night.tint[1], day.tint[1]),
			lerp(night.tint[2], day.tint[2]),
			lerp(night.tint[3], day.tint[3]),
		},
	}
end

return Grade
