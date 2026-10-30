--!strict
-- How fast the stride sway settles back to the centre after moving (Config/Sway.Stride.Return, src/client/Sway). Pure.

local SwayReturn = {}

-- The settling rate (per second): the held item's class rate (`default` for none or an unlisted class), slower by the
-- gun's own weight (Config/Weapons `weight`, W2; 1 when it has none).
function SwayReturn.rate(rates: { [string]: number }, class: string?, weight: number?): number
	local base = class and rates[class] or rates.default
	return base / math.max(weight or 1, 0.1)
end

return SwayReturn
