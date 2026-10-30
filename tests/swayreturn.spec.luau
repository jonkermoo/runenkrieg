--!strict
local S = require("../src/shared/Config/Sway")
local W = require("../src/shared/Config/Weapons")
local R = require("../src/shared/Rules/SwayReturn")

local rates = S.Stride.Return :: any

local function of(name: string): number
	local w = W[name] :: any
	return R.rate(rates, w.class, w.weight)
end

return {
	["the class's rate, the default with nothing held or an unlisted class"] = function()
		assert(R.rate(rates, "Pistol", nil) == rates.Pistol)
		assert(R.rate(rates, nil, nil) == rates.default)
		assert(R.rate(rates, "Nothing", nil) == rates.default)
	end,
	["a heavier gun settles slower"] = function()
		assert(math.abs(R.rate({ default = 4 }, nil, 1.25) - 3.2) < 1e-9)
		assert(R.rate({ default = 4 }, nil, 0) > 0, "a zero weight never divides by zero")
	end,
	["pistols fastest, then the bolt rifles, the semi-automatics by their weight, the MG slowest"] = function()
		local pistol = of("pistol_c96")
		local bolt = of("rifle_m91")
		local mondragon, remington, winchester =
			of("rifle_mondragon"), of("rifle_remington8"), of("rifle_winchester1907")
		assert(pistol > bolt and bolt > mondragon and mondragon > remington and remington > winchester)
		assert(winchester > rates.MachineGun)
		assert(of("pistol_webley") == pistol and of("pistol_nagant") == pistol)
	end,
	["every rifle settles faster than before (3 per second)"] = function()
		for _, name in
			{ "rifle_m91", "rifle_g98", "rifle_smle", "rifle_mondragon", "rifle_remington8", "rifle_winchester1907" }
		do
			assert(of(name) > 3, name)
		end
	end,
}
