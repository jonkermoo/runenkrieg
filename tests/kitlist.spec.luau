--!strict
local Hud = require("../src/shared/Config/Hud")
local W = require("../src/shared/Config/Weapons")
local R = require("../src/shared/Rules/KitList")

local K = Hud.Kit

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["the rows go primary, grenades, shovel, then anything else as it came"] = function()
		local rows = {
			{ slot = "Shovel", first = 1 },
			{ slot = "Other", first = 2 },
			{ slot = "Grenade", first = 3 },
			{ slot = "Extra", first = 0 },
			{ slot = "Primary", first = 4 },
		}
		local out = R.sort(rows, K.order)
		local got = {}
		for _, r in out do
			table.insert(got, r.slot)
		end
		assert(table.concat(got, ",") == "Primary,Grenade,Shovel,Extra,Other", table.concat(got, ","))
		assert(rows[1].slot == "Shovel", "the input is left as it is")
	end,
	["every weapon slot in Config/Weapons has a place in the order"] = function()
		for name, w in W :: any do
			if type(w) == "table" and w.slot then
				assert(table.find(K.order, w.slot), `{name}: slot {w.slot} not in Config/Hud.Kit.order`)
			end
		end
	end,
	["a key draws its row's item, puts away the one in the hands, and does nothing past the list or on an empty row"] = function()
		assert(R.press(1, 3, false, false) == "draw")
		assert(R.press(2, 3, false, true) == "stow")
		assert(R.press(4, 3, false, false) == nil, "no fourth row")
		assert(R.press(0, 3, false, false) == nil)
		assert(R.press(2, 3, true, false) == nil, "the last grenade thrown")
	end,
	["the list lingers, fades out, stays up in build mode and hides while aiming"] = function()
		assert(R.alpha(0, false, false, K) == 1)
		assert(R.alpha(K.linger - 0.01, false, false, K) == 1)
		assert(near(R.alpha(K.linger + K.fade / 2, false, false, K), 0.5))
		assert(near(R.alpha(K.linger + K.fade, false, false, K), 0))
		assert(R.alpha(1e6, false, false, K) == 0)
		assert(R.alpha(1e6, true, false, K) == 1, "build mode keeps it up")
		assert(R.alpha(0, true, true, K) == 0, "aiming hides it, build mode or not")
		assert(R.alpha(5, false, false, { linger = 2, fade = 0 }) == 0, "no fade: gone at once")
	end,
	["one key per row, nine at most, each a key name"] = function()
		assert(#K.keys >= 1 and #K.keys <= 9)
		for _, k in K.keys do
			assert(type(k) == "string" and #k > 0)
		end
	end,
}
