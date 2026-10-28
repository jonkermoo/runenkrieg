--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Cfg = require("../src/shared/Config/Prompts")
local Palette = require("../src/shared/Config/Palette")
local R = require("../src/shared/Rules/Prompts")

local function seen(id: string, dist: number, extra: { [string]: any }?): R.Seen
	local s: any = { id = id, dist = dist, reach = 9, enabled = true, blocked = nil, mine = false }
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

return {
	["the shown prompt is near, the others in reach only pins"] = function()
		local out = R.states({ seen("a", 4), seen("b", 6), seen("c", 30) }, "a", 2, 8)
		assert(out.a == "near")
		assert(out.b == "far")
		assert(out.c == nil, "past twice its reach: nothing")
	end,
	["only the nearest pins show"] = function()
		local list = {}
		for i = 1, 5 do
			table.insert(list, seen(`p{i}`, i))
		end
		local out = R.states(list, nil, 2, 3)
		assert(out.p1 == "far" and out.p2 == "far" and out.p3 == "far")
		assert(out.p4 == nil and out.p5 == nil)
	end,
	["a prompt that can't be used shows its reason when nothing else is up"] = function()
		local out = R.states({ seen("gun", 5, { enabled = false, blocked = "InUse" }) }, nil, 2, 8)
		assert(out.gun == "blocked")
		out = R.states({ seen("gun", 5, { enabled = false, blocked = "InUse" }), seen("door", 7) }, "door", 2, 8)
		assert(out.gun == "far" and out.door == "near", "another prompt up: only its pin")
		out = R.states({ seen("gun", 12, { enabled = false, blocked = "InUse" }) }, nil, 2, 8)
		assert(out.gun == "far", "out of reach: only its pin")
		out = R.states({
			seen("a", 6, { enabled = false, blocked = "Broken" }),
			seen("b", 3, { enabled = false, blocked = "InUse" }),
		}, nil, 2, 8)
		assert(out.b == "blocked" and out.a == "far", "the nearest one")
	end,
	["a prompt off with no reason, or one I'm using, shows nothing"] = function()
		local out =
			R.states({ seen("a", 2, { enabled = false }), seen("b", 2, { mine = true, blocked = "InUse" }) }, nil, 2, 8)
		assert(out.a == nil and out.b == nil)
	end,
	["the hold fills over its time, a tap never"] = function()
		assert(R.progress(nil, 1) == 0)
		assert(R.progress(0.5, 1) == 0.5)
		assert(R.progress(3, 1) == 1)
		assert(R.progress(1, 0) == 0)
	end,
	["the pin sits on the thing"] = function()
		local x, y = R.offset(10, 90, 320, 100)
		-- the canvas moved right by half its width less the pin's x, and up by the pin's distance below the middle
		assert(math.abs(x - (0.5 - 10 / 320)) < 1e-9 and math.abs(y - 0.4) < 1e-9)
	end,
	["the spec's colours and reasons exist"] = function()
		local spec = serde.decode("json", fs.readFile("src/shared/ui/Prompt.json"))
		local C = (Palette.UI :: any).Prompt
		for _, name in
			{ "pin", "ring", "lead", "key", "keyText", "object", "action", "reason", "shadow", "line", "fill" }
		do
			assert(C[name], `Palette.UI.Prompt.{name}`)
		end
		assert(Cfg.Reasons.InUse and Cfg.Reasons.Broken)
		-- the tag (line end up to its words) fits inside the canvas above the pin
		local a = math.rad(spec.lead.angle)
		local endY = spec.pin.at[2] + math.sin(a) * spec.lead.length
		local tall = spec.text.object + spec.text.action + spec.text.reason + spec.tag.padBottom
		assert(endY - tall >= 0, "the tag runs off the top of the canvas")
		assert(spec.pin.at[1] - spec.pin.size / 2 >= 0 and spec.pin.at[2] + spec.pin.size / 2 <= spec.canvas[2])
	end,
}
