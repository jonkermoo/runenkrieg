--!strict
local Cfg = require("../src/shared/Config/TeamOutline")
local Palette = require("../src/shared/Config/Palette")
local R = require("../src/shared/Rules/TeamOutline")
local Settings = require("../src/shared/Config/Settings")

local stops = Palette.UI.TeamOutline

local function same(a: { number }, b: { number }): boolean
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

return {
	["full health is the first stop's colour, nothing left the last's"] = function()
		assert(same(R.shade(100, 100, stops), stops[1].color), "full")
		assert(same(R.shade(150, 100, stops), stops[1].color), "over full")
		assert(same(R.shade(0, 100, stops), stops[#stops].color), "zero")
		assert(same(R.shade(-5, 100, stops), stops[#stops].color), "negative")
		assert(same(R.shade(10, 100, stops), stops[#stops].color), "below the last stop")
		assert(same(R.shade(10, 0, stops), stops[#stops].color), "no max")
	end,
	["each stop's own share gives its colour, shaded in between"] = function()
		for _, s in stops do
			assert(same(R.shade(s.at * 100, 100, stops), s.color), `stop at {s.at}`)
		end
		local mid = R.shade(75, 100, stops)
		for c = 1, 3 do
			local lo, hi =
				math.min(stops[1].color[c], stops[2].color[c]), math.max(stops[1].color[c], stops[2].color[c])
			assert(mid[c] >= lo and mid[c] <= hi, "75 lies between full and half")
		end
	end,
	["the stops run from full down, colours in 0-255"] = function()
		assert(stops[1].at == 1, "the first stop is full health")
		for i, s in stops do
			assert(i == 1 or s.at < stops[i - 1].at, "shares fall")
			for c = 1, 3 do
				assert(s.color[c] >= 0 and s.color[c] <= 255, "a colour channel")
			end
		end
	end,
	["only the nearest in range are picked, at most the cap"] = function()
		local c = {
			{ key = "far", dist = 500 },
			{ key = "b", dist = 20 },
			{ key = "a", dist = 5 },
			{ key = "c", dist = 90 },
		}
		local got = R.pick(c, 2, 400)
		assert(#got == 2 and got[1] == "a" and got[2] == "b", "the two nearest")
		local all = R.pick(c, 10, 400)
		assert(#all == 3 and not table.find(all, "far"), "the far one out of range")
		assert(#R.pick(c, 0, 400) == 0, "a zero cap")
		assert(#R.pick({}, 5, 400) == 0, "nobody")
	end,
	["the cap leaves room under Roblox's 31 Highlights"] = function()
		assert(Cfg.MaxOutlines > 0 and Cfg.MaxOutlines <= 28, "room for the game's other Highlights")
		assert(Cfg.Rate > 0 and Cfg.MaxDistance > 0, "a rate and a range")
		assert(Cfg.DepthMode == "Occluded" or Cfg.DepthMode == "AlwaysOnTop", "a HighlightDepthMode")
	end,
	["shown only while the map key is held"] = function()
		assert(Cfg.Key == "Key_Map", "the map key, with the dots and the health bars")
		assert(Settings.Options[Cfg.Key] ~= nil, "a real keybind")
		assert(Cfg.AlwaysAttribute ~= Cfg.OffAttribute and Cfg.AlwaysAttribute ~= Cfg.SelfAttribute, "its own switch")
	end,
}
